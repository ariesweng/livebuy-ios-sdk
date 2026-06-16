import SwiftUI
import LiveBuySDK
import LiveBuyUI

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
                onHoldStart: context.onHoldStart,
                onHoldEnd: context.onHoldEnd,
                onMinimize: context.onMinimize,
                onToggleMute: context.onToggleMute,
                onOpenProductList: context.onOpenProductList,
                onShowChatFeed: context.onShowChatFeed,
                onComment: context.onComment,
                onNickname: context.onNickname,
                onNicknameSubmit: context.onNicknameSubmit,
                onProductTap: context.onProductTap,
                onShare: context.onShare,
                onSeekToProductIntro: context.onSeekToProductIntro,
                onShareProduct: context.onShareProduct,
                onSend: context.onSend,
                onSkip: context.onSkip,
                onWatchNext: context.onWatchNext,
                onPickHot: context.onPickHot,
                onCancel: context.onCancel,
                onRetry: context.onRetry,
                onDismiss: context.onDismiss))
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
    /// LEFT column (`live-chrome.jsx` `LBLiveChatOverlay` `right:152`) and leaves the bottom-right
    /// `LBLivePinnedCard` column (`right:8 width:132`) free — both visually and for hit-testing,
    /// so the product card shows and is tappable (rb-ios-live-pinned-card-appears).
    static let liveChatTrailingClearance: CGFloat = 152

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
    /// Host-feed swipe overrides forwarded into `PlayerShellView`. nil → the shell uses its
    /// own channel-adjacency forwarders (see `LiveBuyPlayerConfig.swipeFeed`).
    let onSwipeUp: (() -> Void)?
    let onSwipeDown: (() -> Void)?
    /// Hold-to-pause start/end → default-wired to core `player.pause()` / `player.play()`.
    let onHoldStart: (() -> Void)?
    let onHoldEnd: (() -> Void)?
    let onMinimize: (() -> Void)?
    let onToggleMute: () -> Void
    let onOpenProductList: () -> Void
    let onShowChatFeed: () -> Void
    let onComment: () -> Void
    /// LIVE 底部 bar 暱稱按鈕 → 本地呈現 設定暱稱 modal（不走被 gating 的 core 路徑）。
    let onNickname: () -> Void
    /// 設定暱稱 modal 送出 → 設定顯示名（容器預設 `LiveBuy.setUser`）。
    let onNicknameSubmit: (String) -> Void
    let onProductTap: (LBProduct) -> Void
    let onShare: () -> Void
    let onSeekToProductIntro: (LBProduct) -> Void
    let onShareProduct: (LBProduct) -> Void
    let onSend: (String) -> Void
    let onSkip: () -> Void
    let onWatchNext: () -> Void
    let onPickHot: (LBHotItem) -> Void
    let onCancel: () -> Void
    let onRetry: () -> Void
    let onDismiss: () -> Void

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
                onNickname: onNickname,
                onSwipeUp: onSwipeUp,
                onSwipeDown: onSwipeDown,
                onHoldStart: onHoldStart,
                onHoldEnd: onHoldEnd,
                // Hide the LIVE bottom bar while the composer is up (avoid bottom overlap).
                composerPresented: composerController.isPresented,
                // Mirror info-panel open state to hide the chat feed while it's up.
                onInfoPanelPresentedChange: { infoPanelOpen = $0 },
                // Mirror LIVE/VOD so the LIVE-only chat feed is dropped in VOD.
                onIsLiveChange: { isLiveMode = $0 })

            // Keep the merged chat feed above the LIVE bottom bar (they share this ZStack /
            // safe-area space). Clearance = LiveBottomBarView height (8+36+8 ≈ 52) + its own
            // .padding(.bottom, 8) + a small visual gap ≈ 68pt (rb-ios-chat-feed-avoid-bottom-bar).
            // Runtime: scrollable chat feed (binds the deeper history) so the user can
            // scroll up to view history (rb-ios-chat-feed-scrollable); snapshot/demo
            // paths keep the non-scrollable baseline.
            FeedWinOverlayView(model: feedModel, theme: theme,
                               chatBottomInset: Self.liveBottomBarClearance,
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
                               // LIVE-only: drop the chat feed entirely in VOD so it doesn't
                               // occlude / eat the VOD side rail's taps (rb-ios-hide-chat-feed-
                               // in-vod).
                               showsChatFeed: isLiveMode)
            ProductSheetsOverlayView(
                model: productModel,
                theme: theme,
                // Real video surface (placeholder bg suppressed) → load real product photos;
                // standalone / snapshot keeps deterministic placeholders (rb-ios-product-real-images).
                live: !paintsBackgroundPlaceholder,
                onProductTap: onProductTap,
                onShare: onShare,
                onSeekToProductIntro: onSeekToProductIntro,
                onShareProduct: onShareProduct)

            ChatComposerBar(
                controller: composerController,
                theme: theme,
                onSend: onSend)

            // On-demand 設定暱稱 modal — the reference-ui `GuestNameEditModalView` composed
            // into the drop-in overlay (rb-ios-live-nickname-modal-and-comment-gate). Gated on
            // `nicknameController.isPresented` (default false → snapshot-neutral): the LIVE
            // bottom-bar 暱稱 button and the 留言 pill's未設定-暱稱 branch present it; the modal
            // owns its own scrim. `displayName` / `isLoggedIn` bind from the shell snapshot;
            // 送出 → `onNicknameSubmit` (container fulfils via `LiveBuy.setUser`).
            if nicknameController.isPresented {
                GuestNameEditModalView(
                    theme: theme,
                    displayName: shellModel.displayName,
                    isLoggedIn: shellModel.isLoggedIn,
                    onSubmit: { name in onNicknameSubmit(name) },
                    onDismiss: { nicknameController.dismiss() })
            }

            // On-demand「請先登入」modal — the reference-ui `AuthGateModalView(.commentSend)` composed
            // into the drop-in overlay (rb-ios-live-comment-login-gate, 方案 A). Gated on
            // `loginController.isPresented` (default false → snapshot-neutral): a guest tapping the
            // LIVE 留言 pill on a `guest_comment == 0` live (`chatEnabled == false`) presents it; 前往
            // 登入 → host login flow (`onRequestLogin`, reference-ui NEVER logs in itself) then
            // dismiss; 稍後再說 / scrim → dismiss. The modal owns its own scrim.
            if loginController.isPresented {
                AuthGateModalView(
                    theme: theme,
                    triggerAction: .commentSend,
                    onLogin: {
                        loginController.dismiss()
                        onRequestLogin?()
                    },
                    onDismiss: { loginController.dismiss() })
            }

            MomentsOverlayView(
                model: momentsModel,
                theme: theme,
                onWatchNext: onWatchNext,
                onPickHot: onPickHot,
                onCancel: onCancel,
                onRetry: onRetry,
                onDismiss: onDismiss)

            // Start lifecycle (loading / buffering / splash) — a PLAYER-SHELL surface,
            // NOT a moment (rb-ios-start-screen-out-of-moments). Composed topmost so the
            // full-bleed `.loading` covers everything; `.splash` is a transparent skip
            // overlay over the subject chrome. Observes `PlayerShellModel.startPhase`.
            StartScreenHostView(model: shellModel, theme: theme, onSkip: onSkip)
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
    let onSkip: () -> Void

    var body: some View {
        if model.startPhase != .done {
            StartScreenView(theme: theme, phase: model.startPhase, onSkip: onSkip)
        }
    }
}
