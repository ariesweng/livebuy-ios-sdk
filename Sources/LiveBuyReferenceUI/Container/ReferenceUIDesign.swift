import SwiftUI
import LivebuySDK
import LivebuyUI

// MARK: - ReferenceUIDesign — the design seam (granularity A)
//
// The three turnkey containers (`LivebuyPlayer` / `LivebuyWidget` / `View.livebuyPlayer`
// presenter) used to hard-code the concrete `minimal` surfaces at the assembly point: the
// player overlay's ZStack instantiated `PlayerShellView` + `FeedWinOverlayView` +
// `ProductSheetsOverlayView` + `MomentsOverlayView` + `ChatComposerBar` +
// `StartScreenHostView`; the widget container `new`ed `ScrollableCarouselView` /
// `ScrollableVideoShopView`; the presenter drew `FloatingWidgetView`.
//
// The container is already decoupled from THEME (`resolveTheme()` resolves a
// `ReferenceUITheme` 5-token palette and passes it down), but it was hard-bound to the
// `minimal` DESIGN (which surfaces, in what layout). A whole different design — different
// component shapes + layout structure + color system, beyond what the thin `ReferenceUITheme`
// palette can express — had no seam to plug into.
//
// `ReferenceUIDesign` is that seam (decision D1: granularity A — the WHOLE overlay / widget
// surface / floating card is one builder, so a design can change the LAYOUT, not just swap
// surfaces). It is a PROTOCOL, not an enum switch (D2): the container holds the abstraction
// and knows NOTHING about any concrete design — no `switch design { case .minimal … }`. That
// also forward-fits an externally-hosted design (the container MUST NOT import any concrete
// design; see `docs/reference-ui/backend-selectable-design.md` §8). Builders return `AnyView`
// (D3, type-erased) because a `some View` return would introduce an associatedtype and block
// heterogeneous storage; each container has exactly one overlay root, so the cost is moot.
//
// This is a PURE DECOUPLING seam: `MinimalDesign` (below in `MinimalDesign.swift`) wraps the
// existing minimal composition verbatim and is the default conformer; behavior is pixel-for-
// pixel unchanged (existing snapshot baselines stay zero-diff). The container does NOT接後台
// `sdkConfig.design` here — backend-selectable design is a follow-up change.

// MARK: - Per-surface context value types
//
// Each builder receives a context value type that bundles the bound view-models + the
// resolved `ReferenceUITheme` + the host-wired interaction closures the surface needs. The
// context holds NO state of its own — only references to the existing models — so a design
// reads it and returns pixels. All fields are public so a host-supplied `ReferenceUIDesign`
// conformer (via `config.design`) can read them.

/// Inputs for the WHOLE player overlay (granularity A: the entire ZStack is one seam). Mirror
/// of the fields the minimal `PlayerOverlayRootView` composes; a design decides how to lay
/// them out.
public struct PlayerOverlayContext {
    public let shellModel: PlayerShellModel
    public let productModel: ProductSheetsModel
    public let feedModel: FeedWinModel
    public let momentsModel: MomentsModel
    public let composerController: ChatComposerController
    /// Presentation state for the on-demand 設定暱稱 modal (composed gated on `isPresented`).
    public let nicknameController: NicknamePromptController
    /// Presentation state for the on-demand「請先登入」(commentSend) modal raised by the LIVE 留言
    /// login gate (composed gated on `isPresented`; rb-ios-live-comment-login-gate).
    public let loginController: LoginPromptController
    /// 「前往登入」CTA on the「請先登入」modal → the HOST's login flow (`config.onLogin`).
    /// reference-ui NEVER logs in itself; nil → the CTA is inert.
    public let onRequestLogin: (() -> Void)?
    public let theme: ReferenceUITheme

    public let paintsBackgroundPlaceholder: Bool
    public let showGestureHints: Bool
    public let onSwipeUp: (() -> Void)?
    public let onSwipeDown: (() -> Void)?
    /// Swipe toward an EMPTY direction (no next / prev video) → close the player
    /// (swipe-nav-close-on-empty #7). Only on the template-nav fallback path (a host
    /// swipe override always wins). nil → swipe-to-empty is a no-op.
    public let onCloseRequest: (() -> Void)?
    public let onHoldStart: (() -> Void)?
    public let onHoldEnd: (() -> Void)?
    public let onMinimize: (() -> Void)?
    public let onToggleMute: () -> Void
    public let onOpenProductList: () -> Void
    public let onShowChatFeed: () -> Void
    public let onComment: () -> Void
    /// 訂閱按鈕（PlayerHeader 頭像徽章 + VideoInfoPanel 訂閱 pill 共用同一入口）→ 未登入訪客先本地
    /// 呈現「請先登入」modal（`AuthGateModalView(.subscribe)`），已登入 → `toggleSubscribe()`
    /// （rb-ios-subscribe-login-gate）。header 徽章與 info pill 兩處都走這一個注入 closure。
    public let onSubscribe: () -> Void
    /// LIVE 底部 bar 暱稱（person-edit）按鈕 → 本地呈現 設定暱稱 modal（不走被 gating 的 core 路徑）。
    public let onNickname: () -> Void
    /// 設定暱稱 modal 送出 → 設定顯示名（容器預設 `Livebuy.setUser`）。傳 trimmed 暱稱。
    public let onNicknameSubmit: (String) -> Void
    public let onProductTap: (LBProduct) -> Void
    public let onShare: () -> Void
    /// 商品列表列縮圖點擊 → 影片跳轉到該商品介紹時間（`LBProduct.beginTime`）。issue 5。
    public let onSeekToProductIntro: (LBProduct) -> Void
    /// 商品列表列分享鈕 → 系統分享，連結帶該商品介紹時間 `?t=beginTime`。issue 6。
    public let onShareProduct: (LBProduct) -> Void
    public let onSend: (String) -> Void
    public let onSkip: () -> Void
    public let onWatchNext: () -> Void
    public let onPickHot: (LBHotItem) -> Void
    public let onCancel: () -> Void
    public let onRetry: () -> Void
    public let onDismiss: () -> Void

    public init(
        shellModel: PlayerShellModel,
        productModel: ProductSheetsModel,
        feedModel: FeedWinModel,
        momentsModel: MomentsModel,
        composerController: ChatComposerController,
        nicknameController: NicknamePromptController = NicknamePromptController(),
        loginController: LoginPromptController = LoginPromptController(),
        onRequestLogin: (() -> Void)? = nil,
        theme: ReferenceUITheme,
        paintsBackgroundPlaceholder: Bool,
        showGestureHints: Bool,
        onSwipeUp: (() -> Void)?,
        onSwipeDown: (() -> Void)?,
        onCloseRequest: (() -> Void)? = nil,
        onHoldStart: (() -> Void)?,
        onHoldEnd: (() -> Void)?,
        onMinimize: (() -> Void)?,
        onToggleMute: @escaping () -> Void,
        onOpenProductList: @escaping () -> Void,
        onShowChatFeed: @escaping () -> Void,
        onComment: @escaping () -> Void,
        onSubscribe: @escaping () -> Void = {},
        onNickname: @escaping () -> Void = {},
        onNicknameSubmit: @escaping (String) -> Void = { _ in },
        onProductTap: @escaping (LBProduct) -> Void,
        onShare: @escaping () -> Void,
        onSeekToProductIntro: @escaping (LBProduct) -> Void,
        onShareProduct: @escaping (LBProduct) -> Void,
        onSend: @escaping (String) -> Void,
        onSkip: @escaping () -> Void,
        onWatchNext: @escaping () -> Void,
        onPickHot: @escaping (LBHotItem) -> Void,
        onCancel: @escaping () -> Void,
        onRetry: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.shellModel = shellModel
        self.productModel = productModel
        self.feedModel = feedModel
        self.momentsModel = momentsModel
        self.composerController = composerController
        self.nicknameController = nicknameController
        self.loginController = loginController
        self.onRequestLogin = onRequestLogin
        self.theme = theme
        self.paintsBackgroundPlaceholder = paintsBackgroundPlaceholder
        self.showGestureHints = showGestureHints
        self.onSwipeUp = onSwipeUp
        self.onSwipeDown = onSwipeDown
        self.onCloseRequest = onCloseRequest
        self.onHoldStart = onHoldStart
        self.onHoldEnd = onHoldEnd
        self.onMinimize = onMinimize
        self.onToggleMute = onToggleMute
        self.onOpenProductList = onOpenProductList
        self.onShowChatFeed = onShowChatFeed
        self.onComment = onComment
        self.onSubscribe = onSubscribe
        self.onNickname = onNickname
        self.onNicknameSubmit = onNicknameSubmit
        self.onProductTap = onProductTap
        self.onShare = onShare
        self.onSeekToProductIntro = onSeekToProductIntro
        self.onShareProduct = onShareProduct
        self.onSend = onSend
        self.onSkip = onSkip
        self.onWatchNext = onWatchNext
        self.onPickHot = onPickHot
        self.onCancel = onCancel
        self.onRetry = onRetry
        self.onDismiss = onDismiss
    }
}

/// Inputs for a widget surface (carousel or grid). The same context drives both — the
/// design picks the layout per builder.
public struct WidgetSurfaceContext {
    public let model: WidgetModel
    public let theme: ReferenceUITheme
    public let live: Bool
    public let onTapVideo: ((LBVideoItem) -> Void)?
    public let onSeeMore: (() -> Void)?
    public let onLoadMore: () -> Void

    public init(
        model: WidgetModel,
        theme: ReferenceUITheme,
        live: Bool,
        onTapVideo: ((LBVideoItem) -> Void)?,
        onSeeMore: (() -> Void)?,
        onLoadMore: @escaping () -> Void
    ) {
        self.model = model
        self.theme = theme
        self.live = live
        self.onTapVideo = onTapVideo
        self.onSeeMore = onSeeMore
        self.onLoadMore = onLoadMore
    }
}

/// Inputs for the minimize floating-preview card.
public struct FloatingCardContext {
    public let video: LBVideoItem
    public let theme: ReferenceUITheme
    public let live: Bool
    public let onTap: (LBVideoItem) -> Void
    public let onClose: () -> Void

    public init(
        video: LBVideoItem,
        theme: ReferenceUITheme,
        live: Bool,
        onTap: @escaping (LBVideoItem) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.video = video
        self.theme = theme
        self.live = live
        self.onTap = onTap
        self.onClose = onClose
    }
}

// MARK: - The design seam

/// A `ReferenceUIDesign` composes a WHOLE container surface from the bound view-models +
/// theme + host closures it is handed (granularity A). The turnkey containers delegate to it
/// and know nothing about any concrete design (D2: protocol, not enum). `MinimalDesign` is
/// the default conformer; a host overrides via `LivebuyPlayerConfig.design` /
/// `LivebuyWidgetConfig.design`.
public protocol ReferenceUIDesign {
    /// The whole player overlay (chrome + feed/win + product sheets + moments + start
    /// lifecycle + on-demand chat composer), composed however this design lays it out.
    func playerOverlay(_ context: PlayerOverlayContext) -> AnyView

    /// The horizontally-scrolling widget carousel surface.
    func widgetCarousel(_ context: WidgetSurfaceContext) -> AnyView

    /// The 2-column widget video-shop grid surface.
    func widgetGrid(_ context: WidgetSurfaceContext) -> AnyView

    /// The minimize floating-preview card.
    func floatingPlayerCard(_ context: FloatingCardContext) -> AnyView
}
