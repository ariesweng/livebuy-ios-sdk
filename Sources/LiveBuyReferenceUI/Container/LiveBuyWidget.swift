import SwiftUI
import LivebuySDK
import LivebuyUI

// MARK: - LivebuyWidget — turnkey drop-in 直播列表容器（黃金名）
//
// The SDK `LivebuyWidgetCore` is a HEADLESS data source (zero pixels): it owns the
// videos / pagination / preview-pool and `LivebuyUI` attaches a zero-pixel view-model.
// To SEE a widget list a host must (1) own a `LivebuyWidgetCore`, (2) attach the Default
// template, (3) bridge it through `WidgetModel`, (4) render a reference-ui surface, and
// (5) drive the load lifecycle (configure-wait → reload → demo fallback → grid paging →
// periodic refresh). That assembly was proven TWICE in the Example (ExampleApp's
// `WidgetEntryController/WidgetEntryView` + ShopHost's `ShopWidgetController/
// LivebuyWidgetModule`, near-identical). `LivebuyWidget` PROMOTES it into the package so a
// host gets a working list in ONE line:
//
//     LivebuyWidget(shopId: "Pw8PJ99J")                  // turnkey carousel
//     LivebuyWidget(shopId: "Pw8PJ99J", mode: .grid, config: cfg)
//
// `LivebuyWidget` is the GOLDEN NAME (design D-0), freed for this container by the
// prerequisite core change `rename-bare-widget-to-core` (bare data source → `LivebuyWidgetCore`).
//
// PURE ASSEMBLY (governance): it only composes existing reference-ui surfaces
// (`ScrollableCarouselView` / `ScrollableVideoShopView`) + the existing `WidgetModel`
// bridge + existing template forwarders (`reload` / `requestLoadMore`). It adds NO
// view-model and NO pixels. Dependency stays one-way `reference-ui → template → core`.

/// Per-instance wiring for `LivebuyWidget`. Every interaction closure is OPTIONAL with a
/// documented default; the behavior flags carry production-safe defaults. Promoted from the
/// two Example controllers' parameters.
public struct LivebuyWidgetConfig {

    /// The event listener attached to the underlying `LivebuyWidgetCore` (per-instance). The
    /// per-host divergence point (ExampleApp's QA stub vs. ShopHost's commerce listener).
    /// Default: none (the SDK's own default flow only).
    public var eventListener: LivebuyEventListener?

    /// Card tap. DEFAULT: `nil` → the tap is inert. This is the most common wire point — a
    /// host that wants tapping a card to open the player wires this (the container does not
    /// guess the host's navigation). "全預設" still shows the list correctly; only the tap
    /// is inert until wired.
    public var onTapVideo: ((LBVideoItem) -> Void)?

    /// Carousel「查看更多 ›」header link. DEFAULT: `nil` → inert link. A host wires this to
    /// push its own see-all / 影音商城 page.
    public var onSeeMore: (() -> Void)?

    /// Called after the first load with the ordered video feed, so a host can keep its own
    /// list state in sync (e.g. a floating live-entry preview). DEFAULT: `nil`.
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

/// Owns the headless `LivebuyWidgetCore` + its reference-ui `WidgetModel` for the view's
/// lifetime, and drives the first-page load, grid pagination, and the host-policy list
/// refresh. Held by `LivebuyWidget` as a `@StateObject`.
final class LivebuyWidgetController: ObservableObject {

    /// The headless data source. Retained for the view's lifetime so its attached
    /// `DefaultWidgetTemplate` (which `model` observes) stays alive.
    private let widget: LivebuyWidgetCore
    /// The attached Default template (nil only if `LivebuyUI.install()` never ran).
    private let template: DefaultWidgetTemplate?
    /// Carousel or grid — drives the demo-fallback shape and the surface choice.
    private let mode: WidgetMode
    private let config: LivebuyWidgetConfig

    /// The reference-ui content snapshot the surface binds to. Swapped to demo fixtures only
    /// when the live fetch yields nothing AND `config.showsDemoFallbackWhenEmpty`.
    @Published private(set) var model: WidgetModel
    /// True only when `model` holds demo fixtures (opted-in demo fallback) — surfaces a caption.
    @Published private(set) var usingDemoData = false

    /// Resolved reference-ui theme (`sdkConfig.theme` → host options → minimal palette).
    let theme: ReferenceUITheme

    private var didLoad = false

    init(shopId: String, mode: WidgetMode, config: LivebuyWidgetConfig) {
        self.mode = mode
        self.config = config

        let widget = LivebuyWidgetCore(shopId: shopId, mode: mode)
        if let listener = config.eventListener { widget.setEventListener(listener) }
        self.widget = widget

        let template = LivebuyUI.widgetTemplate(for: widget)
        self.template = template
        self.model = template.map { WidgetModel(template: $0) } ?? WidgetModel()

        self.theme = ReferenceUIThemeResolver.resolve(
            coreTheme: (try? Livebuy.sdkConfig())?.theme, hostOptions: nil)
    }

    /// Load the first page once. Waits for `Livebuy.configure()` (kicked off at launch) to
    /// finish first — otherwise `loadFirstPage()` would hit `requireAPIClient()` and `fatalError`.
    /// With a valid shop + credentials this shows REAL `/sdk/widget` videos; it only falls back
    /// to demo fixtures when the live fetch is empty AND the host opted in.
    @MainActor
    func loadIfNeeded() async {
        guard !didLoad else { return }
        didLoad = true

        var waited = 0
        while Livebuy.shared == nil && waited < 50 {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
            waited += 1
        }

        if Livebuy.shared != nil { await template?.reload() }

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

    /// Restart the periodic list refresh when the widget re-appears (`onDisappear` stops it).
    /// The FIRST `onAppear` already starts the timer inside `loadIfNeeded()`, so this is a no-op
    /// then; every LATER `onAppear` early-returns from `loadIfNeeded()` (guarded by `didLoad`),
    /// so this call is what re-arms the timer that `stopAutoRefresh()` invalidated. Idempotent —
    /// `startAutoRefreshIfNeeded()` already guards `refreshTimer == nil`, so repeated calls never
    /// spawn a second timer; skips while showing demo fixtures (mirrors `loadIfNeeded`'s demo gate).
    func resumeAutoRefreshIfNeeded() {
        guard !usingDemoData else { return }
        startAutoRefreshIfNeeded()
    }

    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    #if DEBUG
    /// Test-only read-only seam: whether the periodic list-refresh timer is currently armed.
    /// Lets unit tests assert the start → stop → resume lifecycle (the reappear-restart regression)
    /// without depending on the timer actually firing. Compiled only in DEBUG.
    var isAutoRefreshActiveForTesting: Bool { refreshTimer != nil }

    /// Test-only mutator: force the demo-fixtures state so a test can assert the demo gate on
    /// `resumeAutoRefreshIfNeeded()` deterministically (without a 5s configure-poll). Compiled only
    /// in DEBUG.
    func setUsingDemoDataForTesting(_ value: Bool) { usingDemoData = value }
    #endif

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

// MARK: - LivebuyWidget (public turnkey container)

/// Turnkey drop-in 直播列表容器. Owns a headless `LivebuyWidgetCore` (via an internal
/// `@StateObject` controller), attaches the Default template, bridges through `WidgetModel`,
/// and renders the drop-in scrollable surface for the host-chosen `mode`. Self-manages the
/// load lifecycle: configure-wait → `reload()` → optional demo fallback → grid pagination →
/// host-policy list refresh. Card taps / see-more / feed publication forward via `config`.
public struct LivebuyWidget: View {

    @StateObject private var controller: LivebuyWidgetController
    /// Fixed at init by the host — drives which surface renders (NOT `model.mode`, which can
    /// lag during the demo-fixture fallback).
    private let mode: WidgetMode
    private let config: LivebuyWidgetConfig

    /// Default-open player presentation (dropin-widget-default-open-player): a tap on a
    /// NON-external card sets this ONLY when the host did NOT wire `config.onTapVideo`; the
    /// `.fullScreenCover` in `body` then presents a full-screen `LivebuyPlayer`. `fullScreenCover`
    /// (not a self-attached persistent `.livebuyPlayer` overlay) so the player is full-screen
    /// regardless of how small the widget is embedded (design D1). Stays `nil` when the host set
    /// `onTapVideo` (override) → the cover never arms. Wrapped because `LBVideoItem` is not
    /// `Identifiable`.
    @State private var defaultPresented: PresentedVideo?

    /// `Identifiable` wrapper for `fullScreenCover(item:)` (LBVideoItem itself is not Identifiable).
    private struct PresentedVideo: Identifiable {
        let id: String
        let item: LBVideoItem
    }

    public init(shopId: String,
                mode: WidgetMode = .carousel,
                config: LivebuyWidgetConfig = LivebuyWidgetConfig()) {
        _controller = StateObject(
            wrappedValue: LivebuyWidgetController(shopId: shopId, mode: mode, config: config))
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
                    // Re-arm the periodic list refresh on EVERY appear. First appear: `loadIfNeeded`
                    // already started it → this is a no-op (idempotent). Later appears: `loadIfNeeded`
                    // early-returns (`didLoad`), so this is what restarts the timer that `onDisappear`
                    // stopped — otherwise the 30s refresh dies permanently after the widget leaves
                    // and returns once (tab switch / player return / carousel scroll-out).
                    controller.resumeAutoRefreshIfNeeded()
                    config.onVideosChanged?(controller.model.videos)
                }
            }
            .onDisappear { controller.stopAutoRefresh() }
            // Default-open player (dropin-widget-default-open-player). Inert while
            // `defaultPresented == nil` (host wired `onTapVideo`, or no tap yet) → at rest this
            // adds nothing visible, so existing widget snapshots stay byte-identical.
            .fullScreenCover(item: $defaultPresented) { p in
                LivebuyPlayer(videoId: p.id, config: defaultPlayerConfig)
                    .ignoresSafeArea()
            }
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
            // Tap routing (dropin-widget-default-open-player):
            //   external-platform live → open platform URL (externalLiveAwareTap, highest
            //   precedence, unchanged); non-external → host `onTapVideo` if wired, else the
            //   DEFAULT in-app player (effectiveOnTapVideo).
            onTapVideo: externalLiveAwareTap(effectiveOnTapVideo),
            onSeeMore: config.onSeeMore,
            onLoadMore: { controller.requestLoadMore() })
        switch mode {
        case .grid:
            return resolveDesign().widgetGrid(context)
        default:
            return resolveDesign().widgetCarousel(context)
        }
    }

    /// The design composing the widget surface (mirrors `LivebuyPlayer.resolveDesign()`):
    /// host-set `config.design`, default `MinimalDesign`. Backend `sdkConfig.design` is a
    /// follow-up change.
    private func resolveDesign() -> ReferenceUIDesign {
        config.design
    }

    /// Non-external card tap handler (dropin-widget-default-open-player): the host's
    /// `config.onTapVideo` when wired (full override — the default cover never arms), else the
    /// DEFAULT that opens the in-app player via `fullScreenCover`. A host wanting tap to be a true
    /// no-op sets `onTapVideo = { _ in }`. External-platform lives never reach here (handled by
    /// the enclosing `externalLiveAwareTap`).
    private var effectiveOnTapVideo: (LBVideoItem) -> Void {
        if let hostTap = config.onTapVideo { return hostTap }
        return { item in defaultPresented = PresentedVideo(id: item.id, item: item) }
    }

    /// Config for the default-open player. Inherits the widget's `design` so the player matches
    /// the widget visually (D4). `onDismiss` / `onMinimize` clear `defaultPresented` to dismiss the
    /// `fullScreenCover` — the default cover has no floating-preview target (the minimize→floating
    /// collapse needs the root-level `.livebuyPlayer` presenter; design D1 tradeoff), so minimize
    /// closes. The player's own `dismiss(animated:)` default would not dismiss a SwiftUI cover.
    private var defaultPlayerConfig: LivebuyPlayerConfig {
        var c = LivebuyPlayerConfig()
        c.design = config.design
        c.onDismiss = { _ in defaultPresented = nil }
        c.onMinimize = { defaultPresented = nil }
        return c
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
