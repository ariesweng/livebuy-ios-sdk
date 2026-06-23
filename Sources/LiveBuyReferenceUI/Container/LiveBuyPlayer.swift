import SwiftUI
import LiveBuySDK
import LiveBuyUI

// MARK: - LiveBuyPlayer — turnkey drop-in player container
//
// The SDK `LiveBuyPlayerViewController` is HEADLESS: it paints a black background + a
// video layer only, and `LiveBuyUI` attaches a zero-pixel view-model. To SEE player
// chrome (header / rail / info panel / moments / product+feed overlays / chat composer)
// a host must overlay the reference-ui pixel layer on top of the video surface and wire
// every interaction back to the bound template. That assembly — proven in the Example's
// `LiveBuyPlayerHost` — is what `LiveBuyPlayer` PROMOTES into the package so a host gets
// it in ONE line:
//
//     LiveBuyPlayer(videoId: "123")               // turnkey: all 13 seams defaulted
//     LiveBuyPlayer(videoId: "123", config: cfg)  // override only what differs
//
// It is a PURE ASSEMBLY layer (governance: reference-ui MUST NOT add/modify view-models
// or pixels beyond composing existing surfaces): it only composes existing reference-ui
// surfaces + existing template/core forwarders. Dependency direction stays one-way
// `reference-ui → template (LiveBuyUI) → core (LiveBuySDK)`.
//
// `LiveBuyPlayer` is the GOLDEN NAME (design D-0): most hosts want the assembled drop-in,
// so it gets the most intuitive name; the bare headless VC stays `LiveBuyPlayerViewController`.
//
// OVERLAY COMPOSITION (R1, master `099a367`): ALL surfaces live in ONE `UIHostingController`
// hosting ONE `PlayerOverlayRootView` (a single ZStack). They MUST NOT be stacked as
// sibling hosting controllers — `_UIHostingView.hitTest` claims its entire bounds
// regardless of SwiftUI content, so a sibling on top swallows every touch meant for the
// layers below. Inside one hierarchy, SwiftUI hit-testing is content-based (passthrough
// where nothing is drawn), so the chrome below stays interactive.

/// Per-instance wiring for `LiveBuyPlayer`. Every interaction closure is OPTIONAL with a
/// documented sensible default — a host that passes nothing still gets a working player
/// ("不 wire 也能跑"); passing a closure REPLACES that one default. Promoted from the
/// Example's `LiveBuyPlayerHostConfig`.
public struct LiveBuyPlayerConfig {

    /// The event listener attached to the player. The per-host divergence point (e.g.
    /// ExampleApp's QA stubs vs. ShopHost's commerce flows). Default: none (the SDK's own
    /// default flow only).
    public var eventListener: LiveBuyEventListener?

    /// Top-right minimize tap. DEFAULT (R2): forwards to core `player.minimize()` — the
    /// architecturally-correct seam (today a safe no-op stub; activates when core ships the
    /// deferred in-app PiP transition). The in-app floating-preview collapse is a HOST
    /// presentation concern (it must dismiss the player's presenting sheet and raise a
    /// sibling overlay), so a host that wants it overrides `onMinimize` at its presentation
    /// layer — as both Example hosts do (ExampleApp → floating preview; ShopHost → close).
    public var onMinimize: (() -> Void)?

    /// Tap the video to unmute (REQ5c). Default: the bound template's `toggleMute()`
    /// (→ core engine) so playback produces sound. A host override still receives the
    /// bound template.
    public var onToggleMute: ((DefaultPlayerTemplate) -> Void)?

    /// Rail「商品」open-intent. Default: present the reference-ui `ProductListView` sheet,
    /// a row tap forwarding to `performProductTap` → the product-detail sheet. Receives the
    /// player VC, the bound product model, and the resolved theme.
    public var onOpenProductList: ((LiveBuyPlayerViewController, ProductSheetsModel, ReferenceUITheme) -> Void)?

    /// Rail「聊天」toggle. The merged chat feed is composed always-on; default is a no-op
    /// (the telemetry chat-toggle event already fired).
    public var onShowChatFeed: (() -> Void)?

    /// LIVE「留言...」pill. Default: open + focus the on-demand chat composer (passed in so
    /// a host override can also react to / defer to the same composer). When the live is
    /// guest-comment-gated (`guest_comment == 0`) and the user is a guest, the default first
    /// raises the「請先登入」modal instead (rb-ios-live-comment-login-gate, 方案 A).
    public var onComment: ((ChatComposerController) -> Void)?

    ///「前往登入」CTA on the comment-gate「請先登入」modal → the HOST's own login flow (open a
    /// login screen, then `LiveBuySDK.login(...)`). reference-ui NEVER logs in itself; nil → the
    /// CTA is inert (the modal still informs + dismisses). rb-ios-live-comment-login-gate.
    public var onLogin: (() -> Void)?

    /// Product-row / pinned-card tap. Default: the core product-tap flow (`performProductTap`).
    public var onProductTap: ((LiveBuyPlayerViewController, LBProduct) -> Void)?

    /// Detail-footer 分享. Default: re-emit the SDK share event (`performShare`) so the
    /// listener's share handling fires.
    public var onShare: ((LiveBuyPlayerViewController) -> Void)?

    /// 商品列表列**縮圖**點擊 → 影片跳轉到該商品介紹時間（issue 5）. Default: `player.seek(seconds:
    /// Double(product.beginTime))`（VOD / replay 有效；live 由 core 略過；`beginTime == nil` 不 seek）.
    /// 收到 player VC + 該 `LBProduct`，host override 可改走自家深連結 / 章節跳轉。
    public var onSeekToProductIntro: ((LiveBuyPlayerViewController, LBProduct) -> Void)?

    /// 商品列表列**分享鈕**點擊 → 系統分享，連結帶該商品介紹時間 `?t=beginTime`（issue 6）. Default:
    /// 以 `PlayerShellModel.shareUrl`（= `channel.share_url`）+ `?t=<beginTime>` present 系統
    /// `UIActivityViewController`；`shareUrl` 為空時退回 `performShare()`（channel-level 分享事件）.
    /// 收到 player VC + 該 `LBProduct`，host override 可改走自家分享流程。
    public var onShareProduct: ((LiveBuyPlayerViewController, LBProduct) -> Void)?

    /// End-screen 立即觀看. Default: advance in place to the auto-next target (`next.first`).
    public var onWatchNext: ((LiveBuyPlayerViewController, MomentsModel) -> Void)?

    /// 熱門卡 tap. Default: switch in place to that video (`LBHotItem.id`).
    public var onPickHot: ((LiveBuyPlayerViewController, LBHotItem) -> Void)?

    /// Start-screen 跳過. Default: `skipStart()`.
    public var onSkip: ((LiveBuyPlayerViewController) -> Void)?

    /// End-screen 取消. Default: `cancelAutoNext()` (stop the countdown, NOT a dismiss).
    public var onCancel: ((LiveBuyPlayerViewController) -> Void)?

    /// Error 重試. Default: reload what the player is actually SHOWING (an in-place switch
    /// may have moved off the cover's id).
    public var onRetry: ((LiveBuyPlayerViewController) -> Void)?

    /// Moment dismiss. Default: `dismiss(animated:)`.
    public var onDismiss: ((LiveBuyPlayerViewController) -> Void)?

    /// Whether `PlayerShellView` paints its opaque background placeholder. Default `false`
    /// (overlaying a real video surface — painting it would cover the video).
    public var paintsBackgroundPlaceholder: Bool = false

    /// Whether to show the one-time gesture hint. Default `false` — the container persists
    /// nothing; a host that wants once-per-install behavior computes this in its config.
    public var showGestureHints: Bool = false

    /// Fired when an IN-PLACE switch (hot-pick / watch-next) changes the shown
    /// video, with the NEW video id (R3), so a host can keep its own "current video" state
    /// in sync (e.g. a minimized preview shows the right video). Default `nil`.
    public var onVideoSwitched: ((String) -> Void)?

    /// Like `onVideoSwitched`, but carries the new video as a full `LBVideoItem` — the id PLUS
    /// the REAL `cover` / `title` resolved from the adjacency nav item (swipe) / hot item
    /// (hot-pick) / next item (watch-next) that drove the switch. A host-bound video mirror (the
    /// `liveBuyPlayer(video:)` minimized floating preview card's `video`) consumes this so the
    /// card shows the SWITCHED video's REAL thumbnail — not a placeholder. Fired together with
    /// `onVideoSwitched(id)` on every in-place switch (with an empty `cover` only in the rare
    /// case the switch target is not an adjacency / hot / next item). Default `nil`.
    public var onVideoSwitchedItem: ((LBVideoItem) -> Void)?

    /// The design that composes the overlay surfaces (D-decouple). DEFAULT: `MinimalDesign` —
    /// the existing minimal composition, pixel-for-pixel unchanged. A host supplies a custom
    /// `ReferenceUIDesign` to compose a whole different design (layout + surfaces, beyond what
    /// the thin `ReferenceUITheme` palette can express); the container delegates to it and
    /// never instantiates concrete surface types itself. Backend-selected design is a follow-up.
    public var design: ReferenceUIDesign = MinimalDesign()

    public init() {}
}

/// 留言 pill 預設 gating（純函式，與容器 `onComment` closure 共用一份；問題 2）：暱稱**尚未選名**
/// （`!isLoggedIn && displayName.isEmpty`）→ 回 `true`，容器先呈現 設定暱稱 modal；已選名（訪客經
/// `setGuestNickname` 設名 → `displayName` 非空）或已登入 → 回 `false`，直接開 composer。
/// host 自訂 `config.onComment` 時 MUST NOT 經此函式（完全接管、不套 gating）。
/// rb-ios-nickname-modal-use-guest-nickname（改用 `displayName` 而非僅 `isLoggedIn`，因設名走
/// `setGuestNickname` 後訪客仍 `isLoggedIn == false`）。
func liveCommentRequiresNickname(isLoggedIn: Bool, displayName: String) -> Bool {
    !isLoggedIn && displayName.isEmpty
}

/// 留言 pill 預設**登入**閘（純函式，與容器 `onComment` closure 共用一份；rb-ios-live-comment-login-gate，
/// 方案 A）：該場直播 `guest_comment == 0` → `chatEnabled == false`（留言 pill 只在 LIVE 出現，故
/// `!chatEnabled ⟺ guest_comment==0`）且使用者**未登入** → 回 `true`，容器先本地呈現「請先登入」modal
/// （`AuthGateModalView(.commentSend)`），MUST NOT 開 composer / 跳暱稱 modal。已登入者一律 `false`
/// （`guest_comment` 只閘訪客）。**登入閘 MUST 優先於暱稱閘**——非登入不可留言的訪客不該先被叫去設一個
/// 用不到的暱稱。host 自訂 `config.onComment` 時 MUST NOT 經此函式（完全接管、不套 gating）。
func liveCommentRequiresLogin(isLoggedIn: Bool, chatEnabled: Bool) -> Bool {
    !isLoggedIn && !chatEnabled
}

/// 組商品分享連結（issue 6）：在 `base`（= `channel.share_url`）後加上商品介紹時間 `t=<beginTime>`（秒）。
/// Pure（無副作用）所以容器的分享預設與單元測共用一份實作。
/// - `base` 為空 → 回 `""`（呼叫端退回 channel-level `performShare()`）。
/// - `beginTime` 為 nil 或負 → 回 `base`（不加 `?t=`）。
/// - `base` 已含 query（`?`）→ 用 `&` 串接，否則 `?`。
func productShareURLString(base: String, beginTime: Int?) -> String {
    guard !base.isEmpty else { return "" }
    guard let t = beginTime, t >= 0 else { return base }
    let sep = base.contains("?") ? "&" : "?"
    return "\(base)\(sep)t=\(t)"
}

/// Turnkey drop-in player. Builds a `LiveBuyPlayerViewController`, attaches the Default
/// template, composes all reference-ui surfaces into ONE hosting controller, wires each
/// seam to `config` (defaults where unset), `load`s, and wraps in a nav controller (bar
/// hidden) so a host can push a PDP from a product-tap callback.
public struct LiveBuyPlayer: UIViewControllerRepresentable {

    let videoId: String
    var config: LiveBuyPlayerConfig

    public init(videoId: String, config: LiveBuyPlayerConfig = LiveBuyPlayerConfig()) {
        self.videoId = videoId
        self.config = config
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public func makeUIViewController(context: Context) -> UINavigationController {
        let coordinator = context.coordinator
        let player = makePlayer(coordinator: coordinator)

        if let template = LiveBuyUI.playerTemplate(for: player) {
            let theme = resolveTheme()
            buildModels(template: template, coordinator: coordinator)
            // Decouple seam (D-decouple): build the overlay inputs, then let the resolved
            // `ReferenceUIDesign` (default `MinimalDesign`) compose the pixels. The container
            // never instantiates a concrete surface type itself.
            let context = makeOverlayContext(player: player, template: template,
                                             theme: theme, coordinator: coordinator)
            let overlay = resolveDesign().playerOverlay(context)
            attachOverlay(overlay, to: player, coordinator: coordinator)
        }

        return startPlayback(player: player, coordinator: coordinator)
    }

    /// SwiftUI re-rendered the representable with a (possibly) different video id. Compare
    /// against the COVER's last id — not `currentVideoId` — so a host-driven re-render never
    /// clobbers an in-place switch the viewer made via hot-pick / watch-next / swipe. Reload
    /// in place; the overlay models re-publish on `load` (the proven onPickHot pattern).
    public func updateUIViewController(_ vc: UINavigationController, context: Context) {
        let coordinator = context.coordinator
        guard let player = coordinator.player,
              coordinator.coverVideoId != videoId else { return }
        coordinator.coverVideoId = videoId
        coordinator.currentVideoId = videoId
        player.load(videoId: videoId)
    }

    // MARK: - Compose helpers (D-6: each ≤ 40 lines; side effects injected via params)

    /// New core VC + optional listener + force `viewDidLoad` (so core's `onInstantiate`
    /// fires → LiveBuyUI attaches the template). Also ensures PiP is armed (task 4.1) and
    /// connects core's auto-PiP entry to backgrounding (task 4.1; honest boundary in 4.2/4.3).
    private func makePlayer(coordinator: Coordinator) -> LiveBuyPlayerViewController {
        let player = LiveBuyPlayerViewController()
        if let listener = config.eventListener {
            player.setEventListener(listener)
        }
        // OS PiP (D-4): the container ARMS auto-PiP (core's PiPManager already sets
        // `canStartPictureInPictureAutomaticallyFromInline = true`). It also forwards the
        // genuine background transition to core's existing `requestAutoPiP()`.
        // It CANNOT set the host app target's Background Modes (Audio / Picture in Picture)
        // capability — that is the host's Xcode project / Info.plist. When the capability is
        // absent (`isPiPPossible == false`) core falls back (`auto_pip_fallback` metric +
        // pause); the container does not crash and does not fake success.
        player.enablePiP = true
        coordinator.armAutoPiP(for: player)

        // Force loadView/viewDidLoad so the core fires `onInstantiate` → LiveBuyUI attaches
        // the DefaultPlayerTemplate that `makeUIViewController` reads next.
        _ = player.view
        return player
    }

    /// `sdkConfig.theme` > host options > minimal palette (existing resolver). No host
    /// options surface yet → nil (sdkConfig / minimal).
    private func resolveTheme() -> ReferenceUITheme {
        ReferenceUIThemeResolver.resolve(
            coreTheme: (try? LiveBuy.sdkConfig())?.theme,
            hostOptions: nil)
    }

    /// The design composing the overlay surfaces. Mirrors `resolveTheme()`'s resolution slot:
    /// today it returns the host-set `config.design` (default `MinimalDesign`); backend
    /// `sdkConfig.design` resolution is a follow-up change (`backend-selectable-design.md`).
    private func resolveDesign() -> ReferenceUIDesign {
        config.design
    }

    /// Build the four turnkey overlay models (TK-4), all bound to the SAME attached template
    /// so a reference-ui tap → template perform-method → core → the not-intercepted default
    /// flow publishes back into these snapshots. Plus the on-demand chat composer controller.
    private func buildModels(template: DefaultPlayerTemplate, coordinator: Coordinator) {
        coordinator.model = PlayerShellModel(template: template)
        // Swipe-navigation in-place switch → report `onVideoSwitched` (swipe-video-switched-notify),
        // parity with the onWatchNext / onPickHot paths so a host-bound video mirror (the minimized
        // floating preview card's `video`) tracks the shown video after a swipe. Update cover AND
        // current id: when the host re-renders with the new bound `videoId`, `updateUIViewController`'s
        // cover-guard (`coverVideoId != videoId`) then no-ops → no redundant reload (the swipe already
        // loaded via the template forwarder; we MUST NOT load again here). `[weak coordinator]` breaks
        // the coordinator → model → closure → coordinator retain cycle.
        coordinator.model?.onDidSwitchVideo = { [weak coordinator] id in
            coordinator?.currentVideoId = id
            coordinator?.coverVideoId = id
            config.onVideoSwitched?(id)
            // Report the SWITCHED video as a full item carrying its REAL cover / title so a bound
            // floating preview shows the right thumbnail. The swipe target IS the current channel's
            // `next.first` / `prev.first` (resolved by id); empty cover only if it isn't found.
            config.onVideoSwitchedItem?(coordinator?.switchedItemForSwipe(id: id)
                ?? switchedVideoItem(id: id, cover: "", title: "", duration: 0, liveStatus: 1))
        }
        coordinator.productModel = ProductSheetsModel(template: template)
        coordinator.feedModel = FeedWinModel(template: template)
        coordinator.momentsModel = MomentsModel(template: template)
        coordinator.composerController = ChatComposerController()
        coordinator.nicknameController = NicknamePromptController()
        coordinator.loginController = LoginPromptController()
    }

    /// Single overlay hierarchy attached as ONE child hosting controller (R1). The merged
    /// hosting view swallowing UIKit-level touches is harmless: the player VC below is
    /// headless (video layer only, no touchable UIKit UI). The overlay arrives type-erased
    /// (`AnyView`) from `design.playerOverlay(...)` — the container does not know the concrete
    /// surface type.
    private func attachOverlay(_ root: AnyView,
                               to player: LiveBuyPlayerViewController,
                               coordinator: Coordinator) {
        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        player.addChild(host)
        player.view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: player.view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: player.view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: player.view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: player.view.trailingAnchor),
        ])
        host.didMove(toParent: player)
        coordinator.overlayHost = host
    }

    /// Seed coordinator state, load the cover video, wrap in a nav controller (bar hidden).
    private func startPlayback(player: LiveBuyPlayerViewController,
                               coordinator: Coordinator) -> UINavigationController {
        coordinator.player = player
        coordinator.coverVideoId = videoId
        coordinator.currentVideoId = videoId
        player.load(videoId: videoId)

        let nav = UINavigationController(rootViewController: player)
        nav.setNavigationBarHidden(true, animated: false)
        return nav
    }

    /// 預設商品分享（issue 6）：以 `shareUrl` + `?t=beginTime` present 系統 `UIActivityViewController`。
    /// `shareUrl` 為空 → 退回 core `performShare()`（channel-level 分享事件，由 host listener 處理）。
    /// 從 player VC 最上層呈現（drawer 為 in-shell SheetKit overlay、非 presented VC，故不衝突）。
    static func presentProductShare(from player: LiveBuyPlayerViewController,
                                    shareUrl: String,
                                    product: LBProduct) {
        let urlString = productShareURLString(base: shareUrl, beginTime: product.beginTime)
        guard !urlString.isEmpty else { player.performShare(); return }

        let items: [Any] = URL(string: urlString).map { [$0] } ?? [urlString]
        let activity = UIActivityViewController(activityItems: items, applicationActivities: nil)
        // iPad popover 需 anchor（避免 crash）：錨在播放區底部中央。
        if let pop = activity.popoverPresentationController {
            pop.sourceView = player.view
            pop.sourceRect = CGRect(x: player.view.bounds.midX,
                                    y: player.view.bounds.maxY - 80, width: 0, height: 0)
            pop.permittedArrowDirections = []
        }
        let presenter = player.presentedViewController ?? player
        presenter.present(activity, animated: true)
    }

    /// Wire every seam to `config.onX ?? default` and bundle them into a `PlayerOverlayContext`
    /// (the inputs `design.playerOverlay(...)` composes; for `MinimalDesign` that is the same
    /// `PlayerOverlayRootView` ZStack as before).
    ///
    /// NOTE (unit-test-discipline): this exceeds the ≤40-line guideline — it is a FLAT
    /// list of seam forwards (cyclomatic complexity ~1; each closure is `config.onX ??
    /// default`). It is kept as one cohesive helper deliberately: the seam forwards cannot
    /// be fake-tested (R4: `LiveBuyPlayerViewController` / `DefaultPlayerTemplate` are
    /// `public final` in layers this change MUST NOT modify), so byte-faithfulness to the
    /// proven Example wiring is the correctness guarantee. Splitting it would only scatter
    /// that faithfulness across more surfaces.
    private func makeOverlayContext(player: LiveBuyPlayerViewController,
                                    template: DefaultPlayerTemplate,
                                    theme: ReferenceUITheme,
                                    coordinator: Coordinator) -> PlayerOverlayContext {
        let composerController = coordinator.composerController ?? ChatComposerController()
        let nicknameController = coordinator.nicknameController ?? NicknamePromptController()
        let loginController = coordinator.loginController ?? LoginPromptController()
        let shellModel = coordinator.model!
        let productModel = coordinator.productModel!
        let momentsModel = coordinator.momentsModel!
        let feedModel = coordinator.feedModel!

        // Vertical swipe-to-switch-video: the drop-in NO LONGER injects a host-feed override
        // (`swipeFeed` removed — rb-ios-swipe-always-channel-adjacency). With `onSwipeUp` /
        // `onSwipeDown` left nil, `PlayerShellView` drives the swipe via its built-in
        // channel-adjacency fallback (`navigateToNext()` / `navigateToPrev()`, reading the
        // backend `/sdk/video` `prev` / `next`) and raises `onCloseRequest` at the backend
        // head / tail (swipe-nav-close-on-empty). The host-override seam is retained for hosts
        // wiring `PlayerShellView` directly; the turnkey container just never uses it.
        return PlayerOverlayContext(
            shellModel: shellModel,
            productModel: productModel,
            feedModel: feedModel,
            momentsModel: momentsModel,
            composerController: composerController,
            nicknameController: nicknameController,
            loginController: loginController,
            // 「前往登入」CTA → host 的登入流程（reference-ui NEVER 自登入）。host 未接 → inert。
            onRequestLogin: { config.onLogin?() },
            theme: theme,
            paintsBackgroundPlaceholder: config.paintsBackgroundPlaceholder,
            showGestureHints: config.showGestureHints,
            onSwipeUp: nil,
            onSwipeDown: nil,
            // Swipe toward an EMPTY direction (no next / prev video) → close the player
            // (swipe-nav-close-on-empty #7). Prefer the host's `onDismiss` (host decides
            // dismiss / unload); fall back to core `unload()` when the host wired none.
            onCloseRequest: { [weak player] in
                guard let player = player else { return }
                if let custom = config.onDismiss { custom(player) } else { player.unload() }
            },
            // Hold-to-pause: default forwards to the existing public core engine controls
            // (reference-ui → core). Hold start pauses, release resumes.
            onHoldStart: { [weak player] in player?.pause() },
            onHoldEnd: { [weak player] in player?.play() },
            // Minimize (R2): default forwards to core `player.minimize()` seam.
            onMinimize: config.onMinimize ?? { [weak player] in player?.minimize() },
            // Tap the video to unmute (REQ5c): default → bound template `toggleMute()`.
            onToggleMute: { [weak template] in
                guard let template = template else { return }
                if let custom = config.onToggleMute { custom(template) } else { template.toggleMute() }
            },
            // Rail「商品」→ present the product list (TK-4); a row tap → performProductTap →
            // the product-detail sheet auto-presents from the composed overlay.
            onOpenProductList: { [weak player, weak productModel] in
                guard let player = player, let productModel = productModel else { return }
                if let custom = config.onOpenProductList {
                    custom(player, productModel, theme)
                } else {
                    // Default: open the IN-SHELL product list drawer via the shared SheetKit
                    // `.lbBottomSheet` slide-up presenter (rb-ios-product-list-slide-sheet) —
                    // NOT a system `.pageSheet`. `ProductSheetsOverlayView` observes this flag
                    // and slides the drawer up (dim scrim + handle + drag-to-dismiss).
                    withAnimation { productModel.listPresented = true }
                }
            },
            onShowChatFeed: { config.onShowChatFeed?() },
            // LIVE「留言...」pill → 預設先判斷暱稱是否已設定（`shellModel.isLoggedIn`，鏡像自
            // `template.identityLabel`）：已設定 → 開 composer；未設定 → 先呈現 設定暱稱 modal，
            // 送出後再開 composer（`composeAfter: true`）。host 自訂 `config.onComment` 則完全接管、
            // 不套用 gating（rb-ios-live-nickname-modal-and-comment-gate 問題 2）。
            // 三層 gating（rb-ios-live-comment-login-gate，方案 A）：①登入閘優先——訪客且該場
            // `guest_comment==0`（`chatEnabled==false`）→ 先本地呈現「請先登入」modal；②否則暱稱閘——
            // 未設名訪客 → 設定暱稱 modal（送出後接 composer）；③否則開 composer。host 自訂 `config.onComment`
            // 完全接管、不套 gating。
            onComment: { [weak shellModel] in
                if let custom = config.onComment {
                    custom(composerController)
                } else if liveCommentRequiresLogin(isLoggedIn: shellModel?.isLoggedIn ?? false,
                                                   chatEnabled: shellModel?.chatEnabled ?? true) {
                    loginController.present()
                } else if liveCommentRequiresNickname(isLoggedIn: shellModel?.isLoggedIn ?? false,
                                                      displayName: shellModel?.displayName ?? "") {
                    nicknameController.present(composeAfter: true)
                } else {
                    composerController.open()
                }
            },
            // LIVE 底部 bar 暱稱按鈕 → 本地呈現 設定暱稱 modal（不走被 gating 的 core
            // requestGuestNameEdit；問題 1）。送出後不接 composer（`composeAfter: false`）。
            // **登入閘**（rb-ios-nickname-login-gate）：若該場直播留言需登入（訪客 + `guest_comment==0`
            // ⟺ `!chatEnabled`），點暱稱也比照留言先跳「請先登入」（`loginController.present()` →
            // `config.onLogin`），MUST NOT 開暱稱 modal——非登入不可留言的訪客不該先去設一個用不到的暱稱。
            // 與 `onComment` 共用同一純函式 `liveCommentRequiresLogin`，決策完全一致。
            onNickname: { [weak shellModel] in
                if liveCommentRequiresLogin(isLoggedIn: shellModel?.isLoggedIn ?? false,
                                            chatEnabled: shellModel?.chatEnabled ?? true) {
                    loginController.present()
                } else {
                    nicknameController.present(composeAfter: false)
                }
            },
            // 設定暱稱 modal 送出 → 以 `LiveBuy.setGuestNickname` 設訪客留言暱稱（**不**用
            // `setUser`：設名 ≠ 登入，避免誤觸 logged_in 事件 / PendingAuth 重放 / isGuest 翻 false；
            // rb-ios-nickname-modal-use-guest-nickname / set-guest-nickname-core）、關閉 modal，
            // 並依進入意圖決定是否接著開 composer。
            onNicknameSubmit: { name in
                LiveBuy.setGuestNickname(name)
                let compose = nicknameController.composeAfterSubmit
                nicknameController.dismiss()
                if compose { composerController.open() }
            },
            onProductTap: { [weak player] product in
                guard let player = player else { return }
                if let custom = config.onProductTap { custom(player, product) } else { player.performProductTap(product) }
            },
            // Share is presented by the host on the videoShareRequest event; the footer 分享
            // just re-emits it.
            onShare: { [weak player] in
                guard let player = player else { return }
                if let custom = config.onShare { custom(player) } else { player.performShare() }
            },
            // 商品列表列縮圖點擊 → 影片跳轉到商品介紹時間（issue 5）。預設 seek 到 `beginTime`
            // （VOD / replay；live 由 core `seek` gate 略過；`beginTime == nil` 不 seek）。
            onSeekToProductIntro: { [weak player] product in
                guard let player = player else { return }
                if let custom = config.onSeekToProductIntro {
                    custom(player, product)
                } else if let begin = product.beginTime {
                    player.seek(seconds: Double(begin))
                }
            },
            // 商品列表列分享鈕 → 系統分享，連結帶商品介紹時間 `?t=beginTime`（issue 6）。
            // 預設以 `shellModel.shareUrl` + `?t=` present 系統分享；shareUrl 空 → 退回 performShare()。
            onShareProduct: { [weak player, weak shellModel] product in
                guard let player = player else { return }
                if let custom = config.onShareProduct {
                    custom(player, product)
                } else {
                    Self.presentProductShare(from: player, shareUrl: shellModel?.shareUrl ?? "", product: product)
                }
            },
            onSend: { [weak template] text in template?.sendChat(text) },
            onSkip: { [weak player] in
                guard let player = player else { return }
                if let custom = config.onSkip { custom(player) } else { player.skipStart() }
            },
            // 立即觀看 → advance in place to next.first; guard nil so a missing next no-ops.
            onWatchNext: { [weak player, weak momentsModel, weak coordinator] in
                guard let player = player, let momentsModel = momentsModel else { return }
                if let custom = config.onWatchNext {
                    custom(player, momentsModel)
                } else {
                    guard let next = momentsModel.next.first else { return }
                    coordinator?.currentVideoId = next.id
                    coordinator?.coverVideoId = next.id
                    player.load(videoId: next.id)
                    config.onVideoSwitched?(next.id)
                    // Carry the next item's REAL cover / title (+ preview once backend sends it).
                    config.onVideoSwitchedItem?(switchedVideoItem(
                        id: next.id, cover: next.cover, title: next.title ?? "",
                        duration: next.duration, liveStatus: player.channel?.liveStatus ?? 1,
                        preview: next.preview))
                }
            },
            // 熱門卡 tap → switch in place (`LBHotItem.id` is the target video id).
            onPickHot: { [weak player, weak coordinator] hot in
                guard let player = player else { return }
                if let custom = config.onPickHot {
                    custom(player, hot)
                } else {
                    coordinator?.currentVideoId = hot.id
                    coordinator?.coverVideoId = hot.id
                    player.load(videoId: hot.id)
                    config.onVideoSwitched?(hot.id)
                    // Carry the hot item's REAL cover / title (+ preview once backend sends it)
                    // (`LBHotItem.duration` is a formatted String, not seconds → pass 0).
                    config.onVideoSwitchedItem?(switchedVideoItem(
                        id: hot.id, cover: hot.cover, title: hot.title,
                        duration: 0, liveStatus: player.channel?.liveStatus ?? 1,
                        preview: hot.preview))
                }
            },
            // 取消 → stop the auto-next countdown (NOT a dismiss).
            onCancel: { [weak player] in
                guard let player = player else { return }
                if let custom = config.onCancel { custom(player) } else { player.cancelAutoNext() }
            },
            // 重試 reloads what the player is actually SHOWING.
            onRetry: { [weak player, weak coordinator] in
                guard let player = player else { return }
                if let custom = config.onRetry { custom(player) } else { player.load(videoId: coordinator?.currentVideoId ?? videoId) }
            },
            onDismiss: { [weak player] in
                guard let player = player else { return }
                if let custom = config.onDismiss { custom(player) } else { player.dismiss(animated: true) }
            })
    }

    /// Retains the reference-ui models + the single overlay hosting controller for the
    /// player's lifetime, tracks cover-vs-shown video identity (in-place switches), and owns
    /// the background→auto-PiP observer.
    public final class Coordinator {
        var model: PlayerShellModel?
        var momentsModel: MomentsModel?
        var productModel: ProductSheetsModel?
        var feedModel: FeedWinModel?
        var composerController: ChatComposerController?
        var nicknameController: NicknamePromptController?
        var loginController: LoginPromptController?
        var overlayHost: UIViewController?   // type-erased (PlayerOverlayRootView host)

        weak var player: LiveBuyPlayerViewController?
        /// The last `videoId` prop the representable consumed (cover identity).
        var coverVideoId: String?
        /// What the player actually shows — cover loads AND default in-place switches.
        var currentVideoId: String?

        private var bgObserver: NSObjectProtocol?

        public init() {}

        /// Resolve the SWITCHED-to video's display item for a SWIPE, with its REAL cover / title,
        /// from the CURRENT channel's adjacency nav items (at switch time that channel is still the
        /// pre-switch one, so its `next.first` / `prev.first` ARE the swipe targets). Delegates the
        /// pure lookup to `resolveSwipeSwitchItem`; returns nil with no channel (caller falls back).
        func switchedItemForSwipe(id: String) -> LBVideoItem? {
            guard let ch = player?.channel else { return nil }
            return resolveSwipeSwitchItem(id: id, next: ch.next, prev: ch.prev,
                                          liveStatus: ch.liveStatus)
        }

        /// Forward the genuine background transition to core's existing `requestAutoPiP()`
        /// (task 4.1). `didEnterBackground` fires only on a real background (not transient
        /// interruptions), so this never over-triggers; core guards `enablePiP` + capability
        /// and falls back safely if PiP is impossible (task 4.3).
        func armAutoPiP(for player: LiveBuyPlayerViewController) {
            self.player = player
            bgObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil, queue: .main) { [weak player] _ in
                    player?.requestAutoPiP()
                }
        }

        deinit {
            if let bgObserver = bgObserver { NotificationCenter.default.removeObserver(bgObserver) }
        }
    }
}

// (ProductListSheet was removed — the product list now opens via the in-shell SheetKit
//  `.lbBottomSheet` slide-up presenter driven by `ProductSheetsModel.listPresented`, not a
//  separately-presented `UIHostingController(.pageSheet)`. rb-ios-product-list-slide-sheet.)

/// Resolve a SWIPE switch target's display item from the channel's adjacency nav arrays. The
/// swipe target is the channel's `next.first` (swipe-up) / `prev.first` (swipe-down); match by id
/// and carry that nav item's REAL `cover` / `title` / `duration`. Returns nil when `id` is not an
/// adjacency target (caller falls back to an empty-cover placeholder item). `prev[]` items carry
/// no `title` (backend omits it) → "". Pure (no UIKit / VC) so the lookup is unit-testable.
func resolveSwipeSwitchItem(id: String, next: [LBNavItem], prev: [LBNavItem],
                            liveStatus: Int) -> LBVideoItem? {
    guard let nav = next.first(where: { $0.id == id })
            ?? prev.first(where: { $0.id == id }) else { return nil }
    return switchedVideoItem(id: id, cover: nav.cover, title: nav.title ?? "",
                             duration: nav.duration, liveStatus: liveStatus,
                             preview: nav.preview)
}

/// Build the `LBVideoItem` reported via `onVideoSwitchedItem` after an in-place switch, from the
/// switch target's display fields — the REAL `cover` / `title` (+ `preview` once the backend
/// returns it) taken from the adjacency nav item (swipe) / hot item (hot-pick) / next item
/// (watch-next) that drove the switch. So the bound floating preview card shows the switched
/// video's REAL thumbnail — and, when `preview` is non-empty, its animated preview loop
/// (`rb-ios-collapsible-player-track-switch` + core `nav-hot-item-preview-decode-core`). KIND is
/// derived from `liveStatus` (`type == 2` when live, else `1`); `goods` left empty. `preview`
/// stays "" until the backend adds it to `/sdk/video` nav / hot items, then the card animates with
/// no further SDK change. Pure (no UIKit / I/O) so it is unit-testable.
func switchedVideoItem(id: String, cover: String, title: String,
                       duration: Int, liveStatus: Int, preview: String = "") -> LBVideoItem {
    LBVideoItem(
        id: id,
        type: liveStatus == 1 ? 2 : 1,
        title: title,
        sessionName: nil,
        cover: cover,
        preview: preview,
        duration: duration,
        publishAt: "",
        watchNum: 0,
        pvNum: 0,
        liveStatus: liveStatus,
        pin: 0,
        showPvNum: 0,
        liveurl: "",
        playbackurl: "",
        previewTime: "",
        showStock: false,
        goods: nil)
}
