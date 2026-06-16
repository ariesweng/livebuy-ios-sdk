import SwiftUI
import LiveBuySDK
import LiveBuyUI

// MARK: - LiveBuyWidget — turnkey drop-in 直播列表容器（黃金名）
//
// The SDK `LiveBuyWidgetCore` is a HEADLESS data source (zero pixels): it owns the
// videos / pagination / preview-pool and `LiveBuyUI` attaches a zero-pixel view-model.
// To SEE a widget list a host must (1) own a `LiveBuyWidgetCore`, (2) attach the Default
// template, (3) bridge it through `WidgetModel`, (4) render a reference-ui surface, and
// (5) drive the load lifecycle (configure-wait → reload → demo fallback → grid paging →
// periodic refresh). That assembly was proven TWICE in the Example (ExampleApp's
// `WidgetEntryController/WidgetEntryView` + ShopHost's `ShopWidgetController/
// LiveBuyWidgetModule`, near-identical). `LiveBuyWidget` PROMOTES it into the package so a
// host gets a working list in ONE line:
//
//     LiveBuyWidget(shopId: "Pw8PJ99J")                  // turnkey carousel
//     LiveBuyWidget(shopId: "Pw8PJ99J", mode: .grid, config: cfg)
//
// `LiveBuyWidget` is the GOLDEN NAME (design D-0), freed for this container by the
// prerequisite core change `rename-bare-widget-to-core` (bare data source → `LiveBuyWidgetCore`).
//
// PURE ASSEMBLY (governance): it only composes existing reference-ui surfaces
// (`ScrollableCarouselView` / `ScrollableVideoShopView`) + the existing `WidgetModel`
// bridge + existing template forwarders (`reload` / `requestLoadMore`). It adds NO
// view-model and NO pixels. Dependency stays one-way `reference-ui → template → core`.

/// Per-instance wiring for `LiveBuyWidget`. Every interaction closure is OPTIONAL with a
/// documented default; the behavior flags carry production-safe defaults. Promoted from the
/// two Example controllers' parameters.
public struct LiveBuyWidgetConfig {

    /// The event listener attached to the underlying `LiveBuyWidgetCore` (per-instance). The
    /// per-host divergence point (ExampleApp's QA stub vs. ShopHost's commerce listener).
    /// Default: none (the SDK's own default flow only).
    public var eventListener: LiveBuyEventListener?

    /// Card tap. DEFAULT: `nil` → the tap is inert. This is the most common wire point — a
    /// host that wants tapping a card to open the player wires this (the container does not
    /// guess the host's navigation). "全預設" still shows the list correctly; only the tap
    /// is inert until wired.
    public var onTapVideo: ((LBVideoItem) -> Void)?

    /// Carousel「查看更多 ›」header link. DEFAULT: `nil` → inert link. A host wires this to
    /// push its own see-all / 影音商城 page.
    public var onSeeMore: (() -> Void)?

    /// Called after the first load with the ordered video feed, so a host can drive
    /// swipe-to-switch-video in the player (`LiveBuyPlayerConfig.swipeFeed`). DEFAULT: `nil`.
    public var onVideosChanged: (([LBVideoItem]) -> Void)?

    /// Render real thumbnails at runtime (`preview → cover → placeholder`, REQ1 host opt-in).
    /// DEFAULT: `true` (runtime-appropriate; snapshot tests use the raw surfaces with `false`).
    public var live: Bool = true

    /// When the live `/sdk/widget` fetch returns nothing (bad shop / no network), show demo
    /// fixtures + a「示範資料」caption. DEFAULT: `false` (PRODUCTION-SAFE — never show fake
    /// data to real users). Example hosts opt-in `true` to keep their QA demo behavior.
    public var showsDemoFallbackWhenEmpty: Bool = false

    /// Host-policy list auto-refresh interval in seconds. DEFAULT: `30` (`0` = disabled).
    /// Distinct from `PollManager`'s 5s comment polling — this re-fetches page 1 of the list.
    public var listRefreshInterval: TimeInterval = 30

    /// The design that composes the widget surface (D-decouple). DEFAULT: `MinimalDesign` —
    /// the existing `ScrollableCarouselView` / `ScrollableVideoShopView`. A host supplies a
    /// custom `ReferenceUIDesign` to compose a whole different widget design; the container
    /// delegates to it and never instantiates concrete surface types itself.
    public var design: ReferenceUIDesign = MinimalDesign()

    public init() {}
}

// MARK: - Pure helpers (testable; mirror the two Example controllers' guards)

/// Demo-fallback decision: show fixtures only when the live fetch is empty AND the host
/// opted in. Pure (no side effects) so the container and unit tests share one implementation.
func lbWidgetShouldUseDemoFallback(videosEmpty: Bool, enabled: Bool) -> Bool {
    videosEmpty && enabled
}

/// Auto-refresh tick guard: skip while showing demo fixtures, and skip once a grid has paged
/// forward (`currentPage > 1`) — `reload()` resets to page 1 and would collapse accumulated
/// pages. Pure so the container and unit tests share one implementation.
func lbWidgetShouldAutoRefreshTick(usingDemo: Bool, currentPage: Int) -> Bool {
    !usingDemo && currentPage <= 1
}

// MARK: - Controller (promoted + deduped from WidgetEntryController / ShopWidgetController)

/// Owns the headless `LiveBuyWidgetCore` + its reference-ui `WidgetModel` for the view's
/// lifetime, and drives the first-page load, grid pagination, and the host-policy list
/// refresh. Held by `LiveBuyWidget` as a `@StateObject`.
final class LiveBuyWidgetController: ObservableObject {

    /// The headless data source. Retained for the view's lifetime so its attached
    /// `DefaultWidgetTemplate` (which `model` observes) stays alive.
    private let widget: LiveBuyWidgetCore
    /// The attached Default template (nil only if `LiveBuyUI.install()` never ran).
    private let template: DefaultWidgetTemplate?
    /// Carousel or grid — drives the demo-fallback shape and the surface choice.
    private let mode: WidgetMode
    private let config: LiveBuyWidgetConfig

    /// The reference-ui content snapshot the surface binds to. Swapped to demo fixtures only
    /// when the live fetch yields nothing AND `config.showsDemoFallbackWhenEmpty`.
    @Published private(set) var model: WidgetModel
    /// True only when `model` holds demo fixtures (opted-in demo fallback) — surfaces a caption.
    @Published private(set) var usingDemoData = false

    /// Resolved reference-ui theme (`sdkConfig.theme` → host options → minimal palette).
    let theme: ReferenceUITheme

    private var didLoad = false

    init(shopId: String, mode: WidgetMode, config: LiveBuyWidgetConfig) {
        self.mode = mode
        self.config = config

        let widget = LiveBuyWidgetCore(shopId: shopId, mode: mode)
        if let listener = config.eventListener { widget.setEventListener(listener) }
        self.widget = widget

        let template = LiveBuyUI.widgetTemplate(for: widget)
        self.template = template
        self.model = template.map { WidgetModel(template: $0) } ?? WidgetModel()

        self.theme = ReferenceUIThemeResolver.resolve(
            coreTheme: (try? LiveBuy.sdkConfig())?.theme, hostOptions: nil)
    }

    /// Load the first page once. Waits for `LiveBuy.configure()` (kicked off at launch) to
    /// finish first — otherwise `loadFirstPage()` would hit `requireAPIClient()` and `fatalError`.
    /// With a valid shop + credentials this shows REAL `/sdk/widget` videos; it only falls back
    /// to demo fixtures when the live fetch is empty AND the host opted in.
    @MainActor
    func loadIfNeeded() async {
        guard !didLoad else { return }
        didLoad = true

        var waited = 0
        while LiveBuy.shared == nil && waited < 50 {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
            waited += 1
        }

        if LiveBuy.shared != nil { await template?.reload() }

        if lbWidgetShouldUseDemoFallback(
            videosEmpty: model.videos.isEmpty, enabled: config.showsDemoFallbackWhenEmpty) {
            model = Self.demoModel(for: mode)
            usingDemoData = true
        }

        if !usingDemoData { startAutoRefreshIfNeeded() }
    }

    /// Grid load-more footer → core `requestLoadMore()` (fetch next page + refresh snapshot).
    /// No-op for carousel / once past the last page / in demo.
    func requestLoadMore() {
        Task { await template?.requestLoadMore() }
    }

    // MARK: - Periodic list refresh (host policy; default 30s, distinct from PollManager 5s)

    private var refreshTimer: Timer?

    func startAutoRefreshIfNeeded() {
        guard refreshTimer == nil, config.listRefreshInterval > 0 else { return }
        refreshTimer = Timer.scheduledTimer(
            withTimeInterval: config.listRefreshInterval, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                Task { @MainActor in await self.autoRefreshTick() }
            }
    }

    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    @MainActor
    private func autoRefreshTick() async {
        guard lbWidgetShouldAutoRefreshTick(
            usingDemo: usingDemoData, currentPage: model.currentPage) else { return }
        await template?.reload()
    }

    deinit { refreshTimer?.invalidate() }

    // MARK: - Demo fixtures (used only on opted-in empty-live fallback)

    private static func demoModel(for mode: WidgetMode) -> WidgetModel {
        switch mode {
        case .grid:
            return WidgetModel(videos: demoVideos, mode: .grid, currentPage: 1, lastPage: 3)
        default:
            return CarouselView.demoModel()
        }
    }

    private static var demoVideos: [LBVideoItem] {
        [
            .demo(id: "demo-0", title: "週五美妝直播・新品開箱", live: true, goods: .demo()),
            .demo(id: "demo-1", title: "早春保養・限時特賣", duration: 482,
                  goods: .demo(name: "玫瑰面膜", price: "390")),
            .demo(id: "demo-2", title: "居家香氛・職人手作", duration: 1126, goods: nil),
            .demo(id: "demo-3", title: "廚房好物・週年慶", duration: 738,
                  goods: .demo(name: "鑄鐵鍋 24cm", price: "2,480")),
            .demo(id: "demo-4", title: "親子穿搭・換季出清", duration: 295, goods: .demo()),
            .demo(id: "demo-5", title: "彩妝師示範教學", duration: 728, goods: nil),
        ]
    }
}

// MARK: - LiveBuyWidget (public turnkey container)

/// Turnkey drop-in 直播列表容器. Owns a headless `LiveBuyWidgetCore` (via an internal
/// `@StateObject` controller), attaches the Default template, bridges through `WidgetModel`,
/// and renders the drop-in scrollable surface for the host-chosen `mode`. Self-manages the
/// load lifecycle: configure-wait → `reload()` → optional demo fallback → grid pagination →
/// host-policy list refresh. Card taps / see-more / feed publication forward via `config`.
public struct LiveBuyWidget: View {

    @StateObject private var controller: LiveBuyWidgetController
    /// Fixed at init by the host — drives which surface renders (NOT `model.mode`, which can
    /// lag during the demo-fixture fallback).
    private let mode: WidgetMode
    private let config: LiveBuyWidgetConfig

    public init(shopId: String,
                mode: WidgetMode = .carousel,
                config: LiveBuyWidgetConfig = LiveBuyWidgetConfig()) {
        _controller = StateObject(
            wrappedValue: LiveBuyWidgetController(shopId: shopId, mode: mode, config: config))
        self.mode = mode
        self.config = config
    }

    public var body: some View {
        surface
            .overlay(demoCaption, alignment: .bottom)
            // `.task` is iOS 15+; the package floors at iOS 14, so kick the one-shot load off
            // `onAppear` (guarded by `didLoad`). After loading, publish the ordered feed up.
            .onAppear {
                Task {
                    await controller.loadIfNeeded()
                    config.onVideosChanged?(controller.model.videos)
                }
            }
            .onDisappear { controller.stopAutoRefresh() }
    }

    /// The drop-in scrollable wrapper for the host-chosen mode, composed via the resolved
    /// `ReferenceUIDesign` (default `MinimalDesign`): carousel swipes ALL videos; grid scrolls
    /// all loaded pages with the load-more footer self-wired to pagination. The container does
    /// NOT instantiate `ScrollableCarouselView` / `ScrollableVideoShopView` directly — it
    /// hands the bundled inputs to the design.
    private var surface: some View {
        let context = WidgetSurfaceContext(
            model: controller.model,
            theme: controller.theme,
            live: config.live,
            onTapVideo: config.onTapVideo,
            onSeeMore: config.onSeeMore,
            onLoadMore: { controller.requestLoadMore() })
        switch mode {
        case .grid:
            return resolveDesign().widgetGrid(context)
        default:
            return resolveDesign().widgetCarousel(context)
        }
    }

    /// The design composing the widget surface (mirrors `LiveBuyPlayer.resolveDesign()`):
    /// host-set `config.design`, default `MinimalDesign`. Backend `sdkConfig.design` is a
    /// follow-up change.
    private func resolveDesign() -> ReferenceUIDesign {
        config.design
    }

    @ViewBuilder
    private var demoCaption: some View {
        if controller.usingDemoData {
            Text("（示範資料 — 未取得直播列表）")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.bottom, 6)
        }
    }
}
