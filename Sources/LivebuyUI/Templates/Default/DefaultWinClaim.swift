import LivebuySDK

// MARK: - DefaultWinClaim — §2/§3/§4 win unclaimed + claim submit + result state
//
// Spec: `ui-template-foundation/spec.md`
//   § "Default Template 中獎未領入口狀態（`LBWinEntry` 行為）"
//   § "Default Template 領獎提交行為（`LBWinSheet` 行為）"
//   § "Default Template 領獎結果狀態消費與攔截"
//   § "Default Template 領獎 email 前端驗證（純函式）"          (win-claim-email-submit-template)
//   § "Default Template 領獎送出中狀態（in-flight）"            (win-claim-email-submit-template)
//   § "Default Template 關閉領獎畫面僅 dismiss（不放棄中獎資格）" (win-claim-email-submit-template)
// Design: design.md D2 / D3 / D4.
//
// Behaviour / view-model layer ONLY (no pixels). The host draws `LBWinEntry`
// (floating icon + badge) bound to `unclaimedCount` / `unclaimedWinners`, and
// `LBWinSheet` (award detail + email field + CTA) driven by
// `awardPresentation(for:)` and the `submit(winner:email:)` action +
// `submitInFlight` / `resultState` feedback + `dismissClaim()`. core stays
// headless: it never maintains unclaimed state and never renders an entry / sheet.

/// Abstraction over the core's 領獎 entry point so the win-claim view-model is
/// unit-testable with a `Capturing` requester (no UIKit / live SDK needed).
/// `LivebuyPlayerViewController` already exposes this exact signature; it
/// conforms via a source-compatible extension (no behaviour change).
public protocol AwardClaimRequesting: AnyObject {
    func requestAwardClaim(winner: LBWinner, contact: LBAwardClaimInput?)
}

extension LivebuyPlayerViewController: AwardClaimRequesting {}

/// Host-facing CTA classification for a win award (design D2 / spec table).
/// Drives wording / glyph routing only — it does NOT gate the email step
/// (both award types need the SAME single email field, see `submit(winner:email:)`).
public enum LBAwardPresentation: Equatable {
    /// `award.type == "product"` → CTA 語意「查看獎品」.
    case product
    /// `award.type == "discount"` → CTA 語意「立即使用」.
    case discount

    init(awardType: String) {
        self = (awardType == "discount") ? .discount : .product
    }
}

/// Mapped 領獎結果狀態 (design D3 table). `awardCode` is present ONLY for
/// `.success(.discount)`; product success carries no code field (nil).
public enum LBAwardClaimResultState: Equatable {
    /// 成功 · 獎品類 (no code).
    case successProduct
    /// 成功 · 優惠類 + 折扣碼.
    case successDiscount(awardCode: String)
    /// 失敗 · 可重試 (also `.unknown(Int)` maps here).
    case failureRetryable
}

public final class DefaultWinClaim {

    private weak var requester: AwardClaimRequesting?

    /// Unclaimed winners, deduped by `winner.id`, insertion-ordered.
    private(set) public var unclaimedWinners: [LBWinner] = []
    private var unclaimedIds: Set<String> = []

    /// Latest mapped claim-result feedback state (host binds to draw success /
    /// failure). nil until a result arrives (or while a native host intercepts).
    private(set) public var resultState: LBAwardClaimResultState?

    /// The winner.id of the most recent submit. The core `awardClaimResult`
    /// notification carries NO winner id, so the template uses this to know which
    /// unclaimed entry to clear on `.claimed`. Deliberately NOT reset by
    /// `dismissClaim()` — a result that lands AFTER the sheet was closed must
    /// still be able to clear the right unclaimed entry.
    private(set) public var lastSubmittedWinnerId: String?

    /// 領獎「送出中」flag (win-claim-email-submit-template). Host / reference-ui bind
    /// this to draw the `LBWinSheet` `submitting` stage (scrim + spinner +「送出中…」)
    /// and to disable the CTA for the request lifecycle.
    ///
    /// Naming + lifecycle deliberately MIRROR the existing
    /// `DefaultPlayerTemplate.addToCartInFlight` (`cart-add-loading-state-template`)
    /// convention — do NOT invent a second style:
    ///   • `submit(...)` past its guards → `true` (+ one `onMutation`)
    ///   • guard rejected (invalid email / already in flight) → UNCHANGED
    ///     (mirrors the sold-out / unselected-variant guards, which never enter in-flight)
    ///   • `consumeResult(...)` (success AND failure) / `dismissClaim()` / `clear()` → `false`
    ///
    /// Known hang: when a NATIVE host intercepts `awardClaimIntent` (returns true) the
    /// core never emits `awardClaimResult`, so there is no result to consume — the host
    /// clears this by calling `dismissClaim()` when it closes its own claim UI (or via
    /// `clear()` on video switch / release). The template MUST NOT guess the outcome.
    private(set) public var submitInFlight: Bool = false

    /// Internal coalesced "win-claim state mutated" hook. The owning
    /// `DefaultPlayerTemplate` wires this to fan a single host-facing `onChange`
    /// (main-thread) per mutation. NOT public — the host observes via the
    /// template's `onChange`, it does NOT subscribe to this model directly.
    var onMutation: (() -> Void)?

    public init(requester: AwardClaimRequesting?) {
        self.requester = requester
    }

    /// Count of distinct unclaimed wins (drives the `LBWinEntry` badge).
    public var unclaimedCount: Int { unclaimedWinners.count }

    // MARK: - §2 Unclaimed set

    /// Record a new win (from core `showWin(text, winner)`). Deduped by
    /// `winner.id`; a repeated id does NOT increment the count.
    public func recordWin(_ winner: LBWinner) {
        guard unclaimedIds.insert(winner.id).inserted else { return }
        unclaimedWinners.append(winner)
        onMutation?()
    }

    // MARK: - §3 Claim submit + classification

    /// CTA classification for a winner's award (product → 查看獎品, discount →
    /// 立即使用). Host reads this to pick wording / glyph; it does NOT affect whether
    /// an email is required — every claim goes through `submit(winner:email:)`.
    public func awardPresentation(for winner: LBWinner) -> LBAwardPresentation {
        LBAwardPresentation(awardType: winner.award.type)
    }

    /// Pure front-end email validation (win-claim-email-submit-template). The host /
    /// reference-ui calls this on every keystroke to decide whether the「確認領獎」CTA
    /// is disabled; `submit(winner:email:)` uses the SAME function to fail fast.
    ///
    /// Rule mirrors the delivery design `design/templates/minimal/moments.jsx`
    /// (`LBWinSheet`): trim, then `.+@.+\..+` — local part, `@`, domain, `.`, TLD.
    /// The JS side runs that regex UNANCHORED; here it is anchored (`^…$`) so a
    /// multi-line paste like `"junk\na@b.c"` is rejected. For SINGLE-LINE input —
    /// i.e. every real email field — the two are identical, so anchoring only ever
    /// tightens the multi-line edge case; it can never reject something the design
    /// accepts on one line.
    ///
    /// Deliberately NOT stricter (no RFC 5322 / `NSDataDetector`): the truth lives in
    /// the backend (deliverability is only known once the mail is sent), and over-strict
    /// rules would kill valid addresses such as `user+tag@sub.domain.io`.
    public static func isValidEmail(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.range(of: "^.+@.+\\..+$", options: .regularExpression) != nil
    }

    /// Submit a claim for `winner` carrying the user-entered `email`
    /// (win-claim-email-submit-template — the fix for the EMAIL-LESS trap).
    ///
    /// Returns `true` when the request was actually handed to core (and the model
    /// entered `submitInFlight`); `false` when a guard rejected the call, in which
    /// case core is NOT called and NO state changes at all.
    ///
    /// Guards, in order:
    ///   1. re-entrancy — already in flight (double-tap「確認領獎」/ host re-entry).
    ///      Re-sending `POST /sdk/video/claim` would come back as「已領過」→ `500
    ///      api.fail` → a FAKE failure for the user, so it is cheapest to stop here.
    ///   2. `isValidEmail` — an invalid address never reaches the network.
    ///
    /// The email is trimmed ONCE and the SAME trimmed string is both validated and
    /// sent, so「驗證過的字串」and「送出的字串」can never diverge. The result arrives
    /// via `consumeResult` (driven by the core `awardClaimResult` notification).
    @discardableResult
    public func submit(winner: LBWinner, email: String) -> Bool {
        guard !submitInFlight else { return false }
        guard Self.isValidEmail(email) else { return false }
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        beginSubmit(winner: winner, contact: LBAwardClaimInput(email: trimmed))
        return true
    }

    /// EMAIL-LESS claim submit — **DEPRECATED**, kept only for source compatibility.
    ///
    /// It calls `requestAwardClaim(winner, nil)`, and the core's default (non-intercepted)
    /// claim path requires `email`, so this entry point **always fails** unless a native
    /// host intercepts `awardClaimIntent`: core fails fast, never sends
    /// `POST /sdk/video/claim`, and emits `awardClaimResult(.failed)`. That is the very
    /// bug this change fixes — use `submit(winner:email:)`.
    ///
    /// Signature + `contact: nil` behaviour are intentionally UNCHANGED (per
    /// `docs/contract-governance.md` I6 / 情境 F, removal only in the next MAJOR).
    /// It does now share the in-flight state machine with the new entry point so the
    /// model never exposes a half-populated state.
    @available(*, deprecated, message: "EMAIL-LESS 領獎在未被 host 攔截時必然失敗（core 預設領獎路徑 email 必填，缺 email 直接 fail-fast、連 API 都不送）。改用 submit(winner:email:)；本入口將於下一個 major 移除。")
    public func submit(winner: LBWinner) {
        guard !submitInFlight else { return }
        beginSubmit(winner: winner, contact: nil)
    }

    /// Shared submit core for BOTH entry points: remember the target winner, drop any
    /// stale result (so「重新領獎」does not show last round's failure underneath the
    /// spinner), enter in-flight, hand off to core, notify ONCE.
    private func beginSubmit(winner: LBWinner, contact: LBAwardClaimInput?) {
        lastSubmittedWinnerId = winner.id
        resultState = nil
        submitInFlight = true
        requester?.requestAwardClaim(winner: winner, contact: contact)
        onMutation?()
    }

    /// Close the claim sheet (design `LBWinSheet`「關閉視窗」/ ✕ / done-stage scrim tap).
    ///
    /// ⚠️ **DELIBERATELY COUNTER-INTUITIVE — read before "fixing" this.** The design's
    /// `confirmClose` copy says「您將放棄【獎品】的中獎資格，此動作無法復原」, but the
    /// behaviour is a **pure dismiss**: the strong wording is UX friction meant to lower
    /// accidental closes, it does NOT actually forfeit anything (authority:
    /// `design/contract/claude-design-sync.md` R13「刻意分歧（1/2）」). The same component's
    /// `FailCard`「你的中獎資格仍保留」is the accurate description; the two strings
    /// contradicting each other is known and intended — do NOT "make them consistent".
    ///
    /// Therefore this method MUST only reset the per-presentation transient state
    /// (`resultState` / `submitInFlight`) and MUST NOT:
    ///   • remove the winner from `unclaimedWinners`
    ///   • decrement `unclaimedCount` (the entry badge stays — the user can claim again)
    ///   • call ANY API
    ///   • reset `lastSubmittedWinnerId` (a late `.claimed` must still clear the entry)
    public func dismissClaim() {
        resultState = nil
        submitInFlight = false
        onMutation?()
    }

    // MARK: - §4 Result-state mapping + claimed → unclaimed removal

    /// Map a core `awardClaimResult` into the host-bindable feedback state and,
    /// on `.claimed`, remove `winner.id` from the unclaimed set (count decrements).
    /// `awardCode` is honoured ONLY for `.claimed` + discount. The request is over
    /// either way, so `submitInFlight` clears on BOTH success and failure (failure
    /// must let the host draw「重新領獎」).
    @discardableResult
    public func consumeResult(status: LBAwardClaimStatus,
                              awardType: String,
                              winnerId: String?,
                              awardCode: String?) -> LBAwardClaimResultState {
        let state = Self.mapResult(status: status, awardType: awardType, awardCode: awardCode)
        if status == .claimed, let id = winnerId { remove(winnerId: id) }
        submitInFlight = false
        resultState = state
        // A single result consumption (result-state update + optional claimed
        // removal) is one coalesced mutation → notify exactly once.
        onMutation?()
        return state
    }

    /// Event-routing convenience: the core `awardClaimResult` notification has no
    /// winner id, so the `.claimed` removal targets the most recent submit
    /// (`lastSubmittedWinnerId`).
    @discardableResult
    public func consumeResult(status: LBAwardClaimStatus,
                              awardType: String,
                              awardCode: String?) -> LBAwardClaimResultState {
        consumeResult(status: status, awardType: awardType,
                      winnerId: lastSubmittedWinnerId, awardCode: awardCode)
    }

    /// Pure mapping of (status, awardType, awardCode) → result state.
    /// `.unknown(Int)` is treated as `.failed`. discount carries the code;
    /// product never carries an (empty) code field.
    static func mapResult(status: LBAwardClaimStatus,
                          awardType: String,
                          awardCode: String?) -> LBAwardClaimResultState {
        switch status {
        case .claimed:
            if awardType == "discount" {
                return .successDiscount(awardCode: awardCode ?? "")
            }
            return .successProduct
        case .failed, .unknown:
            return .failureRetryable
        }
    }

    private func remove(winnerId: String) {
        guard unclaimedIds.remove(winnerId) != nil else { return }
        unclaimedWinners.removeAll { $0.id == winnerId }
    }

    /// Reset feedback + unclaimed state (e.g. on release / new video). Also drops any
    /// in-flight submit — including one left hanging by an intercepted claim.
    public func clear() {
        unclaimedWinners.removeAll()
        unclaimedIds.removeAll()
        resultState = nil
        submitInFlight = false
        onMutation?()
    }
}
