import SwiftUI
import LivebuySDK
import LivebuyUI

// MARK: - ScrollableVideoShopView — family-5 wrapper tier (drop-in scrolling grid)
//
// Spec: `reference-ui-rendering/spec.md` (wrapper 子層 — 零新像素、drop-in 可捲 widget).
// Design: rb-ios-widget-scroll-wrappers design.md D1 +
//          `design/templates/minimal/widgets.jsx` `LBPVideoShop` (`overflowY: auto`).
//
// The DROP-IN scrolling video-shop grid a host actually uses (user decision
// 2026-06-10:「要讓 host app 可以簡單的使用 SDK」). Place it, wire two closures,
// done — no width plumbing, loaded pages display and scroll:
//
//   ScrollableVideoShopView(
//       model: widgetModel,                       // from widgetTemplate
//       theme: theme,
//       onTapVideo: { item in /* host opens player for item.id */ },
//       onLoadMore: { /* host → widgetTemplate.requestLoadMore() */ })
//
// It owns the composition recipe the host would otherwise need to know: a
// wrapper-owned `GeometryReader` measures the LIVE embed width and feeds it as
// `containerWidth` into a wrapper-owned vertical `ScrollView` around
// `VideoShopGridView(hostScrollable: true)` (intrinsic-height, no card cap —
// every page the host appends via `onLoadMore` actually displays).
//
// The wrapper is a PAGE-LEVEL view: the host gives it a layout area and the
// `GeometryReader` fills the proposal — that is expected and correct here. (The
// prior grid trap was a `GeometryReader` placed INSIDE a host ScrollView's
// unbounded proposal; this wrapper's ScrollView sits INSIDE the GeometryReader,
// so the collapse cannot occur.)
//
// WRAPPER TIER RULES (the narrowed no-ScrollView invariant):
//   • This tier MAY own `ScrollView` / `GeometryReader` — it is NEVER
//     snapshot-rendered via `ImageRenderer` (scroll containers render BLANK
//     there; behavior tests cover it instead, and it MUST NOT get a baseline).
//   • ZERO NEW PIXELS: the body composes the existing snapshot-baselined
//     `VideoShopGridView` plus layout modifiers ONLY — no new Text / Image /
//     shape / fill. Visual correctness stays pinned by the grid's own baselines.
//   • Interactions pass through UNTOUCHED as host-wired closures (nil → inert,
//     demo-constructible). This layer NEVER calls core `simulate*` /
//     `requestLoadMore` / template internals, never paginates, never opens the
//     player.
//   • MUST NOT be composed into `WidgetOverlayView` (snapshot-composed
//     container — its baseline would go blank).
//
// ESCAPE HATCH: a host needing custom scroll behavior wraps its OWN vertical
// `ScrollView` around `VideoShopGridView(hostScrollable: true, containerWidth:)`
// (the `rb-ios-widget-host-scroll` recipe).
//
// iOS-14-safe SwiftUI only (`ScrollView` / `GeometryReader` are iOS-13+).

/// The drop-in scrolling video-shop grid (wrapper tier — zero new pixels): a
/// wrapper-owned `GeometryReader` feeds the live embed width into a vertical
/// `ScrollView` around `VideoShopGridView(hostScrollable: true)` — ALL loaded
/// pages render and scroll, no host width plumbing. Host wires `onTapVideo` /
/// `onLoadMore`; nil closures render an inert demo form. Never
/// snapshot-baselined — behavior-tested.
public struct ScrollableVideoShopView: View {

    /// The read-only widget content snapshot, passed through to the grid surface.
    @ObservedObject public var model: WidgetModel

    /// The resolved reference-ui theme, passed through to the grid surface.
    public let theme: ReferenceUITheme

    /// Runtime media gate, forwarded to the grid surface (`true` → cards render
    /// `preview → cover → placeholder`).
    public let live: Bool

    /// Card tap → host-wired exit, passed through UNTOUCHED to the grid surface
    /// (→ host → core open player for `item.id`). nil → inert.
    private let onTapVideo: ((LBVideoItem) -> Void)?

    /// Footer「載入更多影片...」→ host-wired exit, passed through UNTOUCHED
    /// (→ host → `widgetTemplate.requestLoadMore()`). nil → inert.
    private let onLoadMore: (() -> Void)?

    public init(
        model: WidgetModel,
        theme: ReferenceUITheme,
        live: Bool = false,
        onTapVideo: ((LBVideoItem) -> Void)? = nil,
        onLoadMore: (() -> Void)? = nil
    ) {
        self.model = model
        self.theme = theme
        self.live = live
        self.onTapVideo = onTapVideo
        self.onLoadMore = onLoadMore
    }

    /// Named scroll coordinate space (the sentinel's `minY` is measured relative to it).
    private static let scrollSpace = "lbVideoShopScroll"

    /// Auto-load when the bottom sentinel is within this many points of the viewport
    /// bottom — prefetch one viewport early so scrolling stays smooth (no visible stall).
    static let prefetchMargin: CGFloat = 300

    /// The `WidgetModel.currentPage` we last auto-loaded for, so the same page only
    /// triggers ONE `onLoadMore` (per-page debounce). Re-armed when a new page loads
    /// (`currentPage` increments) → the next bottom-reach is eligible again.
    @State private var lastTriggeredPage: Int = -1

    /// PURE auto-load decision (extracted for unit testing — internal-testability /
    /// the wrapper is never `ImageRenderer`-snapshotted, so behavior is covered by this
    /// + the model paging, not a baseline). Auto-load iff there is a next page
    /// (`currentPage < lastPage`), this page hasn't already triggered
    /// (`currentPage != lastTriggeredPage`), and the bottom sentinel is within
    /// `prefetchMargin` of the viewport bottom (`sentinelMinY <= viewportHeight + margin`).
    static func shouldAutoLoadMore(
        currentPage: Int,
        lastPage: Int,
        lastTriggeredPage: Int,
        sentinelMinY: CGFloat,
        viewportHeight: CGFloat,
        prefetchMargin: CGFloat
    ) -> Bool {
        guard currentPage < lastPage else { return false }            // hasMore
        guard currentPage != lastTriggeredPage else { return false }  // this page already triggered
        return sentinelMinY <= viewportHeight + prefetchMargin        // near the bottom
    }

    public var body: some View {
        // Wrapper-owned width measurement: the ScrollView sits INSIDE the
        // GeometryReader (page-level fill), so the grid's intrinsic-height mode
        // gets a concrete, live containerWidth with zero host plumbing. The same
        // GeometryReader also gives the viewport height used to detect "near bottom".
        GeometryReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 0) {
                    VideoShopGridView(
                        model: model,
                        theme: theme,
                        live: live,
                        hostScrollable: true,
                        containerWidth: proxy.size.width,
                        // Lazy-load drop-in: the wrapper auto-loads on scroll, so the grid's
                        // footer drops its manual button for a dim caption.
                        autoLoadOnScroll: true,
                        onTapVideo: onTapVideo,
                        onLoadMore: onLoadMore)

                    // Zero-pixel bottom sentinel (Color.clear → no visible output, not a new
                    // drawn pixel): reports its minY in the named scroll space so we can detect
                    // when the user has scrolled near the bottom and auto-load the next page.
                    Color.clear
                        .frame(height: 1)
                        .background(
                            GeometryReader { sentinel in
                                Color.clear.preference(
                                    key: BottomSentinelKey.self,
                                    value: sentinel.frame(in: .named(Self.scrollSpace)).minY)
                            })
                }
            }
            .coordinateSpace(name: Self.scrollSpace)
            .onPreferenceChange(BottomSentinelKey.self) { minY in
                if Self.shouldAutoLoadMore(
                    currentPage: model.currentPage,
                    lastPage: model.lastPage,
                    lastTriggeredPage: lastTriggeredPage,
                    sentinelMinY: minY,
                    viewportHeight: proxy.size.height,
                    prefetchMargin: Self.prefetchMargin) {
                    lastTriggeredPage = model.currentPage
                    onLoadMore?()
                }
            }
        }
    }
}

/// Carries the bottom sentinel's `minY` (in the scroll coordinate space) up to the
/// wrapper so it can decide whether to auto-load the next page.
private struct BottomSentinelKey: PreferenceKey {
    static var defaultValue: CGFloat = .greatestFiniteMagnitude
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = min(value, nextValue())
    }
}

#if DEBUG
struct ScrollableVideoShopView_Previews: PreviewProvider {
    static var previews: some View {
        let theme = ReferenceUIThemePalette.minimal
        ScrollableVideoShopView(
            model: WidgetModel(
                videos: VideoShopGridView_Previews.demoVideos,
                mode: .grid,
                currentPage: 0,
                lastPage: 3),
            theme: theme)
            .frame(width: 393, height: 700)
            .previewDisplayName("scrollable video-shop · drop-in")
            .previewLayout(.sizeThatFits)
    }
}
#endif
