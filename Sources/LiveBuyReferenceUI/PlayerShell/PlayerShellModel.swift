import SwiftUI
import Combine
import LiveBuySDK
import LiveBuyUI

// MARK: - PlayerShellModel — family-1 player-shell observable snapshot bridge
//
// Spec: `reference-ui-rendering/spec.md` (family-1 player-shell, 4 surfaces)
// Design: rb-ios-player-shell design.md D-1 / D-4 / D-7.
//
// This is the SKELETON for rb-ios-player-shell. It bridges the headless template
// view-models exposed by `DefaultPlayerTemplate` (obtained via
// `LiveBuyUI.playerTemplate(for:)`) into a SwiftUI-observable snapshot that the
// four family-1 surface sub-views read. It is a read-only mirror:
//
//   - It does NOT own a second copy of authoritative state — it republishes
//     SNAPSHOT VALUES taken from the template's own `private(set) public` reads
//     each time the template fires its single coalesced `onChange` (D-1).
//   - It does NOT add pixels and it does NOT add any accessor to `LiveBuyUI`
//     (that would be a template-layer concern, out of scope here — D-4).
//   - Interactions stay in core's existing `simulate*` exits; this layer only
//     reads. Optional action closures the surface sub-views accept are wired by
//     the host, NOT by this model.
//
// iOS-14-safe: `ObservableObject` + `@Published` are available from iOS 13, so
// no `@available` guard is needed here.

/// Observable snapshot of the family-1 player-shell state, republished from a
/// live `DefaultPlayerTemplate` (or constructed deterministically for demos /
/// snapshot tests via the memberwise initializer).
public final class PlayerShellModel: ObservableObject {

    // MARK: - Published surface snapshots
    //
    // Each group is the read-only value set ONE family-1 surface sub-view needs.
    // The grouping intentionally mirrors the four surfaces so a surface sub-view
    // binds exactly one snapshot value (see the documented sub-view input
    // pattern at the bottom of this file).

    // -- Surface 1: PlayerHeaderBarView ← header chrome ------------------------

    /// Top-bar host-pill title (`DefaultPlayerHeaderState.title`).
    @Published public private(set) var title: String
    /// Host / shop name (`DefaultPlayerHeaderState.hostName`).
    @Published public private(set) var hostName: String
    /// Host pill / top-bar logo URL (`DefaultPlayerHeaderState.shopLogo`).
    @Published public private(set) var shopLogo: String
    /// Live viewer count (`DefaultPlayerHeaderState.viewerCount`).
    @Published public private(set) var viewerCount: Int
    /// Subscribe badge state (`DefaultPlayerHeaderState.isSubscribed`).
    @Published public private(set) var isSubscribed: Bool
    /// Share action context URL (`DefaultPlayerHeaderState.shareUrl`).
    @Published public private(set) var shareUrl: String

    // -- Surface 2: OperationRailView ← side-rail ------------------------------

    /// Ordered side-rail action items (`DefaultOperationRail.items`).
    @Published public private(set) var railItems: [LBSideRailItem]
    /// Shopping-bag badge count (`DefaultOperationRail.bagCount`); >0 → draw badge.
    @Published public private(set) var bagCount: Int
    /// Monotonic heart-burst tick (`DefaultOperationRail.heartBurstTick`); observe
    /// its INCREASE to play the heart-burst animation — this layer never calls like.
    @Published public private(set) var heartBurstTick: Int

    // -- Surface 1 + 2 shared: mute --------------------------------------------

    /// Mute gesture state (single truth — `header.muted` == `operationRail.muted`,
    /// both fed from the template's same `handleMuted`). Auto-muted (true) at start.
    @Published public private(set) var muted: Bool

    /// LIVE vs VOD flag (`DefaultPlayerHeaderState.isLive`, channel-derived). The
    /// header branches chrome on it (LIVE pill + viewer count only when live).
    @Published public private(set) var isLive: Bool

    // -- VOD playback progress (DefaultPlaybackProgressState, VOD-2) ------------

    /// Current playhead, seconds (VOD progress bar / timestamp).
    @Published public private(set) var position: Double
    /// Total duration, seconds (0 for live).
    @Published public private(set) var duration: Double
    /// Whether the stream is playing (VOD play/pause icon).
    @Published public private(set) var isPlaying: Bool
    /// LIVE stream scrubbed behind the live edge (`liveStatus == 1`).
    @Published public private(set) var isReplay: Bool

    /// Subtitle (CC) currently enabled — gates the VOD caption overlay.
    @Published public private(set) var subtitleEnabled: Bool

    // -- Upcoming (直播預告 awaitingLive) chrome state (DefaultUpcomingState) -------

    /// Whether the player is in the awaiting-live sub-state (`DefaultUpcomingState.active`).
    /// `true` → the shell composes the upcoming LIVE chrome (cover + date/time background +
    /// slim bottom bar), not the LIVE / VOD chrome.
    @Published public private(set) var isUpcoming: Bool
    /// Whether the UPCOMING video's opening video (intro MP4) is playing
    /// (`DefaultUpcomingState.introPlaying`). `true` → the shell wears the LIVE chrome
    /// (header + slim bottom bar) over the PLAYING opening video — but does NOT draw the
    /// `UpcomingCountdownView` countdown (that is `isUpcoming` / awaitingLive only). A VOD's
    /// intro keeps this `false` → VOD chrome. Mutually exclusive with `isUpcoming`.
    @Published public private(set) var introPlaying: Bool
    /// Scheduled start (`DefaultUpcomingState.scheduledStartAt` / backend `publish_at`),
    /// parsed by the upcoming surface for the date + time display.
    @Published public private(set) var upcomingStartAt: String
    /// Video cover URL (`DefaultUpcomingState.cover` / backend `channel.cover`) — the
    /// upcoming surface's full-bleed background.
    @Published public private(set) var upcomingCover: String

    // -- Start lifecycle (開場 loading / buffering / splash) state ----------------

    /// The start-lifecycle phase (`DefaultStartScreenState.phase`): `.loading` 全螢幕品牌
    /// 載入 / `.buffering` 內容上方輕量指示 / `.splash` 開場影片輕量 skip overlay / `.done` 不畫.
    /// `startPhase != .done` → the container composes the `StartScreenView` start-lifecycle
    /// surface over the subject chrome. Decoupled from the moments family
    /// (rb-ios-start-screen-out-of-moments): the opening is a player-shell concern, NOT a
    /// moment — `MomentsModel` / `MomentsOverlayView` no longer carry it.
    @Published public private(set) var startPhase: LBStartScreenPhase

    // -- Swipe navigation (DefaultPlayerNavigation, swipe-navigate-template) ----

    /// Previous adjacent video id (`DefaultPlayerNavigation.prevVideoId`,
    /// channel-derived). nil → no previous video; the vertical swipe-DOWN gesture
    /// no-ops via `navigateToPrev()`'s template forwarder.
    @Published public private(set) var prevVideoId: String?
    /// Next adjacent video id (`DefaultPlayerNavigation.nextVideoId`,
    /// channel-derived). nil → no next video; the vertical swipe-UP gesture no-ops
    /// via `navigateToNext()`'s template forwarder.
    @Published public private(set) var nextVideoId: String?

    // -- Surface 3: VideoInfoPanelView ← info-tab + notice-tab -----------------

    /// Info-tab snapshot (`DefaultInfoTab.current` — `LBInfoTabState`).
    @Published public private(set) var infoTab: LBInfoTabState
    /// Currently selected info-panel tab (`DefaultInfoTab.activeTab`).
    @Published public private(set) var activeTab: LBInfoPanelTab
    /// Whether the 公告 (notice) tab is selectable (`DefaultNoticeTab.canOpen`).
    @Published public private(set) var canOpenNotice: Bool
    /// System notice text (`DefaultNoticeTab.systemNotice`).
    @Published public private(set) var systemNotice: String
    /// Notice text (`DefaultNoticeTab.notice`).
    @Published public private(set) var notice: String

    // -- Surface 4: LiveOverlayChromeView ← moment + chrome --------------------

    /// Announce marquee text for `LBLiveAnnounce` — REACHABLE source is the
    /// notice-tab `notice` text (announce / pinned announcement). See GAP NOTE.
    @Published public private(set) var announceText: String
    /// Pinned-product card source (`LBLivePinnedCard`). Derived as the narrating product
    /// (`DefaultProductOverlayState.activeProduct`, `narrate_status == 2`) when present,
    /// ELSE the first `is_hot == 1` product — per component-contracts §ProductOverlay
    /// 推播卡 trigger (is_hot OR narrate_status==2). nil → no pinned card. The「介紹中」
    /// tag on the card stays gated on `narrate_status == 2` (LiveOverlayChromeView), so an
    /// is_hot-only product shows the card WITHOUT that tag.
    @Published public private(set) var pinnedProduct: LBProduct?
    /// VOD「目前介紹中商品」card source — the product whose `[beginTime,endTime)`
    /// window contains the playhead (`DefaultPlayerTemplate.vodActiveProduct`). nil →
    /// no VOD product card. Distinct from `pinnedProduct` (LIVE narrate_status==2).
    @Published public private(set) var vodActiveProduct: LBProduct?
    /// ALL VOD now-introducing products — every product whose `[beginTime,endTime)` window
    /// contains the playhead (`DefaultPlayerTemplate.vodActiveProducts`, beginTime ascending).
    /// Feeds the now-introducing carousel (rb-ios-now-introducing-real-image-carousel, 問題 10).
    /// Empty → no VOD product card.
    @Published public private(set) var vodActiveProducts: [LBProduct]

    // -- Identity (DefaultIdentityLabel, AUTH_STATE_CHANGED) --------------------

    /// Whether the user currently has a set identity / display name
    /// (`template.identityLabel.current?.isLoggedIn`). A guest who has NOT set a
    /// 留言暱稱 reads `false`; a guest who sets one via the nickname modal (→
    /// `LiveBuy.setUser`) and a genuinely logged-in user both read `true`. The
    /// drop-in container uses this to gate the 留言 pill (未設定 → 先引導設定暱稱).
    @Published public private(set) var isLoggedIn: Bool
    /// Current resolved display name (`template.identityLabel.current?.displayName`)
    /// — the nickname modal's prefill / context. Empty when no identity has been set.
    @Published public private(set) var displayName: String
    /// Whether LIVE comments are open to all guests on this channel
    /// (`template.operationRail.chatEnabled` = `liveStatus == 1 && guest_comment == 1`). The
    /// drop-in container reads this to gate the 留言 pill to a「請先登入」modal when a guest taps it
    /// on a `guest_comment == 0` live (`chatEnabled == false`) — rb-ios-live-comment-login-gate.
    /// Default `false` (pre-channel / non-live); set true once a live + open-comments channel loads.
    @Published public private(set) var chatEnabled: Bool

    // MARK: - Live binding

    /// The bound template, when constructed from a live player. nil for demo /
    /// snapshot instances. Held weakly so this model never retains the template
    /// (the player VC owns it; dependency stays one-way UI → core).
    private weak var template: DefaultPlayerTemplate?

    /// The template's `onChange` we installed, so we can restore the previous one
    /// on deinit (we chain rather than clobber).
    private var previousOnChange: (() -> Void)?

    // MARK: - Live initializer (D-1)

    /// Bridge a live `DefaultPlayerTemplate`: take an initial snapshot and
    /// subscribe to its single coalesced `onChange` so every state change
    /// re-snapshots and republishes to the surface sub-views.
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
            title: t.header.title,
            hostName: t.header.hostName,
            shopLogo: t.header.shopLogo,
            viewerCount: t.header.viewerCount,
            isSubscribed: t.header.isSubscribed,
            shareUrl: t.header.shareUrl,
            railItems: t.operationRail.items,
            bagCount: t.operationRail.bagCount,
            heartBurstTick: t.operationRail.heartBurstTick,
            muted: t.header.muted,
            isLive: t.header.isLive,
            position: t.playbackProgress.position,
            duration: t.playbackProgress.duration,
            isPlaying: t.playbackProgress.isPlaying,
            isReplay: t.playbackProgress.isReplay,
            subtitleEnabled: t.subtitle.enabled,
            isUpcoming: t.upcoming.active,
            introPlaying: t.upcoming.introPlaying,
            startPhase: t.startScreen.phase,
            upcomingStartAt: t.upcoming.scheduledStartAt,
            upcomingCover: t.upcoming.cover,
            prevVideoId: t.navigation.prevVideoId,
            nextVideoId: t.navigation.nextVideoId,
            infoTab: t.infoTab.current,
            activeTab: t.infoTab.activeTab,
            canOpenNotice: t.noticeTab.canOpen,
            systemNotice: t.noticeTab.systemNotice,
            notice: t.noticeTab.notice,
            announceText: t.noticeTab.notice,
            pinnedProduct: Self.derivePinnedProduct(t.productOverlay),
            vodActiveProduct: t.vodActiveProduct,
            vodActiveProducts: t.vodActiveProducts,
            isLoggedIn: t.identityLabel.current?.isLoggedIn ?? false,
            displayName: t.identityLabel.current?.displayName ?? ""
        )
    }

    // MARK: - Memberwise / demo initializer (D-1)

    /// Construct a deterministic instance WITHOUT a live player — for the surface
    /// sub-views' previews and the per-surface snapshot tests. Every value
    /// defaults to the at-attach seed (auto-muted, empty chrome, default rail
    /// items) so a zero-argument call yields a stable baseline.
    public init(
        title: String = "",
        hostName: String = "",
        shopLogo: String = "",
        viewerCount: Int = 0,
        isSubscribed: Bool = false,
        shareUrl: String = "",
        railItems: [LBSideRailItem] = PlayerShellModel.defaultRailItems,
        bagCount: Int = 0,
        heartBurstTick: Int = 0,
        muted: Bool = true,
        isLive: Bool = false,
        position: Double = 0,
        duration: Double = 0,
        isPlaying: Bool = false,
        isReplay: Bool = false,
        subtitleEnabled: Bool = false,
        isUpcoming: Bool = false,
        introPlaying: Bool = false,
        startPhase: LBStartScreenPhase = .loading,
        upcomingStartAt: String = "",
        upcomingCover: String = "",
        prevVideoId: String? = nil,
        nextVideoId: String? = nil,
        infoTab: LBInfoTabState = PlayerShellModel.emptyInfoTab,
        activeTab: LBInfoPanelTab = .info,
        canOpenNotice: Bool = false,
        systemNotice: String = "",
        notice: String = "",
        announceText: String = "",
        pinnedProduct: LBProduct? = nil,
        vodActiveProduct: LBProduct? = nil,
        vodActiveProducts: [LBProduct]? = nil,
        isLoggedIn: Bool = false,
        displayName: String = "",
        chatEnabled: Bool = false
    ) {
        self.title = title
        self.hostName = hostName
        self.shopLogo = shopLogo
        self.viewerCount = viewerCount
        self.isSubscribed = isSubscribed
        self.shareUrl = shareUrl
        self.railItems = railItems
        self.bagCount = bagCount
        self.heartBurstTick = heartBurstTick
        self.muted = muted
        self.isLive = isLive
        self.position = position
        self.duration = duration
        self.isPlaying = isPlaying
        self.isReplay = isReplay
        self.subtitleEnabled = subtitleEnabled
        self.isUpcoming = isUpcoming
        self.introPlaying = introPlaying
        self.startPhase = startPhase
        self.upcomingStartAt = upcomingStartAt
        self.upcomingCover = upcomingCover
        self.prevVideoId = prevVideoId
        self.nextVideoId = nextVideoId
        self.infoTab = infoTab
        self.activeTab = activeTab
        self.canOpenNotice = canOpenNotice
        self.systemNotice = systemNotice
        self.notice = notice
        self.announceText = announceText
        self.pinnedProduct = pinnedProduct
        self.vodActiveProduct = vodActiveProduct
        // Back-compat: callers passing only `vodActiveProduct` (e.g. existing snapshot tests)
        // get a single-element list; the live snapshot path passes the full plural.
        self.vodActiveProducts = vodActiveProducts ?? [vodActiveProduct].compactMap { $0 }
        self.isLoggedIn = isLoggedIn
        self.displayName = displayName
        self.chatEnabled = chatEnabled
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
        title = t.header.title
        hostName = t.header.hostName
        shopLogo = t.header.shopLogo
        viewerCount = t.header.viewerCount
        isSubscribed = t.header.isSubscribed
        shareUrl = t.header.shareUrl

        railItems = t.operationRail.items
        bagCount = t.operationRail.bagCount
        heartBurstTick = t.operationRail.heartBurstTick
        muted = t.header.muted
        isLive = t.header.isLive
        position = t.playbackProgress.position
        duration = t.playbackProgress.duration
        isPlaying = t.playbackProgress.isPlaying
        isReplay = t.playbackProgress.isReplay
        subtitleEnabled = t.subtitle.enabled
        isUpcoming = t.upcoming.active
        introPlaying = t.upcoming.introPlaying
        startPhase = t.startScreen.phase
        upcomingStartAt = t.upcoming.scheduledStartAt
        upcomingCover = t.upcoming.cover

        prevVideoId = t.navigation.prevVideoId
        nextVideoId = t.navigation.nextVideoId

        infoTab = t.infoTab.current
        activeTab = t.infoTab.activeTab
        canOpenNotice = t.noticeTab.canOpen
        systemNotice = t.noticeTab.systemNotice
        notice = t.noticeTab.notice

        announceText = t.noticeTab.notice
        pinnedProduct = Self.derivePinnedProduct(t.productOverlay)
        vodActiveProduct = t.vodActiveProduct
        vodActiveProducts = t.vodActiveProducts

        isLoggedIn = t.identityLabel.current?.isLoggedIn ?? false
        displayName = t.identityLabel.current?.displayName ?? ""
        chatEnabled = t.operationRail.chatEnabled
    }

    // MARK: - Read-only host intents (pass-through to the bound template)
    //
    // The shell does NOT carry actions. These are thin forwarders for the SINGLE
    // template-owned navigation intent family-1 needs that has no core `simulate*`
    // equivalent: switching the info-panel tab. (`selectInfoTab` is a public
    // template method — it only flips presentation state, it does NOT call any
    // API.) Everything else — mute / like / share / 訂閱 — goes through the host's
    // already-wired core `simulate*` exits, NOT here (D-4).

    /// Forward an info-panel tab switch to the bound template (`info` always
    /// honoured; `notice` honoured only when `canOpenNotice`). No-op for demo
    /// instances (no bound template).
    public func selectInfoTab(_ tab: LBInfoPanelTab) {
        template?.selectInfoTab(tab)
    }

    // MARK: - Turnkey action forwarders (→ DefaultPlayerTemplate perform-methods, TK-2)
    //
    // Thin forwarders so a reference-ui tap drives the template's turnkey perform-
    // methods (→ core public exits → not-intercepted design default flow). These live
    // in reference-ui (PlayerShellModel) — NOT the template — because reference-ui
    // already holds the model; the model forwards to the template (same one-way flow
    // as `selectInfoTab`). No-op for demo / snapshot instances (no bound template).

    /// Like (❤️) — forward to the template's turnkey like.
    public func performLike() { template?.performLike() }
    /// Share — forward (template → core; host presents the share sheet on the event).
    public func performShare() { template?.performShare() }
    /// Toggle subtitles (CC).
    public func toggleSubtitle() { template?.toggleSubtitle() }
    /// Open the shop service link (template → core; host presents the in-app browser).
    public func openServiceLink() { template?.openServiceLink() }
    /// Subscribe / unsubscribe.
    public func toggleSubscribe() { template?.toggleSubscribe() }
    /// Tap a product (pinned card / list item) → product-detail default flow.
    public func performProductTap(_ product: LBProduct) { template?.performProductTap(product) }
    /// Open the guest-name-edit flow.
    public func requestGuestNameEdit() { template?.requestGuestNameEdit() }
    /// Request the next page of chat history.
    public func loadChatHistory() { template?.loadChatHistory() }
    /// Telemetry-only: product-panel toggle event (list visibility is host-owned).
    public func performGoodsTap() { template?.performGoodsTap() }
    /// Telemetry-only: chat toggle event (chat visibility is host-owned).
    public func performChatToggle() { template?.performChatToggle() }

    // -- VOD controls (→ template → core, VOD-2) --------------------------------

    /// VOD play/pause toggle.
    public func togglePlayPause() { template?.togglePlayPause() }
    /// VOD absolute seek (seconds).
    public func seek(to seconds: Double) { template?.seek(to: seconds) }
    /// VOD relative seek (±seconds).
    public func seekBy(_ delta: Double) { template?.seekBy(delta) }

    // -- Swipe navigation (→ template → core load(videoId:), swipe-navigate-template) --

    /// Switch to the PREVIOUS adjacent video (vertical swipe-DOWN) — forward to the
    /// template's `navigateToPrev()` (→ core `load(videoId:)`); no-op when there is
    /// no previous video or no bound template (demo / snapshot instance).
    public func navigateToPrev() { template?.navigateToPrev() }
    /// Switch to the NEXT adjacent video (vertical swipe-UP) — forward to the
    /// template's `navigateToNext()` (→ core `load(videoId:)`); no-op when there is
    /// no next video or no bound template (demo / snapshot instance).
    public func navigateToNext() { template?.navigateToNext() }

    // MARK: - Deterministic defaults (demo / snapshot seeds)

    /// The side-rail items as they appear pre-channel (matches
    /// `DefaultOperationRail`'s default order: goods / chat / like / share /
    /// subtitle / serviceLink / guestNameEdit / more; conditional kinds disabled).
    public static let defaultRailItems: [LBSideRailItem] = [
        LBSideRailItem(kind: .goods, enabled: true),
        LBSideRailItem(kind: .chat, enabled: false),
        LBSideRailItem(kind: .like, enabled: true),
        LBSideRailItem(kind: .share, enabled: true),
        LBSideRailItem(kind: .subtitle, enabled: false),
        LBSideRailItem(kind: .serviceLink, enabled: false),
        LBSideRailItem(kind: .guestNameEdit, enabled: false),
        LBSideRailItem(kind: .more, enabled: true),
    ]

    /// An empty info-tab snapshot (pre-channel seed).
    public static let emptyInfoTab = LBInfoTabState(
        title: "", publishAt: "", shopName: "",
        shopIntro: "", shopLogo: "", isSubscribed: false)

    /// The LIVE pinned-card product: the narrating product (`narrate_status == 2`) when
    /// present, ELSE the first `is_hot == 1` product. Mirrors the component-contracts
    /// 推播卡 trigger (is_hot OR narrate_status==2) so the card appears for the introduced
    /// OR featured product. Reads ONLY data the template already exposes publicly
    /// (`activeProduct` + `products`) — it does NOT alter the template's `activeProduct`
    /// (`narrate_status==2`) contract. Pure.
    static func derivePinnedProduct(_ overlay: DefaultProductOverlayState) -> LBProduct? {
        overlay.activeProduct ?? overlay.products.first { $0.isHot == 1 }
    }
}

// MARK: - GAP NOTES (reachability of family-1 surfaces from the public template)
//
// Per design D-4, this layer ONLY reads what `DefaultPlayerTemplate` already
// exposes publicly. It MUST NOT add pixels or add accessors to `LiveBuyUI`.
// The following family-1 surface inputs are NOT directly reachable from the
// template's public read surface today; the surface agents must treat them as
// host-supplied (or omit them until a future template change exposes them):
//
//   • LiveOverlayChromeView — host caption (`LBLiveHostCaption`): there is NO
//     public host-caption / subtitle-text view-model on `DefaultPlayerTemplate`
//     (only `subtitle.{available,enabled}` is internal-fed and NOT public on the
//     template type). The shell exposes `announceText` (from `noticeTab.notice`)
//     and `pinnedProduct` (from `productOverlay.activeProduct`); the host caption
//     and gesture-hint copy stay STATIC / host-supplied in the surface sub-view.
//
//   • LiveOverlayChromeView — gesture hints (`LBPGestureHint`): pure static
//     presentation copy (tap-to-mute / long-press-pause / swipe). No view-model
//     binding — the surface sub-view renders fixed localized strings.
//
//   • PlayerHeaderBarView — PiP affordance: there is no public PiP-state mirror
//     on the template. The mute icon binds `muted`; the PiP control (if drawn) is
//     a static affordance whose action goes through the host's wiring.
//
// None of these gaps block the skeleton: the published surface values above are
// the full set the four surface sub-views bind. Surfaces that need a host-caption
// / gesture-hint / PiP affordance accept them as STATIC sub-view inputs, NOT as
// PlayerShellModel publishes (so we never invent a view-model).
