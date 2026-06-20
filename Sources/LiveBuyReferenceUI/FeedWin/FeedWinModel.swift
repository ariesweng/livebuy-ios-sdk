import SwiftUI
import Combine
import LiveBuySDK
import LiveBuyUI

// MARK: - FeedWinModel — family-2 feed + win observable snapshot bridge
//
// Spec: `reference-ui-rendering/spec.md` (family-2 feed-win, 3 surfaces)
// Design: rb-ios-feed-win design.md D-1 / D-2 / D-3 / D-4.
//
// This is the SKELETON for rb-ios-feed-win. It bridges the headless template
// view-models exposed by `DefaultPlayerTemplate` (obtained via
// `LiveBuyUI.playerTemplate(for:)`) into a SwiftUI-observable snapshot that the
// three family-2 surface sub-views read. It is a read-only mirror — IDENTICAL
// pattern to `PlayerShellModel` (family-1):
//
//   - It does NOT own a second copy of authoritative state — it republishes
//     SNAPSHOT VALUES taken from the template's own `private(set) public` reads
//     (`activityFeed.items` / `winClaim.unclaimedCount` /
//     `winClaim.unclaimedWinners` / `winClaim.resultState`) each time the
//     template fires its single coalesced `onChange` (D-1).
//   - It does NOT add pixels and it does NOT add any accessor to `LiveBuyUI`
//     (that would be a template-layer concern, out of scope here).
//   - It does NOT subscribe to the feed / winClaim internal `onMutation`
//     (that is a template-internal hook); it observes ONLY the template's single
//     public `onChange` (design §"容器與 view-model 橋接").
//   - The ONLY mutating interaction this layer carries is the win-claim submit,
//     which goes through the existing template exit `submitClaim(for:)` →
//     `DefaultWinClaim.submit(winner:)` (internally core
//     `requestAwardClaim(winner, nil)` — EMAIL-LESS, contact always nil). The
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

    // MARK: - Live binding

    /// The bound template, when constructed from a live player. nil for demo /
    /// snapshot instances. Held weakly so this model never retains the template
    /// (the player VC owns it; dependency stays one-way UI → core).
    private weak var template: DefaultPlayerTemplate?

    /// The template's `onChange` we installed, so we can restore the previous one
    /// on deinit (we chain rather than clobber — same as `PlayerShellModel`).
    private var previousOnChange: (() -> Void)?

    // MARK: - Live initializer (D-1)

    /// Bridge a live `DefaultPlayerTemplate`: take an initial snapshot and
    /// subscribe to its single coalesced `onChange` so every feed append / win
    /// record / claim result re-snapshots and republishes to the surface sub-views.
    ///
    /// The host obtains the template via `LiveBuyUI.playerTemplate(for:)` and
    /// passes it here. Returns a model whose published values mirror the template
    /// (read-only). The previous `onChange` (if any host already installed one) is
    /// chained, not replaced.
    public convenience init(template: DefaultPlayerTemplate) {
        self.init(snapshotting: template)
        self.template = template
        self.previousOnChange = template.onChange
        template.onChange = { [weak self] in
            self?.previousOnChange?()
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
            pinned: t.pinnedMessage
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
        pinned: LBPinnedMessage? = nil
    ) {
        self.feedItems = feedItems
        self.feedHistory = feedHistory
        self.unclaimedCount = unclaimedCount
        self.unclaimedWinners = unclaimedWinners
        self.resultState = resultState
        self.pinned = pinned
    }

    deinit {
        // Restore the previous handler so a re-bound template is not left with a
        // dangling closure capturing this (now gone) model.
        template?.onChange = previousOnChange
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
    }

    // MARK: - Read-only host intents (pass-through to the bound template)
    //
    // The feed-win layer does NOT carry actions. These are thin forwarders for the
    // template-owned intents the family-2 surfaces need that have no direct core
    // `simulate*` equivalent reachable here:
    //
    //   • `submitClaim(for:)` — the EMAIL-LESS win-claim submit (the one true
    //     mutating interaction of this family). It forwards to
    //     `DefaultWinClaim.submit(winner:)`, which internally calls core
    //     `requestAwardClaim(winner, nil)` (contact ALWAYS nil). The result then
    //     arrives via the template's `awardClaimResult` → `onChange` → `refresh`.
    //   • `joinEvent(eid:keyword:)` — the「加入活動」intent for an event-join feed
    //     row. It forwards to the template's `joinEvent` (core
    //     `requestEventJoin` + optimistic `markJoined`). The design notes this is
    //     a host-wired upstream exit; the forwarder is provided so the container's
    //     event-join CTA has a single funnel, but a host that takes over the
    //     intent itself can ignore it. No-op for demo instances (no template).

    /// Forward an EMAIL-LESS win claim to the bound template (template exit
    /// `DefaultWinClaim.submit(winner:)`, internally `requestAwardClaim(winner,
    /// nil)`). No-op for demo instances (no bound template).
    public func submitClaim(for winner: LBWinner) {
        template?.winClaim.submit(winner: winner)
    }

    /// Forward an「加入活動」intent for an event-join feed row to the bound template
    /// (`joinEvent(eid:keyword:)` → core `requestEventJoin` + optimistic
    /// `markJoined`). No-op for demo instances (no bound template).
    public func joinEvent(eid: Int, keyword: String) {
        template?.joinEvent(eid: eid, keyword: keyword)
    }

    /// Forward a 商品開賣卡「立即搶購」intent (問題5) to the bound template
    /// (`openProductSaleByName(_:)` → resolve the 商品名 in `channel.goods` → open that product's
    /// detail sheet). No-op for demo instances (no bound template) / unmatched names.
    public func openSaleProduct(name: String) {
        template?.openProductSaleByName(name)
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
