import SwiftUI
import LivebuySDK
import LivebuyUI

// MARK: - MinimalDesign — the default ReferenceUIDesign conformer
//
// `MinimalDesign` wraps the existing `minimal` surface composition VERBATIM (decision D5):
// the same surfaces, the same single ZStack / z-order / passthrough hit-test, the same
// `ScrollableCarouselView` / `ScrollableVideoShopView` / `FloatingWidgetView`. It is the
// default design for all three containers (`resolveDesign()` returns it when the host does
// not override). Because the composition is unchanged, behavior is pixel-for-pixel identical
// and the existing reference-ui snapshot baselines stay zero-diff — that zero-diff is the
// acceptance gate for this pure-decoupling change.
//
// This is the ONLY place the concrete minimal surface types are instantiated; the containers
// themselves only see the `ReferenceUIDesign` abstraction.
public struct MinimalDesign: ReferenceUIDesign {

    public init() {}

    /// The whole player overlay: the existing single `ZStack` of `PlayerShellView` +
    /// `FeedWinOverlayView` + `ProductSheetsOverlayView` + `ChatComposerBar` +
    /// `MomentsOverlayView` + `StartScreenHostView`, composed by `PlayerOverlayRootView`
    /// exactly as before — only the inputs now arrive bundled in a `PlayerOverlayContext`.
    public func playerOverlay(_ context: PlayerOverlayContext) -> AnyView {
        AnyView(
            PlayerOverlayRootView(
                shellModel: context.shellModel,
                productModel: context.productModel,
                feedModel: context.feedModel,
                momentsModel: context.momentsModel,
                composerController: context.composerController,
                nicknameController: context.nicknameController,
                loginController: context.loginController,
                onRequestLogin: context.onRequestLogin,
                theme: context.theme,
                paintsBackgroundPlaceholder: context.paintsBackgroundPlaceholder,
                showGestureHints: context.showGestureHints,
                onSwipeUp: context.onSwipeUp,
                onSwipeDown: context.onSwipeDown,
                onCloseRequest: context.onCloseRequest,
                onHoldStart: context.onHoldStart,
                onHoldEnd: context.onHoldEnd,
                onMinimize: context.onMinimize,
                onToggleMute: context.onToggleMute,
                onOpenProductList: context.onOpenProductList,
                onShowChatFeed: context.onShowChatFeed,
                onComment: context.onComment,
                onSubscribe: context.onSubscribe,
                onNickname: context.onNickname,
                onNicknameSubmit: context.onNicknameSubmit,
                onProductTap: context.onProductTap,
                onShare: context.onShare,
                liveNowController: context.liveNowController,
                onGoLive: context.onGoLive,
                onSeekToProductIntro: context.onSeekToProductIntro,
                onShareProduct: context.onShareProduct,
                onSend: context.onSend,
                onSkip: context.onSkip,
                onWatchNext: context.onWatchNext,
                onPickHot: context.onPickHot,
                onCancel: context.onCancel,
                onRetry: context.onRetry,
                onDismiss: context.onDismiss,
                onResolveProduct: context.onResolveProduct,
                onSwitchVideo: context.onSwitchVideo))
    }

    /// The horizontally-scrolling widget carousel — the existing `ScrollableCarouselView`.
    public func widgetCarousel(_ context: WidgetSurfaceContext) -> AnyView {
        AnyView(
            ScrollableCarouselView(
                model: context.model,
                theme: context.theme,
                live: context.live,
                onSeeMore: context.onSeeMore,
                onTapVideo: context.onTapVideo))
    }

    /// The 2-column widget video-shop grid — the existing `ScrollableVideoShopView`.
    public func widgetGrid(_ context: WidgetSurfaceContext) -> AnyView {
        AnyView(
            ScrollableVideoShopView(
                model: context.model,
                theme: context.theme,
                live: context.live,
                onTapVideo: context.onTapVideo,
                onLoadMore: context.onLoadMore))
    }

    /// The minimize floating-preview card — the existing family-5 `FloatingWidgetView`.
    public func floatingPlayerCard(_ context: FloatingCardContext) -> AnyView {
        AnyView(
            FloatingWidgetView(
                video: context.video,
                theme: context.theme,
                live: context.live,
                onTap: context.onTap,
                onClose: context.onClose))
    }
}

// MARK: - PlayerOverlayRootView (single merged overlay hierarchy, R1)
//
// ALL reference-ui overlay surfaces composed in ONE SwiftUI ZStack, bottom→top:
//   1. PlayerShellView — chrome (header / rail / bottom bar) + full-bleed tap-to-mute and
//      swipe gesture layer
//   2. FeedWinOverlayView + ProductSheetsOverlayView — turnkey family-2/3 overlays
//   3. ChatComposerBar — on-demand composer
//   4. MomentsOverlayView — end / error / upcoming-countdown moments
//   5. StartScreenHostView — start lifecycle (loading / buffering / splash); a PLAYER-SHELL
//      surface, NOT a moment (rb-ios-start-screen-out-of-moments); topmost
//
// One hierarchy (not sibling hosting controllers) because `_UIHostingView.hitTest` claims
// its entire bounds regardless of content; within one SwiftUI hierarchy hit-testing is
// content-based, so an empty moment / hidden composer / empty feed area claims nothing
// while an active moment or sheet correctly wins above the chrome.
struct PlayerOverlayRootView: View {

    /// Bottom clearance fed to `FeedWinOverlayView` so the merged chat feed's newest rows
    /// stay above the LIVE bottom bar (they share this ZStack / safe-area space). Derived
    /// from `LiveBottomBarView`: container height (8 + 36 + 8 ≈ 52) + its `.padding(.bottom, 8)`
    /// + a small visual gap (rb-ios-chat-feed-avoid-bottom-bar).
    static let liveBottomBarClearance: CGFloat = 68

    /// Trailing inset fed to `FeedWinOverlayView` so the merged chat feed stays in the design's
    /// LEFT column (`live-chrome.jsx` `LBLiveChatOverlay` `right:120`, R31 — was `right:152`,
    /// tightened as a ripple of the pinned card's width shrink) and leaves the bottom-right
    /// `LBLivePinnedCard` column (`right:8 width:132`) free — both visually and for hit-testing,
    /// so the product card shows and is tappable (rb-ios-live-pinned-card-appears;
    /// value itself corrected by rb-ios-live-announce-chat-clearance-restore).
    static let liveChatTrailingClearance: CGFloat = 120

    /// Leading inset fed to `FeedWinOverlayView` so the merged chat feed's left edge aligns
    /// with the LIVE bottom bar's bag button left margin (`LiveBottomBarView.barHPadding == 10`)
    /// instead of sitting flush against the screen edge (rb-ios-live-chat-card-edge-align).
    static let liveChatLeadingClearance: CGFloat = 10

    /// EXTRA bottom clearance added to the chat feed when the LBLiveAnnounce banner is showing,
    /// so the chat's newest rows clear the bottom-left 公告 banner instead of overlapping it
    /// (rb-ios-live-announce-chat-clearance, 問題 4). ≈ the announce banner's height: vertical
    /// padding 6×2 + 2-line 10.5pt copy (~28) ≈ 40, plus a small gap → 44. Mirrors the design's
    /// chat / announce vertical offset (`live-chrome.jsx` chat `bottom:110` vs announce `bottom:70`,
    /// 差 40). Only applied while a 公告 is present; no announce → no extra inset (baseline unchanged).
    static let liveAnnounceClearance: CGFloat = 44

    /// EXTRA bottom lift added to the chat feed while it has reappeared during the playback-
    /// progress transport bar's post-release hold window (`scrubBarExpanded && !isScrubbing`),
    /// so it clears the still-expanded transport bar — mirrors `PlayerShellView`'s own (private)
    /// `scrubChromeLift` and the identical lift already applied to the announce banner / pinned
    /// card / LIVE bottom bar (design `screens.jsx`'s `scrubVisible ? 36 : 0`,
    /// rb-ios-restore-vod-playback-progress-bar).
    static let scrubChromeLift: CGFloat = 36

    /// The chat feed's bottom inset: the LIVE-bottom-bar clearance, PLUS the announce banner's
    /// height WHEN a 公告 is showing (so the chat avoids overlapping LBLiveAnnounce), PLUS the
    /// scrub-hold lift WHEN the transport bar has reappeared during its post-release hold window.
    /// Pure function (unit-testable). `hasAnnounce == false, scrubExpanded == false` →
    /// `liveBottomBarClearance` (既有 baseline byte-identical).
    static func liveChatBottomInset(hasAnnounce: Bool, scrubHoldLifted: Bool) -> CGFloat {
        var inset = liveBottomBarClearance
        if hasAnnounce { inset += liveAnnounceClearance }
        if scrubHoldLifted { inset += scrubChromeLift }
        return inset
    }

    let shellModel: PlayerShellModel
    let productModel: ProductSheetsModel
    let feedModel: FeedWinModel
    let momentsModel: MomentsModel
    /// On-demand chat composer state — OBSERVED so toggling `isPresented` re-renders this
    /// root, hiding / restoring the LIVE bottom bar via `PlayerShellView(composerPresented:)`
    /// (rb-ios-chat-composer-opaque-hide-bottom-bar).
    @ObservedObject var composerController: ChatComposerController
    /// On-demand 設定暱稱 modal presentation state (composed gated on `isPresented`).
    @ObservedObject var nicknameController: NicknamePromptController
    /// On-demand「請先登入」(commentSend) modal presentation state — OBSERVED so `present()` /
    /// `dismiss()` re-renders this root (rb-ios-live-comment-login-gate). Default false → snapshot-neutral.
    @ObservedObject var loginController: LoginPromptController
    /// 「前往登入」CTA → host login flow (`config.onLogin`). reference-ui NEVER logs in itself.
    let onRequestLogin: (() -> Void)?
    let theme: ReferenceUITheme

    let paintsBackgroundPlaceholder: Bool
    let showGestureHints: Bool
    /// Optional host swipe overrides forwarded into `PlayerShellView`. The turnkey container
    /// always passes nil (it no longer drives swipe from a host feed — the swipe-feed was
    /// removed), so the shell uses its own channel-adjacency forwarders + close-on-empty;
    /// the seam is retained for hosts wiring `PlayerShellView` directly.
    let onSwipeUp: (() -> Void)?
    let onSwipeDown: (() -> Void)?
    /// Swipe toward an empty direction (no next / prev) → close the player (#7).
    let onCloseRequest: (() -> Void)?
    /// Hold-to-pause start/end → default-wired to core `player.pause()` / `player.play()`.
    let onHoldStart: (() -> Void)?
    let onHoldEnd: (() -> Void)?
    let onMinimize: (() -> Void)?
    let onToggleMute: () -> Void
    let onOpenProductList: () -> Void
    let onShowChatFeed: () -> Void
    let onComment: () -> Void
    /// 訂閱按鈕（header 頭像徽章 + info-panel 訂閱 pill 共用）→ 未登入先跳「請先登入」modal
    /// （`.subscribe`），已登入 → `toggleSubscribe()`（rb-ios-subscribe-login-gate）。
    let onSubscribe: () -> Void
    /// LIVE 底部 bar 暱稱按鈕 → 本地呈現 設定暱稱 modal（不走被 gating 的 core 路徑）。
    let onNickname: () -> Void
    /// 設定暱稱 modal 送出 → 設定訪客留言暱稱（容器預設走 checkName 驗證過的
    /// `LivebuyPlayerViewController.setGuestNicknameVerified`；**不**是 `Livebuy.setUser`——設名 ≠ 登入）。
    /// 僅在驗證通過時關閉 modal / 接續後續流程，失敗時留在 modal 顯示 inline 錯誤
    /// （rb-ios-nickname-taken-inline-error）。傳 trimmed 暱稱。
    let onNicknameSubmit: (String) -> Void
    let onProductTap: (LBProduct) -> Void
    let onShare: () -> Void
    /// 「現正直播」右緣半藥丸鈕 (rb-ios-live-now-pill) 的輪詢 controller — `@ObservedObject` 讓
    /// `liveNow` 每次更新都重新渲染，鏡像 `composerController`/`nicknameController` 的既有模式。
    @ObservedObject var liveNowController: LiveNowPollController
    let onGoLive: () -> Void
    let onSeekToProductIntro: (LBProduct) -> Void
    let onShareProduct: (LBProduct) -> Void
    let onSend: (String) -> Void
    let onSkip: () -> Void
    let onWatchNext: () -> Void
    let onPickHot: (LBHotItem) -> Void
    let onCancel: () -> Void
    let onRetry: () -> Void
    let onDismiss: () -> Void
    /// productId → real `LBProduct` resolver (rb-ios-product-detail-recommendations §5).
    let onResolveProduct: ((String) -> LBProduct?)?
    /// 「更多商品」推薦卡播放圖示 → 換片（design.md D3）。
    let onSwitchVideo: ((String) -> Void)?

    /// Mirrors `PlayerShellView`'s info-panel (VideoInfoPanel bottom sheet) open state, so the
    /// chat feed (a HIGHER overlay layer that would otherwise occlude the sheet / swallow its
    /// taps) can be hidden while the panel is up (rb-ios-info-panel-not-covered-by-chat). The
    /// single `UIHostingController` host keeps this `@State` stable; `PlayerShellView` reports
    /// every open/close via `onInfoPanelPresentedChange` so the mirror never desyncs.
    @State private var infoPanelOpen: Bool = false

    /// Mirrors `PlayerShellModel.isLive` so the LIVE-only chat feed is dropped in VOD (where its
    /// full-bleed ScrollView would otherwise occlude / swallow taps on the VOD side rail) —
    /// rb-ios-hide-chat-feed-in-vod. `PlayerShellView` reports the initial value + every switch
    /// via `onIsLiveChange` (the root does NOT observe `shellModel` directly to avoid re-evaluating
    /// on its frequent position/viewer publishes). Defaults VOD (false) until the first report.
    @State private var isLiveMode: Bool = false

    /// Mirrors whether the LBLiveAnnounce banner is showing (`shellModel.announceText` non-empty),
    /// so the chat feed gets EXTRA bottom clearance only while a 公告 is present
    /// (rb-ios-live-announce-chat-clearance, 問題 4). `PlayerShellView` reports the initial value +
    /// every change via `onHasAnnounceChange` (the root does NOT observe `shellModel` directly, to
    /// avoid re-evaluating on its frequent position/viewer publishes). Defaults false (no 公告 →
    /// no extra inset → baseline unchanged) until the first report.
    @State private var hasAnnounce: Bool = false

    /// Mirrors the NARROW `isScrubbing` (finger actually down on the VOD/replay
    /// `PlaybackProgressBarView` transport bar — `PlayerShellView`'s `onScrubbingChange`), so the
    /// merged chat feed is hidden for that same active-drag window, matching how the in-shell
    /// chrome (announce banner / pinned card) hides during `scrubbing` (rb-ios-restore-vod-
    /// playback-progress-bar, corrected post-design-review — see [isScrubBarExpanded] below for
    /// the wider post-release hold window, which LIFTS rather than hides). Only has any effect
    /// while the chat feed would otherwise show (`isLiveMode == true` AND a finished-live replay,
    /// `model.isFinishedLiveReplay` — the only state where the progress bar and the chat feed
    /// can coexist; the progress bar never shows while genuinely live, so a live stream merely
    /// scrubbed behind the live edge does not reach this either); defaults `false` (no chat-feed
    /// impact) until the first report.
    @State private var isScrubbingProgressBar: Bool = false

    /// Mirrors the WIDE `scrubBarExpanded` (touch-down through the 2.8s post-release hold —
    /// `PlayerShellView`'s `onScrubBarExpandedChange`), so the chat feed can be LIFTED (extra
    /// bottom inset, [Self].`scrubChromeLift`) once it reappears during the hold window
    /// (`isScrubBarExpanded && !isScrubbingProgressBar` — design `screens.jsx`
    /// `LBLiveChatOverlay`'s `safeBottom + (isReplay && scrubVisible ? 36 : 0)`, the SAME
    /// treatment as the announce banner / pinned card). Same coexistence scope as
    /// [isScrubbingProgressBar] above. Defaults `false` until the first report.
    @State private var isScrubBarExpanded: Bool = false

    /// Mirrors `PlayerShellView`'s private `cleanMode` `@State` (long-press toggle), so the
    /// family-2 chat feed (`FeedWinOverlayView`'s `ChatFeed`, a sibling composed here — NOT a
    /// descendant of `PlayerShellView` — so `cleanMode` cannot reach it any other way) can be
    /// hidden while clean mode is on, parity with Android/Flutter (rb-ios-clean-mode-hide-chat-
    /// feed). `PlayerShellView` reports the initial value + every toggle via `onCleanModeChange`
    /// (the root does NOT observe `shellModel` directly, same rationale as the mirrors above).
    /// Defaults `false` (baseline unchanged) until the first report.
    @State private var cleanMode: Bool = false

    /// Mirrors `PlayerShellView`'s private `liveMoreSheetPresented` `@State` (LIVE bottom bar
    /// 「更多」(⋯) collapsible menu open/closed), so the family-2 chat feed (a sibling composed
    /// here — NOT a descendant of `PlayerShellView`, so `liveMoreSheetPresented` cannot reach it
    /// any other way) can be hidden while the menu is up — the menu is presented as an internal
    /// `PlayerShellView` bottom sheet, whose visual stacking is confined to that layer, and this
    /// merged ZStack composes the chat feed ABOVE it, so without this mirror the menu would be
    /// occluded / have its taps swallowed by the chat feed (rb-ios-live-more-sheet-above-chat).
    /// `PlayerShellView` reports every open/close via `onMoreSheetPresentedChange`, mirroring the
    /// existing `infoPanelOpen` precedent above. Defaults `false` (baseline unchanged) until the
    /// first report.
    @State private var moreSheetOpen: Bool = false

    /// Mirrors `ProductSheetsOverlayView`'s aggregate "any product sheet/modal presented" signal
    /// (list drawer / detail-or-restock sheet / zoom lightbox / cart-needs-login gate /
    /// variant-select prompt), so the sibling `PlayerShellView` (composed BELOW it in this same
    /// ZStack, not a descendant) can suppress its vertical-swipe video-switch gesture while a
    /// sheet is visually covering the video (rb-ios-block-swipe-nav-when-sheet-open).
    /// `ProductSheetsOverlayView` reports the initial value + every change via
    /// `onPresentationChange`, mirroring the existing `infoPanelOpen` / `cleanMode` /
    /// `moreSheetOpen` mirrors above. Defaults `false` (baseline unchanged) until the first report.
    @State private var productSheetsPresented: Bool = false

    var body: some View {
        ZStack {
            PlayerShellView(
                model: shellModel, theme: theme,
                paintsBackgroundPlaceholder: paintsBackgroundPlaceholder,
                showGestureHints: showGestureHints,
                onMinimize: onMinimize,
                onToggleMute: onToggleMute,
                onOpenProductList: onOpenProductList,
                onShowChatFeed: onShowChatFeed,
                onComment: onComment,
                // 訂閱鈕（header 徽章 + info pill）走容器注入的 gate（未登入 → AuthGate(.subscribe)）。
                onSubscribe: onSubscribe,
                onNickname: onNickname,
                // LIVE 底部 bar 分享鈕走與商品詳情分享同一條 `context.onShare` fallback
                // （host 未攔截 → presentChannelShare 系統 sheet；rb-ios-live-share-default-sheet）。
                onShare: onShare,
                // 「現正直播」鈕：`hasLiveNow` 由本 root 觀察 `liveNowController.liveNow` 現算
                // （每次輪詢更新都會經 `@ObservedObject` 重新渲染），`onGoLive` 原樣轉發
                // （rb-ios-live-now-pill）。
                hasLiveNow: liveNowController.liveNow != nil,
                onGoLive: onGoLive,
                onSwipeUp: onSwipeUp,
                onSwipeDown: onSwipeDown,
                onCloseRequest: onCloseRequest,
                onHoldStart: onHoldStart,
                onHoldEnd: onHoldEnd,
                // Hide the LIVE bottom bar while the composer is up (avoid bottom overlap).
                composerPresented: composerController.isPresented,
                // Suppress the vertical-swipe video-switch gesture while any product sheet/modal
                // is presented (mirrored from `ProductSheetsOverlayView.onPresentationChange`
                // below) — rb-ios-block-swipe-nav-when-sheet-open.
                sheetsPresented: productSheetsPresented,
                // Mirror info-panel open state to hide the chat feed while it's up.
                onInfoPanelPresentedChange: { infoPanelOpen = $0 },
                // Mirror LIVE/VOD so the LIVE-only chat feed is dropped in VOD.
                onIsLiveChange: { isLiveMode = $0 },
                // Mirror 公告 presence so the chat feed avoids overlapping the LBLiveAnnounce
                // banner (extra bottom clearance only while a 公告 is showing) — 問題 4.
                onHasAnnounceChange: { hasAnnounce = $0 },
                // Mirror the playback-progress transport bar's active-drag / expanded-hold
                // windows so the chat feed hides during the drag and reappears LIFTED during the
                // hold (rb-ios-restore-vod-playback-progress-bar).
                onScrubbingChange: { isScrubbingProgressBar = $0 },
                onScrubBarExpandedChange: { isScrubBarExpanded = $0 },
                // Mirror clean mode so the family-2 chat feed can be hidden while it's on
                // (rb-ios-clean-mode-hide-chat-feed).
                onCleanModeChange: { cleanMode = $0 },
                // Mirror the LIVE bottom bar「更多」(⋯) menu open/closed so the family-2 chat feed
                // can be hidden while it's up (rb-ios-live-more-sheet-above-chat).
                onMoreSheetPresentedChange: { moreSheetOpen = $0 })

            // Keep the merged chat feed above the LIVE bottom bar (they share this ZStack /
            // safe-area space). Clearance = LiveBottomBarView height (8+36+8 ≈ 52) + its own
            // .padding(.bottom, 8) + a small visual gap ≈ 68pt (rb-ios-chat-feed-avoid-bottom-bar).
            // Runtime: scrollable chat feed (binds the deeper history) so the user can
            // scroll up to view history (rb-ios-chat-feed-scrollable); snapshot/demo
            // paths keep the non-scrollable baseline.
            FeedWinOverlayView(model: feedModel, theme: theme,
                               // 有公告（LBLiveAnnounce 橫幅）時加大底部避讓，讓聊天最底行不與公告
                               // 重疊；無公告時維持原 clearance（baseline 不變）— 問題 4。放開播放進度
                               // 條到 2.8 秒收回這段期間（scrubBarExpanded && !isScrubbing）額外加上
                               // scrubChromeLift，讓重新出現的聊天避開仍展開的 transport bar。
                               chatBottomInset: Self.liveChatBottomInset(
                                   hasAnnounce: hasAnnounce,
                                   scrubHoldLifted: isScrubBarExpanded && !isScrubbingProgressBar),
                               chatScrollable: true,
                               // Hide the chat feed while the info panel is up so it doesn't
                               // occlude the sheet / swallow its taps (the panel's own scrim
                               // then cleanly covers the background) — rb-ios-info-panel-not-
                               // covered-by-chat.
                               infoPanelOpen: infoPanelOpen,
                               // Keep the chat in the design's left column so it leaves the
                               // bottom-right LBLivePinnedCard column free (rb-ios-live-pinned-
                               // card-appears).
                               chatTrailingInset: Self.liveChatTrailingClearance,
                               // Align the chat's left edge with the LIVE bottom bar's bag
                               // button left margin (rb-ios-live-chat-card-edge-align).
                               chatLeadingInset: Self.liveChatLeadingClearance,
                               // LIVE-only: drop the chat feed entirely in VOD so it doesn't
                               // occlude / eat the VOD side rail's taps (rb-ios-hide-chat-feed-
                               // in-vod). Also dropped while ACTIVELY dragging the playback-
                               // progress transport bar (rb-ios-restore-vod-playback-progress-bar)
                               // — only has an effect in the finished-live-replay state, where
                               // both can coexist. Reappears (lifted, via chatBottomInset above)
                               // once the finger lifts, even during the post-release hold window
                               // — it does NOT stay hidden through the hold (corrected post-
                               // design-review: matches announce banner / pinned card treatment).
                               showsChatFeed: isLiveMode && !isScrubbingProgressBar,
                               // Hide the chat feed while clean mode is on, parity Android/
                               // Flutter — WinEntryView / claim sheet below are NOT gated by
                               // cleanMode (rb-ios-clean-mode-hide-chat-feed).
                               cleanMode: cleanMode,
                               // Hide the chat feed while the LIVE bottom bar「更多」(⋯) menu is
                               // up so it doesn't occlude the menu / swallow its taps (the menu's
                               // own scrim then cleanly covers the background) — rb-ios-live-
                               // more-sheet-above-chat.
                               moreSheetOpen: moreSheetOpen)
            ProductSheetsOverlayView(
                model: productModel,
                theme: theme,
                // Real video surface (placeholder bg suppressed) → load real product photos;
                // standalone / snapshot keeps deterministic placeholders (rb-ios-product-real-images).
                live: !paintsBackgroundPlaceholder,
                onProductTap: onProductTap,
                onShare: onShare,
                onSeekToProductIntro: onSeekToProductIntro,
                onShareProduct: onShareProduct,
                // 加購「需登入」gate's 前往登入 → host login flow (`config.onLogin`), the SAME
                // host hook the comment login-gate uses. reference-ui NEVER logs in itself
                // (cart-needs-login-gate).
                onRequestLogin: onRequestLogin,
                // 「更多商品」推薦格（rb-ios-product-detail-recommendations）——resolve + 換片。
                onResolveProduct: onResolveProduct,
                onSwitchVideo: onSwitchVideo,
                // Mirror the aggregate sheet-presented signal into `PlayerShellView.sheetsPresented`
                // above (rb-ios-block-swipe-nav-when-sheet-open).
                onPresentationChange: { productSheetsPresented = $0 })

            ChatComposerBar(
                controller: composerController,
                theme: theme,
                onSend: onSend)

            // On-demand 設定暱稱 modal — the reference-ui `GuestNameEditModalView` composed
            // into the drop-in overlay (rb-ios-live-nickname-modal-and-comment-gate). Gated on
            // `nicknameController.isPresented` (default false → snapshot-neutral): the LIVE
            // bottom-bar 暱稱 button and the 留言 pill's未設定-暱稱 branch present it; the modal
            // owns its own scrim. `displayName` / `isLoggedIn` bind from the shell snapshot;
            // `errorMessage` / `isSubmitting` bind from `nicknameController` (rb-ios-nickname-taken-
            // inline-error) so a taken/failed verified set shows inline WITHOUT dismissing (both
            // default nil/false when idle → snapshot-neutral, same as `isPresented`); 送出 →
            // `onNicknameSubmit` (container fulfils via `LivebuyPlayerViewController.setGuestNicknameVerified`).
            if nicknameController.isPresented {
                GuestNameEditModalView(
                    theme: theme,
                    displayName: shellModel.displayName,
                    isLoggedIn: shellModel.isLoggedIn,
                    errorMessage: nicknameController.errorMessage,
                    isSubmitting: nicknameController.isSubmitting,
                    onSubmit: { name in onNicknameSubmit(name) },
                    onDismiss: { nicknameController.dismiss() })
            }

            // On-demand「請先登入」modal — the reference-ui `AuthGateModalView` composed into the
            // drop-in overlay. Gated on `loginController.isPresented` (default false → snapshot-
            // neutral). Raised by MULTIPLE gates: a guest tapping the LIVE 留言 pill on a
            // `guest_comment == 0` live presents `.commentSend` (rb-ios-live-comment-login-gate,
            // 方案 A); a guest tapping 訂閱 presents `.subscribe` (rb-ios-subscribe-login-gate). The
            // body copy follows `loginController.triggerAction` (set by `present(triggerAction:)`),
            // so ONE controller serves every gate. 前往登入 → host login flow (`onRequestLogin`,
            // reference-ui NEVER logs in itself) then dismiss; 稍後再說 / scrim → dismiss. The modal
            // owns its own scrim.
            if loginController.isPresented {
                AuthGateModalView(
                    theme: theme,
                    triggerAction: loginController.triggerAction,
                    // Forward optional-ness (design D2.5): unwired `config.onLogin` → nil →
                    // the「前往登入」CTA is hidden, not dead. When wired, dismiss the login
                    // prompt first, then run the host login. (Dismiss is not lost when the
                    // CTA hides — 稍後再說 / scrim still dismisses.)
                    onLogin: lbForwardLogin(onRequestLogin) { loginController.dismiss() },
                    onDismiss: { loginController.dismiss() })
            }

            MomentsOverlayView(
                model: momentsModel,
                theme: theme,
                // Real video surface (placeholder bg suppressed) → the end-screen
                // next-video preview card loads real cover / preview media;
                // standalone / snapshot keeps deterministic placeholders (same flag the
                // product sheets / start-screen surfaces use).
                live: !paintsBackgroundPlaceholder,
                // EndScreen is now LIVE-ONLY (rb-ios-endscreen-live-empty-state): reuse
                // this root's OWN reactive isLive mirror (`isLiveMode`, already fed by
                // `PlayerShellView.onIsLiveChange` — see its declaration above) instead of
                // reading `shellModel.isLive` directly (a plain, non-observed `let` at
                // this level would not trigger a re-render on change).
                isLiveChannel: isLiveMode,
                onWatchNext: onWatchNext,
                onPickHot: onPickHot,
                onCancel: onCancel,
                onRetry: onRetry,
                onDismiss: onDismiss,
                // 空狀態變體「查看購物車」CTA → the SAME `onOpenProductList` action the
                // LIVE bottom bar's bag button uses (no deeper "jump straight to the
                // cart" seam exists at this assembly point — rb-ios-endscreen-live-
                // empty-state design.md「onViewCart wiring」).
                onViewCart: onOpenProductList)

            // Start lifecycle (loading / buffering / splash) — a PLAYER-SHELL surface,
            // NOT a moment (rb-ios-start-screen-out-of-moments). Composed topmost so the
            // full-bleed `.loading` covers everything; `.splash` is a transparent skip
            // overlay over the subject chrome. Observes `PlayerShellModel.startPhase`.
            // `live:` (= runtime, not placeholder) loads the `.loading` cover background
            // (`model.loadingCover`); the snapshot / demo path keeps the solid `#0C0C10`
            // backdrop — the SAME flag `UpcomingCountdownView` uses (design provenance).
            StartScreenHostView(model: shellModel, theme: theme,
                                live: !paintsBackgroundPlaceholder, onSkip: onSkip)
        }
    }
}

/// Observing wrapper so the container-composed start-lifecycle surface stays live with
/// `PlayerShellModel.startPhase` (decoupled from the moments family —
/// rb-ios-start-screen-out-of-moments). Composes `StartScreenView` over the subject
/// chrome while `startPhase != .done`; `onSkip` forwards to the host's core `skipStart()`
/// exit. `.done` renders nothing (the player is in stable playback).
struct StartScreenHostView: View {
    @ObservedObject var model: PlayerShellModel
    let theme: ReferenceUITheme
    /// Runtime opt-in for the `.loading` cover background: `true` on a real video surface
    /// (`!paintsBackgroundPlaceholder`) → loads `model.loadingCover`; `false` (snapshot /
    /// demo) → solid `#0C0C10` backdrop. Same mechanism as `UpcomingCountdownView.live`.
    let live: Bool
    let onSkip: () -> Void

    var body: some View {
        if model.startPhase != .done {
            StartScreenView(theme: theme, phase: model.startPhase,
                            coverUrl: model.loadingCover, live: live, onSkip: onSkip)
        }
    }
}
