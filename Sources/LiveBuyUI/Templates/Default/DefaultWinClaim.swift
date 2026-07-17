import LivebuySDK

// MARK: - DefaultWinClaim — §2/§3/§4 win unclaimed + claim submit + result state
//
// Spec: `ui-template-foundation/spec.md`
//   § "Default Template 中獎未領入口狀態（`LBWinEntry` 行為）"
//   § "Default Template 領獎提交行為（`LBWinSheet` 行為）"
//   § "Default Template 領獎結果狀態消費與攔截"
// Design: design.md D2 / D3 / D4.
//
// Behaviour / view-model layer ONLY (no pixels). The host draws `LBWinEntry`
// (floating icon + badge) bound to `unclaimedCount` / `unclaimedWinners`, and
// `LBWinSheet` (award detail + CTA) driven by `awardPresentation(for:)` and the
// `submit(winner:)` action + `resultState` feedback. core stays headless: it
// never maintains unclaimed state and never renders an entry / sheet.

/// Abstraction over the core's 領獎 entry point so the win-claim view-model is
/// unit-testable with a `Capturing` requester (no UIKit / live SDK needed).
/// `LivebuyPlayerViewController` already exposes this exact signature; it
/// conforms via a source-compatible extension (no behaviour change).
public protocol AwardClaimRequesting: AnyObject {
    func requestAwardClaim(winner: LBWinner, contact: LBAwardClaimInput?)
}

extension LivebuyPlayerViewController: AwardClaimRequesting {}

/// Host-facing CTA classification for a win award (design D2 / spec table).
/// Default flow has NO email step — these only drive CTA wording.
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

    /// The winner.id of the most recent `submit(winner:)`. The core
    /// `awardClaimResult` notification carries NO winner id, so the template
    /// uses this to know which unclaimed entry to clear on `.claimed`.
    private(set) public var lastSubmittedWinnerId: String?

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
    /// 立即使用). Host reads this to pick wording; Default flow needs no email.
    public func awardPresentation(for winner: LBWinner) -> LBAwardPresentation {
        LBAwardPresentation(awardType: winner.award.type)
    }

    /// Submit a claim for `winner`. Default flow collects NO email / contact —
    /// it calls `requestAwardClaim(winner, nil)`. The result arrives via
    /// `consumeResult` (driven by the core `awardClaimResult` notification).
    public func submit(winner: LBWinner) {
        lastSubmittedWinnerId = winner.id
        requester?.requestAwardClaim(winner: winner, contact: nil)
    }

    // MARK: - §4 Result-state mapping + claimed → unclaimed removal

    /// Map a core `awardClaimResult` into the host-bindable feedback state and,
    /// on `.claimed`, remove `winner.id` from the unclaimed set (count decrements).
    /// `awardCode` is honoured ONLY for `.claimed` + discount.
    @discardableResult
    public func consumeResult(status: LBAwardClaimStatus,
                              awardType: String,
                              winnerId: String?,
                              awardCode: String?) -> LBAwardClaimResultState {
        let state = Self.mapResult(status: status, awardType: awardType, awardCode: awardCode)
        if status == .claimed, let id = winnerId { remove(winnerId: id) }
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

    /// Reset feedback + unclaimed state (e.g. on release / new video).
    public func clear() {
        unclaimedWinners.removeAll()
        unclaimedIds.removeAll()
        resultState = nil
        onMutation?()
    }
}
