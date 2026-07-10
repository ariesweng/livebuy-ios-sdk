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

    /// EXTRA bottom clearance added to the chat feed when the LBLiveAnnounce banner is showing,
    /// so the chat's newest rows clear the bottom-left 公告 banner instead of overlapping it
    /// (rb-ios-live-announce-chat-clearance, 問題 4). ≈ the announce banner's height: vertical
    /// padding 6×2 + 2-line 10.5pt copy (~28) ≈ 40, plus a small gap → 44. Mirrors the design's
    /// chat / announce vertical offset (`live-chrome.jsx` chat `bottom:110` vs announce `bottom:70`,
    /// 差 40). Only applied while a 公告 is present; no announce → no extra inset (baseline unchanged).
    static let liveAnnounceClearance: CGFloat = 44

    /// The chat feed's bottom inset: the LIVE-bottom-bar clearance, PLUS the announce banner's
    /// height WHEN a 公告 is showing (so the chat avoids overlapping LBLiveAnnounce). Pure function
    /// (unit-testable). `hasAnnounce == false` → `liveBottomBarClearance` (既有 baseline byte-identical).
    static func liveChatBottomInset(hasAnnounce: Bool) -> CGFloat {
        hasAnnounce ? liveBottomBarClearance + liveAnnounceClearance : liveBottomBarClearance
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

    /// Mirrors whether the LBLiveAnnounce banner is showing (`shellModel.announceText` non-empty),
    /// so the chat feed gets EXTRA bottom clearance only while a 公告 is present
    /// (rb-ios-live-announce-chat-clearance, 問題 4). `PlayerShellView` reports the initial value +
    /// every change via `onHasAnnounceChange` (the root does NOT observe `shellModel` directly, to
    /// avoid re-evaluating on its frequent position/viewer publishes). Defaults false (no 公告 →
    /// no extra inset → baseline unchanged) until the first report.
    @State private var hasAnnounce: Bool = false

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
                onSwipeUp: onSwipeUp,
                onSwipeDown: onSwipeDown,
                onCloseRequest: onCloseRequest,
                onHoldStart: onHoldStart,
                onHoldEnd: onHoldEnd,
                // Hide the LIVE bottom bar while the composer is up (avoid bottom overlap).
                composerPresented: composerController.isPresented,
                // Mirror info-panel open state to hide the chat feed while it's up.
                onInfoPanelPresentedChange: { infoPanelOpen = $0 },
                // Mirror LIVE/VOD so the LIVE-only chat feed is dropped in VOD.
                onIsLiveChange: { isLiveMode = $0 },
                // Mirror 公告 presence so the chat feed avoids overlapping the LBLiveAnnounce
                // banner (extra bottom clearance only while a 公告 is showing) — 問題 4.
                onHasAnnounceChange: { hasAnnounce = $0 })

            // Keep the merged chat feed above the LIVE bottom bar (they share this ZStack /
            // safe-area space). Clearance = LiveBottomBarView height (8+36+8 ≈ 52) + its own
            // .padding(.bottom, 8) + a small visual gap ≈ 68pt (rb-ios-chat-feed-avoid-bottom-bar).
            // Runtime: scrollable chat feed (binds the deeper history) so the user can
            // scroll up to view history (rb-ios-chat-feed-scrollable); snapshot/demo
            // paths keep the non-scrollable baseline.
            FeedWinOverlayView(model: feedModel, theme: theme,
                               // 有公告（LBLiveAnnounce 橫幅）時加大底部避讓，讓聊天最底行不與公告
                               // 重疊；無公告時維持原 clearance（baseline 不變）— 問題 4。
                               chatBottomInset: Self.liveChatBottomInset(hasAnnounce: hasAnnounce),
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
                onShareProduct: onShareProduct,
                // 加購「需登入」gate's 前往登入 → host login flow (`config.onLogin`), the SAME
                // host hook the comment login-gate uses. reference-ui NEVER logs in itself
                // (cart-needs-login-gate).
                onRequestLogin: onRequestLogin)

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
                // recommended / next-video cards load real cover / preview media;
                // standalone / snapshot keeps deterministic placeholders (same flag the
                // product sheets / start-screen surfaces use).
                live: !paintsBackgroundPlaceholder,
                onWatchNext: onWatchNext,
                onPickHot: onPickHot,
                onCancel: onCancel,
                onRetry: onRetry,
                onDismiss: onDismiss)

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
