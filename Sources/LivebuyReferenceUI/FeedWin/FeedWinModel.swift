import SwiftUI
import Combine
import LivebuySDK
import LivebuyUI

// MARK: - FeedWinModel — family-2 feed + win observable snapshot bridge
//
// Spec: `reference-ui-rendering/spec.md` (family-2 feed-win, 3 surfaces)
// Design: rb-ios-feed-win design.md D-1 / D-2 / D-3 / D-4.
//
// This is the SKELETON for rb-ios-feed-win. It bridges the headless template
// view-models exposed by `DefaultPlayerTemplate` (obtained via
// `LivebuyUI.playerTemplate(for:)`) into a SwiftUI-observable snapshot that the
// three family-2 surface sub-views read. It is a read-only mirror — IDENTICAL
// pattern to `PlayerShellModel` (family-1):
//
//   - It does NOT own a second copy of authoritative state — it republishes
//     SNAPSHOT VALUES taken from the template's own `private(set) public` reads
//     (`activityFeed.items` / `winClaim.unclaimedCount` /
//     `winClaim.unclaimedWinners` / `winClaim.resultState`) each time the
//     template fires its single coalesced `onChange` (D-1).
//   - It does NOT add pixels and it does NOT add any accessor to `LivebuyUI`
//     (that would be a template-layer concern, out of scope here).
//   - It does NOT subscribe to the feed / winClaim internal `onMutation`
//     (that is a template-internal hook); it observes ONLY the template's single
//     public `onChange` (design §"容器與 view-model 橋接").
//   - The ONLY mutating interaction this layer carries is the win-claim submit,
//     which goes through the template exit `submitClaim(for:email:)` →
//     `DefaultWinClaim.submit(winner:email:)` (帶使用者輸入的 email；EMAIL-LESS 的
//     舊入口已 deprecated —— 缺 email 時 core fail-fast、連 API 都不送). The
//     event-join 「加入活動」submit goes through an upstream exit (host wired); this
//     model does NOT own it.
//
// iOS-14-safe: `ObservableObject` + `@Published` are available from iOS 13, so
// no `@available` guard is needed here.

/// Observable snapshot of the family-2 feed-win state, republished from a live
/// `DefaultPlayerTemplate` (or constructed deterministically for demos / snapshot
/// tests via the memberwise initializer).
public final class FeedWinModel: ObservableObject {

    // MARK: - Published surface snapshots
    //
    // Each group is the read-only value set ONE family-2 surface sub-view needs.
    // The grouping mirrors the three surfaces so a surface sub-view binds exactly
    // the snapshot values it needs (see the documented sub-view input pattern in
    // FeedWinOverlayView.swift).

    // -- Surface 1: ChatFeedView ← merged activity + chat feed (D-2) -----------

    /// The merged, ordered, tail-retained (N=7) feed (`DefaultActivityFeed.items`).
    /// Already merged / ordered by the data layer — this layer MUST NOT slice /
    /// merge / re-sort (doing so would be a second copy, violating single-truth).
    /// This is the AMBIENT slice; the SCROLLABLE feed uses `feedHistory` below.
    @Published public private(set) var feedItems: [LBFeedItem]

    /// The deeper scrollable history buffer (`DefaultActivityFeed.history`, cap 50)
    /// — bound by the SCROLLABLE `ChatFeedView` variant so the user can scroll up to
    /// view recent history. Same merge / order / de-dup rules as `feedItems` (it is a
    /// superset suffix-derived in the data layer). Empty for demo / snapshot instances.
    @Published public private(set) var feedHistory: [LBFeedItem]

    /// 置頂留言（chat-pinned-message-render ⑤c），鏡像自 `DefaultPlayerTemplate.pinnedMessage`
    /// （core `LBPollResponse.top`）。nil → 無置頂（橫幅不出像素）。冪等：每輪覆蓋、取消釘選 → nil。
    @Published public private(set) var pinned: LBPinnedMessage?

    /// Host / shop name (`DefaultPlayerHeaderState.hostName`, mirrored via `DefaultPlayer
    /// Template.header.hostName` — same authoritative source + mirroring technique as
    /// `PlayerShellModel.hostName`). Purely a display value for the `.eventJoin` row's
    /// host-bubble name header (`rb-ios-loading-announce-restyle`); this layer does NOT own
    /// header chrome (that stays family-1 `PlayerShellModel`'s job).
    @Published public private(set) var hostName: String

    // -- Surface 2: WinEntryView ← unclaimed win entry (D-3) -------------------

    /// Distinct unclaimed-win count (`DefaultWinClaim.unclaimedCount`); the entry
    /// badge is drawn only when `> 0`, with the badge number == this count.
    @Published public private(set) var unclaimedCount: Int
    /// Unclaimed winners, insertion-ordered, deduped by id
    /// (`DefaultWinClaim.unclaimedWinners`). The entry opens the claim sheet on
    /// the EARLIEST unclaimed winner (`unclaimedWinners.first`).
    @Published public private(set) var unclaimedWinners: [LBWinner]

    // -- Surface 3: WinClaimModalView ← claim result feedback (D-4) ------------

    /// Latest mapped claim-result feedback (`DefaultWinClaim.resultState`); nil
    /// until a result arrives. `.successProduct` / `.successDiscount(awardCode:)`
    /// / `.failureRetryable`. On `.claimed` the template removes the winner and
    /// `unclaimedCount` decrements — both republished here via `onChange`.
    @Published public private(set) var resultState: LBAwardClaimResultState?

    /// 領獎「送出中」旗標（`DefaultWinClaim.submitInFlight`），驅動 `WinClaimModalView`
    /// 的 `submitting` 階段（scrim + spinner +「送出中…」）。
    /// **這是唯一的 in-flight 真相** —— reference-ui MUST NOT 自造第二份
    /// （否則 view-model 的 guard 擋下提交時畫面會卡住）。
    @Published public private(set) var submitInFlight: Bool

    // MARK: - Live binding

    /// The bound template, when constructed from a live player. nil for demo /
    /// snapshot instances. Held weakly so this model never retains the template
    /// (the player VC owns it; dependency stays one-way UI → core).
    private weak var template: DefaultPlayerTemplate?

    /// The independent observer registration token this model holds. Removed on
    /// deinit so this model unsubscribes ONLY itself — never clobbers another
    /// model's subscription (multi-observer registry, same as `PlayerShellModel`).
    private var observerToken: LBTemplateObserverToken?

    /// Optional three-tier「加入活動」join gate injected by the drop-in container
    /// (rb-ios-event-join-gate). Consulted by `joinEvent` BEFORE forwarding: returns `true`
    /// when it INTERCEPTED the intent (raised a login / nickname modal) → `joinEvent` MUST NOT
    /// forward to the template (MUST NOT join / `markJoined`). `nil` (demo / snapshot instances,
    /// no injection) → NO gating, `joinEvent` forwards unconditionally → baseline byte-identical.
    /// The gate shares the 留言 pill's SAME pure predicates (`liveCommentRequiresLogin` /
    /// `liveCommentRequiresNickname`, via `eventJoinGateDecision`) so the「加入活動」CTA and the
    /// 留言 pill can never diverge. Container-internal wiring seam (not a host API).
    var joinEventGate: ((Int, String) -> Bool)?

    // MARK: - Live initializer (D-1)

    /// Bridge a live `DefaultPlayerTemplate`: take an initial snapshot and
    /// register an observer on its single coalesced change notification so every
    /// feed append / win record / claim result re-snapshots and republishes to the
    /// surface sub-views.
    ///
    /// The host obtains the template via `LivebuyUI.playerTemplate(for:)` and
    /// passes it here. Returns a model whose published values mirror the template
    /// (read-only). This registers an INDEPENDENT observer via `addObserver`; it
    /// does NOT chain or replace the template's legacy `onChange`.
    public convenience init(template: DefaultPlayerTemplate) {
        self.init(snapshotting: template)
        self.template = template
        self.observerToken = template.addObserver { [weak self] in
            self?.refresh(from: template)
        }
    }

    /// Take an immediate snapshot of a template (no subscription) — used by the
    /// live convenience init for the seed values.
    private convenience init(snapshotting t: DefaultPlayerTemplate) {
        self.init(
            feedItems: t.activityFeed.items,
            feedHistory: t.activityFeed.history,
            unclaimedCount: t.winClaim.unclaimedCount,
            unclaimedWinners: t.winClaim.unclaimedWinners,
            resultState: t.winClaim.resultState,
            pinned: t.pinnedMessage,
            hostName: t.header.hostName,
            submitInFlight: t.winClaim.submitInFlight
        )
    }

    // MARK: - Memberwise / demo initializer (D-1)

    /// Construct a deterministic instance WITHOUT a live player — for the surface
    /// sub-views' previews and the per-surface snapshot tests. Every value
    /// defaults to the at-attach seed (empty feed, no unclaimed wins, no result)
    /// so a zero-argument call yields a stable baseline.
    public init(
        feedItems: [LBFeedItem] = [],
        feedHistory: [LBFeedItem] = [],
        unclaimedCount: Int = 0,
        unclaimedWinners: [LBWinner] = [],
        resultState: LBAwardClaimResultState? = nil,
        pinned: LBPinnedMessage? = nil,
        hostName: String = "",
        submitInFlight: Bool = false
    ) {
        self.feedItems = feedItems
        self.feedHistory = feedHistory
        self.unclaimedCount = unclaimedCount
        self.unclaimedWinners = unclaimedWinners
        self.resultState = resultState
        self.pinned = pinned
        self.hostName = hostName
        self.submitInFlight = submitInFlight
    }

    deinit {
        // Remove ONLY this model's own observer so a re-bound template is not left
        // with a dangling closure capturing this (now gone) model — other models'
        // subscriptions are untouched (no chain to restore, no clobber).
        if let token = observerToken { template?.removeObserver(token) }
    }

    // MARK: - Re-snapshot on change (D-1)

    /// Pull the latest values from the bound template into the published mirrors.
    /// Always on the main thread (the template dispatches `onChange` on main; the
    /// live init only installs this from the main-thread `onChange`). `objectWill
    /// Change` fires once per `@Published` write — acceptable for the skeleton;
    /// surface sub-views read final values within one runloop.
    private func refresh(from t: DefaultPlayerTemplate) {
        feedItems = t.activityFeed.items
        feedHistory = t.activityFeed.history
        unclaimedCount = t.winClaim.unclaimedCount
        unclaimedWinners = t.winClaim.unclaimedWinners
        resultState = t.winClaim.resultState
        pinned = t.pinnedMessage
        hostName = t.header.hostName
        submitInFlight = t.winClaim.submitInFlight
    }

    // MARK: - Read-only host intents (pass-through to the bound template)
    //
    // The feed-win layer does NOT carry actions. These are thin forwarders for the
    // template-owned intents the family-2 surfaces need that have no direct core
    // `simulate*` equivalent reachable here:
    //
    //   • `submitClaim(for:email:)` — the win-claim submit carrying the user-entered
    //     email (the one true mutating interaction of this family). It forwards to
    //     `DefaultWinClaim.submit(winner:email:)`. The result then arrives via the
    //     template's `awardClaimResult` → `onChange` → `refresh`. (The EMAIL-LESS
    //     `submitClaim(for:)` is DEPRECATED — see below.)
    //   • `dismissClaim()` — 關閉領獎畫面。**僅 dismiss**：只清 view-model 的
    //     `resultState` / `submitInFlight`，MUST NOT 移除未領中獎 / 呼叫 API /
    //     遞減徽章（見 `WinClaimModalView.dismissConfirmed` 的 R13 說明）。
    //   • `joinEvent(eid:keyword:)` — the「加入活動」intent for an event-join feed
    //     row. It forwards to the template's `joinEvent` (core
    //     `requestEventJoin` + optimistic `markJoined`). The design notes this is
    //     a host-wired upstream exit; the forwarder is provided so the container's
    //     event-join CTA has a single funnel, but a host that takes over the
    //     intent itself can ignore it. No-op for demo instances (no template).

    /// Forward a win claim carrying the user-entered `email` to the bound template
    /// (template exit `DefaultWinClaim.submit(winner:email:)`). The template
    /// validates (`isValidEmail`) + guards re-entrancy before handing off to core,
    /// so an invalid address never reaches the network. No-op for demo instances
    /// (no bound template).
    public func submitClaim(for winner: LBWinner, email: String) {
        template?.winClaim.submit(winner: winner, email: email)
    }

    /// Forward「關閉領獎畫面」to the bound template
    /// (`DefaultWinClaim.dismissClaim()` — clears `resultState` + `submitInFlight`).
    ///
    /// 🔴 這是**純 dismiss**：MUST NOT 從 `unclaimedWinners` 移除該 winner、MUST NOT
    /// 呼叫任何 API、MUST NOT 遞減未領徽章 —— 使用者可以再次開啟領取。設計稿的
    /// 「放棄資格、此動作無法復原」是**刻意的 UX 摩擦文案**，行為不跟隨（權威：
    /// `design/contract/claude-design-sync.md` R13 刻意分歧 1/2）。
    /// No-op for demo instances (no bound template).
    public func dismissClaim() {
        template?.winClaim.dismissClaim()
    }

    /// EMAIL-LESS 領獎轉發 —— **DEPRECATED**，只為源碼相容保留。
    ///
    /// 它走 `DefaultWinClaim.submit(winner:)`（contact 恆 nil），而 core 預設領獎路徑
    /// `email` 必填，故未被 host 攔截時**必然失敗**（core fail-fast、連
    /// `POST /sdk/video/claim` 都不送）。請改用 `submitClaim(for:email:)`。
    ///
    /// （標為 deprecated 亦使其內部對 deprecated template 入口的呼叫不再產生警告。）
    @available(*, deprecated, renamed: "submitClaim(for:email:)", message: "EMAIL-LESS 領獎未被 host 攔截時必然失敗（core 預設領獎路徑 email 必填）。改用 submitClaim(for:email:)。")
    public func submitClaim(for winner: LBWinner) {
        template?.winClaim.submit(winner: winner)
    }

    /// Forward an「加入活動」intent for an event-join feed row to the bound template
    /// (`joinEvent(eid:keyword:)` → core `requestEventJoin` + optimistic `markJoined`).
    ///
    /// rb-ios-event-join-gate: consult the drop-in container's injected three-tier gate FIRST
    /// (login / nickname / proceed, sharing the 留言 pill's pure predicates). `true` → the gate
    /// INTERCEPTED the intent (raised a login / nickname modal) → this method MUST NOT forward
    /// (MUST NOT join / `markJoined`). `nil` gate (demo / snapshot instances) → NO gating, forward
    /// as before (baseline byte-identical). No-op for demo instances (no bound template).
    public func joinEvent(eid: Int, keyword: String) {
        if joinEventGate?(eid, keyword) == true { return }
        template?.joinEvent(eid: eid, keyword: keyword)
    }

    /// Forward「加入活動」DIRECTLY to the bound template, **BYPASSING `joinEventGate`**. The drop-in
    /// container's `onNicknameSubmit` continuation calls this after a guest sets a nickname to
    /// complete the ONE join the nickname gate deferred (rb-ios-event-join-gate). It bypasses the
    /// gate deliberately: the guest just satisfied the nickname requirement, but `displayName`
    /// refreshes ASYNCHRONOUSLY (template `onChange` → a later runloop), so re-running the gate here
    /// could still read an empty name and wrongly re-present the nickname modal. Mirrors the 留言
    /// pill's「set nickname → open composer directly」continuation (no re-gate). The container clears
    /// the pending intent (`NicknamePromptController.dismiss()`) before calling, so this sends EXACTLY
    /// ONCE. No-op for demo instances (no bound template). Container-internal continuation seam.
    func forwardJoinEventBypassingGate(eid: Int, keyword: String) {
        template?.joinEvent(eid: eid, keyword: keyword)
    }

    // MARK: - Presentation classification (read-only)
    //
    // `LBAwardPresentation.init(awardType:)` is INTERNAL to the template layer, so
    // reference-ui cannot construct it directly. The public classifier is the
    // template's `DefaultWinClaim.awardPresentation(for:)`. When a live template is
    // bound we route through it (single source of the mapping); for demo instances
    // (no template) we derive the SAME classification from the public
    // `winner.award.type` ("discount" → .discount, else .product) so the claim
    // sheet still classifies correctly in previews / snapshot tests.

    /// CTA classification for `winner` (`.product`「查看獎品」/ `.discount`「立即使用」).
    public func presentation(for winner: LBWinner) -> LBAwardPresentation {
        if let template = template {
            return template.winClaim.awardPresentation(for: winner)
        }
        // Demo fallback — identical rule to the template's internal classifier.
        return (winner.award.type == "discount") ? .discount : .product
    }

    // MARK: - Convenience reads (surface helpers, pure)

    /// The earliest unclaimed winner the entry should open the sheet on, or nil
    /// when there is nothing to claim (`unclaimedCount == 0`).
    public var nextUnclaimedWinner: LBWinner? { unclaimedWinners.first }
}
