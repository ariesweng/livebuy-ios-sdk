import LivebuySDK

// MARK: - DefaultPlayerChrome — OperationPanel side-rail + VideoInfoPanel info-tab
//
// Spec: `ui-template-foundation/spec.md`
//   § "Default Template OperationPanel Side-Rail 狀態暴露"
//   § "Default Template VideoInfoPanel Info-Tab 與分頁切換狀態暴露"
//   § "Default Template Bindable State 變更通知" (MODIFIED — side-rail / info-tab)
// Design: player-chrome-template design.md D2 / D4 / D5 / D6.
//
// Behaviour / view-model layer ONLY (no pixels). core stays headless: it owns the
// 10 `simulate*` exits, the like 250ms throttle, the `VIDEO_LIKE` API-success
// notification, the `channel` data + subscribe API. These models EXPOSE the
// presentation state (side-rail item enablement / bag-count / heart-burst tick /
// muted; info-tab fields + two-tab switching) so the host can draw the side rail
// (`LBLiveBottomBar` / `LBPSideRail`) and the info sheet (`LBPSheetHeader`).
//
// Each model mirrors `DefaultMomentStates` / `DefaultNoticeTab`: PUBLIC read
// surface (`private(set) public var`), an INTERNAL coalesced `onMutation` hook
// (the host observes the owning template's single `onChange`, never the model),
// and INTERNAL mutators that DIFF-then-notify (fire `onMutation` exactly once per
// REAL change — never on an unchanged re-feed, e.g. the 5s products poll).

// MARK: - OperationPanel side-rail (D2)

/// Side-rail action kinds — the subset of core's existing `simulate*` exits that
/// `LBLiveBottomBar` / `LBPSideRail` surface. The ORDER of `DefaultOperationRail
/// .items` follows the design's bottom-bar order (goods / chat / like / share /
/// subtitle / serviceLink / guestNameEdit / more). The template MUST NOT add a
/// `kind` for an action core does not already expose.
public enum LBSideRailKind: Equatable {
    case goods
    case chat
    case like
    case share
    case subtitle
    case serviceLink
    case guestNameEdit
    case more
}

/// One host-bindable side-rail action item. `enabled` is DERIVED from existing
/// reachable flags (never stored independently of the rail's enablement feed).
/// The host draws the button for `kind` and dims it when `!enabled`; the actual
/// action goes through the matching core `simulate*` (the rail does NOT carry the
/// action — it is presentation state only).
public struct LBSideRailItem: Equatable {
    public let kind: LBSideRailKind
    public let enabled: Bool

    public init(kind: LBSideRailKind, enabled: Bool) {
        self.kind = kind
        self.enabled = enabled
    }
}

/// Side-rail / bottom-bar view-model. Exposes the ordered action items with
/// derived `enabled`, the bag-count badge, a monotonic heart-burst tick, and the
/// mute gesture state. The actual taps go through the core's existing `simulate*`
/// exits — this model is presentation state only (D2).
public final class DefaultOperationRail {

    /// Ordered side-rail action items `{ kind, enabled }`. `goods` / `like` /
    /// `share` / `more` are ALWAYS enabled; `chat` / `subtitle` / `serviceLink` /
    /// `guestNameEdit` derive their `enabled` from the latest enablement feed.
    private(set) public var items: [LBSideRailItem] = DefaultOperationRail.defaultItems

    /// Bag badge count — equals the current product list length (derived from the
    /// ProductOverlay view-model's `products.count`; the template MUST NOT store a
    /// second copy of products).
    private(set) public var bagCount: Int = 0

    /// MONOTONIC heart-burst counter, +1 each time a core `VIDEO_LIKE` (like API
    /// actually succeeded) arrives. The host observes its increase to play the
    /// heart-burst animation. The template MUST NOT draw the animation and MUST
    /// NOT call like itself (real like = `simulateLikeTap` + core 250ms throttle).
    private(set) public var heartBurstTick: Int = 0

    /// Mute gesture state, mirrored from the PlayerHeader mute source (single
    /// truth — `DefaultPlayerTemplate` feeds both from the same `handleMuted`).
    private(set) public var muted: Bool = false  // unmuted by default (sound on)

    // Cached enablement inputs so `goods`/`like`/`share`/`more` stay constant and
    // only the conditional kinds rebuild from the latest flags.
    //
    // `chatEnabled` (= `liveStatus == 1 && guest_comment == 1`, "LIVE 留言對所有訪客開放") is
    // host-bindable read-only state (ui-template-foundation): reference-ui reads it to gate the
    // LIVE「留言」pill to a「請先登入」modal when a guest taps it on a `guest_comment == 0` live
    // (rb-ios-live-comment-login-gate). It mirrors the `.chat` side-rail item's `enabled` flag
    // (same value, same `handleEnablement` maintenance + `onChange` notify) — exposing it here
    // changes NO behaviour (the rail items are unchanged).
    private(set) public var chatEnabled = false
    private var subtitleAvailable = false
    private var serviceLinkAvailable = false
    private var guestEditAvailable = false

    var onMutation: (() -> Void)?

    init() {}

    /// The action items as they appear with all conditional kinds disabled (the
    /// pre-channel default; `goods`/`like`/`share`/`more` already enabled).
    private static let defaultItems: [LBSideRailItem] = [
        LBSideRailItem(kind: .goods, enabled: true),
        LBSideRailItem(kind: .chat, enabled: false),
        LBSideRailItem(kind: .like, enabled: true),
        LBSideRailItem(kind: .share, enabled: true),
        LBSideRailItem(kind: .subtitle, enabled: false),
        LBSideRailItem(kind: .serviceLink, enabled: false),
        LBSideRailItem(kind: .guestNameEdit, enabled: false),
        LBSideRailItem(kind: .more, enabled: true),
    ]

    // MARK: - Enablement feed (D2)

    /// Feed the derived enablement flags for the conditional kinds. `goods` /
    /// `like` / `share` / `more` stay ALWAYS enabled. Diff-then-notify on the
    /// resulting `items` so an unchanged re-feed is a no-op.
    func handleEnablement(chatEnabled: Bool, subtitleAvailable: Bool,
                          serviceLinkAvailable: Bool, guestEditAvailable: Bool) {
        guard chatEnabled != self.chatEnabled
            || subtitleAvailable != self.subtitleAvailable
            || serviceLinkAvailable != self.serviceLinkAvailable
            || guestEditAvailable != self.guestEditAvailable else { return }
        self.chatEnabled = chatEnabled
        self.subtitleAvailable = subtitleAvailable
        self.serviceLinkAvailable = serviceLinkAvailable
        self.guestEditAvailable = guestEditAvailable
        items = [
            LBSideRailItem(kind: .goods, enabled: true),
            LBSideRailItem(kind: .chat, enabled: chatEnabled),
            LBSideRailItem(kind: .like, enabled: true),
            LBSideRailItem(kind: .share, enabled: true),
            LBSideRailItem(kind: .subtitle, enabled: subtitleAvailable),
            LBSideRailItem(kind: .serviceLink, enabled: serviceLinkAvailable),
            LBSideRailItem(kind: .guestNameEdit, enabled: guestEditAvailable),
            LBSideRailItem(kind: .more, enabled: true),
        ]
        onMutation?()
    }

    /// Bag badge count = product list length. Diff-then-notify.
    func handleBagCount(_ count: Int) {
        guard count != bagCount else { return }
        bagCount = count
        onMutation?()
    }

    /// A core `VIDEO_LIKE` (like API success) arrived → bump the heart-burst tick.
    /// ALWAYS notifies (a burst is a discrete event, not a diff'd value).
    func handleLikePerformed() {
        heartBurstTick += 1
        onMutation?()
    }

    /// Mirror the player mute flag (same source as PlayerHeader). Diff-then-notify.
    func handleMuted(_ muted: Bool) {
        guard muted != self.muted else { return }
        self.muted = muted
        onMutation?()
    }
}

// MARK: - VideoInfoPanel info-tab + two-tab switching (D4)

/// The two VideoInfoPanel tabs. `info` is the「直播資訊」tab (always selectable);
/// `notice` is the existing公告 tab (selectable only when the notice-tab `canOpen`).
public enum LBInfoPanelTab: Equatable {
    case info
    case notice
}

/// One host-bindable info-tab snapshot. EXCLUDES `description` — `LBChannel` has
/// no such field, and depending on it would force a core split (player-chrome-
/// template design §reachability). `isSubscribed` is NOT stored here — it mirrors
/// the SAME truth as PlayerHeader / moment-state and is supplied at read time.
public struct LBInfoTabState: Equatable {
    public let title: String
    public let publishAt: String
    public let shopName: String
    public let shopIntro: String
    public let shopLogo: String
    public let isSubscribed: Bool

    public init(title: String, publishAt: String, shopName: String,
                shopIntro: String, shopLogo: String, isSubscribed: Bool) {
        self.title = title
        self.publishAt = publishAt
        self.shopName = shopName
        self.shopIntro = shopIntro
        self.shopLogo = shopLogo
        self.isSubscribed = isSubscribed
    }
}

/// VideoInfoPanel info-tab + two-tab switching view-model. Exposes the info-tab
/// fields (from public `channel`), the active tab, and the `selectTab` intent.
/// `isSubscribed` is NOT stored here — `DefaultPlayerTemplate` supplies the SAME
/// `header.isSubscribed` truth via `isSubscribedProvider` so the two views never
/// diverge (D4 / R2). The notice tab's selectability is governed by an injected
/// `canOpenNotice` so this model can react to the notice-tab `canOpen` without
/// owning a second copy of the notice texts (D4 / R4).
public final class DefaultInfoTab {

    private(set) public var title: String = ""
    private(set) public var publishAt: String = ""
    private(set) public var shopName: String = ""
    private(set) public var shopIntro: String = ""
    private(set) public var shopLogo: String = ""

    /// Currently selected tab. Initial `info` (always selectable).
    private(set) public var activeTab: LBInfoPanelTab = .info

    /// SAME-truth subscribe mirror — supplied by the owning template (reads
    /// `header.isSubscribed`). nil → `false` (pre-attach). NOT stored here (R2).
    var isSubscribedProvider: (() -> Bool)?

    /// Whether the notice tab may currently be selected — supplied by the owning
    /// template (reads `noticeTab.canOpen`). nil → `false` (notice un-selectable).
    var canOpenNoticeProvider: (() -> Bool)?

    var onMutation: (() -> Void)?

    init() {}

    /// Whether the notice tab is currently selectable (derived from the injected
    /// provider; never stored).
    private var canOpenNotice: Bool { canOpenNoticeProvider?() ?? false }

    /// Host-bindable info-tab snapshot. `isSubscribed` reads the SAME truth as
    /// PlayerHeader / moment-state at read time (never a stored, divergent copy).
    public var current: LBInfoTabState {
        LBInfoTabState(title: title, publishAt: publishAt, shopName: shopName,
                       shopIntro: shopIntro, shopLogo: shopLogo,
                       isSubscribed: isSubscribedProvider?() ?? false)
    }

    // MARK: - Info-tab field feed (D4) — from public `channel`

    /// Feed the info-tab fields from the public `channel` (read once loaded;
    /// idempotent — re-feeding identical values is a no-op). Diff-then-notify on
    /// the field tuple so a single channel load fires `onMutation` at most once.
    func handleInfo(title: String, publishAt: String, shopName: String,
                    shopIntro: String, shopLogo: String) {
        guard title != self.title || publishAt != self.publishAt
            || shopName != self.shopName || shopIntro != self.shopIntro
            || shopLogo != self.shopLogo else { return }
        self.title = title
        self.publishAt = publishAt
        self.shopName = shopName
        self.shopIntro = shopIntro
        self.shopLogo = shopLogo
        onMutation?()
    }

    // MARK: - Two-tab switching (D4)

    /// Select a tab. `info` is ALWAYS selectable. `notice` is selectable ONLY when
    /// the notice-tab `canOpen == true`; otherwise this is a NO-OP (activeTab kept
    /// unchanged). Diff-then-notify (selecting the already-active tab is a no-op).
    public func selectTab(_ tab: LBInfoPanelTab) {
        let resolved: LBInfoPanelTab
        switch tab {
        case .info:   resolved = .info
        case .notice: resolved = canOpenNotice ? .notice : activeTab   // no-op when un-selectable
        }
        guard resolved != activeTab else { return }
        activeTab = resolved
        onMutation?()
    }

    /// Called when the notice-tab `canOpen` may have changed (texts injected). If
    /// the active tab is `notice` and it is no longer selectable (公告轉空), auto-
    /// fall-back to `info` (avoids resting in an illegal un-selectable tab, D4 /
    /// R4). Notifies iff the active tab actually changed.
    func reconcileActiveTab() {
        guard activeTab == .notice, !canOpenNotice else { return }
        activeTab = .info
        onMutation?()
    }
}
