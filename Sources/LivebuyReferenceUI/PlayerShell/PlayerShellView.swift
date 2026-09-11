import SwiftUI
import UIKit
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

    /// Local heart-burst trigger for the LIVE bottom bar's like tap (rb-ios-live-bottom-heart-burst,
    /// restyled by `rb-ios-live-like-burst-restyle`). Bumped ONCE PER BURST — a single like tap
    /// now bumps this 1–4 times, staggered 300ms apart (`resolveLikeBurstCount` /
    /// `likeGlowDurationMs` below), each bump driving one more `HeartBurstView` burst anchored
    /// above the like button (design `LBLiveBottomBar onLike → likeAnimation`). Local
    /// presentation state only.
    @State private var liveHeartTick: Int = 0

    /// LIVE like button bright (accent) state (design R37 `LBLiveBottomBar liked` prop,
    /// `rb-ios-live-like-burst-restyle`). `true` while the staggered burst sequence from the
    /// most recent like tap is still playing out; reverts to `false` after
    /// `likeGlowDurationMs(count:)`. Local presentation state only — mirrors `liveHeartTick`'s
    /// existing pattern, does NOT touch `PlayerShellModel`.
    @State private var liveLiked: Bool = false

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

    /// 「乾淨模式」(`rb-ios-gesture-clean-mode-v2`, design R29 — SUPERSEDES the retired
    /// `rb-ios-gesture-clean-mode-rewrite`/R23 long-press trigger) — toggled by a SHORT TAP
    /// on the video area (see `handleVideoTap(zone:)`): while actually live or in the
    /// upcoming preview (`!isSeekable`) the toggle fires immediately; while seekable (VOD or
    /// an already-ended live replay) it is DEFERRED (see `pendingCleanModeToggleCancel`) so a
    /// following second tap in the same half can be recognized as a double-tap seek instead.
    /// Unconditional for both LIVE and VOD/replay (no `isLive` gate on whether the toggle
    /// itself happens — only on whether it is deferred). `true` hides most floating chrome
    /// (§6 hide-lists) while keeping the minimize button, the clean-mode-only mute button, the
    /// new「退出乾淨模式」button, the expanded transport bar, and — LIVE only — the currently-
    /// narrating pinned product card. Pure呈現層 local state (design.md §1): it does NOT
    /// belong on `PlayerShellModel` and MUST NOT influence any core / view-model state.
    ///
    /// NOT reset on a video switch (design.md §1 flagged this as an apply-stage decision: no
    /// existing per-video local-state reset hook was found to piggyback on — `dismissedVodProductIds`
    /// / `dismissedLivePinnedIds` above are likewise never explicitly reset on switch, they just
    /// naturally stop matching once the new video's product ids differ. `cleanMode` has no such
    /// natural self-clearing mechanism, so carrying it across an in-place video switch is a
    /// deliberate, currently-untested edge case — not a default SwiftUI behavior this comment is
    /// merely documenting).
    ///
    /// Test-seeded via `cleanModeForTesting` on `init` (SwiftUI gestures cannot be driven from
    /// XCTest — TCC-blocked — so the chrome-hiding contract, §6, is proven by pre-seeding this
    /// state's INITIAL value before the view's first, and in the single-shot `ImageRenderer`
    /// snapshot path only, render), mirroring the existing `isScrubbingForTesting` /
    /// `scrubBarExpandedForTesting` precedent below.
    @State private var cleanMode: Bool = false

    /// Whether the「聯絡商家」confirm modal (`ContactMerchantModalView`) is presented.
    /// The rail `serviceLink` tap and the info-panel「與商家一對一對話」now present this
    /// confirm FIRST (design `contact_merchant`); only its「確定」proceeds to the existing
    /// `model.openServiceLink()` exit. Local presentation state only.
    @State private var contactMerchantPresented: Bool = false

    /// Whether the LIVE bottom bar's「更多」(⋯) collapsible menu (`LiveMoreSheetView`) is
    /// presented. Opened by `LiveBottomBarView.onMore` — only rendered by that bar's
    /// `chatClosed` (finished-live-replay) variant (design R32,
    /// rb-ios-live-replay-more-menu-and-video-info-live-copy). Local presentation state only.
    @State private var liveMoreSheetPresented: Bool = false

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

    /// Mute toggle → host-wired forwarder (design「點擊靜音」/ "first tap unmutes"). The
    /// host wires it to the template's `toggleMute()` (→ core `setMuted`). nil → inert
    /// (demo / snapshot). This layer NEVER calls core / template mute itself; it only
    /// forwards the tap.
    ///
    /// RETARGETED (`rb-ios-gesture-clean-mode-v2`, design R29): the video-area tap gesture
    /// that used to call this directly is RETIRED — every short tap now toggles `cleanMode`
    /// instead (see `handleVideoTap(zone:)`). This closure is still forwarded, just from a
    /// NEW source: `PlayerHeaderBarView`'s clean-mode-only mute button (`body` passes a
    /// non-nil closure to it only while `cleanMode == true`).
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

    /// 容器目前是否偵測到「另一場現正直播」(rb-ios-live-now-pill)——drives
    /// `LiveNowPillView`'s composition via the PURE `showsLiveNowPill` gate below. NOT a
    /// template-derived value: the container (`LivebuyPlayer` + `LiveNowPollController`) owns the
    /// polling / gate lifecycle and feeds only this boolean in, mirroring how `composerPresented`
    /// / `onIsLiveChange` mirrors are plain read-only reports rather than owned state. Default
    /// `false` → the pill never composes for direct `PlayerShellView` construction (demo /
    /// snapshot / non-container call sites), baseline unchanged.
    private let hasLiveNow: Bool

    /// LIVE-now pill tap → host-wired switch-to-that-live intent. The drop-in container wires
    /// this to `LivebuyPlayerConfig.onGoLive ?? default in-place switch` (mirrors `onPickHot` /
    /// `onWatchNext`'s "container resolves the target, this view only reports the tap" shape —
    /// this view has no bound `LBVideoItem` to hand back, the container already holds the ONE
    /// currently-detected item). nil → inert (demo / snapshot).
    private let onGoLive: (() -> Void)?

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

    /// RETIRED (rb-ios-gesture-clean-mode-rewrite, `rb-ios-gesture-clean-mode-v2`): long-press no
    /// longer drives pause/resume — it drives 2×-speed seeking on seekable content instead — so
    /// this closure is NEVER invoked any more (`handleDragEnded`'s `.hold` case only resets
    /// `longPressFired` and calls `stopSpeedMode()`). Kept (not removed) for source
    /// compatibility: any existing host that explicitly passed a non-nil closure here still
    /// compiles; it silently stops firing. VOD/replay pause is reached via
    /// `PlaybackProgressBarView`'s expanded-state play/pause button.
    @available(*, deprecated, message: "long-press no longer drives pause/resume; see PlaybackProgressBarView's expanded play/pause button")
    private let onHoldStart: (() -> Void)?

    /// RETIRED (rb-ios-gesture-clean-mode-rewrite, `rb-ios-gesture-clean-mode-v2`) — see
    /// `onHoldStart`'s doc comment; never invoked any more, kept for source compatibility only.
    @available(*, deprecated, message: "long-press no longer drives pause/resume; see PlaybackProgressBarView's expanded play/pause button")
    private let onHoldEnd: (() -> Void)?

    /// Whether the on-demand chat composer (`ChatComposerBar`) is currently presented. When
    /// `true`, the LIVE bottom bar (`LiveBottomBarView` + its heart-burst sibling) is HIDDEN
    /// so the composer (which replaces the 留言 entry) does not overlap it at the bottom
    /// (rb-ios-chat-composer-opaque-hide-bottom-bar). Default `false` → bottom bar shows as
    /// before (snapshot-neutral); the drop-in container drives it from
    /// `ChatComposerController.isPresented`.
    private let composerPresented: Bool

    /// Whether any product sheet/modal (the sibling `ProductSheetsOverlayView`'s list drawer /
    /// detail-or-restock sheet / zoom lightbox / cart-needs-login gate / variant-select prompt)
    /// is currently presented — fed by the container's mirror of
    /// `ProductSheetsOverlayView.onPresentationChange` (rb-ios-block-swipe-nav-when-sheet-open).
    /// `true` suppresses the vertical-swipe video-switch gesture (`allowsSwipeNav`) exactly like
    /// `model.isLive == true` does — see `handleSwipeEnded`. Default `false` → existing call
    /// sites unchanged (snapshot-neutral).
    private let sheetsPresented: Bool

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

    /// Reports the NARROW `isScrubbing` (finger actually down) — so the container can hide the
    /// separately-composed chat feed while ACTIVELY dragging, mirroring the in-shell chrome's
    /// own `!isScrubbing` gates (rb-ios-restore-vod-playback-progress-bar, corrected post-
    /// design-review: an earlier draft mirrored the wider `scrubBarExpanded` here instead, which
    /// kept the chat feed hidden through the whole 2.8s post-release hold window instead of
    /// letting it reappear lifted — design `screens.jsx` `LBLiveChatOverlay` treats chat
    /// identically to the announce banner / pinned card: hidden only while `scrubbing`, and
    /// lifted (not hidden) while merely `scrubVisible`). Only has any effect while
    /// `usesLiveChrome` is also true (the only state where the progress bar and the chat feed
    /// can coexist — a finished-live replay, `model.isFinishedLiveReplay`); a no-op in pure VOD
    /// (chat already off) and pure live (bar never shows there). nil (default / snapshot) → no
    /// report (baseline unchanged).
    private let onScrubbingChange: ((Bool) -> Void)?

    /// Reports the WIDE `scrubBarExpanded` (touch-down through the 2.8s post-release hold) — so
    /// the container can additionally LIFT the chat feed (extra bottom inset, mirroring this
    /// view's own `scrubChromeLiftIfExpanded`) while it is visible again during the hold window
    /// (`scrubBarExpanded && !isScrubbing` — design `screens.jsx` `LBLiveChatOverlay`'s
    /// `safeBottom + (isReplay && scrubVisible ? 36 : 0)`). Same coexistence scope as
    /// [onScrubbingChange] above. nil (default / snapshot) → no report (baseline unchanged).
    private let onScrubBarExpandedChange: ((Bool) -> Void)?

    /// Reports `cleanMode` — its initial value and every change (long-press toggle) — to the
    /// container, so it can hide the family-2 chat feed (`FeedWinOverlayView`'s `ChatFeed`,
    /// which is a sibling composed by `MinimalDesign.playerOverlay`, not a descendant of this
    /// view, so `cleanMode` — a private `@State` here — cannot reach it any other way) while
    /// clean mode is on (rb-ios-clean-mode-hide-chat-feed). Read-only state report, mirrors the
    /// existing `onInfoPanelPresentedChange` / `onIsLiveChange` precedents above. nil (default /
    /// snapshot) → no report (baseline unchanged).
    private let onCleanModeChange: ((Bool) -> Void)?

    /// Reports the LIVE bottom bar「更多」(⋯) collapsible menu (`liveMoreSheetPresented`,
    /// `LiveMoreSheetView`) open/closed state to the container each time it changes, so the
    /// container can hide the family-2 chat feed (which sits in a HIGHER overlay layer and would
    /// otherwise occlude the menu / swallow its taps) while the menu is up
    /// (rb-ios-live-more-sheet-above-chat). The menu itself (content / share / contact actions /
    /// `.lbBottomSheet` presentation) is unchanged — this is a read-only state report, mirrors the
    /// existing `onInfoPanelPresentedChange` precedent above. nil (default / snapshot) → no report
    /// (baseline unchanged).
    private let onMoreSheetPresentedChange: ((Bool) -> Void)?

    /// Reports `hidesChatFeedForReplayCaption` (`model.isFinishedLiveReplay && model
    /// .subtitleEnabled`) — its initial value and every change — to the container, so it can
    /// additionally hide the family-2 chat feed (`FeedWinOverlayView`'s `ChatFeedView`, a sibling
    /// composed by `MinimalDesign.playerOverlay`, not a descendant of this view) while an already-
    /// finished-live replay has CC captions on, letting the caption take over the freed area
    /// (rb-ios-caption-overlay-align-hide-chat — user report: 「回放啟用字幕要隱藏聊天室」). A
    /// genuinely live broadcast (`isFinishedLiveReplay == false`) is NEVER affected by this report,
    /// regardless of `subtitleEnabled`. Read-only state report, mirrors the existing
    /// `onIsLiveChange` / `onHasAnnounceChange` precedents above. nil (default / snapshot) → no
    /// report (baseline unchanged).
    private let onReplayCaptionHidesChatChange: ((Bool) -> Void)?

    /// Test-only observability hook (`rb-ios-gesture-clean-mode-v2`, `docs/unit-test-discipline.md`
    /// `*ForTesting` naming): called SYNCHRONOUSLY, alongside `model.seekBy(_:)`, from BOTH the
    /// double-tap-seek commit (`handleVideoTap(zone:)`) and each 2×-speed tick
    /// (`scheduleSpeedModeTick()`). `nil` (default, every production / non-test call site) →
    /// inert. This exists ONLY because `model.seekBy(_:)` calls `template?.seekBy(_:)`
    /// (`PlayerShellModel.swift`), and `template` is a `private weak var`, always `nil` on a
    /// demo/no-template `PlayerShellModel` — so the call itself has no other externally observable
    /// effect on such a model (the same constraint `testTapDispatch_nonLiveDoesNotCallOnToggleMute`'s
    /// doc comment already notes for `togglePlayPause()`). Passes the exact delta seconds
    /// (`+10`/`-10` for a seek commit, `+speedModeExtraSeekPerTick` for a speed tick) so a test can
    /// tell the two apart.
    private let seekByForTesting: ((Double) -> Void)?

    /// Ctor-injected scheduling function for a DEFERRED action: `(delay, action) -> cancel`.
    /// Renamed from `liveTapSchedule` (`rb-ios-gesture-clean-mode-v2`, design R29 — the R23
    /// lineage's "defer a LIVE mute-commit / already-ended-replay play-pause-commit so a
    /// following double-tap can cancel it" concept is RETIRED along with double-tap-to-like; this
    /// injection point is GENERIC scheduling machinery, not tied to that retired semantic, so it
    /// is reused rather than reinvented): now drives TWO independent things, both reusing the same
    /// primitive —
    ///   1. `handleVideoTap(zone:)`'s deferred `cleanMode` toggle (seekable content only): a short
    ///      tap schedules the toggle `doubleTapSeekWindow` (0.32s) out; a following same-half tap
    ///      within that window cancels it and commits a seek instead.
    ///   2. `scheduleSpeedModeTick()`'s recursive 2×-speed re-scheduling while a long-press is held
    ///      (each tick, if `speedMode` is still `true`, calls `model.seekBy(_:)` then schedules the
    ///      next tick via this SAME function).
    /// Production default (set in `init`) wraps `DispatchWorkItem` + `DispatchQueue.main.asyncAfter`
    /// — the SAME primitive `showMuteToast` already uses elsewhere in this file, just made
    /// swappable. A plain function type (not a named `protocol`) so it can sit in this `public
    /// init` without any cross-module accessibility mismatch.
    ///
    /// Tests inject a capturing fake instead of the production default (`Fake*` naming,
    /// `docs/unit-test-discipline.md`, defined in the test target) that records every
    /// `(delay, action)` pair and the cancel-call count of the closure it returns — "scheduled" /
    /// "cancelled" / "fired" (by invoking the captured `action` directly) are each observed via a
    /// plain reference type the TEST itself holds — never by reading `@State` back across two
    /// separate top-level calls, which `PlayerShellGestureCleanModeRewriteTests.swift` §9.3
    /// already empirically proved unreliable outside a live SwiftUI hierarchy.
    private let cleanModeTapSchedule: (TimeInterval, @escaping () -> Void) -> (() -> Void)

    // MARK: - Transient gesture-feedback state (default hidden → snapshot-neutral)

    /// True once the CURRENT press has crossed the long-press threshold (`holdDelay`).
    /// Renamed from `isHolding` (rb-ios-gesture-clean-mode-rewrite, design.md §2). Meaning
    /// updated AGAIN by `rb-ios-gesture-clean-mode-v2` (design R29): it no longer answers "has
    /// this gesture toggled `cleanMode`" (R23's long-press semantic) — long-press now drives
    /// `speedMode` (2× seek, seekable content only) instead — this flag answers "has this
    /// gesture's speed-mode timer already fired" for `resolveGestureEnd`'s tap/hold/swipe
    /// classification. Reset to `false` on release (`handleDragEnded`'s `.hold` case) so the
    /// NEXT press starts clean.
    @State private var longPressFired: Bool = false

    /// `true` while the CURRENT long-press is driving 2×-speed seeking (`rb-ios-gesture-clean-
    /// mode-v2`, design R29) — only ever set while `isSeekable == true` (a real live stream in
    /// progress, or its upcoming preview, never schedules the long-press timer that would set
    /// this — see `handleDragChanged`). Set `true` when `scheduleSpeedModeStart()`'s timer fires;
    /// set back to `false` on release (`handleDragEnded`'s `.hold` case), which also stops the
    /// recursive `scheduleSpeedModeTick()` chain (each tick checks this before calling
    /// `model.seekBy(_:)` and before re-scheduling itself).
    @State private var speedMode: Bool = false

    /// The half of the video area (`TapZone`) the CURRENT press started in — captured once per
    /// press (`handleDragChanged`'s first call) from the gesture's `startLocation.x` relative to
    /// the container width, and read back by `handleVideoTap(zone:)` to decide double-tap-seek
    /// direction. `nil` between presses. `rb-ios-gesture-clean-mode-v2`, design R29.
    @State private var pressZone: TapZone?

    /// Cancel closure for the currently-pending 2×-speed tick (`scheduleSpeedModeTick()`) —
    /// `rb-ios-gesture-clean-mode-v2`, design R29. Kept mainly for symmetry / an immediate-stop
    /// path on release; the recursive tick chain already self-terminates on its own the NEXT
    /// time it fires and observes `speedMode == false` (see that method's doc comment).
    @State private var speedModeTickCancel: (() -> Void)?

    /// True for ~0.7s after a tap toggles mute. Drives the centre `GestureMuteToastView`.
    ///
    /// ⚠️ NEVER SET by production code any more (`rb-ios-gesture-clean-mode-v2`, design R29):
    /// the only call site that used to flip this — the video-area tap-to-mute gesture — is
    /// retired (every short tap now toggles `cleanMode` instead; mute is reached via
    /// `PlayerHeaderBarView`'s new clean-mode-only button, which does not show this toast).
    /// Kept alongside `showMuteToast()` / `muteToastWorkItem` / `muteToastDuration` rather than
    /// removed — mirrors this file's own established precedent for other retired-but-kept
    /// mechanisms (`onHoldStart` / `onHoldEnd`, `PlaybackPausedOverlayView`'s composition).
    @State private var muteToastVisible: Bool = false

    /// Cancel closure for the currently-pending long-press-arms-2×-speed timer (after
    /// `holdDelay`). Cancelled if the finger moves past `moveTolerance` first (it is a
    /// swipe/scroll). Renamed from `holdWorkItem: DispatchWorkItem?`
    /// (`rb-ios-gesture-clean-mode-v2`): now goes through the SAME injected
    /// `cleanModeTapSchedule` primitive every other deferred action in this file uses, instead
    /// of a raw `DispatchWorkItem` — this makes "was a long-press timer even armed" (it is
    /// ONLY armed while `isSeekable`, see `handleDragChanged`) directly observable by a test's
    /// injected fake scheduler, closing a gap the raw-timer version could not be tested for.
    @State private var pendingSpeedModeStartCancel: (() -> Void)?

    /// Cancellable timer that auto-dismisses the mute toast after `muteToastDuration`.
    @State private var muteToastWorkItem: DispatchWorkItem?

    /// Cancel closure for the currently-pending deferred `cleanMode` toggle
    /// (`rb-ios-gesture-clean-mode-v2`, design R29 — renamed from `pendingLiveTapMuteCommitCancel`
    /// / merges what used to be TWO separate pending slots, `pendingLiveTapMuteCommitCancel` and
    /// `pendingReplayTapPauseCommitCancel`, into ONE: R29's short tap always defers the SAME
    /// action — toggling `cleanMode` — regardless of which seekable branch it came from, so there
    /// is only one kind of pending commit left to track) — `nil` once fired / cancelled / never
    /// scheduled. Set by `handleVideoTap(zone:)`'s single-tap branch (holds the cancel closure
    /// `cleanModeTapSchedule` returned); cleared (and invoked first) by the SAME method's
    /// double-tap branch, so a following same-half double-tap cancels the FIRST tap's pending
    /// toggle instead of letting it fire. Same `@State`-across-escaping-closure PRODUCTION-
    /// persistence shape as `pendingSpeedModeStartCancel` / `muteToastWorkItem` above (works correctly once
    /// installed in a live SwiftUI hierarchy). This value's mutations are never read back ACROSS
    /// two separate top-level test calls (the §9.3 limitation) — `cleanModeTapSchedule`'s injected
    /// fake is the observable surface for that. It CAN be pre-seeded via
    /// `pendingCleanModeToggleCancelForTesting` on `init` (mirrors the `lastSeekTapAtForTesting`
    /// precedent below) so a test can simulate "a first tap already scheduled a pending toggle"
    /// and drive a SINGLE call under test to observe that seeded closure being invoked.
    @State private var pendingCleanModeToggleCancel: (() -> Void)?

    /// Whether a single touch's drag is in progress (prevents re-scheduling the hold on
    /// every `onChanged`; reset on `onEnded`).
    @State private var dragActive: Bool = false

    /// Wall-clock time of the most recent SEEK-ELIGIBLE tap — a tap landing while `isSeekable ==
    /// true` (VOD or an already-ended live replay). Renamed from `lastLikeableTapAt`
    /// (`rb-ios-gesture-clean-mode-v2`, design R29: double-tap-to-like is retired; this tracker
    /// now serves double-tap-to-SEEK instead — see `handleVideoTap(zone:)`). Used together with
    /// `lastSeekTapZone` to detect a following same-half double-tap within `doubleTapSeekWindow`.
    /// `nil` = no seek-eligible tap tracked yet (or the previous one was just consumed). NOT reset
    /// on a video switch — mirrors the existing `cleanMode` / `dismissedVodProductIds` precedent of
    /// local presentation state with no natural reset hook to piggyback on; the window is only
    /// 0.32s, so the risk of a stray cross-video double-tap match is negligible.
    ///
    /// ⚠️ Like every OTHER `@State` on this SwiftUI `View` value type, a write made by ONE
    /// `handleDragEnded` call is NOT reliably observable by reading this property back — even via
    /// a SECOND, separate, purely-synchronous direct method call on the exact same `view` value
    /// held by a test outside a live SwiftUI hierarchy (empirically verified while building the
    /// R23 lineage this supersedes: two immediate, non-escaping, back-to-back
    /// `handleDragEnded(.zero)` calls did NOT recognize a double-tap — broader than, but consistent
    /// with, the escaping-closure-specific limitation `PlayerShellGestureCleanModeRewriteTests`
    /// §9.3's doc comment already documents for `cleanMode`). Tests therefore seed this via
    /// `lastSeekTapAtForTesting` on `init` (mirrors the `cleanModeForTesting` /
    /// `isScrubbingForTesting` precedent) and drive the SINGLE call whose outcome is under test —
    /// never two separate calls expecting this to have carried a value from the first into the
    /// second.
    @State private var lastSeekTapAt: Date?

    /// The `TapZone` of the tap tracked by `lastSeekTapAt` — a double-tap only counts if the
    /// SECOND tap lands in the SAME half as this one (mirrors design `screens.jsx`'s
    /// `last.zone === ps.zone` check). `nil` alongside `lastSeekTapAt == nil`. Seedable via
    /// `lastSeekTapZoneForTesting` on `init`.
    @State private var lastSeekTapZone: TapZone?

    /// Long-press (→ 2×-speed seeking while held, seekable content only) is recognized after
    /// this press duration (distinguishes it from a quick tap). `0.45` — VALUE UNCHANGED across
    /// R23 → R29 (aligned to `screens.jsx`'s `450`ms both times), only what fires at the end of
    /// it changed (R23: toggle `cleanMode`; R29: start `speedMode`).
    private static let holdDelay: TimeInterval = 0.45
    /// The mute toast auto-dismisses after this duration (issue 5: ~0.7s).
    private static let muteToastDuration: TimeInterval = 0.7
    /// Finger movement (pt) past which a pending hold is cancelled (it is a swipe/scroll).
    private static let moveTolerance: CGFloat = 12
    /// Double-tap-to-SEEK recognition window (renamed from `doubleTapLikeWindow`,
    /// `rb-ios-gesture-clean-mode-v2`, design R29: double-tap-to-like is retired; this window now
    /// serves double-tap-to-seek AND doubles as the seekable short-tap's `cleanMode`-toggle DEFER
    /// delay — see `handleVideoTap(zone:)`): a second same-half tap landing within this many
    /// seconds of the first counts as a double-tap. `0.32` — VALUE UNCHANGED from the retired
    /// `doubleTapLikeWindow` (aligned to `design/templates/minimal/screens.jsx`'s
    /// `tapTimerRef.current = setTimeout(..., 320)`, which serves BOTH roles in the design
    /// reference too — the same `320`ms literal is both the defer delay and the double-tap match
    /// window there).
    private static let doubleTapSeekWindow: TimeInterval = 0.32

    /// Double-tap-seek step, seconds (`rb-ios-gesture-clean-mode-v2`, design R29): a same-half
    /// double-tap seeks the video forward (right half) or backward (left half) by this many
    /// seconds via `model.seekBy(_:)`. `10`, matching design `screens.jsx`'s `deltaSec = ps.zone
    /// === 'ff' ? 10 : -10`.
    private static let seekStepSeconds: Double = 10

    /// 2×-speed tick interval, seconds (`rb-ios-gesture-clean-mode-v2`, design R29) — while a
    /// long-press is held on seekable content, `scheduleSpeedModeTick()` re-fires this often.
    /// reference-ui has no playback-engine rate-change API to call (see design.md Decision 3), so
    /// this approximates "2× forward" by additionally seeking `speedModeExtraSeekPerTick` forward
    /// every tick ON TOP OF the engine's own normal 1× playback — net effect ≈ 2× real time.
    private static let speedModeTickInterval: TimeInterval = 0.5

    /// Extra seconds seeked forward per 2×-speed tick (`rb-ios-gesture-clean-mode-v2`, design
    /// R29) — see `speedModeTickInterval`'s doc comment for the approximation this implements.
    /// Equal to `speedModeTickInterval` so the extra seek exactly doubles the engine's own
    /// concurrent 1× progress (1× + 1× ≈ 2×).
    private static let speedModeExtraSeekPerTick: Double = 0.5

    // MARK: - Playback-progress scrub state (rb-ios-restore-vod-playback-progress-bar)

    /// `true` while the finger is actually down on `PlaybackProgressBarView` (touch-down…
    /// touch-up). Drives: hiding the VOD/LIVE chrome that would otherwise sit under the
    /// expanded transport bar, and (inside the bar itself) the drag-time timestamp readout.
    /// Distinct from `scrubBarExpanded` — see that property's doc comment.
    @State private var isScrubbing: Bool = false

    /// `true` from touch-down through `scrubHoldDuration` (2.8s) after touch-up. Drives the
    /// transport-bar-vs-thin-line visual AND the ~36pt bottom lift applied to chrome that has
    /// reappeared during the post-release hold window. MUST be a SEPARATE `@State` from
    /// `isScrubbing`: the design wants the transport bar (and the lifted chrome) to keep
    /// showing after release while the drag-time readout disappears immediately.
    @State private var scrubBarExpanded: Bool = false

    /// Cancellable timer that collapses `scrubBarExpanded` back to `false` `scrubHoldDuration`
    /// after the finger lifts. Re-scheduled (cancelling any pending collapse) on every new
    /// scrub start, mirroring `pendingSpeedModeStartCancel` / `muteToastWorkItem` above.
    @State private var scrubCollapseWorkItem: DispatchWorkItem?

    /// The transport bar stays expanded this long after the finger lifts (design: 2.8s).
    private static let scrubHoldDuration: TimeInterval = 2.8
    /// The bottom lift applied to chrome that reappears during the post-release hold window, so
    /// it clears the still-expanded transport bar (design: ~36pt).
    private static let scrubChromeLift: CGFloat = 36

    /// PURE: whether `PlaybackProgressBarView` should be composed (design `screens.jsx`
    /// `LBPPlayerScreen` "Playback progress bar — VOD and replay only": `isMain && !isUpcoming
    /// && (!isLive || isReplay)`). The `isReplay` disjunct is fed `model.isFinishedLiveReplay`
    /// (`type == 3 || (type == 2 && liveStatus == 3)` — an ALREADY-ENDED live now watched back,
    /// `isLive == false` there too) — NOT the narrower core `playbackProgress.isReplay` DVR
    /// concept (a stream still actively live, `liveStatus == 1`, scrubbed behind the live edge).
    /// The two are mutually exclusive with `isLive` in incompatible ways: `isFinishedLiveReplay`
    /// can NEVER be `true` while `isLive` is `true`, so in practice this reduces to `isMain &&
    /// !isUpcoming && !isLive` — the bar shows for pure VOD and a finished-live replay, and NEVER
    /// while genuinely live (matches core's `vodScrubAllowed`, which rejects any seek while
    /// `liveStatus == 1` — a bar that showed there could visually drag but never actually seek).
    /// Kept as a literal `isReplay` PARAMETER (not simplified to a 3-arg function) for 1:1
    /// fidelity with the documented design formula; only the CALL SITE decides which flag feeds
    /// it. Unit-testable without rendering a view (rb-ios-restore-vod-playback-progress-bar).
    static func showsPlaybackProgressBar(isMain: Bool, isUpcoming: Bool, isLive: Bool, isReplay: Bool) -> Bool {
        isMain && !isUpcoming && (!isLive || isReplay)
    }

    /// The MAIN playback phase feeding `showsPlaybackProgressBar`'s `isMain` — not the intro MP4
    /// and out of the cold-start loading/splash sequence (mirrors design `screens.jsx`'s
    /// `isMain`). `isUpcoming` is passed separately to `showsPlaybackProgressBar` for 1:1
    /// fidelity with the documented formula, even though it never overlaps `introPlaying` here.
    private var isMainPlaybackPhase: Bool {
        !model.introPlaying && model.startPhase != .loading && model.startPhase != .splash
    }

    /// Whether `PlaybackProgressBarView` should be composed for the current model snapshot.
    /// Feeds `model.isFinishedLiveReplay` (已結束直播回放) as the `isReplay` disjunct — NOT
    /// `model.isReplay` (the narrower behind-live-edge-while-still-live DVR concept, which
    /// `vodScrubAllowed` would reject any seek for anyway). See the static function's doc
    /// comment.
    private var showsPlaybackProgressBar: Bool {
        Self.showsPlaybackProgressBar(isMain: isMainPlaybackPhase, isUpcoming: model.isUpcoming,
                                      isLive: model.isLive, isReplay: model.isFinishedLiveReplay)
    }

    // MARK: - LIVE-now pill display gate (rb-ios-live-now-pill, fix-ios-live-now-pill-active-live-leak)

    /// PURE: whether `LiveNowPillView` should be composed (design `screens.jsx` `LBPPlayerScreen`
    /// mount condition: `tweaks.showLiveNowPill !== false && (state === 'main' || isReplay) &&
    /// !isUpcoming && !isMinimized && showMainChrome && !cleanMode && !scrubbing`).
    ///
    /// Two design terms have NO parameter here, by design:
    /// - `tweaks.showLiveNowPill` is a Claude Design canvas DEMO-ONLY toggle — a stand-in for "is
    ///   there actually another live in progress" in a canvas with no real data layer. Its real
    ///   iOS equivalent is `hasLiveNow` (the live signal from `LiveNowPollController`), which
    ///   THIS function takes as a genuine parameter instead.
    /// - `isMinimized` has no analog to thread through HERE — NOT because `PlayerShellView` is
    ///   removed from the view hierarchy (it is NOT: `LivebuyPlayerPresenter` is a KEEP-ALIVE
    ///   design, `playerLayer` stays mounted for the lifetime of a session — see
    ///   `LivebuyPlayerPresenter.swift:308-323`), but because the ANCESTOR overlays it with
    ///   `.opacity(0)` + `.allowsHitTesting(false)` while a separate `floatingPreviewLayer`
    ///   (`FloatingWidgetView`) visually takes over on top. So even a `true` result here stays
    ///   invisible/untappable once minimized, automatically, without this function needing to
    ///   know about `isMinimized` at all.
    ///
    /// `isMain` mirrors `showsPlaybackProgressBar`'s identical parameter (`isMainPlaybackPhase` —
    /// not the intro MP4, not the cold-start loading/splash sequence), which already subsumes the
    /// design's separate `showMainChrome` term (that term ONLY additionally hides the opening
    /// loader / intro — see `isMainPlaybackPhase`'s doc comment — so `isMain` alone captures both).
    /// **`isMain` alone stays `true` throughout genuinely-live playback** — it says nothing about
    /// `isLive`, only about being out of intro/loading/splash — so `(isMain || isReplay)` CANNOT
    /// by itself exclude "actively live" (this was `fix-ios-live-now-pill-active-live-leak`'s bug:
    /// the pill leaked onto real live playback whenever another live was detected). `isReplay`
    /// mirrors `showsPlaybackProgressBar`'s identical disjunct: feed `model.isFinishedLiveReplay`
    /// (已結束直播回放), NOT `model.isReplay` (the narrower behind-live-edge-while-still-live DVR
    /// concept). `isLive` mirrors `showsPlaybackProgressBar`'s identical parameter (`model.isLive`)
    /// and is combined the same way, `(!isLive || isReplay)` — but appended as an INDEPENDENT
    /// trailing conjunct rather than replacing the `isMain` term, because this function's second
    /// clause is the disjunction `(isMain || isReplay)`, not `showsPlaybackProgressBar`'s bare
    /// `isMain`. `isReplay` and `isLive` are mutually exclusive (`isFinishedLiveReplay == true`
    /// implies `isLive == false`), so the trailing conjunct is a no-op on the replay branch and
    /// only ever suppresses the genuinely-live branch. Unit-testable without rendering a view.
    static func showsLiveNowPill(hasLiveNow: Bool, isMain: Bool, isUpcoming: Bool, isReplay: Bool,
                                 isLive: Bool, cleanMode: Bool, isScrubbing: Bool) -> Bool {
        hasLiveNow && (isMain || isReplay) && !isUpcoming && !cleanMode && !isScrubbing
            && (!isLive || isReplay)
    }

    /// Whether `LiveNowPillView` should be composed for the current model snapshot + local
    /// gesture state. See the static function's doc comment for the full parameter mapping.
    private var showsLiveNowPill: Bool {
        Self.showsLiveNowPill(hasLiveNow: hasLiveNow, isMain: isMainPlaybackPhase,
                              isUpcoming: model.isUpcoming, isReplay: model.isFinishedLiveReplay,
                              isLive: model.isLive, cleanMode: cleanMode, isScrubbing: isScrubbing)
    }

    /// Test seam exposing the private `showsLiveNowPill` computed property (`*ForTesting` naming
    /// per `docs/unit-test-discipline.md` §3; mirrors existing precedents such as
    /// `LivebuyWidget.isAutoRefreshActiveForTesting` / `LivebuyLiveEntry.appearedForTesting`) so a
    /// test can construct a REAL `PlayerShellView` and assert the CALL-SITE wiring — i.e. that
    /// `model.isLive` is actually threaded through to `showsLiveNowPill`'s `isLive` parameter —
    /// rather than only exercising the pure static function with hand-picked arguments. This is
    /// the specific class of gap `fix-ios-live-now-pill-active-live-leak` closes: the pure
    /// function was correct, but nothing proved the call site actually fed it the right values.
    var showsLiveNowPillForTesting: Bool { showsLiveNowPill }

    /// The extra bottom padding (`scrubChromeLift`, ~36pt) applied to VOD chrome that has
    /// reappeared during the post-release hold window (`scrubBarExpanded && !isScrubbing`) so it
    /// clears the still-expanded transport bar; `0` at every other time (including while hidden
    /// during an active drag, where the value is moot). Mirrors the `bottomInset` passed to
    /// `LiveOverlayChromeView` for the LIVE-side equivalents.
    private var scrubChromeLiftIfExpanded: CGFloat {
        (scrubBarExpanded && !isScrubbing) ? Self.scrubChromeLift : 0
    }

    /// The "exit clean mode" button's full bottom offset: the `isLive`-branched base value (see
    /// `cleanModeExitButtonBaseBottomInset(isLive:)`'s doc comment) — `rb-ios-clean-mode-exit-
    /// button-scrub-lift`: MUST NOT additionally superimpose the dynamic `scrubChromeLiftIfExpanded`
    /// lift. This button only ever renders while `cleanMode == true` (guarded at the call site
    /// below), and design `screens.jsx:401`'s formula for it — `bottom: 16 + safeArea.bottom +
    /// ((scrubVisible || cleanMode) ? 36 : 0)` — has `cleanMode` permanently true at that render
    /// site, so the ternary is permanently saturated at `36` regardless of `scrubVisible`
    /// (`_scrubBarExpanded`'s design counterpart): the `52`/`16` base values above ALREADY are that
    /// complete, one-time-computed story (see the base function's own doc comment). Superimposing
    /// `scrubChromeLiftIfExpanded` on top double-counts that `36` during the post-release hold
    /// window (`scrubBarExpanded && !isScrubbing`), producing an `88` this button never has in the
    /// design, in Android (`cleanModeExitButtonBottomDp`, a pure function with no scrub parameter),
    /// or in RN (this same button's existing Requirement: "MUST NOT depend on `scrubChromeLift`").
    /// `scrubChromeLiftIfExpanded` remains the correct dynamic lift for every OTHER floating
    /// element in this file that is mutually exclusive with — and independently visible from —
    /// this button (those render only while `!cleanMode`, so they still need the dynamic lift to
    /// bridge their own "not yet expanded" vs. "temporarily expanded" states).
    private var cleanModeExitButtonBottomInset: CGFloat {
        Self.cleanModeExitButtonBaseBottomInset(isLive: model.isLive)
    }

    /// Test seam exposing the private `cleanModeExitButtonBottomInset` computed property
    /// (`*ForTesting` naming per `docs/unit-test-discipline.md` §3; mirrors the existing
    /// `showsLiveNowPillForTesting` precedent above) so a test can construct a REAL
    /// `PlayerShellView` and assert the CALL-SITE wiring — i.e. that `model.isLive` is actually
    /// threaded through to `cleanModeExitButtonBaseBottomInset(isLive:)` — rather than only
    /// exercising the pure static function with hand-picked arguments.
    var cleanModeExitButtonBottomInsetForTesting: CGFloat { cleanModeExitButtonBottomInset }

    /// Touch-down on the progress bar → begin a scrub: cancel any pending collapse, mark both
    /// `isScrubbing` and `scrubBarExpanded` true, report both transitions.
    private func handleScrubStarted() {
        scrubCollapseWorkItem?.cancel()
        isScrubbing = true
        onScrubbingChange?(true)
        let wasExpanded = scrubBarExpanded
        scrubBarExpanded = true
        if !wasExpanded { onScrubBarExpandedChange?(true) }
    }

    /// Drag moved → forward the new absolute position to the EXISTING `model.seek(to:)`
    /// forwarder (no new core / view-model API; no debounce, per design).
    private func handleScrub(_ ratio: Double) {
        model.seek(to: ratio * model.duration)
    }

    /// Finger lifted → `isScrubbing` ends immediately (the readout disappears, and
    /// [onScrubbingChange] reports `false` right away so the chat feed can reappear lifted);
    /// schedule the transport bar's collapse back to the thin line after `scrubHoldDuration`
    /// ([onScrubBarExpandedChange] reports `false` only once that hold window actually ends).
    private func handleScrubEnded() {
        isScrubbing = false
        onScrubbingChange?(false)
        let work = DispatchWorkItem {
            self.scrubBarExpanded = false
            self.onScrubBarExpandedChange?(false)
        }
        scrubCollapseWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.scrubHoldDuration, execute: work)
    }

    /// App 進背景（`didEnterBackgroundNotification`，含觸發系統自動 PiP 的那次轉場）視同放開手指——
    /// `DragGesture` 沒有「被系統中斷」的回呼，唯一能偵測「拖曳被打斷」的訊號就是這個生命週期通知。
    /// 只在真的正在拖曳中才動作，重用既有 [handleScrubEnded] 路徑（不直接改 `scrubBarExpanded`），
    /// 讓 `onScrubbingChange` / `onScrubBarExpandedChange` 照既有時序正常回報；非拖曳中（含放開手指後
    /// 2.8 秒維持展開期間）MUST NOT 有任何可觀察副作用 (ios-scrub-reset-on-background-reference-ui)。
    ///
    /// 存取層級比照同檔案 `handleDragChanged` / `handleDragEnded`（非 `private`）——讓測試能在一個
    /// 真實建構的 struct instance 上直接同步呼叫並斷言 `onScrubbingChange` 是否觸發，而不必透過
    /// `.onReceive` 的 Combine 訂閱本身（後者是非同步、跨 escaping closure 邊界的路徑，本檔案
    /// `PlayerShellGestureCleanModeRewriteTests.swift` §9.3 已記載其在此 struct + `@State` 情境下
    /// 對測試不可觀察）；`.onReceive` 對它的接線本身以原始碼檢閱 + 全套 snapshot suite 零回歸驗證。
    func handleDidEnterBackground() {
        if isScrubbing {
            handleScrubEnded()
        }
    }

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
                hasLiveNow: Bool = false,
                onGoLive: (() -> Void)? = nil,
                captionText: String = "",
                onSwipeUp: (() -> Void)? = nil,
                onSwipeDown: (() -> Void)? = nil,
                onCloseRequest: (() -> Void)? = nil,
                onHoldStart: (() -> Void)? = nil,
                onHoldEnd: (() -> Void)? = nil,
                composerPresented: Bool = false,
                sheetsPresented: Bool = false,
                onInfoPanelPresentedChange: ((Bool) -> Void)? = nil,
                onIsLiveChange: ((Bool) -> Void)? = nil,
                onHasAnnounceChange: ((Bool) -> Void)? = nil,
                onScrubbingChange: ((Bool) -> Void)? = nil,
                onScrubBarExpandedChange: ((Bool) -> Void)? = nil,
                onCleanModeChange: ((Bool) -> Void)? = nil,
                onMoreSheetPresentedChange: ((Bool) -> Void)? = nil,
                onReplayCaptionHidesChatChange: ((Bool) -> Void)? = nil,
                isScrubbingForTesting: Bool = false,
                scrubBarExpandedForTesting: Bool = false,
                cleanModeForTesting: Bool = false,
                lastSeekTapAtForTesting: Date? = nil,
                lastSeekTapZoneForTesting: TapZone? = nil,
                seekByForTesting: ((Double) -> Void)? = nil,
                cleanModeTapSchedule: @escaping (TimeInterval, @escaping () -> Void) -> (() -> Void) = { delay, action in
                    let work = DispatchWorkItem(block: action)
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
                    return { work.cancel() }
                },
                pendingCleanModeToggleCancelForTesting: (() -> Void)? = nil) {
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
        self.hasLiveNow = hasLiveNow
        self.onGoLive = onGoLive
        self.captionText = captionText
        self.onSwipeUp = onSwipeUp
        self.onSwipeDown = onSwipeDown
        self.onCloseRequest = onCloseRequest
        self.onHoldStart = onHoldStart
        self.onHoldEnd = onHoldEnd
        self.composerPresented = composerPresented
        self.sheetsPresented = sheetsPresented
        self.onInfoPanelPresentedChange = onInfoPanelPresentedChange
        self.onIsLiveChange = onIsLiveChange
        self.onHasAnnounceChange = onHasAnnounceChange
        self.onScrubbingChange = onScrubbingChange
        self.onScrubBarExpandedChange = onScrubBarExpandedChange
        self.onCleanModeChange = onCleanModeChange
        self.onMoreSheetPresentedChange = onMoreSheetPresentedChange
        self.onReplayCaptionHidesChatChange = onReplayCaptionHidesChatChange
        self.seekByForTesting = seekByForTesting
        self.cleanModeTapSchedule = cleanModeTapSchedule
        // Test-only seed for the two scrub-driven `@State` properties (see their doc comments
        // below) — there is no production gesture-simulation path to reach these states in a
        // synchronous snapshot render, so `PlayerShellPlaybackProgressBarSnapshotTests` seeds them
        // directly via this initializer (docs/unit-test-discipline.md `*ForTesting` naming).
        _isScrubbing = State(initialValue: isScrubbingForTesting)
        _scrubBarExpanded = State(initialValue: scrubBarExpandedForTesting)
        // Test-only seed for `cleanMode` (rb-ios-gesture-clean-mode-rewrite §6 chrome-hiding
        // contract) — same rationale as the two scrub seeds directly above.
        _cleanMode = State(initialValue: cleanModeForTesting)
        // Test-only seed for `lastSeekTapAt` / `lastSeekTapZone` (`rb-ios-gesture-clean-mode-v2`)
        // — same rationale: lets a test simulate "a first seek-eligible tap already happened Δt
        // ago, in this half" and drive the SINGLE `handleDragEnded` call under test, without
        // depending on `@State` carrying a value from one call into a separate one (see
        // `lastSeekTapAt`'s doc comment for why that is NOT reliable outside a live SwiftUI
        // hierarchy).
        _lastSeekTapAt = State(initialValue: lastSeekTapAtForTesting)
        _lastSeekTapZone = State(initialValue: lastSeekTapZoneForTesting)
        // Test-only seed for `pendingCleanModeToggleCancel` (`rb-ios-gesture-clean-mode-v2`) —
        // same rationale as `lastSeekTapAtForTesting` directly above: lets a test simulate "the
        // FIRST tap already scheduled a pending `cleanMode` toggle" and drive the SINGLE
        // `handleDragEnded` call under test (the SECOND tap, classified as a double-tap via
        // `lastSeekTapAtForTesting` / `lastSeekTapZoneForTesting` above), asserting that call
        // cancels the seeded closure — without depending on `@State` carrying a value written by
        // one top-level call into a separate one.
        _pendingCleanModeToggleCancel = State(initialValue: pendingCleanModeToggleCancelForTesting)
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

    /// PURE: whether a vertical swipe is allowed to trigger a video-switch / close action.
    /// **直播正在進行中**（`isLive`, `liveStatus == 1`，涵蓋「串流直播」與「預錄直播」兩者，與
    /// `isUpcoming` / `isFinishedLiveReplay` 互斥）MUST NOT 用垂直滑動切換影片（design R18，
    /// `screens.jsx` 的 `liveInProgress = effectiveState === 'live_main' && !isUpcoming && !isReplay`）；
    /// 預告倒數（upcoming）與已結束直播的回放（finished-live replay）不受影響，維持可滑動換片
    /// （rb-ios-live-swipe-gesture-gating）。
    ///
    /// **任一商品 sheet 呈現中同樣 MUST NOT 用垂直滑動切換影片**（`sheetsPresented`——商品列表抽屜 /
    /// 明細-補貨 sheet / 放大燈箱 / 加購需登入閘 / 「請選規格」提示中任一者，見
    /// `ProductSheetsOverlayView.anyProductSheetPresented`。純防禦性：`ProductSheetsOverlayView`
    /// 的 sheet/modal scrim 目前只掛 tap 手勢，沒有掛任何垂直拖曳辨識器與此視圖競爭，理論上跨越 sheet
    /// 邊界起手的垂直拖曳仍可能被此層判定為換片並執行——`rb-ios-block-swipe-nav-when-sheet-open`）。
    /// 預設 `false`，既有呼叫端零改動、行為不變。抽成純函式使此 gate 可單元測試（不需渲染手勢）。
    static func allowsSwipeNav(isLive: Bool, sheetsPresented: Bool = false) -> Bool {
        !isLive && !sheetsPresented
    }

    /// Resolves a committed vertical drag into the correct action, honoring host overrides.
    /// - **直播進行中**（`model.isLive == true`）MUST NOT 觸發任何換片 / 關閉動作——本函式整個提早
    ///   return，host override（`onSwipeUp`/`onSwipeDown`）、model fallback（`navigateToNext`/
    ///   `navigateToPrev`）、close-on-empty（`onCloseRequest`）三者皆不觸發（rb-ios-live-swipe-
    ///   gesture-gating）。拖曳事件本身仍由呼叫端（`resolveGestureEnd`）分類為 swipe，不會落回 tap，
    ///   故仍被手勢層吞掉，不會誤觸點擊靜音。
    /// - **任一商品 sheet 呈現中**（`sheetsPresented == true`）同樣 MUST NOT 觸發任何換片 / 關閉動作，
    ///   抑制範圍與「直播進行中」完全相同（`rb-ios-block-swipe-nav-when-sheet-open`）。
    /// - A host `onSwipeUp` / `onSwipeDown` override ALWAYS wins (called instead of any
    ///   template-nav / close behavior).
    /// - Otherwise (template-nav fallback): swipe toward a video → navigate; swipe toward
    ///   an EMPTY direction (no next / no prev) → `onCloseRequest()` (close the player, #7).
    func handleSwipeEnded(translationHeight dy: CGFloat) {
        // 直播進行中 / 任一商品 sheet 呈現中：不換片、不關閉（拖曳事件已由呼叫端分類為 swipe，仍算被
        // 吞掉，只是無 side effect）。
        guard Self.allowsSwipeNav(isLive: model.isLive, sheetsPresented: sheetsPresented) else { return }
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

    /// Classify a finished gesture: a recognized long-press wins; else a committed vertical
    /// drag is a swipe (up = next, down = prev); else (quick, small translation) a tap. The
    /// `isHolding` parameter label is UNCHANGED (design.md §2: renaming it is cosmetic, not
    /// mandatory — kept verbatim to avoid churning every existing call site) but its SEMANTICS
    /// changed (rb-ios-gesture-clean-mode-rewrite): it now answers "has this gesture already
    /// crossed the long-press threshold" (fed `longPressFired` at the call site), not "is a
    /// hold-to-pause currently in progress".
    static func resolveGestureEnd(isHolding: Bool, translationHeight dy: CGFloat) -> GestureOutcome {
        if isHolding { return .hold }
        if dy <= -swipeThreshold { return .swipeUp }
        if dy >= swipeThreshold { return .swipeDown }
        return .tap
    }

    /// Which half of the video area a press started in (`rb-ios-gesture-clean-mode-v2`, design
    /// R29) — mirrors design `screens.jsx`'s `zone = (e.clientX - rect.left) < rect.width / 2 ?
    /// 'rw' : 'ff'`. Drives double-tap-seek direction (`.rewind` → `-10s`, `.fastForward` →
    /// `+10s`) — see `handleVideoTap(zone:)`. Deliberately NOT consulted by the long-press 2×
    /// speed path (`scheduleSpeedModeStart()`) — see that method's doc comment for why the
    /// direction bug is preserved on purpose.
    public enum TapZone: Equatable { case rewind, fastForward }

    /// PURE: classify a press's starting X position into a `TapZone`. `containerWidth <= 0`
    /// (never expected in practice) falls back to `.fastForward` rather than dividing by zero.
    static func tapZone(startX: CGFloat, containerWidth: CGFloat) -> TapZone {
        guard containerWidth > 0 else { return .fastForward }
        return startX < containerWidth / 2 ? .rewind : .fastForward
    }

    /// PURE: whether the CURRENT mode supports seeking (double-tap ±10s, long-press 2× speed) —
    /// `rb-ios-gesture-clean-mode-v2`, design R29's single decision point for both gestures.
    /// Mirrors design `screens.jsx`'s `seekable = isReplay || !isLive`, where that `isLive`
    /// bundles upcoming INTO the live family (`stateInLiveFamily` includes `'upcoming_main'`) —
    /// this iOS formula therefore takes `isUpcoming` as an EXPLICIT separate parameter rather
    /// than relying on `model.isLive` alone: `model.isLive` is narrower here (`liveStatus == 1`,
    /// mutually exclusive with `isUpcoming` — see `resolveGestureEnd`'s historical `isLive`
    /// usage elsewhere in this file), so `!isLive` alone would wrongly mark the upcoming preview
    /// as seekable. `isFinishedLiveReplay` and `(isLive || isUpcoming)` are mutually exclusive in
    /// practice, so the two disjuncts never both fire, but both are written out for 1:1 fidelity
    /// with the documented design formula.
    static func isSeekable(isLive: Bool, isUpcoming: Bool, isFinishedLiveReplay: Bool) -> Bool {
        isFinishedLiveReplay || !(isLive || isUpcoming)
    }

    /// PURE: whether a seek-eligible tap ending `elapsed` seconds after the previous tracked
    /// seek-eligible tap, in the SAME `TapZone`, counts as a double-tap-seek hit
    /// (`rb-ios-gesture-clean-mode-v2`, design R29 — renamed from the retired
    /// `isDoubleTapLikeHit`, mirrors design `screens.jsx`'s `(now - last.t) < 320 && last.zone
    /// === ps.zone` compound condition). `elapsed == nil` (no seek-eligible tap tracked yet, or
    /// the tracker was just consumed) or `sameZone == false` (second tap landed in the OTHER
    /// half) is never a double-tap — a following tap in a different half instead falls back to
    /// its own independent deferred `cleanMode` toggle. Extracted (unit-test discipline) so the
    /// timing boundary is directly testable with synthetic elapsed values — no real clock /
    /// timer / rendered gesture required.
    static func isDoubleTapSeekHit(elapsedSinceLastSeekTap elapsed: TimeInterval?, sameZone: Bool, window: TimeInterval) -> Bool {
        guard let elapsed = elapsed, sameZone else { return false }
        return elapsed <= window
    }

    /// PURE: base bottom offset (pt, BEFORE the dynamic post-scrub-release `scrubChromeLiftIfExpanded`
    /// lift) for the "exit clean mode" button — `rb-ios-clean-mode-exit-icon-fix`, aligning the
    /// button to design `screens.jsx`'s two separate clean-mode-exit-button branches: the LIVE
    /// branch (`cleanMode && !isReplay`) anchors at `bottom: 16 + safeArea.bottom`; the VOD/replay
    /// branch anchors at `bottom: 16 + safeArea.bottom + 36` (i.e. `52`) — that `+36` there is a
    /// FIXED clearance baked into that design branch (it always renders with the transport bar
    /// expanded), NOT this view's own dynamic `scrubChromeLiftIfExpanded`, which is layered on top
    /// separately by the caller. `isLive` mirrors `model.isLive` (`liveStatus == 1`, mutually
    /// exclusive with VOD / finished-live replay — see `isSeekable`'s doc comment above), matching
    /// the design's LIVE-vs-VOD/replay split exactly. This view is documented (file header) as
    /// safe-area-inset-free manual padding — no other bottom-anchored element in this file reads a
    /// dynamic safe-area value, so neither does this one (see design.md Decision 2 for the full
    /// rationale); the `52`/`16` constants are the complete story, not a partial one.
    static func cleanModeExitButtonBaseBottomInset(isLive: Bool) -> CGFloat {
        isLive ? 16 : 52
    }

    // MARK: - LIVE like burst count / timing (rb-ios-live-like-burst-restyle, design R37)
    //
    // Design `LBLiveBottomBar`'s `likeAnimation(n)`: `count = (n ?? random(0...3)) + 1` (1...4
    // hearts), each spawned 300ms apart, with the like icon staying bright (accent) until
    // `300*(count-1) + 2000` ms after the tap. Both resolved here as PURE functions (no
    // rendering, no timers) so the count RANGE and the duration FORMULA are unit-testable
    // without driving SwiftUI state — the actual scheduling (staggered `liveHeartTick` bumps +
    // the `liveLiked` revert) lives in the `onLike` closure below, which is not unit-testable
    // (it's a `DispatchQueue`-driven closure), matching this file's existing
    // pure-decision/impure-dispatch split (see `handleDragChanged` above).

    /// Pure — resolves how many hearts one like tap spawns. Range **1...4** (design `+ 1` after
    /// a `0...3` random draw). Injectable RNG for test determinism.
    static func resolveLikeBurstCount<G: RandomNumberGenerator>(using generator: inout G) -> Int {
        Int.random(in: 0...3, using: &generator) + 1
    }

    /// Production entry point — uses the system RNG.
    static func resolveLikeBurstCount() -> Int {
        var rng = SystemRandomNumberGenerator()
        return resolveLikeBurstCount(using: &rng)
    }

    /// Pure — total milliseconds the like icon stays bright (accent) after a tap that spawned
    /// `count` staggered bursts `staggerMs` apart, mirroring design `300*(count-1) + 2000`.
    static func likeGlowDurationMs(count: Int, staggerMs: Double = 300, tailMs: Double = 2000) -> Double {
        staggerMs * Double(count - 1) + tailMs
    }

    /// Drag in progress: on the first change, record which half the press started in
    /// (`pressZone`) and — ONLY while `isSeekable` — schedule the long-press 2×-speed promotion.
    /// A real live stream in progress or its upcoming preview never schedules this timer at all,
    /// so long-press is a structural no-op there (see `scheduleSpeedModeStart()`'s doc comment —
    /// this is the specific detail R29 is easiest to get wrong: R23's long-press toggled
    /// `cleanMode` unconditionally including LIVE; R29's long-press is seekable-ONLY). If the
    /// finger moves past `moveTolerance` before the timer fires, cancel it (it is a swipe/scroll,
    /// not a long-press).
    ///
    /// `startX` / `containerWidth` default to `0` / `1` so existing call sites that don't care
    /// about `pressZone` (most tap/swipe/hold classification tests) need no changes.
    ///
    /// Extracted (`internal`, not `private`) so the schedule/cancel dispatch is directly
    /// unit-testable without rendering a SwiftUI gesture — mirrors the EXISTING
    /// `handleSwipeEnded` precedent.
    func handleDragChanged(_ translation: CGSize, startX: CGFloat = 0, containerWidth: CGFloat = 1) {
        if !dragActive {
            dragActive = true
            pressZone = Self.tapZone(startX: startX, containerWidth: containerWidth)
            if Self.isSeekable(isLive: model.isLive, isUpcoming: model.isUpcoming,
                               isFinishedLiveReplay: model.isFinishedLiveReplay) {
                scheduleSpeedModeStart()
            }
        }
        if !longPressFired,
           abs(translation.width) > Self.moveTolerance || abs(translation.height) > Self.moveTolerance {
            cancelPendingHold()
        }
    }

    /// Drag ended: classify and dispatch (`rb-ios-gesture-clean-mode-v2`, design R29 — SUPERSEDES
    /// the retired R23 dispatch entirely; see this type's other doc comments for the individual
    /// pieces). Long-press (`.hold`, only ever reachable when `isSeekable` scheduled the timer in
    /// `handleDragChanged`) → stop 2×-speed seeking and reset the classification flag; it does
    /// NOT call `onHoldStart`/`onHoldEnd` (retired). Swipe → existing `handleSwipeEnded`,
    /// unaffected. Tap → `handleVideoTap(zone:)`, fed the zone recorded at press-start.
    ///
    /// Extracted (`internal`, not `private`) — same rationale as `handleDragChanged` above.
    func handleDragEnded(_ translation: CGSize, startX: CGFloat = 0, containerWidth: CGFloat = 1) {
        cancelPendingHold()
        let zone = pressZone ?? Self.tapZone(startX: startX, containerWidth: containerWidth)
        switch Self.resolveGestureEnd(isHolding: longPressFired, translationHeight: translation.height) {
        case .hold:
            longPressFired = false
            stopSpeedMode()
        case .swipeUp, .swipeDown:
            handleSwipeEnded(translationHeight: translation.height)
        case .tap:
            handleVideoTap(zone: zone)
        }
        dragActive = false
        pressZone = nil
    }

    /// Schedule the long-press promotion: after `holdDelay` (~0.45s) of a sustained press on
    /// SEEKABLE content, start 2×-speed seeking (`rb-ios-gesture-clean-mode-v2`, design R29 —
    /// renamed from the retired `scheduleCleanModeToggle`, which used to toggle `cleanMode`
    /// here instead). Only ever scheduled when `isSeekable` (see `handleDragChanged`) — a real
    /// live stream in progress or its upcoming preview never reaches this method at all, so
    /// long-press has NO effect there (not merely "does nothing when it fires" — the timer is
    /// never even armed). Cancelled by movement or release first (`cancelPendingHold`).
    private func scheduleSpeedModeStart() {
        pendingSpeedModeStartCancel = cleanModeTapSchedule(Self.holdDelay) {
            self.longPressFired = true
            self.speedMode = true
            self.speedModeTickCancel = self.scheduleSpeedModeTick()
        }
    }

    /// Recursively re-schedules itself every `speedModeTickInterval` (0.5s) for as long as
    /// `speedMode` stays `true`, calling `model.seekBy(speedModeExtraSeekPerTick)` (+
    /// `seekByForTesting?(_:)`) on each tick — see `speedModeTickInterval`'s doc comment for the
    /// "extra seek on top of normal 1× playback ≈ 2×" approximation this implements
    /// (`rb-ios-gesture-clean-mode-v2`, design R29; no reference-ui-level playback-rate API
    /// exists to call instead — design.md Decision 3).
    ///
    /// Reuses the SAME injected `cleanModeTapSchedule` primitive `handleVideoTap(zone:)` uses for
    /// its deferred `cleanMode` toggle (not a second scheduling mechanism) — this is exactly the
    /// generic reuse that property's doc comment describes.
    ///
    /// **Direction bug preserved on purpose**: this method does NOT read `pressZone` — every
    /// tick seeks FORWARD (`+speedModeExtraSeekPerTick`) regardless of which half the press
    /// started in. This mirrors design `screens.jsx`'s own `setSpeedMode('ff')` (literal, not
    /// zone-derived) — the user explicitly confirmed (after two rounds of back-and-forth
    /// clarification, see design.md Decision 3) that this is intentional, not a defect to fix.
    ///
    /// Stops itself the NEXT time it fires after `stopSpeedMode()` sets `speedMode = false` — it
    /// checks the flag BEFORE doing anything, so no extra `seekBy` call and no further
    /// re-scheduling happen once released.
    private func scheduleSpeedModeTick() -> (() -> Void) {
        cleanModeTapSchedule(Self.speedModeTickInterval) {
            guard self.speedMode else { return }
            self.model.seekBy(Self.speedModeExtraSeekPerTick)
            self.seekByForTesting?(Self.speedModeExtraSeekPerTick)
            self.speedModeTickCancel = self.scheduleSpeedModeTick()
        }
    }

    /// Stop 2×-speed seeking (release, or a re-entrant `.hold` outcome) — resumes normal playback
    /// speed. The recursive `scheduleSpeedModeTick()` chain self-terminates the NEXT time it
    /// fires and observes `speedMode == false`; this ALSO cancels the currently-pending tick
    /// immediately, so no further `seekBy` call happens even if the tick interval has not yet
    /// elapsed.
    private func stopSpeedMode() {
        speedMode = false
        speedModeTickCancel?()
        speedModeTickCancel = nil
    }

    /// Cancel a pending (not-yet-fired) hold timer.
    private func cancelPendingHold() {
        pendingSpeedModeStartCancel?()
        pendingSpeedModeStartCancel = nil
    }

    /// Show the centre mute toast and auto-dismiss it after `muteToastDuration` (~0.7s).
    ///
    /// ⚠️ NEVER CALLED by production code any more (`rb-ios-gesture-clean-mode-v2`) — see
    /// `muteToastVisible`'s doc comment. Kept (not removed) for the same reason.
    private func showMuteToast() {
        muteToastWorkItem?.cancel()
        muteToastVisible = true
        let work = DispatchWorkItem { self.muteToastVisible = false }
        muteToastWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.muteToastDuration, execute: work)
    }

    /// Video-area single-tap dispatch (`rb-ios-gesture-clean-mode-v2`, design R29 — SUPERSEDES
    /// the retired `handleLiveTap()` / `handleReplayTap()` / `registerLikeableTap()` trio and the
    /// double-tap-to-like feature they protected). Every short tap toggles `cleanMode` — the
    /// only question is WHEN:
    ///
    /// - **Not seekable** (a real live stream in progress, or its upcoming preview): toggles
    ///   `cleanMode` IMMEDIATELY. There is no double-tap outcome to protect against here (design
    ///   R29: "直播進行中完全沒有雙擊反應"), so no defer is needed.
    /// - **Seekable** (VOD or an already-ended live replay): DEFERS the toggle by
    ///   `doubleTapSeekWindow` (0.32s) via the injected `cleanModeTapSchedule`, storing the
    ///   returned cancel closure in `pendingCleanModeToggleCancel`. If a SECOND tap lands in the
    ///   SAME `TapZone` within that window (`isDoubleTapSeekHit`), this method instead CANCELS
    ///   the pending toggle (so the user never sees a `cleanMode` flicker — the exact class of
    ///   bug the retired `live-tap-heart-delay-mute-commit-ios` / `-replay-ios` change pair
    ///   fixed for the PREVIOUS gesture pairing, now prevented from EVER regressing under the
    ///   NEW one) and commits `model.seekBy(±seekStepSeconds)` instead (+ `seekByForTesting?(_:)`)
    ///   — `.fastForward` → `+10s`, `.rewind` → `-10s`. No following second tap in the window (or
    ///   one landing in the OTHER half, which starts its OWN independent tracked/deferred pair
    ///   instead of cancelling this one) → the deferred toggle fires on its own.
    private func handleVideoTap(zone: TapZone) {
        guard Self.isSeekable(isLive: model.isLive, isUpcoming: model.isUpcoming,
                              isFinishedLiveReplay: model.isFinishedLiveReplay) else {
            cleanMode.toggle()
            return
        }
        let now = Date()
        let elapsed = lastSeekTapAt.map { now.timeIntervalSince($0) }
        let isDoubleTap = Self.isDoubleTapSeekHit(elapsedSinceLastSeekTap: elapsed,
                                                  sameZone: lastSeekTapZone == zone,
                                                  window: Self.doubleTapSeekWindow)
        if isDoubleTap {
            // Cancel the FIRST tap's pending `cleanMode` toggle instead of letting it fire — this
            // is the whole point of deferring.
            pendingCleanModeToggleCancel?()
            pendingCleanModeToggleCancel = nil
            lastSeekTapAt = nil
            lastSeekTapZone = nil
            let delta = zone == .fastForward ? Self.seekStepSeconds : -Self.seekStepSeconds
            model.seekBy(delta)
            seekByForTesting?(delta)
        } else {
            lastSeekTapAt = now
            lastSeekTapZone = zone
            pendingCleanModeToggleCancel = cleanModeTapSchedule(Self.doubleTapSeekWindow) {
                self.pendingCleanModeToggleCancel = nil
                self.cleanMode.toggle()
            }
        }
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
    /// This single source of truth drives the rail, the floating bag, the now-introducing
    /// card's bag-clearance inset (rb-ios-vod-rail-show-on-buffering), AND — since
    /// rb-ios-now-introducing-carousel-buffering-gate — whether the now-introducing card
    /// renders AT ALL (previously only its trailing inset consulted this property, so an
    /// early-non-empty `vodActiveProducts` could show the card before the rail/bag).
    private var showsVodMainChrome: Bool {
        isVodMainChrome && model.startPhase != .loading && model.startPhase != .splash
    }

    /// 右下角浮動商品袋（`FloatingBagButtonView`，48×48 + trailing 12）佔據的右側淨寬（pt）：
    /// trailing 12 + 袋 48 + 8 間隙 = 68。VOD「正在介紹」卡在浮動袋存在時，trailing 以此量內縮
    /// （往左縮短）避讓浮動袋，浮動袋本身不動（rb-ios-vod-now-introducing-no-bag-overlap）。
    private static let floatingBagClearance: CGFloat = 68

    // MARK: - CC caption overlay gate (rb-ios-replay-caption-overlay-fix)
    //
    // BUG: the real VTT/CC caption (`CaptionOverlayView`, fed by `effectiveCaption`) used to be
    // gated on `!usesLiveChrome` (`!isLive && !isFinishedLiveReplay`) — i.e. it only ever rendered
    // in the pure-VOD branch. A finished-live REPLAY (`isFinishedLiveReplay == true`) falls into
    // the `usesLiveChrome == true` branch, which instead renders the completely different,
    // host-supplied STATIC `LBLiveHostCaption` (see `PlayerShellModel`'s GAP NOTE — there is no
    // public host-caption view-model, and no `PlayerShellView` call site ever feeds it real data
    // in production) — so toggling CC during a replay flipped `model.subtitleEnabled` but no
    // caption text ever appeared. Fix: gate on `!isLive` instead, which covers pure VOD AND
    // finished-live replay; only a GENUINELY live broadcast in progress (which also has no
    // `subtitle_url` in practice) suppresses it.

    /// PURE: whether the VTT/CC caption overlay (`CaptionOverlayView`) SHOULD render for the given
    /// snapshot of flags. Unit-testable without rendering a view (mirrors the
    /// `showsPlaybackProgressBar` pure-function precedent above).
    static func showsCaptionOverlay(isLive: Bool, subtitleEnabled: Bool, hasCaption: Bool,
                                     isScrubbing: Bool, cleanMode: Bool) -> Bool {
        !isLive && subtitleEnabled && hasCaption && !isScrubbing && !cleanMode
    }

    /// VOD 字幕來源（`effectiveCaption`，rb-ios-subtitle-vtt-caption-display）：host 明確傳入的
    /// `captionText`（既有參數）優先；為空才 fallback 到 `VTTSubtitleParser.activeCue(model
    /// .subtitleCues, at: model.position)?.text ?? ""`。Hoisted to a computed property
    /// (rb-ios-replay-caption-overlay-fix) so BOTH the pure-VOD branch AND the live-chrome/replay
    /// branch can share the exact same caption-text resolution — previously this was a `let`
    /// local only to the VOD branch.
    private var effectiveCaption: String {
        captionText.isEmpty
            ? (VTTSubtitleParser.activeCue(model.subtitleCues, at: model.position)?.text ?? "")
            : captionText
    }

    /// Whether `CaptionOverlayView` should currently render, for the live model snapshot. Shared
    /// by the VOD branch (unconditionally `!model.isLive == true` there already, so behavior is
    /// unchanged / baseline-neutral) and the live-chrome branch (where it now resolves `true` for
    /// a finished-live replay, `false` for a genuine live broadcast in progress).
    private var showsCaptionOverlay: Bool {
        Self.showsCaptionOverlay(isLive: model.isLive, subtitleEnabled: model.subtitleEnabled,
                                 hasCaption: !effectiveCaption.isEmpty, isScrubbing: isScrubbing,
                                 cleanMode: cleanMode)
    }

    /// PURE: whether the merged LIVE-family chat feed (rendered by a SIBLING `FeedWinOverlayView`
    /// in `PlayerOverlayRootView`, NOT a descendant of this view) should be hidden because a
    /// finished-live replay has CC captions on (rb-ios-caption-overlay-align-hide-chat — user
    /// report: 「回放啟用字幕要隱藏聊天室」, so the caption can take over the freed area, design
    /// `screens.jsx` ~571-576). Genuinely live (`isFinishedLiveReplay == false`) NEVER hides the
    /// chat feed via this path, regardless of `subtitleEnabled` — a real live broadcast has no
    /// usable caption source today (the CC button is rendered unavailable there,
    /// `rb-ios-cc-icon-availability-redesign`), so this asymmetry mirrors `showsCaptionOverlay`'s
    /// own `!isLive` gate rather than the design's literal (but for iOS's data model equivalent)
    /// `!ccOn` condition. `subtitleAvailable` (rb-ios-caption-chat-hide-availability-gate — user
    /// report: 「CC 跨影片保留但沒字幕的影片沒辦法關閉，導致聊天室被隱藏」) additionally requires the
    /// CURRENT video to actually have a caption source: `subtitleEnabled` deliberately persists
    /// across a video switch (`DefaultPlayerTemplate.handleSubtitleChannelInfo` preserves it), but
    /// the CC button is rendered `unavailable` and swallows taps when the new video has none — the
    /// user cannot turn a stale `true` back off, so without this third clause a caption-less video
    /// would keep the chat feed hidden for no visible reason. Unit-testable without rendering any
    /// view.
    static func hidesChatFeedForReplayCaption(isFinishedLiveReplay: Bool, subtitleEnabled: Bool,
                                               subtitleAvailable: Bool) -> Bool {
        isFinishedLiveReplay && subtitleEnabled && subtitleAvailable
    }

    /// Whether the CURRENT video has a caption source (`railItems`' `.subtitle` item's `enabled`)
    /// — parity the CC button's own availability read (`rb-ios-cc-icon-availability-redesign`, NOT
    /// a new `PlayerShellModel` API). Exposed as its own `Bool` (rather than inlined) so
    /// `.onChange(of: subtitleAvailable)` below can detect a flip that neither `isFinishedLiveReplay`
    /// nor `subtitleEnabled` alone would catch (rb-ios-caption-chat-hide-availability-gate).
    private var subtitleAvailable: Bool {
        model.railItems.first(where: { $0.kind == .subtitle })?.enabled == true
    }

    /// Wraps `hidesChatFeedForReplayCaption(isFinishedLiveReplay:subtitleEnabled:subtitleAvailable:)`
    /// for the live model snapshot — reported to the container via `onReplayCaptionHidesChatChange`
    /// below.
    private var hidesChatFeedForReplayCaption: Bool {
        Self.hidesChatFeedForReplayCaption(isFinishedLiveReplay: model.isFinishedLiveReplay,
                                            subtitleEnabled: model.subtitleEnabled,
                                            subtitleAvailable: subtitleAvailable)
    }

    // MARK: - Header top-right button override while END screen is active
    //         (fix-ios-endscreen-close-button-blocked)
    //
    // While the family-4 END moment (`EndScreenView`, composed by `MomentsOverlayView` ABOVE
    // this view) is showing, its full-screen scrim makes "minimize to floating widget" an
    // unreachable dead end — the button MUST behave as a direct close instead, regardless of
    // the per-shell `enableDirectCloseButton` / `model.showCloseIcon` constant.

    /// PURE: the top-right button's effective `showCloseIcon`, forced to `true` while the END
    /// moment is active. Unit-testable without rendering (mirrors the `showsCaptionOverlay(...)`
    /// / `hidesChatFeedForReplayCaption(...)` pure-function precedent above).
    static func effectiveShowCloseIcon(isEndScreenActive: Bool, showCloseIcon: Bool) -> Bool {
        isEndScreenActive || showCloseIcon
    }

    /// The header's top-right tap target: while the END screen is active it ALWAYS closes the
    /// whole player (`onCloseRequest` — the same exit `swipe-nav-close-on-empty` already uses);
    /// otherwise it falls back to the existing `onMinimize` forwarding, unchanged.
    private func handleHeaderTopRightTap() {
        if model.isEndScreenActive {
            onCloseRequest?()
        } else {
            onMinimize?()
        }
    }

    /// The family-1 header chrome, hoisted to a computed property (concrete return type, not
    /// `some View`) so a test can read the EXACT `PlayerHeaderBarView` instance `body` composes
    /// — including `showCloseIcon` and the top-right tap closure's actual routing — via
    /// `headerBarForTesting` below (mirrors `activeMomentForTesting` in `MomentsOverlayView` /
    /// the `PlayerHeaderBarCloseIconTests` doc comment's rationale against a parallel copy).
    /// Every parameter is byte-identical to the pre-existing inline construction except
    /// `showCloseIcon` / `onMinimize`, which now route through the two helpers above.
    private var headerBar: PlayerHeaderBarView {
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
            // Backend / merchant title-marquee capability gate (rb-ios-video-title-scroll):
            // mirrors `extensions.video_title_scroll` via `LivebuyPlayerConfig.titleScroll`.
            // `false` keeps the title (single line + ellipsis, same height) but stops it
            // scrolling; the overflow MEASUREMENT itself is untouched.
            titleScroll: model.titleScroll,
            // Cold-start loading gate (rb-live-entry-viewer-count-loading-gate):
            // mirrors `model.startPhase`. While `.loading` (the `/sdk/video` fetch
            // has not yet resolved) the viewer-count badge is suppressed so a
            // not-yet-real `viewerCount` (type default `0`) is never drawn as if it
            // were a real count.
            startPhase: model.startPhase,
            // 乾淨模式隱藏「top bar logo」+「host badge」（design 兩個獨立元件，iOS 合併
            // 成同一顆 hostPill）——保留頂欄唯一的 minimize(PIP) 鈕不受影響（rb-ios-gesture-
            // clean-mode-rewrite ADDED Requirement，見 `PlayerHeaderBarView.cleanMode`）。
            cleanMode: cleanMode,
            // 乾淨模式限定靜音切換鈕（`rb-ios-gesture-clean-mode-v2`, design R29）：補回
            // 單擊切靜音手勢退役後的操作管道。`onToggleMute` 只在 `cleanMode == true` 期間
            // 非 nil——`PlayerHeaderBarView` 依此決定是否渲染這顆鈕（不佔位）。
            muted: model.muted,
            // 右上角鈕圖示模式（rb-ios-player-direct-close-button）：per-shell 常數，
            // 由 `LivebuyPlayer.buildModels()` 解析 `LivebuyPlayerConfig
            // .enableDirectCloseButton` 對全域偏好後寫入；純呈現旗標，本層不知道
            // 全域設定的存在。強制升為 `true`（且點擊改觸發 `onCloseRequest`）當 END
            // moment 正在顯示（fix-ios-endscreen-close-button-blocked）——見上方
            // `effectiveShowCloseIcon` / `handleHeaderTopRightTap`。
            showCloseIcon: Self.effectiveShowCloseIcon(
                isEndScreenActive: model.isEndScreenActive, showCloseIcon: model.showCloseIcon),
            onMinimize: { handleHeaderTopRightTap() },
            // 訂閱徽章 → 容器注入的 gate（未登入 → AuthGate(.subscribe)）；未注入 fallback
            // `model.toggleSubscribe()`（rb-ios-subscribe-login-gate）。與 info pill 共用。
            onSubscribe: { performSubscribe() },
            // Host badge tap → open the VideoInfoPanel (design LBPHostBadge →
            // video_info; presentation-only, replaces the removed VOD rail
            // `more` pill). Same presentation toggle the `more` pill used.
            onTapHostBadge: { withAnimation { infoPanelPresented.toggle() } },
            onToggleMute: cleanMode ? { onToggleMute?() } : nil)
    }

    /// Test seam exposing the private `headerBar` computed property (`*ForTesting` naming,
    /// mirrors `showsLiveNowPillForTesting` / `cleanModeExitButtonBottomInsetForTesting` above)
    /// so a test can read the EXACT `PlayerHeaderBarView` instance `body` composes — including
    /// `showCloseIcon` and the top-right tap closure's actual routing
    /// (fix-ios-endscreen-close-button-blocked).
    var headerBarForTesting: PlayerHeaderBarView { headerBar }

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
            // Wrapped in a `GeometryReader` SOLELY to read the container's width for
            // `TapZone` classification (`rb-ios-gesture-clean-mode-v2`, design R29) — the
            // reader's own size is NOT the primary sizing mechanism for anything (this base
            // view already fills its `ZStack` slot via `.frame(maxWidth: .infinity, maxHeight:
            // .infinity)` below), avoiding the blank-under-`ImageRenderer` pitfall other
            // `GeometryReader`-as-primary-sizing usages in this module document.
            GeometryReader { proxy in
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                handleDragChanged(value.translation,
                                                  startX: value.startLocation.x,
                                                  containerWidth: proxy.size.width)
                            }
                            .onEnded { value in
                                handleDragEnded(value.translation,
                                               startX: value.startLocation.x,
                                               containerWidth: proxy.size.width)
                            }
                    )
                    .accessibilityIdentifier(LBAccessibilityID.playerVideoSurface)
            }

            // Mode-branched chrome (design screens.jsx「VOD vs LIVE switches here」):
            //   UPCOMING → nothing drawn here (the UpcomingCountdownView background IS the
            //          surface; no live overlay / no VOD mini-cart / no announce-pinned-chat).
            //   LIVE → the live overlay chrome (announce / pinned card / host caption
            //          / floating gesture hints). `PlaybackProgressBarView` (composed further
            //          below, as an independent top-level sibling) additionally overlays this
            //          branch ONLY when the stream is a finished-live replay
            //          (`model.isFinishedLiveReplay`, `isLive == false` there too) — NEVER while
            //          genuinely live (rb-ios-restore-vod-playback-progress-bar).
            //   VOD  → the currently-introduced product card (MiniCartView bound to
            //          model.vodActiveProduct, bottom-leading) + the CC caption line
            //          when subtitles are on + `PlaybackProgressBarView`. The live chat /
            //          pinned / announce / host-caption are NOT drawn for VOD.
            if model.isUpcoming || model.introPlaying {
                // upcoming awaitingLive OR the upcoming intro is playing → no live-overlay
                // chrome (announce / pinned / chat / host-caption don't exist pre-live).
                EmptyView()
            } else if usesLiveChrome {
                LiveOverlayChromeView(
                    theme: theme,
                    // 拖曳播放進度條期間（isScrubbing）隱藏公告 banner，讓出畫面給 transport bar
                    // （rb-ios-restore-vod-playback-progress-bar；只在 usesLiveChrome 與進度條同時
                    // 出現的「已結束直播回放」狀態下才有實際效果——純直播進行中進度條本不顯示，
                    // 即使已被拖到 live edge 之後〔model.isReplay〕也不顯示，見 showsPlaybackProgressBar
                    // 的文件註解）。
                    announceText: isScrubbing ? "" : model.announceText,
                    // 釘選卡來源依真直播 vs 回放分流（rb-ios-replay-live-chrome）：
                    //   真直播 → livePinnedProducts（多件 narrate_status==2 輪播 + 分頁點；空時
                    //            fallback 單一 activeProduct ?? first isHot，問題 7）。
                    //   回放   → vodActiveProducts（時間軸窗格 [beginTime,endTime) 含 playhead，隨
                    //            播放進度更新；回放無即時 narrate_status==2，改用後端介紹時間窗）。
                    // 先算來源分支、再以本地 dismiss set 過濾（涵蓋真直播 / 回放兩分支），使 close X
                    // 逐商品本地隱藏（rb-ios-live-pinned-card-dismiss，鏡像 VOD dismissedVodProductIds）。
                    // 拖曳播放進度條期間同樣清空（見上 announceText 的理由）。
                    pinnedProducts: isScrubbing ? [] : LiveOverlayChromeView.visiblePinnedProducts(
                        model.isLive ? model.livePinnedProducts : model.vodActiveProducts,
                        dismissedIds: dismissedLivePinnedIds),
                    // 放開手指到 2.8 秒收回這段期間（scrubBarExpanded && !isScrubbing），釘選卡 /
                    // 公告 banner 重新出現時上移，讓出底部 transport bar 空間
                    // （rb-ios-restore-vod-playback-progress-bar）。預設 0 對既有呼叫點無影響。
                    bottomInset: (scrubBarExpanded && !isScrubbing) ? Self.scrubChromeLift : 0,
                    // Real product image on the pinned card only over a live video surface
                    // (placeholder suppressed) — same gate as the shop logo / VOD card
                    // (live-pinned-card-image-radius). Snapshot/demo keeps the placeholder.
                    live: !paintsBackgroundPlaceholder,
                    // rb-ios-replay-caption-overlay-fix: the REAL VTT/CC caption (distinct from
                    // the host-supplied static `LBLiveHostCaption` below) — non-empty only for a
                    // finished-live REPLAY with CC on (never for a genuine live broadcast in
                    // progress; `showsCaptionOverlay` already folds in `isScrubbing` / `cleanMode`,
                    // the latter re-checked internally by `LiveOverlayChromeView` too, matching its
                    // `announceText` / `hostCaption` convention).
                    subtitleCaption: showsCaptionOverlay ? effectiveCaption : "",
                    // Host-suppressible: a host that has already shown the hint once
                    // passes showGestureHints: false (it owns the persisted flag).
                    showGestureHints: showGestureHints,
                    // `showsHoldPauseHint`（deprecated）恆吃預設值，不再有任何 gating 效果
                    // （rb-ios-gesture-clean-mode-rewrite）。點擊提示文案自 `rb-ios-gesture-clean-
                    // mode-v2`（design R29）起不分直播/VOD 恆為「切換乾淨模式」；長按提示改依
                    // `isLive` 決定是否渲染——`isLive: model.isLive` 這裡餵的正是
                    // `handleVideoTap(zone:)` / `isSeekable(isLive:isUpcoming:isFinishedLiveReplay:)`
                    // 判斷用的同一個 `model.isLive`，故長按提示只在已結束直播回放（`isLive ==
                    // false`）時顯示，對齊真直播進行中長按無對應動作的事實。
                    isLive: model.isLive,
                    // Real video overlay (placeholder bg suppressed) → fade the gesture
                    // hints; standalone / snapshot keeps them static (deterministic).
                    autoFadeGestureHints: !paintsBackgroundPlaceholder,
                    // 乾淨模式（rb-ios-gesture-clean-mode-rewrite ADDED Requirement）：隱藏 announce
                    // banner / host caption / 手勢提示，MUST NOT 影響釘選商品卡（見
                    // `LiveOverlayChromeView.cleanMode` 的內部 gate 範圍）。
                    cleanMode: cleanMode,
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
                // 拖曳播放進度條期間（isScrubbing）隱藏介紹中商品卡輪播，讓出畫面給
                // transport bar；放開手指到 2.8 秒收回這段期間（scrubBarExpanded &&
                // !isScrubbing）重新出現並上移，讓出底部 transport bar 空間
                // （rb-ios-restore-vod-playback-progress-bar）。
                //
                // CC 字幕疊層已抽離為獨立的 top-level ZStack sibling（rb-ios-vod-caption-reserve-
                // card-space，見下方「VOD CC 字幕疊層」區塊）——不再與這個商品卡輪播共用同一個
                // VStack。修正前兩者疊在同一個 VStack 裡，商品卡輪播的渲染 / 消失會讓 VStack 版面
                // 重排，把字幕的實際位置往上推 / 彈回底部（使用者截圖回報「字幕位置會跳動」）。
                VStack(alignment: .leading, spacing: 0) {
                    Spacer(minLength: 0)
                    // VOD now-introducing products: a full-width card carousel (real image + page
                    // dots + swipe) over ALL products whose [beginTime,endTime) window contains
                    // the playhead (`model.vodActiveProducts`), minus the ones dismissed locally.
                    // rb-ios-now-introducing-real-image-carousel (問題 9 滿寬+真實圖, 問題 10 多商品輪播).
                    // 「mini-cart」（design `LBPMiniCart`）在乾淨模式隱藏 — iOS 對應此 now-introducing
                    // carousel（rb-ios-gesture-clean-mode-rewrite ADDED Requirement）。
                    // 卡片本身是否渲染 SHALL 跟隨 `showsVodMainChrome`（與側欄 / 浮動商品袋同一閘門），
                    // MUST NOT 只因 `vodActiveProducts` 提早非空就在開場序列（.loading/.splash）搶先出現
                    // ——先前只有 trailing padding（見下）用了 `showsVodMainChrome`，本身渲染卻沒有，
                    // 導致這張卡比側欄 / 浮動袋更早出現（rb-ios-now-introducing-carousel-buffering-gate）。
                    let introducing = model.vodActiveProducts
                        .filter { !dismissedVodProductIds.contains($0.id) }
                    if !introducing.isEmpty && !isScrubbing && !cleanMode && showsVodMainChrome {
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
                            .padding(.bottom, 12 + scrubChromeLiftIfExpanded)
                    }
                }
            }

            // VOD CC 字幕疊層 — 獨立的 top-level ZStack sibling（rb-ios-vod-caption-reserve-card-
            // space）。從上面 VOD else 分支的 VStack 抽離出來，不再與 now-introducing 商品卡輪播
            // 共用容器：修正前兩者疊在同一個 VStack 裡，商品卡輪播渲染 / 消失時 VStack 版面重排會
            // 把字幕往上推 / 彈回底部（使用者截圖回報「字幕位置會跳動」）。修正後字幕的垂直位置
            // 固定預留 92pt（design `design/templates/minimal/screens.jsx:533` 的 `LBPCaptionOverlay`
            // VOD `safeBottom = safeArea.bottom + 92`，跟同一份設計檔 `sdk-components.jsx` 的
            // `LBPMiniCart` 商品卡是否顯示〔`bottom: 12 + safeBottom`〕完全無關，兩者是各自獨立定位
            // 的元件），無論 vodActiveProducts / 商品卡輪播實際有沒有渲染都套用這個固定值——即「永遠
            // 預留商品卡的空間」。
            //
            // 渲染條件與拖曳/展開行為 100% 沿用抽離前：`showsCaptionOverlay` 本身已經 fold 進
            // `!isScrubbing`（拖曳播放進度條時隱藏字幕）與 `!cleanMode`；`isVodMainChrome` 與進入
            // 上面那個 else 分支的條件完全相同（純 VOD、非 upcoming、非 introPlaying），取代「巢狀
            // 在該分支內」這個結構性保證。`.padding(.bottom, 92 + scrubChromeLiftIfExpanded)` 的
            // `scrubChromeLiftIfExpanded` 項維持「放開手指到 2.8 秒收回這段期間（scrubBarExpanded
            // && !isScrubbing）字幕跟著上移」不變——只有底座常數從 8 改成 92。只影響純 VOD；LIVE /
            // 已結束直播回放（usesLiveChrome）的字幕走 LiveOverlayChromeView 自己的
            // subtitleCaption，不在本次範圍、不受影響。
            //
            // 水平對齊（置中於左緣 8pt / 右緣 floatingBagClearance 的窄框，rb-ios-caption-overlay-
            // align-hide-chat）維持不變，只改錨定容器與底部數字。
            if isVodMainChrome && showsCaptionOverlay {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        CaptionOverlayView(theme: theme, text: effectiveCaption)
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, 8)
                    .padding(.trailing, Self.floatingBagClearance)
                    .padding(.bottom, 92 + scrubChromeLiftIfExpanded)
                }
            }

            // Top bar pinned top, side rail pinned trailing. Surfaces 1 + 2.
            VStack(spacing: 0) {
                // Header is drawn UNCONDITIONALLY in every mode — including the VOD start
                // sequence (opening MP4 / loader): only the VOD side rail + floating bag are
                // suppressed there, the header stays (rb-ios-vod-intro-keep-header).
                headerBar

                Spacer(minLength: 0)

                // Side rail is VOD-ONLY chrome (design screens.jsx gates `LBPSideRail`
                // on `!isLive`; upcoming wears the slim LIVE bar instead). In LIVE /
                // upcoming the bottom bar (below) replaces it; the rail anchors HIGHER
                // (bottom ≈68, `rb-ios-gesture-clean-mode-v2`: was 80, lowered to keep the
                // same visual gap now that `FloatingBagButtonView` below is smaller) so the
                // separate floating bag button (below) can sit lower next to the mini-cart
                // strip (design `LBPSideRail` bottom:68 vs `LBPBagButton` bottom:16).
                // Suppressed only during the VOD OPENING sequence
                // (full-screen loader `.loading` / intro MP4 `.splash`) — from `.buffering`
                // onward the rail shows (rb-ios-vod-rail-show-on-buffering). Additionally hidden
                // while actively dragging the playback-progress bar
                // (rb-ios-restore-vod-playback-progress-bar) — reappears (lifted, see padding
                // below) once the finger lifts. Side rail 在乾淨模式隱藏（rb-ios-gesture-clean-
                // mode-rewrite ADDED Requirement）。
                if showsVodMainChrome && !isScrubbing && !cleanMode {
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        OperationRailView(
                            theme: theme,
                            items: model.railItems,
                            bagCount: model.bagCount,
                            heartBurstTick: model.heartBurstTick,
                            muted: model.muted,
                            subtitleEnabled: model.subtitleEnabled,
                            onTapItem: { kind in
                                // The rail surfaces a tap intent; for the info kinds
                                // the shell can forward presentation-only navigation.
                                // Real actions (like / share / chat …) go through the
                                // host-wired core `simulate*` — NOT owned here (D-4).
                                handleRailTap(kind)
                            })
                            .padding(.trailing, 12)
                            .padding(.bottom, 68 + scrubChromeLiftIfExpanded)
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
            // with the side rail (rb-ios-vod-rail-show-on-buffering). Additionally hidden while
            // actively dragging the playback-progress bar (rb-ios-restore-vod-playback-progress-bar).
            // Hidden in clean mode (rb-ios-gesture-clean-mode-rewrite ADDED Requirement).
            if showsVodMainChrome && !isScrubbing && !cleanMode {
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
                            .padding(.bottom, 16 + scrubChromeLiftIfExpanded)
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
            // 拖曳播放進度條期間（isScrubbing）隱藏 LIVE 底部 bar（+ 愛心 burst），讓出畫面給
            // transport bar（design `screens.jsx` `LBLiveBottomBar` 的 `!(isReplay && scrubbing)`
            // gate）；放開手指到 2.8 秒收回這段期間（scrubBarExpanded && !isScrubbing）重新出現並
            // 上移，讓出底部 transport bar 空間。`isScrubbing` 只會在 `showsPlaybackProgressBar`
            // 為真時被觸發，故對 upcoming / introPlaying（永不與進度條共存）不受影響。
            //
            // 乾淨模式（rb-ios-gesture-clean-mode-rewrite ADDED Requirement）隱藏 LIVE 底部
            // bar —— 但範圍只限「因 usesLiveChrome 而顯示」的情況（真直播 / 已結束直播回放）；
            // upcoming / introPlaying 那段 slim bar 不在本次乾淨模式規範範圍內，`&& !cleanMode`
            // 只 AND 進 `usesLiveChrome` 那一支，不影響 `model.isUpcoming` / `model.introPlaying`
            // 那兩支。
            if ((usesLiveChrome && !cleanMode) || model.isUpcoming || model.introPlaying) && !composerPresented && !isScrubbing {
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
                        liked: liveLiked,
                        // CC 按鈕 active 填色態（rb-ios-live-bottom-bar-cc-icon-active-fill-state）——
                        // 同一個既有欄位，`OperationRailView(...)` 呼叫點（上方）已經在用。
                        subtitleEnabled: model.subtitleEnabled,
                        // 是否有字幕來源可用（rb-ios-cc-icon-availability-redesign）——由既有
                        // `model.railItems` 推導（`.subtitle` 項的 `enabled`，與 `OperationRailView(...)`
                        // 呼叫點〔上方〕讀的是同一份 view-model 資料），NOT 新增任何 `PlayerShellModel` API。
                        subtitleAvailable: model.railItems.first(where: { $0.kind == .subtitle })?.enabled == true,
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
                        // Real like via the existing turnkey forwarder + 1–4 staggered local heart
                        // bursts + a bright (accent) glow on the icon itself while they play out
                        // (rb-ios-live-like-burst-restyle — design `onLike → likeAnimation(n)`).
                        // `model.performLike()` fires ONCE per tap (unchanged turnkey contract);
                        // only the local, presentation-only burst count/glow is randomized —
                        // reference-ui still MUST NOT call like more than once per tap.
                        onLike: {
                            model.performLike()
                            let count = Self.resolveLikeBurstCount()
                            liveLiked = true
                            for i in 0..<count {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3 * Double(i)) {
                                    liveHeartTick &+= 1
                                }
                            }
                            let glowMs = Self.likeGlowDurationMs(count: count)
                            DispatchQueue.main.asyncAfter(deadline: .now() + glowMs / 1000) {
                                liveLiked = false
                            }
                        },
                        // CC (字幕) toggle → the SAME real forwarder `OperationRailView`'s VOD
                        // `.subtitle` rail item uses (`handleRailTap(.subtitle)` → `model.toggleSubtitle()`),
                        // restored 2026-09-03 (correction round) at its NEW trailing-slot position
                        // for the `chatClosed` variant (design R32). ⚠️ This flips real,
                        // meaningful state (`model.subtitleEnabled`) — it is NOT a fake/no-op
                        // wire — but produces NO visible caption here: `CaptionOverlayView` is
                        // gated on `!model.isLive` (unchanged since its first commit), and
                        // `chatClosed` implies the live-chrome branch, not the VOD branch, so
                        // there is currently no rendering consumer for this state on THIS branch
                        // (a pre-existing gap that predates this button's removal — the OLD
                        // isReplay-driven CC button had the identical limitation, since isReplay
                        // also implies `isLive == true`). Extending `CaptionOverlayView`'s gate to
                        // the live-chrome branch is explicitly OUT OF SCOPE for this change — see
                        // design.md.
                        onToggleCC: { model.toggleSubtitle() },
                        // 「更多」(⋯) → open `LiveMoreSheetView` (chatClosed-only leading slot;
                        // design R32, rb-ios-live-replay-more-menu-and-video-info-live-copy).
                        onMore: { withAnimation { liveMoreSheetPresented = true } })
                        // rb-ios-live-bottom-bar-16pt-align: no static offset here — LiveBottomBarView
                        // itself now owns the full 16pt bottom inset internally (barBottomPadding), so
                        // its background sits flush against the true bottom edge (design `bottom: 0`).
                        // Only the dynamic post-scrub-release lift remains.
                        .padding(.bottom, scrubChromeLiftIfExpanded)
                }

                // LIVE bottom-bar heart burst — the shared `HeartBurstView` anchored ABOVE the
                // like button (bottom-trailing), driven by the local `liveHeartTick`, which one
                // like tap now bumps 1–4 times staggered 300ms apart (rb-ios-live-like-burst-
                // restyle). `HeartBurstView` itself still only reacts to ITS `tick` increasing
                // by exactly 1 at a time — the multi-burst richness lives entirely in the
                // staggered bumps above, not in this shared view. Bag-only (introPlaying) draws
                // no like → no burst. Transient + non-interactive → snapshot-neutral at rest.
                // (rb-ios-live-bottom-heart-burst, rb-ios-live-like-burst-restyle)
                // 心動特效在乾淨模式隱藏（rb-ios-gesture-clean-mode-rewrite ADDED Requirement）——
                // 同上，範圍只限 usesLiveChrome 那一支，不影響 upcoming。
                if ((usesLiveChrome && !cleanMode) || model.isUpcoming) && !model.introPlaying {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        HStack(spacing: 0) {
                            Spacer(minLength: 0)
                            HeartBurstView(tick: liveHeartTick, color: theme.accent)
                        }
                    }
                    .padding(.trailing, 18)
                    .padding(.bottom, 64 + scrubChromeLiftIfExpanded)
                    .allowsHitTesting(false)
                }
            }

            // Center gesture-feedback overlays. ZStack centers them.
            //
            // Central paused overlay RETIRED (`rb-ios-gesture-clean-mode-v2`, design R29,
            // supersedes `rb-ios-gesture-clean-mode-rewrite`'s interactive `PlaybackPausedOverlayView`
            // — see that view's own file header for the full history). VOD / already-ended-live-
            // replay play/pause is now reachable via `PlaybackProgressBarView`'s existing expanded-
            // state play/pause button instead (composed further below; `isExpanded` already
            // includes `cleanMode`).
            //
            // 「退出乾淨模式」小圓鈕（`rb-ios-gesture-clean-mode-v2`, design R29 ADDED；icon +
            // 位置由 `rb-ios-clean-mode-exit-icon-fix` 對齊設計稿）：`cleanMode == true` 時顯示，
            // 點擊即退出。單一入口涵蓋 VOD/回放與 LIVE 兩種版型，icon 為 `DetailGlyph`（對齊
            // 設計稿 `Icons.detail`），bottom 依 `model.isLive` 分流為 16（LIVE）/ 52（VOD/回放）
            // （見 `cleanModeExitButtonBaseBottomInset(isLive:)` doc comment）。
            if cleanMode {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    HStack(spacing: 0) {
                        Button(action: { cleanMode = false }) {
                            DetailGlyph(size: 18, color: .white)
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(Color.black.opacity(0.45)))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .accessibilityIdentifier(LBAccessibilityID.cleanModeExitButton)
                        Spacer(minLength: 0)
                    }
                }
                .padding(.leading, 14)
                .padding(.bottom, cleanModeExitButtonBottomInset)
            }
            // Mute toast: 0.7s tap-to-mute feedback (reads model.muted = the post-toggle state).
            // Non-interactive (allowsHitTesting false) so it never blocks the gesture layer /
            // chrome below.
            if muteToastVisible {
                GestureMuteToastView(theme: theme, muted: model.muted)
                    .allowsHitTesting(false)
            }

            // VOD / replay playback-progress transport bar (rb-ios-restore-vod-playback-
            // progress-bar, SUPERSEDES rb-ios-retire-vod-progress-bar 2026-06-10). Composed as
            // an independent top-level ZStack sibling — NOT nested in either the VOD or
            // `usesLiveChrome` branch above — because it must render over BOTH (pure VOD via
            // the VOD branch; a finished-live replay or a live stream scrubbed behind the live
            // edge via the `usesLiveChrome` branch). Pinned to the very bottom edge. All
            // interactions forward to `PlayerShellModel`'s EXISTING `togglePlayPause()` /
            // `seek(to:)` forwarders — no new core / view-model API.
            if showsPlaybackProgressBar {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    PlaybackProgressBarView(
                        theme: theme,
                        position: model.position,
                        duration: model.duration,
                        isPlaying: model.isPlaying,
                        isScrubbing: isScrubbing,
                        // 乾淨模式：進度條從細線態直接展開為完整可互動 transport 列（design
                        // `screens.jsx` 既有的 `(scrubVisible || cleanMode)` 開關模式，rb-ios-
                        // gesture-clean-mode-rewrite ADDED Requirement）。
                        isExpanded: scrubBarExpanded || cleanMode,
                        onTogglePlayPause: { model.togglePlayPause() },
                        onScrubStarted: { handleScrubStarted() },
                        onScrub: { ratio in handleScrub(ratio) },
                        onScrubEnded: { handleScrubEnded() })
                }
            }

            // 「現正直播」右緣半藥丸鈕 (rb-ios-live-now-pill)。獨立的 top-level `ZStack` sibling
            // （不巢在 VOD / `usesLiveChrome` 任一支之內，因為兩者皆可能是它的顯示情境——design
            // 的 `(state === 'main' || isReplay)`）。design `position: absolute, top: 50%, right:
            // 0, transform: translateY(-50%)`：這裡不需要額外定位修飾——`HStack { Spacer();
            // pill }` 本身沒有固定高度，ZStack 預設 `.center` alignment 會把它垂直置中，`Spacer`
            // 把它推到最右緣（`right: 0`），兩者合起來逐位元對齊設計稿的絕對定位。
            if showsLiveNowPill {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    LiveNowPillView(theme: theme, onTap: { onGoLive?() })
                }
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
                // 商家列的真實 logo 圖片閘門 — 與上方 header avatar 呼叫點（`live:` 同一行運算式）
                // 共用**同一來源**，而非各自推導：兩個 surface 畫的是同一顆 `shopLogo`，gate 一旦
                // 分岔就會出現「header 已顯真 logo、面板仍是字母漸層」這種跨面不一致。
                // snapshot / demo 路徑（`paintsBackgroundPlaceholder == true`）維持漸層 chip、不觸網。
                live: !paintsBackgroundPlaceholder,
                // 直播 vs 點播文案分流（design R32）——沿用既有 `model.isLive`（`liveStatus == 1`），
                // 與這個檔案自己的 `live:`（上一行，網路圖片載入 gate）是完全不同的兩件事，故取名
                // `isLiveBroadcast` 而非 `isLive`/`live`，避免與既有語彙混淆（見 `live` prop 文件註解）。
                isLiveBroadcast: model.isLive,
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
        // LIVE bottom bar「更多」(⋯) collapsible menu (design R32,
        // rb-ios-live-replay-more-menu-and-video-info-live-copy) — same shared SheetKit
        // presenter. Both actions dismiss THIS sheet first, then forward to their existing
        // host seam (mirrors the design's own single-`openSheet`-state "pick one action and
        // it takes over" semantics, distinct from the info panel, which stays open underneath
        // its own confirm modal).
        .lbBottomSheet(theme: theme, isPresented: $liveMoreSheetPresented) {
            LiveMoreSheetView(
                theme: theme,
                // 分享 → 與 LIVE 底部 bar 自己的分享鈕同一走線（容器注入的 `onShare`，含
                // presentChannelShare fallback；非容器 / snapshot 維持既有 headless
                // `model.performShare()`，rb-ios-live-share-default-sheet 同款）。
                onShare: {
                    withAnimation { liveMoreSheetPresented = false }
                    if let onShare = onShare { onShare() } else { model.performShare() }
                },
                // 客服 → 與側欄 serviceLink / info-panel「與商家一對一對話」同一「聯絡商家」
                // confirm modal 走線（`contactMerchantPresented` + `ContactMerchantModalView`）。
                onContact: {
                    withAnimation { liveMoreSheetPresented = false }
                    withAnimation { contactMerchantPresented = true }
                })
        }
        // 「聯絡商家」confirm modal — composed ABOVE the info-panel sheet AND the「更多」sheet
        // so it overlays either.
        .overlay(contactMerchantOverlay)
        // Report info-panel open/closed to the container so it can hide the higher-layer
        // chat feed while the panel is up (rb-ios-info-panel-not-covered-by-chat). Read-only
        // report — the panel state / dismiss paths are unchanged.
        .onChange(of: infoPanelPresented) { presented in
            onInfoPanelPresentedChange?(presented)
        }
        // Report「更多」選單 open/closed to the container so it can hide the higher-layer chat
        // feed while the menu is up (rb-ios-live-more-sheet-above-chat). Read-only report — the
        // menu itself / its two actions are unchanged.
        .onChange(of: liveMoreSheetPresented) { presented in
            onMoreSheetPresentedChange?(presented)
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
            // 初值報告 cleanMode（`.onChange` 不會為初值觸發），讓容器一進場（含測試以
            // `cleanModeForTesting` 預先 seed 的情境）就拿到正確初值（rb-ios-clean-mode-hide-
            // chat-feed）。
            onCleanModeChange?(cleanMode)
            // 初值報告「回放啟用字幕→隱藏聊天室」(`.onChange` 不會為初值觸發，
            // rb-ios-caption-overlay-align-hide-chat)，讓容器一進場就拿到正確初值。
            onReplayCaptionHidesChatChange?(hidesChatFeedForReplayCaption)
            // 初值背景 prefetch 商品照片（`.onChange` 不會為初值觸發，rb-ios-product-image-
            // loading-polish）——見下方 `.onChange(of: allProductIdsForPrefetch)`。
            prefetchIntroducibleProductImages()
        }
        .onChange(of: model.isLive) { _ in
            onIsLiveChange?(usesLiveChrome)
        }
        // 回報 cleanMode 每次翻轉（長按觸發）給容器，讓 family-2 聊天 feed 跟著隱藏/恢復
        // （rb-ios-clean-mode-hide-chat-feed）。
        .onChange(of: cleanMode) { newValue in
            onCleanModeChange?(newValue)
        }
        // 回放旗標切換亦回報 live-chrome 家族（換片 live→回放 / 回放→VOD 時聊天 feed 跟著開關），
        // 以及「回放啟用字幕→隱藏聊天室」旗標（rb-ios-caption-overlay-align-hide-chat：換片可能同時
        // 翻轉 isFinishedLiveReplay，須同步重算）。
        .onChange(of: model.isFinishedLiveReplay) { _ in
            onIsLiveChange?(usesLiveChrome)
            onReplayCaptionHidesChatChange?(hidesChatFeedForReplayCaption)
        }
        // CC 開關翻轉時回報「回放啟用字幕→隱藏聊天室」（rb-ios-caption-overlay-align-hide-chat）。
        // 真直播（`isFinishedLiveReplay == false`）下 `hidesChatFeedForReplayCaption` 恆為
        // `false`，此回報對聊天室無實際影響。
        .onChange(of: model.subtitleEnabled) { _ in
            onReplayCaptionHidesChatChange?(hidesChatFeedForReplayCaption)
        }
        // 換片可能只翻轉字幕可用性（`railItems` 的 `.subtitle.enabled`）而不動
        // `isFinishedLiveReplay` / `subtitleEnabled`——沒字幕的新回放影片必須立刻恢復聊天室
        // （rb-ios-caption-chat-hide-availability-gate）。
        .onChange(of: subtitleAvailable) { _ in
            onReplayCaptionHidesChatChange?(hidesChatFeedForReplayCaption)
        }
        // Report whether the LBLiveAnnounce banner is showing (announceText 非空) so the container
        // gives the chat feed extra bottom clearance only when a 公告 is present
        // (rb-ios-live-announce-chat-clearance, 問題 4). announceText 只在後台公告變更時才變，不頻繁。
        .onChange(of: model.announceText) { text in
            onHasAnnounceChange?(!text.isEmpty)
        }
        // 商品照片背景 prefetch（rb-ios-product-image-loading-polish）：`model.allProducts`
        // （完整未篩選清單）變化時重新 prefetch——`LBProduct` 非 `Equatable`，`.onChange(of:)`
        // 追蹤這個 derived 的 `[String]` id 陣列，觸發後仍讀取當下的 `model.allProducts`。初值由
        // 上方 `.onAppear` 觸發（`.onChange` 不會為初值觸發）。
        .onChange(of: allProductIdsForPrefetch) { _ in
            prefetchIntroducibleProductImages()
        }
        // App 進背景（含觸發系統自動 PiP）時，若正在拖曳進度條，`DragGesture` 沒有「被系統中斷」
        // 的回呼可掛（`.onEnded` 永遠不會收到 `touchesCancelled`），視同放開手指走既有
        // `handleScrubEnded()` 路徑，避免從背景/PiP 返回後拖曳讀數卡在展開態
        // (ios-scrub-reset-on-background-reference-ui)。
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            handleDidEnterBackground()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(LBAccessibilityID.playerShell)
    }

    /// Equatable proxy for `model.allProducts` (rb-ios-product-image-loading-polish) —
    /// `LBProduct` itself is not `Equatable` (see `DefaultMomentStates.swift`'s
    /// `handleProducts` doc comment), and `.onChange(of:)` requires an `Equatable` value to
    /// detect real changes. `prefetchIntroducibleProductImages()` always re-reads the LIVE
    /// `model.allProducts` (not this id array), so an id-stable-but-photo-changed edge case
    /// still resolves the current photo URL.
    private var allProductIdsForPrefetch: [String] { model.allProducts.map(\.id) }

    /// Background-prefetch every product's lead photo (`photos.first ?? pic`) into
    /// `ReferenceUIImageCache` as soon as the FULL, unfiltered product list is known — NOT
    /// gated on whether the product is CURRENTLY in the now-introducing / narrating window
    /// (`model.vodActiveProducts` / `model.livePinnedProducts`, both filtered SUBSETS of
    /// `model.allProducts`). The full catalog is already on-device well before any individual
    /// product's `[beginTime,endTime)` window opens or its `narrate_status` flips, so
    /// prefetching against the FULL list — not the already-time/narrate-filtered ones — is
    /// what actually gets ahead of the placeholder flash (rb-ios-product-image-loading-
    /// polish). Because `vodActiveProducts` / `liveActiveProducts` are both subsets of THIS
    /// same list, one loop here covers both the VOD now-introducing carousel and the LIVE
    /// pinned-card carousel — no second, LIVE-specific prefetch path needed. Fire-and-forget;
    /// never touches `@State` / SwiftUI — safe to call from `.onAppear` / `.onChange`.
    private func prefetchIntroducibleProductImages() {
        for product in model.allProducts {
            guard let url = MiniCartView.imageURL(product.photos.first ?? product.pic) else { continue }
            ReferenceUIImagePrefetch.prefetch(url: url)
        }
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
                LockGlyph(size: 30, color: .white)
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
