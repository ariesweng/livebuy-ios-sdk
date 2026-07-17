import SwiftUI
import LivebuySDK
import LivebuyUI

// MARK: - PlayerShellView — family-1 player-shell container (SKELETON)
//
// Spec: `reference-ui-rendering/spec.md` (family-1 player-shell, 4 surfaces)
// Design: rb-ios-player-shell design.md D-1 / D-2 / D-7.
//
// The top-level family-1 container. It lays out the FOUR family-1 surface
// sub-views over a video area:
//
//   1. PlayerHeaderBarView    — pinned TOP        (D-2 #1, `LBPTopBar` / `LBPHostBadge`)
//   2. OperationRailView      — pinned TRAILING   (D-2 #2, `LBPSideRail`)
//   3. VideoInfoPanelView     — bottom-sheet      (D-2 #3, `LBPBottomSheet`)
//   4. LiveOverlayChromeView  — full-bleed overlay (D-2 #4, `live-chrome.jsx`)
//
// This is the SKELETON: it owns the layout + a `PlayerShellModel` + the resolved
// `ReferenceUITheme`, and composes the four surface sub-views BY TYPE NAME. The
// four sub-view TYPES are produced by the four parallel surface agents that run
// after this skeleton — see the "SUB-VIEW INPUT PATTERN" contract below, which
// every surface agent MUST implement verbatim so the container's call sites match.
//
// Until all four surface sub-views exist, this file will not compile on its own —
// that is expected (the surface agents land the types). The container's job is to
// FIX the layout + the call-site shape so the parallel agents converge.
//
// iOS-14-safe: `ZStack` / `VStack` / `HStack` / `Spacer` / `safeAreaInset`-free
// manual padding are all iOS-13+; no `@available` guard needed. Any surface that
// reaches for a >14 API must guard it inside its own sub-view (D-7).
//
// ─────────────────────────────────────────────────────────────────────────────
// SUB-VIEW INPUT PATTERN — the contract the 4 parallel surface agents MUST follow
// ─────────────────────────────────────────────────────────────────────────────
//
// Every family-1 surface sub-view is a `public struct …: View` whose initializer
// takes, IN THIS ORDER:
//
//   1. `theme: ReferenceUITheme`            — the resolved reference-ui theme
//                                             (FIRST positional argument, always).
//   2. its bound SNAPSHOT VALUE(S)          — the read-only state it renders,
//                                             passed BY VALUE from PlayerShellModel
//                                             (never the model, never the template).
//   3. optional action closures            — trailing, each defaulting to `nil`
//                                             (`onX: (() -> Void)? = nil`, etc.).
//                                             The shell does NOT own actions; the
//                                             host wires taps to core `simulate*`.
//
// Concretely, the four surface agents implement EXACTLY these initializers:
//
//   PlayerHeaderBarView(
//       theme: ReferenceUITheme,
//       title: String, hostName: String, shopLogo: String,
//       viewerCount: Int, isSubscribed: Bool, isLive: Bool,
//       onMinimize: (() -> Void)? = nil,
//       onSubscribe: (() -> Void)? = nil)
//   (top-right = a single minimize button → onMinimize; LIVE pill + viewer count
//    shown only when isLive. mute/share/info are NOT header controls.)
//
//   OperationRailView(
//       theme: ReferenceUITheme,
//       items: [LBSideRailItem], bagCount: Int, heartBurstTick: Int, muted: Bool,
//       onTapItem: ((LBSideRailKind) -> Void)? = nil)
//
//   VideoInfoPanelView(
//       theme: ReferenceUITheme,
//       info: LBInfoTabState, activeTab: LBInfoPanelTab,
//       canOpenNotice: Bool, systemNotice: String, notice: String,
//       onSelectTab: ((LBInfoPanelTab) -> Void)? = nil)
//
//   LiveOverlayChromeView(
//       theme: ReferenceUITheme,
//       announceText: String, pinnedProduct: LBProduct?,
//       hostCaption: String = "", showGestureHints: Bool = true)
//
// Rules every surface agent honours:
//   • FIRST positional arg is `theme:`. Snapshot values are passed BY VALUE.
//   • Action closures are LAST, each `… = nil` (the shell passes the host-wired
//     closure or omits it). A surface sub-view MUST render correctly with all
//     actions nil (so demo / snapshot tests construct it action-free).
//   • A surface sub-view reads ONLY its passed-in values — it MUST NOT reach back
//     into PlayerShellModel or DefaultPlayerTemplate (one-way data flow, D-1/D-4).
//   • iOS-14-safe SwiftUI only; any >14 API guarded with `@available` /
//     `if #available` inside the sub-view (D-7).
// ─────────────────────────────────────────────────────────────────────────────

/// The family-1 player-shell container. Drives layout for the four surface
/// sub-views over the video area; reads a `PlayerShellModel` (republished from a
/// live `DefaultPlayerTemplate` or constructed deterministically) and paints with
/// the resolved `ReferenceUITheme`.
public struct PlayerShellView: View {

    /// Minimum committed vertical drag (points) that counts as a video-switch swipe.
    /// Doubles as the `DragGesture.minimumDistance` so a tap (tiny translation) is
    /// never mistaken for a swipe and keeps firing tap-to-mute.
    private static let swipeThreshold: CGFloat = 60

    /// The republished, read-only player-shell snapshot.
    @ObservedObject public var model: PlayerShellModel

    /// The resolved reference-ui theme.
    public let theme: ReferenceUITheme

    /// Whether to paint the opaque `theme.background` placeholder behind the
    /// chrome. `true` (default) keeps snapshot baselines deterministic without a
    /// live stream. Set `false` when the shell is overlaid on a host-supplied
    /// **real video surface** (e.g. AVPlayerLayer / IVSPlayerView) — otherwise
    /// the opaque background covers the video. (See `live-chrome.jsx`: the video
    /// sits behind the chrome; the chrome itself is transparent over it.)
    public let paintsBackgroundPlaceholder: Bool

    /// Whether the info panel (bottom sheet) is currently presented. Local
    /// presentation state — the panel CONTENT (tabs / fields) is driven by the
    /// model; this only governs the sheet affordance's open/closed state.
    @State private var infoPanelPresented: Bool = false

    /// Local heart-burst trigger for the LIVE bottom bar's like tap (rb-ios-live-bottom-heart-burst).
    /// Bumped each time the user taps 愛心 → drives a `HeartBurstView` anchored above the like
    /// button (design `LBLiveBottomBar onLike → spawnHeart`). Local presentation state only.
    @State private var liveHeartTick: Int = 0

    /// The VOD products whose now-introducing cards the viewer has dismissed (by id). Each card
    /// re-appears when the playhead advances and that product re-enters `vodActiveProducts`. A
    /// Set (not a single id) so multiple simultaneously-introduced products dismiss independently
    /// (rb-ios-now-introducing-real-image-carousel, 問題 10). Local presentation state only.
    @State private var dismissedVodProductIds: Set<String> = []

    /// The LIVE pinned products the viewer has dismissed (by id) via the pinned-card close X.
    /// Each card re-appears when a DIFFERENT pinned product (different id) enters the source list
    /// (real live `narrate_status == 2` 換人 / replay timeline advancing). Mirrors the VOD
    /// `dismissedVodProductIds` per-product-id local hide (rb-ios-live-pinned-card-dismiss; parity
    /// to Android `0f6b56a5`). Local presentation state only.
    @State private var dismissedLivePinnedIds: Set<String> = []

    /// Whether the「聯絡商家」confirm modal (`ContactMerchantModalView`) is presented.
    /// The rail `serviceLink` tap and the info-panel「與商家一對一對話」now present this
    /// confirm FIRST (design `contact_merchant`); only its「確定」proceeds to the existing
    /// `model.openServiceLink()` exit. Local presentation state only.
    @State private var contactMerchantPresented: Bool = false

    /// Top-right minimize → host collapses the player into the bottom-right floating
    /// preview (`FloatingWidgetView`). The shell does NOT own the collapse (it holds
    /// no `LBVideoItem`); it only forwards the intent. nil → the button is inert.
    private let onMinimize: (() -> Void)?

    /// Whether to show the gesture-hint overlay (tap-to-mute / long-press-pause /
    /// swipe). `true` (default) keeps the existing behaviour + snapshot baselines.
    /// A host that records "已顯示一次" suppresses it by passing `false` (the host owns
    /// the persisted shown flag — reference-ui only reads this boolean). Forwarded
    /// into `LiveOverlayChromeView(showGestureHints:)`.
    private let showGestureHints: Bool

    /// Tap on the video area → host-wired mute toggle (design「點擊靜音」/ "first tap
    /// unmutes"). The host wires it to the template's `toggleMute()` (→ core
    /// `setMuted`). nil → inert (demo / snapshot). This layer NEVER calls core /
    /// template mute itself; it only forwards the tap.
    private let onToggleMute: (() -> Void)?

    /// Rail「商品」(.goods) open-intent → host opens the product-list overlay
    /// (family-3 ProductSheets). The overlay composition is host-owned (the shell
    /// holds no overlay state); this only signals the intent. nil → inert.
    private let onOpenProductList: (() -> Void)?

    /// Rail「聊天」(.chat) open-intent → host shows the chat feed (family-2 FeedWin).
    /// Host-owned composition; nil → inert.
    private let onShowChatFeed: (() -> Void)?

    /// LIVE bottom-bar「留言」tap → host opens its comment composer (design
    /// `LBLiveBottomBar.onComment` opens a sheet; the real composer is the host's,
    /// already wired to `template.sendChat`). nil → the pill is inert. This is the
    /// ONE bottom-bar intent with no model forwarder; nickname / share / like / CC
    /// route through `PlayerShellModel`'s existing turnkey forwarders.
    private let onComment: (() -> Void)?

    /// 訂閱 tap (PlayerHeader 頭像徽章 + VideoInfoPanel 訂閱 pill 共用同一入口) → host-wired subscribe
    /// gate. The drop-in container wires this so an UNLOGGED-IN guest first sees the「請先登入」modal
    /// (`AuthGateModalView(.subscribe)`) instead of a silent `AUTH_REQUIRED`; a logged-in user
    /// toggles subscribe (rb-ios-subscribe-login-gate). nil (demo / snapshot / non-container) →
    /// falls back to `model.toggleSubscribe()` so those paths (and snapshot baselines) are unchanged.
    private let onSubscribe: (() -> Void)?

    /// LIVE bottom-bar 暱稱（person-edit）tap → host presents the 設定暱稱 modal. The drop-in
    /// container wires this to its local `GuestNameEditModalView` presentation (NOT the
    /// `requestGuestNameEdit()` core path, which is gated on `guestEditAvailable` and silently
    /// no-ops). nil → falls back to the existing `model.requestGuestNameEdit()` forwarder (so
    /// non-container call sites / snapshots are unchanged).
    private let onNickname: (() -> Void)?

    /// LIVE bottom-bar 分享鈕 tap. The drop-in container wires this to `context.onShare`
    /// (= `config.onShare ?? (performShare() 未被 host 攔截時 presentChannelShare)`,
    /// dropin-player-default-share-sheet / rb-ios-live-share-default-sheet), so an unwired
    /// host still gets the default system share sheet. nil → falls back to the existing
    /// headless `model.performShare()` forwarder (只派 `VIDEO_SHARE_REQUEST` 事件；非容器 /
    /// snapshot 路徑不變).
    private let onShare: (() -> Void)?

    /// Host-supplied VOD caption text (core exposes no active-caption text). Shown in
    /// the VOD branch only while `model.subtitleEnabled` and non-empty. Default "".
    private let captionText: String

    /// Optional host override for the swipe-UP gesture (「上一/下一支」switch). When
    /// non-nil, an above-threshold UP swipe calls this INSTEAD of
    /// `model.navigateToNext()`, letting a host drive video navigation from its own
    /// feed list (it owns the `LBVideoItem` list; reference-ui only exposes the
    /// gesture direction). nil (default) → falls back to the existing
    /// channel-adjacency forwarder, so every current call site is unchanged.
    private let onSwipeUp: (() -> Void)?

    /// Optional host override for the swipe-DOWN gesture. Symmetric to `onSwipeUp`:
    /// non-nil → called INSTEAD of `model.navigateToPrev()`; nil → falls back.
    private let onSwipeDown: (() -> Void)?

    /// Close-player request, fired when the user swipes toward a direction that has
    /// NO adjacent video (swipe-nav-close-on-empty #7) — only on the template-nav
    /// FALLBACK path (a host `onSwipeUp` / `onSwipeDown` override always wins and is
    /// never overridden by this). nil → the swipe-to-empty is a no-op (demo / snapshot).
    private let onCloseRequest: (() -> Void)?

    /// Hold-to-pause start → host pauses playback. The container default wires it to core
    /// `player.pause()`. nil → inert (demo / snapshot). This layer NEVER calls core/template
    /// play/pause itself; it only forwards the hold start.
    private let onHoldStart: (() -> Void)?

    /// Hold-to-pause end (finger released) → host resumes playback. The container default
    /// wires it to core `player.play()`. nil → inert.
    private let onHoldEnd: (() -> Void)?

    /// Whether the on-demand chat composer (`ChatComposerBar`) is currently presented. When
    /// `true`, the LIVE bottom bar (`LiveBottomBarView` + its heart-burst sibling) is HIDDEN
    /// so the composer (which replaces the 留言 entry) does not overlap it at the bottom
    /// (rb-ios-chat-composer-opaque-hide-bottom-bar). Default `false` → bottom bar shows as
    /// before (snapshot-neutral); the drop-in container drives it from
    /// `ChatComposerController.isPresented`.
    private let composerPresented: Bool

    /// Reports the info-panel (`VideoInfoPanelView` bottom sheet) open/closed state to the
    /// container each time it changes, so the container can hide the family-2 chat feed
    /// (which sits in a HIGHER overlay layer and would otherwise occlude the sheet / swallow
    /// its taps) while the panel is up (rb-ios-info-panel-not-covered-by-chat). The info
    /// panel itself (state / 4 dismiss paths / contactMerchant) is unchanged — this is a
    /// read-only state report. nil (default / snapshot) → no report (baseline unchanged).
    private let onInfoPanelPresentedChange: ((Bool) -> Void)?

    /// Reports the LIVE/VOD mode (`model.isLive`) — its initial value and every change — to the
    /// container, so it can hide the family-2 chat feed (a LIVE-only surface whose full-bleed
    /// scrollable variant would otherwise occlude / swallow taps on the VOD side rail) while in
    /// VOD (rb-ios-hide-chat-feed-in-vod). Read-only state report. nil (default / snapshot) →
    /// no report (baseline unchanged).
    private let onIsLiveChange: ((Bool) -> Void)?

    /// Reports whether the LIVE announcement banner (`LBLiveAnnounce`) is showing —
    /// i.e. `model.announceText` non-empty — initial value + every change, so the container
    /// can give the chat feed EXTRA bottom clearance to avoid overlapping the bottom-left
    /// announcement banner when (and only when) a 公告 is present (rb-ios-live-announce-chat-
    /// clearance, 問題 4). Read-only state report. nil (default / snapshot) → no report
    /// (baseline unchanged).
    private let onHasAnnounceChange: ((Bool) -> Void)?

    // MARK: - Transient gesture-feedback state (default hidden → snapshot-neutral)

    /// True while the viewer is holding the video area (hold-to-pause). Drives the centre
    /// `GesturePauseIconView`. Default false → no overlay at rest (baselines unchanged).
    @State private var isHolding: Bool = false

    /// True for ~0.7s after a tap toggles mute. Drives the centre `GestureMuteToastView`.
    @State private var muteToastVisible: Bool = false

    /// Cancellable timer that promotes a sustained press into a hold (after `holdDelay`).
    /// Cancelled if the finger moves past `moveTolerance` first (it is a swipe/scroll).
    @State private var holdWorkItem: DispatchWorkItem?

    /// Cancellable timer that auto-dismisses the mute toast after `muteToastDuration`.
    @State private var muteToastWorkItem: DispatchWorkItem?

    /// Whether a single touch's drag is in progress (prevents re-scheduling the hold on
    /// every `onChanged`; reset on `onEnded`).
    @State private var dragActive: Bool = false

    /// Hold is recognized after this press duration (distinguishes hold from a quick tap).
    private static let holdDelay: TimeInterval = 0.3
    /// The mute toast auto-dismisses after this duration (issue 5: ~0.7s).
    private static let muteToastDuration: TimeInterval = 0.7
    /// Finger movement (pt) past which a pending hold is cancelled (it is a swipe/scroll).
    private static let moveTolerance: CGFloat = 12

    public init(model: PlayerShellModel,
                theme: ReferenceUITheme,
                paintsBackgroundPlaceholder: Bool = true,
                showGestureHints: Bool = true,
                onMinimize: (() -> Void)? = nil,
                onToggleMute: (() -> Void)? = nil,
                onOpenProductList: (() -> Void)? = nil,
                onShowChatFeed: (() -> Void)? = nil,
                onComment: (() -> Void)? = nil,
                onSubscribe: (() -> Void)? = nil,
                onNickname: (() -> Void)? = nil,
                onShare: (() -> Void)? = nil,
                captionText: String = "",
                onSwipeUp: (() -> Void)? = nil,
                onSwipeDown: (() -> Void)? = nil,
                onCloseRequest: (() -> Void)? = nil,
                onHoldStart: (() -> Void)? = nil,
                onHoldEnd: (() -> Void)? = nil,
                composerPresented: Bool = false,
                onInfoPanelPresentedChange: ((Bool) -> Void)? = nil,
                onIsLiveChange: ((Bool) -> Void)? = nil,
                onHasAnnounceChange: ((Bool) -> Void)? = nil) {
        self.model = model
        self.theme = theme
        self.paintsBackgroundPlaceholder = paintsBackgroundPlaceholder
        self.showGestureHints = showGestureHints
        self.onMinimize = onMinimize
        self.onToggleMute = onToggleMute
        self.onOpenProductList = onOpenProductList
        self.onShowChatFeed = onShowChatFeed
        self.onComment = onComment
        self.onSubscribe = onSubscribe
        self.onNickname = onNickname
        self.onShare = onShare
        self.captionText = captionText
        self.onSwipeUp = onSwipeUp
        self.onSwipeDown = onSwipeDown
        self.onCloseRequest = onCloseRequest
        self.onHoldStart = onHoldStart
        self.onHoldEnd = onHoldEnd
        self.composerPresented = composerPresented
        self.onInfoPanelPresentedChange = onInfoPanelPresentedChange
        self.onIsLiveChange = onIsLiveChange
        self.onHasAnnounceChange = onHasAnnounceChange
    }

    /// Resolves a committed vertical drag into the correct video-switch action,
    /// honoring optional host overrides. Called verbatim by the swipe gesture's
    /// `.onEnded`; extracted (`internal`) so the override-vs-fallback dispatch is
    /// unit-testable without rendering a SwiftUI gesture (per unit-test discipline).
    ///
    /// The fallback (no host override) swipe-nav action (swipe-nav-close-on-empty #7).
    enum SwipeNavAction: Equatable { case navigateNext, navigatePrev, close, none }

    /// PURE: resolve a committed vertical drag (no host override) into the template-nav
    /// fallback action. A swipe toward a direction WITH an adjacent video navigates; a
    /// swipe toward a direction with NO video → `.close` (close the player); below the
    /// threshold → `.none`. Unit-testable without rendering a gesture.
    static func resolveSwipeNav(translationHeight dy: CGFloat, hasNext: Bool, hasPrev: Bool) -> SwipeNavAction {
        if dy <= -swipeThreshold { return hasNext ? .navigateNext : .close }
        if dy >= swipeThreshold { return hasPrev ? .navigatePrev : .close }
        return .none
    }

    /// Resolves a committed vertical drag into the correct action, honoring host overrides.
    /// - A host `onSwipeUp` / `onSwipeDown` override ALWAYS wins (called instead of any
    ///   template-nav / close behavior).
    /// - Otherwise (template-nav fallback): swipe toward a video → navigate; swipe toward
    ///   an EMPTY direction (no next / no prev) → `onCloseRequest()` (close the player, #7).
    func handleSwipeEnded(translationHeight dy: CGFloat) {
        // Host override wins, regardless of next/prev availability.
        if dy <= -Self.swipeThreshold, let onSwipeUp = onSwipeUp { onSwipeUp(); return }
        if dy >= Self.swipeThreshold, let onSwipeDown = onSwipeDown { onSwipeDown(); return }
        // Fallback: template-nav, closing when there is no video in that direction.
        switch Self.resolveSwipeNav(translationHeight: dy,
                                    hasNext: model.hasNextVideo, hasPrev: model.hasPrevVideo) {
        case .navigateNext: model.navigateToNext()
        case .navigatePrev: model.navigateToPrev()
        case .close:        onCloseRequest?()
        case .none:         break
        }
    }

    // MARK: - Consolidated tap / hold / swipe gesture (single DragGesture(minimumDistance: 0))

    /// The classification of a finished video-area gesture. Extracted as a PURE function
    /// (`resolveGestureEnd`) so the tap-vs-swipe-vs-hold dispatch is unit-testable without
    /// rendering a SwiftUI gesture (unit-test discipline).
    enum GestureOutcome: Equatable { case hold, swipeUp, swipeDown, tap }

    /// Classify a finished gesture: a recognized hold wins; else a committed vertical drag
    /// is a swipe (up = next, down = prev); else (quick, small translation) a tap.
    static func resolveGestureEnd(isHolding: Bool, translationHeight dy: CGFloat) -> GestureOutcome {
        if isHolding { return .hold }
        if dy <= -swipeThreshold { return .swipeUp }
        if dy >= swipeThreshold { return .swipeDown }
        return .tap
    }

    /// PURE: whether hold-to-pause is available in the current mode. 進行中直播（`isLive`,
    /// = `liveStatus == 1`, 涵蓋**串流直播**與**預錄直播**兩者）MUST NOT 用手勢暫停 / 播放
    /// （rb-ios-live-hold-pause-suppress）；已結束直播的回放（`isFinishedLiveReplay`）與純 VOD
    /// （兩者 `isLive == false`）維持可暫停。抽成純函式使此 gate 可單元測試（不需渲染手勢）。
    static func allowsHoldToPause(isLive: Bool) -> Bool { !isLive }

    /// Drag in progress: on the first change schedule the hold timer; if the finger moves
    /// past `moveTolerance` before it fires, cancel the pending hold (it is a swipe/scroll,
    /// not a hold) so playback never pauses on a swipe.
    private func handleDragChanged(_ translation: CGSize) {
        if !dragActive {
            dragActive = true
            scheduleHold()
        }
        if !isHolding,
           abs(translation.width) > Self.moveTolerance || abs(translation.height) > Self.moveTolerance {
            cancelPendingHold()
        }
    }

    /// Drag ended: classify and dispatch. Hold → resume (`onHoldEnd`); swipe → existing
    /// `handleSwipeEnded`; tap → `onToggleMute` + the 0.7s centre mute toast.
    private func handleDragEnded(_ translation: CGSize) {
        cancelPendingHold()
        switch Self.resolveGestureEnd(isHolding: isHolding, translationHeight: translation.height) {
        case .hold:
            isHolding = false
            onHoldEnd?()
        case .swipeUp, .swipeDown:
            handleSwipeEnded(translationHeight: translation.height)
        case .tap:
            onToggleMute?()
            showMuteToast()
        }
        dragActive = false
    }

    /// Schedule the hold promotion: after `holdDelay` of a sustained press, mark `isHolding`
    /// and fire `onHoldStart` (host → core pause). Cancelled by movement or release first.
    private func scheduleHold() {
        // 進行中直播（`model.isLive` == `liveStatus == 1`, 涵蓋串流 + 預錄）禁止手勢暫停：直接不排程
        // hold，使 `isHolding` 永不為 true → 不 fire `onHoldStart` / `onHoldEnd`、`GesturePauseIconView`
        // 不顯示、`resolveGestureEnd` 自然回 tap / swipe（單擊仍切靜音、上下滑仍換片）。已結束直播的回放
        // 與純 VOD（皆 `isLive == false`）不受影響、維持可暫停（rb-ios-live-hold-pause-suppress）。
        guard Self.allowsHoldToPause(isLive: model.isLive) else { return }
        let work = DispatchWorkItem {
            self.isHolding = true
            self.onHoldStart?()
        }
        holdWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.holdDelay, execute: work)
    }

    /// Cancel a pending (not-yet-fired) hold timer.
    private func cancelPendingHold() {
        holdWorkItem?.cancel()
        holdWorkItem = nil
    }

    /// Show the centre mute toast and auto-dismiss it after `muteToastDuration` (~0.7s).
    private func showMuteToast() {
        muteToastWorkItem?.cancel()
        muteToastVisible = true
        let work = DispatchWorkItem { self.muteToastVisible = false }
        muteToastWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.muteToastDuration, execute: work)
    }

    // MARK: - Chrome gating (rb-ios-intro-chrome-minimal)

    /// live-chrome 家族 — 真直播（`isLive`，`liveStatus == 1`）或回放（`isFinishedLiveReplay`，
    /// 已結束的直播 `type == 2 && liveStatus == 3`）。兩者套用相同的 LIVE 版型（LIVE 疊層 chrome +
    /// LIVE 底部 bar + 聊天 feed）；純 VOD 點播（兩旗標皆 false）走 VOD 版型（side rail + 浮動袋 +
    /// now-introducing 輪播）。回放版型對齊直播當下（rb-ios-replay-live-chrome）。
    private var usesLiveChrome: Bool {
        model.isLive || model.isFinishedLiveReplay
    }

    /// The VOD main-chrome family — NOT live-chrome 家族（LIVE / 回放）/ upcoming(awaitingLive) /
    /// upcoming-intro. 純 VOD side rail + floating bag + (in the main state) header live here.
    private var isVodMainChrome: Bool {
        !usesLiveChrome && !model.isUpcoming && !model.introPlaying
    }

    /// Whether the VOD MAIN chrome (side rail + floating bag) should show. Only the
    /// OPENING sequence suppresses it — the full-screen brand loader (`.loading`) and
    /// the intro MP4 (`.splash`). From `.buffering` onward it shows (design `showMainChrome`
    /// only hides the opening loader / intro, not the main-stream buffering). For a
    /// no-intro VOD (the common case) there is no intro MP4, so by `.buffering` the channel
    /// is already loaded (rail enablement set, header data filled) — the rail/bag appear
    /// alongside the header instead of waiting for the first played frame (`.done`).
    /// This single source of truth drives the rail, the floating bag, AND the
    /// now-introducing card's bag-clearance inset (rb-ios-vod-rail-show-on-buffering).
    private var showsVodMainChrome: Bool {
        isVodMainChrome && model.startPhase != .loading && model.startPhase != .splash
    }

    /// 右下角浮動商品袋（`FloatingBagButtonView`，48×48 + trailing 12）佔據的右側淨寬（pt）：
    /// trailing 12 + 袋 48 + 8 間隙 = 68。VOD「正在介紹」卡在浮動袋存在時，trailing 以此量內縮
    /// （往左縮短）避讓浮動袋，浮動袋本身不動（rb-ios-vod-now-introducing-no-bag-overlap）。
    private static let floatingBagClearance: CGFloat = 68

    public var body: some View {
        ZStack {
            // The video area sits behind everything (host supplies the actual
            // video surface; the shell paints the themed background placeholder so
            // snapshot baselines are deterministic without a live stream). When
            // overlaid on a real video surface, skip it so the video shows.
            //
            // Upcoming (直播預告 awaitingLive) wears the LIVE chrome (design screens.jsx:
            // upcoming is in the live-chrome family). Its background is the
            // UpcomingCountdownView (cover + dark mask + date + big time) — promoted from
            // a top-most moment to the shell background, like design `LBLiveUpcomingOverlay`.
            // `live:` loads the cover only when a real video surface is present
            // (placeholder suppressed); the snapshot path stays the deterministic pure-color
            // background. This branch REPLACES the plain placeholder background.
            if model.isUpcoming {
                UpcomingCountdownView(
                    theme: theme,
                    scheduledStartAt: model.upcomingStartAt,
                    live: !paintsBackgroundPlaceholder,
                    coverUrl: model.upcomingCover)
                    .ignoresSafeAreaCompat()
            } else if paintsBackgroundPlaceholder {
                theme.background
                    .ignoresSafeAreaCompat()
            }

            // Tap-to-unmute gesture over the video area (design「點擊靜音」/ "first tap
            // unmutes"). A transparent, full-bleed tap target placed BELOW the chrome
            // controls so header / rail / info-panel / pinned-card taps win; only
            // empty video-area taps fire onToggleMute (host → template.toggleMute()).
            // Color.clear + contentShape = no pixels → snapshot baselines unchanged;
            // inert when onToggleMute == nil (demo / snapshot).
            // Vertical-swipe-to-switch-video (design hint「上下滑動 = 切換影片」). Attached
            // via `.simultaneousGesture` so it COMPOSES with the tap-to-mute above:
            // a tap (small translation) fires onToggleMute; a committed vertical drag
            // past the threshold fires navigation. swipe-UP (height ≤ -threshold) ⇒
            // next video; swipe-DOWN (height ≥ +threshold) ⇒ previous. A below-
            // threshold drag is a no-op (fire on .onEnded, not .onChanged).
            //
            // Host override: if the host injects `onSwipeUp` / `onSwipeDown`, that
            // closure is called INSTEAD of the model forwarder (the host then drives
            // navigation from its own feed list). When nil (default — all demo /
            // snapshot / existing call sites), it falls back to the model forwarders,
            // which no-op when there is no adjacent video / no bound template, so
            // demo / snapshot instances never crash. Invisible → pixel-neutral.
            // ONE DragGesture(minimumDistance: 0) resolves tap / hold / swipe from a single
            // touch (avoids the SwiftUI tap-vs-drag arbitration race): onChanged schedules a
            // cancellable hold timer (cancelled by movement); onEnded classifies via
            // `resolveGestureEnd` → tap (mute + toast) / swipe (handleSwipeEnded) / hold (resume).
            // INVARIANT (design screens.jsx: main gesture layer is `inset:0`): this gesture
            // layer is full-bleed and must stay reachable across the WHOLE screen, incl. the
            // upper half. It sits LOW in the ZStack, so any decorative full/half-bleed overlay
            // ABOVE it MUST be non-interactive (`allowsHitTesting(false)`) or it swallows the
            // empty-area taps before they reach here (the header scrim gradient was the offender
            // — see PlayerHeaderBarView). Genuinely-interactive controls (header buttons / rail /
            // bottom bar / pinned card) hit-test only their own content, so empty-area taps still
            // fall through to this layer.
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in handleDragChanged(value.translation) }
                        .onEnded { value in handleDragEnded(value.translation) }
                )
                .accessibilityIdentifier(LBAccessibilityID.playerVideoSurface)

            // Mode-branched chrome (design screens.jsx「VOD vs LIVE switches here」):
            //   UPCOMING → nothing drawn here (the UpcomingCountdownView background IS the
            //          surface; no live overlay / no VOD mini-cart / no announce-pinned-chat).
            //   LIVE → the live overlay chrome (announce / pinned card / host caption
            //          / floating gesture hints).
            //   VOD  → NO scrub/progress bar (design VOD chrome has none); the
            //          currently-introduced product card (MiniCartView bound to
            //          model.vodActiveProduct, bottom-leading) + the CC caption line
            //          when subtitles are on. The live chat / pinned / announce /
            //          host-caption are NOT drawn for VOD.
            if model.isUpcoming || model.introPlaying {
                // upcoming awaitingLive OR the upcoming intro is playing → no live-overlay
                // chrome (announce / pinned / chat / host-caption don't exist pre-live).
                EmptyView()
            } else if usesLiveChrome {
                LiveOverlayChromeView(
                    theme: theme,
                    announceText: model.announceText,
                    // 釘選卡來源依真直播 vs 回放分流（rb-ios-replay-live-chrome）：
                    //   真直播 → livePinnedProducts（多件 narrate_status==2 輪播 + 分頁點；空時
                    //            fallback 單一 activeProduct ?? first isHot，問題 7）。
                    //   回放   → vodActiveProducts（時間軸窗格 [beginTime,endTime) 含 playhead，隨
                    //            播放進度更新；回放無即時 narrate_status==2，改用後端介紹時間窗）。
                    // 先算來源分支、再以本地 dismiss set 過濾（涵蓋真直播 / 回放兩分支），使 close X
                    // 逐商品本地隱藏（rb-ios-live-pinned-card-dismiss，鏡像 VOD dismissedVodProductIds）。
                    pinnedProducts: LiveOverlayChromeView.visiblePinnedProducts(
                        model.isLive ? model.livePinnedProducts : model.vodActiveProducts,
                        dismissedIds: dismissedLivePinnedIds),
                    // Real product image on the pinned card only over a live video surface
                    // (placeholder suppressed) — same gate as the shop logo / VOD card
                    // (live-pinned-card-image-radius). Snapshot/demo keeps the placeholder.
                    live: !paintsBackgroundPlaceholder,
                    // Host-suppressible: a host that has already shown the hint once
                    // passes showGestureHints: false (it owns the persisted flag).
                    showGestureHints: showGestureHints,
                    // 進行中直播（`model.isLive`）禁止手勢暫停 → 一併隱藏「長按畫面 = 暫停 / 繼續」
                    // 提示（gate 在 isLive，非 usesLiveChrome）；已結束直播的回放仍可暫停 → 保留提示
                    // （rb-ios-live-hold-pause-suppress）。tap / swipe 兩行提示不受影響。
                    showsHoldPauseHint: !model.isLive,
                    // Real video overlay (placeholder bg suppressed) → fade the gesture
                    // hints; standalone / snapshot keeps them static (deterministic).
                    autoFadeGestureHints: !paintsBackgroundPlaceholder,
                    // Pinned-product card tap → turnkey product-detail default flow.
                    onTapPinnedProduct: { product in model.performProductTap(product) },
                    // 釘選卡 close X → 逐商品本地隱藏（把 id 加入本地 dismissedLivePinnedIds，
                    // 下次過濾即不再餵入該卡；鏡像 VOD onDismiss，rb-ios-live-pinned-card-dismiss）。
                    onDismissPinnedProduct: { id in dismissedLivePinnedIds.insert(id) },
                    // 公告橫幅 tap → 切到 VideoInfoPanel 公告分頁並開啟資訊面板（重用 host badge tap
                    // 的同一 infoPanelPresented 狀態）。公告顯示中 ⇒ notice 非空 ⇒ canOpenNotice
                    // ⇒ selectInfoTab(.notice) 生效（live-announce-tap-open-info-panel，問題 2）。
                    onTapAnnounce: {
                        model.selectInfoTab(.notice)
                        withAnimation { infoPanelPresented = true }
                    })
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer(minLength: 0)
                    if model.subtitleEnabled && !captionText.isEmpty {
                        CaptionOverlayView(theme: theme, text: captionText)
                            .padding(.bottom, 8)
                    }
                    // VOD now-introducing products: a full-width card carousel (real image + page
                    // dots + swipe) over ALL products whose [beginTime,endTime) window contains
                    // the playhead (`model.vodActiveProducts`), minus the ones dismissed locally.
                    // No scrub bar (design VOD has none). rb-ios-now-introducing-real-image-carousel
                    // (問題 9 滿寬+真實圖, 問題 10 多商品輪播).
                    let introducing = model.vodActiveProducts
                        .filter { !dismissedVodProductIds.contains($0.id) }
                    if !introducing.isEmpty {
                        NowIntroducingCarouselView(
                            theme: theme,
                            peeks: introducing.map { product in
                                LBMiniCartPeek(
                                    productId: product.id,
                                    name: product.name,
                                    priceShow: product.priceShow,
                                    soldOut: product.soldOut,
                                    pic: product.photos.first ?? product.pic)
                            },
                            // Real image only over a live video surface (placeholder suppressed);
                            // the snapshot path keeps the deterministic placeholder.
                            live: !paintsBackgroundPlaceholder,
                            onDismiss: { id in dismissedVodProductIds.insert(id) },
                            onOpenDetail: { id in
                                if let product = introducing.first(where: { $0.id == id }) {
                                    model.performProductTap(product)
                                }
                            })
                            // 往左佔滿；但在浮動商品袋顯示時（showsVodMainChrome，即 VOD 且
                            // startPhase ∈ {.buffering, .done}），trailing 內縮讓出浮動袋的右側空間，
                            // 避免卡片右下角與袋重疊（rb-ios-vod-now-introducing-no-bag-overlap）。
                            // 開場序列（.loading / .splash）無袋 → 維持 8（避讓跟隨浮動袋顯示時機）。
                            .padding(.leading, 8)
                            .padding(.trailing, showsVodMainChrome ? Self.floatingBagClearance : 8)
                            .padding(.bottom, 12)
                    }
                }
            }

            // Top bar pinned top, side rail pinned trailing. Surfaces 1 + 2.
            VStack(spacing: 0) {
                // Header is drawn UNCONDITIONALLY in every mode — including the VOD start
                // sequence (opening MP4 / loader): only the VOD side rail + floating bag are
                // suppressed there, the header stays (rb-ios-vod-intro-keep-header).
                PlayerHeaderBarView(
                    theme: theme,
                    title: model.title,
                    hostName: model.hostName,
                    shopLogo: model.shopLogo,
                    viewerCount: model.viewerCount,
                    isSubscribed: model.isSubscribed,
                    // live-chrome 家族（真直播 + 回放）皆餵 isLive: true → header 畫 viewer-count
                    // （回放套 LIVE 版型，rb-ios-replay-live-chrome）。
                    isLive: usesLiveChrome,
                    // Replay hides the LIVE pill but keeps the viewer count (design
                    // `hideLivePill = isReplay`). 兩種回放皆隱 LIVE 膠囊：behind-edge replay
                    // （`model.isReplay`，鏡像 playbackProgress.isReplay）與 finished-live replay
                    // （`model.isFinishedLiveReplay`，已結束直播）——後者非正在直播，顯紅 LIVE 會誤導。
                    isReplay: model.isReplay || model.isFinishedLiveReplay,
                    // Real shop logo only over a live video surface (placeholder suppressed) —
                    // reuse the same runtime image gate the cover/upcoming surfaces use; the
                    // snapshot/demo path (`paintsBackgroundPlaceholder == true`) stays monogram.
                    live: !paintsBackgroundPlaceholder,
                    // Host-config viewer-count gate (rb-ios-hide-viewer-count-config): default
                    // true; `false` (host) hides the viewer count even while live / replay.
                    showViewerCount: model.showViewerCount,
                    // Backend viewer-count gate (rb-ios-viewer-count-show-pv-num): mirrors
                    // `channel.show_pv_num == 1` via the view-model (same source as `viewerCount`).
                    // The badge shows ⟺ isLive && viewerCountVisible && showViewerCount — so replay
                    // (LIVE chrome) honours the original live-time show_pv_num setting.
                    viewerCountVisible: model.viewerCountVisible,
                    onMinimize: { onMinimize?() },
                    // 訂閱徽章 → 容器注入的 gate（未登入 → AuthGate(.subscribe)）；未注入 fallback
                    // `model.toggleSubscribe()`（rb-ios-subscribe-login-gate）。與 info pill 共用。
                    onSubscribe: { performSubscribe() },
                    // Host badge tap → open the VideoInfoPanel (design LBPHostBadge →
                    // video_info; presentation-only, replaces the removed VOD rail
                    // `more` pill). Same presentation toggle the `more` pill used.
                    onTapHostBadge: { withAnimation { infoPanelPresented.toggle() } })

                Spacer(minLength: 0)

                // Side rail is VOD-ONLY chrome (design screens.jsx gates `LBPSideRail`
                // on `!isLive`; upcoming wears the slim LIVE bar instead). In LIVE /
                // upcoming the bottom bar (below) replaces it; the rail anchors HIGHER
                // (bottom ≈80) so the separate floating bag button (below) can sit lower
                // next to the mini-cart strip (design `LBPSideRail` bottom:80 vs
                // `LBPBagButton` bottom:16). Suppressed only during the VOD OPENING sequence
                // (full-screen loader `.loading` / intro MP4 `.splash`) — from `.buffering`
                // onward the rail shows (rb-ios-vod-rail-show-on-buffering).
                if showsVodMainChrome {
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        OperationRailView(
                            theme: theme,
                            items: model.railItems,
                            bagCount: model.bagCount,
                            heartBurstTick: model.heartBurstTick,
                            muted: model.muted,
                            onTapItem: { kind in
                                // The rail surfaces a tap intent; for the info kinds
                                // the shell can forward presentation-only navigation.
                                // Real actions (like / share / chat …) go through the
                                // host-wired core `simulate*` — NOT owned here (D-4).
                                handleRailTap(kind)
                            })
                            .padding(.trailing, 12)
                            .padding(.bottom, 80)
                    }
                }
            }

            // Floating shopping-bag button (design `LBPBagButton`, VOD-only; upcoming's
            // bag lives in the slim LIVE bar instead) — composed as a SEPARATE sibling at
            // a LOWER anchor than the rail (bottom ≈16, trailing 12), next to the mini-cart
            // strip region. Tapping it reuses the existing goods path (`performGoodsTap` +
            // host `onOpenProductList`), behavior unchanged — only the trigger surface.
            // Suppressed only during the VOD OPENING sequence (full-screen loader
            // `.loading` / intro MP4 `.splash`); shows from `.buffering` onward, in lockstep
            // with the side rail (rb-ios-vod-rail-show-on-buffering).
            if showsVodMainChrome {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        FloatingBagButtonView(
                            theme: theme,
                            bagCount: model.bagCount,
                            onTap: {
                                model.performGoodsTap()   // telemetry-only panel-toggle
                                onOpenProductList?()        // host opens the product list
                            })
                            .padding(.trailing, 12)
                            .padding(.bottom, 16)
                    }
                }
            }

            // LIVE bottom bar — surfaces the design's `LBLiveBottomBar` at the bottom in
            // LIVE mode AND upcoming mode (VOD uses the side rail above instead). awaitingLive
            // passes `isUpcoming: true` → the SLIM variant (bag + share + like; no 留言 /
            // nickname / CC); the upcoming INTRO MP4 (`introPlaying`) passes `bagOnly: true`
            // → the bag-only minimal variant (just the bag). Pinned bottom, over the live
            // overlay chrome and below the info-panel modal. Nickname / share / like / CC
            // route through the model's existing turnkey forwarders (same host-wired path the
            // rail uses); 留言 raises the host `onComment` intent.
            //
            // Hidden while the on-demand chat composer is presented (`composerPresented`):
            // the composer replaces the 留言 entry and sits in the same bottom region, so the
            // bottom bar (+ its heart-burst sibling) is suppressed to avoid overlap
            // (rb-ios-chat-composer-opaque-hide-bottom-bar).
            if (usesLiveChrome || model.isUpcoming || model.introPlaying) && !composerPresented {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    LiveBottomBarView(
                        theme: theme,
                        bagCount: model.bagCount,
                        isReplay: model.isReplay,
                        isUpcoming: model.isUpcoming || model.introPlaying,
                        // 直播預告的開場影片 (introPlaying) → bag-only minimal bar (just the bag).
                        // awaitingLive keeps the slim three-button bar. bagOnly takes precedence.
                        bagOnly: model.introPlaying,
                        // 回放（已結束直播）→ 留言改 disabled「聊天室已關閉」、暱稱隱藏（後端 commentsub
                        // 對 liveStatus==3 回 404；rb-ios-replay-chat-closed-bottom-bar）。behind-edge
                        // isReplay（仍直播）不受影響——chatClosed 只由 isFinishedLiveReplay 驅動。
                        chatClosed: model.isFinishedLiveReplay,
                        onBag: {
                            model.performGoodsTap()   // telemetry-only panel-toggle event
                            onOpenProductList?()       // host opens the product-list overlay
                        },
                        onComment: { onComment?() },
                        // Container wires `onNickname` to a LOCAL `GuestNameEditModalView`
                        // presentation; absent (non-container / snapshot) → fall back to the
                        // existing `model.requestGuestNameEdit()` forwarder (gated core path).
                        onNickname: { if let onNickname = onNickname { onNickname() } else { model.requestGuestNameEdit() } },
                        // dropin-player-default-share-sheet 的 fallback（presentChannelShare）
                        // 由容器經 `onShare` 注入（rb-ios-live-share-default-sheet）；非容器 /
                        // snapshot（onShare == nil）維持既有 headless `model.performShare()`。
                        onShare: { if let onShare = onShare { onShare() } else { model.performShare() } },
                        // Real like via the existing turnkey forwarder + an immediate local heart
                        // burst (rb-ios-live-bottom-heart-burst — design `onLike → spawnHeart`).
                        onLike: { model.performLike(); liveHeartTick &+= 1 })
                        // onToggleCC intentionally not wired: the LIVE bottom bar no longer has a CC
                        // toggle (the replay variant is removed — prerecorded-live-bottom-bar-comment).
                        .padding(.bottom, 8)
                }

                // LIVE bottom-bar heart burst — the shared `HeartBurstView` anchored ABOVE the
                // like button (bottom-trailing), driven by the local `liveHeartTick`. Bag-only
                // (introPlaying) draws no like → no burst. Transient + non-interactive →
                // snapshot-neutral at rest. (rb-ios-live-bottom-heart-burst)
                if (usesLiveChrome || model.isUpcoming) && !model.introPlaying {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        HStack(spacing: 0) {
                            Spacer(minLength: 0)
                            HeartBurstView(tick: liveHeartTick, color: theme.accent)
                        }
                    }
                    .padding(.trailing, 18)
                    .padding(.bottom, 64)
                    .allowsHitTesting(false)
                }
            }

            // Center gesture-feedback overlays (transient, default hidden → snapshot-neutral).
            // Non-interactive (allowsHitTesting false) so they never block the gesture layer
            // / chrome below. ZStack centers them. pause icon = hold-to-pause; toast = 0.7s
            // mute feedback (reads model.muted = the post-toggle state).
            if isHolding {
                GesturePauseIconView(theme: theme)
                    .allowsHitTesting(false)
            }
            if muteToastVisible {
                GestureMuteToastView(theme: theme, muted: model.muted)
                    .allowsHitTesting(false)
            }

            // 會員等級限定升級遮罩（restriction-mask ②）。`is_restriction` 為**軟性顯示閘門**：
            // core 不擋播放，reference-ui 在播放畫面上疊遮罩 + 升級提示。預設隱藏
            // （`model.isRestricted == false`）→ snapshot baseline byte-identical。最終視覺 /
            // 退出 affordance DECISION-PENDING 待設計稿。
            if model.isRestricted {
                RestrictionMaskView(theme: theme)
            }
        }
        // Info panel (family-1 surface 3) — presented via the shared SheetKit bottom-sheet
        // presenter (dim scrim + grab handle + drag-to-dismiss). FOUR dismiss paths now
        // converge on `infoPanelPresented = false`: drag the handle past threshold, tap the
        // scrim, re-tap the host badge, or tap the header close icon (all animated; the close
        // icon added by rb-ios-sheet-header-close-unify). Replaces the prior hand-rolled
        // `VStack { Spacer(); if … { … .transition } }` that had no scrim / no dismiss.
        .lbBottomSheet(theme: theme, isPresented: $infoPanelPresented) {
            VideoInfoPanelView(
                theme: theme,
                info: model.infoTab,
                activeTab: model.activeTab,
                canOpenNotice: model.canOpenNotice,
                systemNotice: model.systemNotice,
                notice: model.notice,
                onSelectTab: { tab in model.selectInfoTab(tab) },
                // 與商家一對一對話 → present the「聯絡商家」confirm modal FIRST (design
                // `contact_merchant`), same intent as the side-rail serviceLink tap; only its
                // 「確定」proceeds to the existing service-link exit. (前往商城首頁 / storefront
                // has no core exit yet; it renders for design fidelity and stays inert.)
                onContactMerchant: { withAnimation { contactMerchantPresented = true } },
                // header 右上角關閉 icon → 關面板（第四個合法關閉入口，rb-ios-sheet-header-close-unify）。
                onClose: { withAnimation { infoPanelPresented = false } },
                // 訂閱 pill → 與 header 頭像徽章共用同一注入 gate（未登入 → 本地 AuthGate(.subscribe)、
                // 已登入 → toggleSubscribe）；未注入 fallback `model.toggleSubscribe()`
                // （rb-ios-subscribe-login-gate，取代原本一律直接 toggleSubscribe 的寫法）。
                onSubscribe: { performSubscribe() })
        }
        // 「聯絡商家」confirm modal — composed ABOVE the info-panel sheet so it overlays it.
        .overlay(contactMerchantOverlay)
        // Report info-panel open/closed to the container so it can hide the higher-layer
        // chat feed while the panel is up (rb-ios-info-panel-not-covered-by-chat). Read-only
        // report — the panel state / dismiss paths are unchanged.
        .onChange(of: infoPanelPresented) { presented in
            onInfoPanelPresentedChange?(presented)
        }
        // Report LIVE/VOD mode (initial + every change) so the container can hide the LIVE-only
        // chat feed in VOD (rb-ios-hide-chat-feed-in-vod). `.onAppear` supplies the initial value
        // (`.onChange` does not fire for it); `.onChange` tracks switches between videos.
        .onAppear {
            // 回報 live-chrome 家族（真直播 + 回放）而非僅 isLive，使回放也顯示聊天 feed
            // （rb-ios-replay-live-chrome）。
            onIsLiveChange?(usesLiveChrome)
            // 初值報告 announce 顯示與否（`.onChange` 不會為初值觸發），讓容器一進場就給對的避讓。
            onHasAnnounceChange?(!model.announceText.isEmpty)
        }
        .onChange(of: model.isLive) { _ in
            onIsLiveChange?(usesLiveChrome)
        }
        // 回放旗標切換亦回報 live-chrome 家族（換片 live→回放 / 回放→VOD 時聊天 feed 跟著開關）。
        .onChange(of: model.isFinishedLiveReplay) { _ in
            onIsLiveChange?(usesLiveChrome)
        }
        // Report whether the LBLiveAnnounce banner is showing (announceText 非空) so the container
        // gives the chat feed extra bottom clearance only when a 公告 is present
        // (rb-ios-live-announce-chat-clearance, 問題 4). announceText 只在後台公告變更時才變，不頻繁。
        .onChange(of: model.announceText) { text in
            onHasAnnounceChange?(!text.isEmpty)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(LBAccessibilityID.playerShell)
    }

    /// 訂閱 tap 的統一分派（header 頭像徽章 + VideoInfoPanel 訂閱 pill 共用一份 → 決策一致）：容器
    /// 注入的 `onSubscribe` gate（未登入 → 本地 `AuthGateModalView(.subscribe)`、已登入 →
    /// toggleSubscribe）優先；未注入（demo / snapshot / 非容器）→ fallback `model.toggleSubscribe()`
    /// 以保既有路徑與 snapshot baseline 不變（rb-ios-subscribe-login-gate）。
    private func performSubscribe() {
        if let onSubscribe = onSubscribe { onSubscribe() } else { model.toggleSubscribe() }
    }

    /// Forward a side-rail tap to its turnkey destination (TK-3). Every kind is now
    /// handled (no swallow): the action kinds forward to the bound template's perform-
    /// methods via `model` (→ core public exits → not-intercepted design default
    /// flow); `.goods` / `.chat` raise host open-intents (the overlay composition is
    /// host-owned); `.more` toggles the local info-panel presentation. The model
    /// forwarders are no-ops on demo / snapshot instances (no bound template).
    private func handleRailTap(_ kind: LBSideRailKind) {
        // The aligned VOD rail (design `LBPSideRail`) surfaces ONLY subtitle / share /
        // serviceLink. The other kinds are unreachable from the rail: goods → the
        // separate floating bag button; info → the host-badge tap; like / nickname /
        // chat are LIVE bottom-bar / not-in-VOD-rail. Switch stays total for
        // compile-time exhaustiveness.
        switch kind {
        case .subtitle:
            model.toggleSubtitle()
        case .share:
            // 與 LIVE 底部 bar 分享同一走線：容器注入的 `onShare`（含 presentChannelShare
            // fallback）→ unwired host 也能分享；非容器 / snapshot（onShare == nil）維持既有
            // headless `model.performShare()`（rb-ios-vod-rail-share-default-sheet）。
            if let onShare = onShare { onShare() } else { model.performShare() }
        case .serviceLink:
            // Design `contact_merchant`: confirm BEFORE opening the service link. Present
            // the confirm modal; only its「確定」proceeds to `model.openServiceLink()`.
            withAnimation { contactMerchantPresented = true }
        case .goods, .chat, .like, .guestNameEdit, .more:
            break   // not reachable from the aligned rail
        }
    }

    /// The「聯絡商家」confirm modal overlay (design `contact_merchant` → `LBPAlertModal`),
    /// composed ABOVE the info-panel sheet. Presented when the rail serviceLink or the
    /// info-panel「與商家一對一對話」intent fires;「確定」proceeds to the existing
    /// `model.openServiceLink()` exit, 「取消」/ scrim just dismisses.
    @ViewBuilder
    private var contactMerchantOverlay: some View {
        if contactMerchantPresented {
            ContactMerchantModalView(
                theme: theme,
                onConfirm: {
                    withAnimation { contactMerchantPresented = false }
                    model.openServiceLink()
                },
                onDismiss: { withAnimation { contactMerchantPresented = false } })
                .transition(.opacity)
        }
    }
}

// MARK: - iOS-14-safe full-bleed helper (D-7)

private extension View {
    /// `ignoresSafeArea()` is iOS-14+; `edgesIgnoringSafeArea(.all)` is the
    /// iOS-13/14-safe equivalent. Keep the call site clean and the guard local.
    @ViewBuilder
    func ignoresSafeAreaCompat() -> some View {
        if #available(iOS 14.0, *) {
            self.ignoresSafeArea()
        } else {
            self.edgesIgnoringSafeArea(.all)
        }
    }
}

// MARK: - Restriction mask (restriction-mask ②)

/// 會員等級限定升級遮罩：全幅暗罩 + 鎖 glyph + 升級提示。`is_restriction` 為**軟性顯示閘門**
/// （core 不擋播放、後端仍回完整內容），此遮罩疊在播放畫面上擋住受限內容。只在
/// `PlayerShellView` 偵測 `model.isRestricted == true` 時建出，故未受限時不出像素
/// （snapshot baseline byte-identical）。最終視覺 / 退出 affordance DECISION-PENDING 待設計稿。
private struct RestrictionMaskView: View {
    let theme: ReferenceUITheme

    var body: some View {
        ZStack {
            Color.black.opacity(0.78)
            VStack(spacing: 10) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(.white)
                Text("此內容限定會員等級觀看")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                Text("提升會員等級後即可觀看")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(24)
            .multilineTextAlignment(.center)
        }
        // 擋住受限內容（軟閘門：阻擋與下層播放內容互動）。
        .contentShape(Rectangle())
    }
}
