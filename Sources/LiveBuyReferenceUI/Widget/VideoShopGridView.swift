import SwiftUI
import LiveBuySDK
import LiveBuyUI

// MARK: - VideoShopGridView — family-5 widget surface 2 (影音商城 / LBPVideoShop)
//
// Spec: `reference-ui-rendering/spec.md` (family-5 widget surfaces).
// Design: rb-ios-widget design.md §"渲染計畫" +
//          `design/templates/minimal/widgets.jsx` `LBPVideoShop` (lines 290-355).
//
// The 影音商城 widget surface: a 2-COLUMN grid of video cards plus a centered
// load-more / end-of-list footer. It is the second of the four family-5 widget
// surfaces composed by `WidgetOverlayView` (selected when `model.mode == .grid`),
// and it implements the frozen SUB-VIEW INPUT PATTERN documented verbatim in
// `WidgetOverlayView.swift`:
//
//   VideoShopGridView(
//       model: WidgetModel,
//       theme: ReferenceUITheme,
//       live: Bool = false,
//       hostScrollable: Bool = false,        // rb-ios-widget-host-scroll
//       containerWidth: CGFloat = 393,       // rb-ios-widget-host-scroll
//       onTapVideo: ((LBVideoItem) -> Void)? = nil,
//       onLoadMore: (() -> Void)? = nil)
//
// HOST-SCROLL EMBEDDING (rb-ios-widget-host-scroll): `hostScrollable: true` swaps
// the `GeometryReader` root (no intrinsic height — collapses inside a host
// vertical `ScrollView`) for a plain intrinsic-height `VStack` rendering ALL
// `model.videos` (no `maxGridCards` cap — loaded pages actually display), cell
// width derived from the explicit `containerWidth`. The host wraps THIS view in
// its own vertical `ScrollView`; scrolling / pagination stays host-owned. The
// default `false` keeps the windowed rendering below byte-identical.
//
// REUSED PRIMITIVE: every grid cell is a shared `CarouselCardView` (the family-5
// 9:16 card — LBPCarouselCard). This surface NEVER re-draws a card from scratch; it
// only arranges `CarouselCardView`s into rows + draws the footer. The cell width is
// derived from the container width minus the inter-column gap (the design passes
// `width="100%"` to the card inside a `repeat(2, 1fr)` grid — here we compute a
// concrete per-cell width so the plain `HStack` lays out the two columns evenly).
//
// ⚠️ NO ScrollView / LazyVGrid / Lazy* in rendered content — the reference-ui
// snapshot path (`ImageRenderer`) renders lazy / scroll containers BLANK (the
// verified family-3 lesson). The design's `LBPVideoShop` is an INFINITE-SCROLL
// `LazyVGrid` inside an `overflowY: auto` container; here it is drawn as a PLAIN
// `VStack` of `HStack` rows (TWO cards per row) over a FIXED SMALL set of
// `model.videos`. The real scroll / pagination is NOT implemented at this layer —
// the load-more intent is forwarded to the host-wired `onLoadMore` closure.
//
// FOOTER (LBPVideoShop 344-351): a centered footer row. When more pages remain
// (`model.currentPage < model.lastPage`) it shows the「載入更多影片...」load-more
// affordance (a host-wired exit → `onLoadMore`); when the last page has been
// reached (`currentPage >= lastPage`, inclusive — Key Invariant: the widget list
// uses `current_page == last_page`) it shows the terminal「已顯示全部影片」label
// (inert). The design auto-loads via an `IntersectionObserver` sentinel; this layer
// instead forwards the intent through the host-wired `onLoadMore` (no auto-scroll /
// no pagination here).
//
// One-way data flow: this surface reads ONLY its passed-in `model` (the published
// `videos` / `currentPage` / `lastPage` snapshot) + `theme`; it never reaches back
// into `DefaultWidgetTemplate`, holds NO second copy of the list, and NEVER loads /
// paginates / opens the player itself. Card tap → `onTapVideo(item)` (host-wired);
// footer load-more → `onLoadMore` (host-wired). It MUST NOT interpret
// `widgetColor` / `widgetBgcolor` for the native theme (those are a SEPARATE
// raw-passthrough track — theme comes ONLY from `ReferenceUITheme`). It renders
// correctly with all actions nil (so demo / snapshot tests construct it action-free).
//
// iOS-14-safe SwiftUI only. `VStack` / `HStack` / `Text` / `Button` /
// `Image(systemName:)` / `RoundedRectangle` are all iOS-13+. No `.task` /
// `AsyncImage` / `LazyVGrid` / `.foregroundStyle` / `.tint` — any >14 API would be
// guarded with `@available` / `if #available`, but none is reached here.

/// The family-5 影音商城 widget surface (`LBPVideoShop`): a 2-column grid of shared
/// `CarouselCardView`s over a FIXED SMALL set of `model.videos`, plus a centered
/// footer that shows「載入更多影片...」(host-wired `onLoadMore`) while more pages
/// remain, else the terminal「已顯示全部影片」. Card tap forwards `onTapVideo(item)`;
/// this layer never scrolls / paginates / opens the player itself.
public struct VideoShopGridView: View {

    /// The republished, read-only widget content snapshot. This surface binds
    /// `model.videos` (the grid cells) + `model.currentPage` / `model.lastPage`
    /// (the footer load-more vs end-of-list gate). Read-only mirror.
    @ObservedObject public var model: WidgetModel

    /// The resolved reference-ui theme. The footer label uses `theme.text` (dimmed);
    /// the load-more affordance uses `theme.accent`; cards paint with their own
    /// theme-driven title color (via `CarouselCardView`).
    public let theme: ReferenceUITheme

    /// Runtime media gate forwarded to every `CarouselCardView`. `false` (default —
    /// demo / snapshot) → placeholder thumbnails (baselines unchanged); `true` (host
    /// runtime) → cards render `preview → cover → placeholder`.
    public let live: Bool

    /// HOST-SCROLL EMBEDDING opt-in (rb-ios-widget-host-scroll D2). `false`
    /// (default): the unchanged windowed rendering — `GeometryReader` root +
    /// the first `maxGridCards` videos (existing baselines / callers untouched).
    /// `true`: a plain `VStack` root with INTRINSIC height (no `GeometryReader` —
    /// embeddable in a host-owned vertical `ScrollView`) rendering ALL
    /// `model.videos` (no cap — every page the host appends via `onLoadMore` /
    /// core `requestLoadMore` actually displays), cell width derived from
    /// `containerWidth`. Scrolling itself stays the HOST's (this layer still
    /// never scrolls / paginates).
    public let hostScrollable: Bool

    /// The host's embed width (pt), used ONLY when `hostScrollable == true` (the
    /// intrinsic-height mode has no `GeometryReader` to measure the live width, and
    /// the host knows its own layout width). Defaults to the reference-ui 393pt
    /// canvas. Ignored in the default windowed mode.
    public let containerWidth: CGFloat

    /// LAZY-LOAD drop-in mode (rb-ios-widget-grid-lazy-load). `false` (default): the
    /// footer keeps its tappable「載入更多影片...」button (existing pixels / baselines /
    /// callers untouched). `true`: the wrapper (`ScrollableVideoShopView`) drives
    /// auto-load on scroll, so the footer becomes a NON-interactive dim caption (no
    /// manual button needed). Only the wrapper passes `true`, and the wrapper is never
    /// `ImageRenderer`-snapshotted, so no baseline is affected.
    public let autoLoadOnScroll: Bool

    /// Card tap → host-wired exit (→ host → core open player for `item.id`). nil for
    /// demo / snapshot instances. This layer NEVER opens the player itself.
    private let onTapVideo: ((LBVideoItem) -> Void)?

    /// Footer「載入更多影片...」→ host-wired exit (→ host → `requestLoadMore()`). nil
    /// for demo / snapshot instances — the affordance is inert. This layer NEVER
    /// loads / paginates itself.
    private let onLoadMore: (() -> Void)?

    public init(
        model: WidgetModel,
        theme: ReferenceUITheme,
        live: Bool = false,
        hostScrollable: Bool = false,
        containerWidth: CGFloat = 393,
        autoLoadOnScroll: Bool = false,
        onTapVideo: ((LBVideoItem) -> Void)? = nil,
        onLoadMore: (() -> Void)? = nil
    ) {
        self.model = model
        self.theme = theme
        self.live = live
        self.hostScrollable = hostScrollable
        self.containerWidth = containerWidth
        self.autoLoadOnScroll = autoLoadOnScroll
        self.onTapVideo = onTapVideo
        self.onLoadMore = onLoadMore
    }

    /// Whether more pages remain (LBPVideoShop's `hasMore`). Mirrors the widget
    /// list's inclusive `current_page == last_page` terminal convention (Key
    /// Invariant: `POST /sdk/widget` uses `current_page == last_page`) — more pages
    /// remain only while `currentPage < lastPage`.
    private var hasMore: Bool { model.currentPage < model.lastPage }

    @ViewBuilder
    public var body: some View {
        if hostScrollable {
            // HOST-SCROLL EMBEDDING mode: a plain `VStack` root with INTRINSIC height.
            // `GeometryReader` has no intrinsic height — inside a host vertical
            // `ScrollView` (an unbounded height proposal) it collapses to zero — so
            // this mode takes the embed width as the explicit `containerWidth` input
            // instead of measuring it. Still NEVER a ScrollView / Lazy* in here; the
            // vertical scroll container is the HOST's.
            content(containerWidth: containerWidth)
                .frame(maxWidth: .infinity, alignment: .top)
                .background(theme.background)
        } else {
            // GeometryReader makes the 2-column grid FOLLOW the live embed width — a host
            // page, an iPad column, or a host-controlled embed need not be 360pt wide, and
            // the per-cell width is derived from the real container width rather than a
            // hardcoded canvas. GeometryReader is iOS-13+ and, UNLIKE ScrollView / Lazy*,
            // is a plain layout container (not a scroll container), so it renders correctly
            // under the `ImageRenderer` snapshot path. The per-surface snapshot test frames
            // the view at a fixed width, so the baseline stays byte-deterministic while a
            // live host of any width still gets evenly-filled columns.
            GeometryReader { proxy in
                content(containerWidth: proxy.size.width)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background(theme.background)
            }
        }
    }

    /// The shared grid + footer column (both rendering modes — the modes differ only
    /// in the root container / cap, never in the pixels).
    private func content(containerWidth: CGFloat) -> some View {
        VStack(spacing: 0) {
            grid(containerWidth: containerWidth)
            footer
        }
        .padding(.horizontal, Self.gridPadding)
        .padding(.top, Self.gridPadding)
    }

    // MARK: - 2-column grid (PLAIN VStack of HStack rows — NEVER LazyVGrid)
    //
    // Mirrors LBPVideoShop's `repeat(2, 1fr)` grid (widgets.jsx 331-343), but built
    // as a PLAIN `VStack` of `HStack` rows (TWO cards per row) over a FIXED SMALL set
    // — the `ImageRenderer` blank-render trap forbids `LazyVGrid` / `ScrollView`. The
    // real infinite scroll forwards to the host-wired `onLoadMore`.

    private func grid(containerWidth: CGFloat) -> some View {
        let cw = cellWidth(forContainerWidth: containerWidth)
        return VStack(spacing: Self.gridGap) {
            ForEach(rows.indices, id: \.self) { rowIndex in
                gridRow(rows[rowIndex], cellWidth: cw)
            }
        }
    }

    /// One grid row: up to TWO shared `CarouselCardView` cells side by side, each
    /// taking an equal half-width column. A trailing odd cell is left-aligned with an
    /// invisible spacer column so the row keeps the 2-col rhythm. REUSES the shared
    /// `CarouselCardView` primitive (never re-draws a card).
    @ViewBuilder
    private func gridRow(_ row: [LBVideoItem], cellWidth: CGFloat) -> some View {
        HStack(alignment: .top, spacing: Self.gridGap) {
            ForEach(row, id: \.id) { item in
                CarouselCardView(
                    item: item,
                    theme: theme,
                    width: cellWidth,
                    live: live,
                    onTap: { onTapVideo?(item) })
            }
            // Keep the 2-col grid rhythm when the final row has a single (odd) cell.
            if row.count == 1 {
                Color.clear.frame(width: cellWidth, height: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The videos chunked into rows of TWO. Default windowed mode bounds the set to
    /// `maxGridCards` so the PLAIN `VStack` stays snapshot-stable; host-scroll mode
    /// renders ALL videos (no cap — the pages the host appends via `onLoadMore` /
    /// core `requestLoadMore` actually display; the design's infinite scroll stays
    /// host-driven, never rendered here).
    private var rows: [[LBVideoItem]] {
        let source = hostScrollable
            ? model.videos
            : Array(model.videos.prefix(Self.maxGridCards))
        return stride(from: 0, to: source.count, by: 2).map { start in
            Array(source[start ..< min(start + 2, source.count)])
        }
    }

    /// The per-cell width for a 2-column grid that FOLLOWS the live container width
    /// (`containerWidth` minus the side paddings + the single inter-column gap,
    /// halved). The design passes `width="100%"` inside a `1fr` grid track; here we
    /// resolve a concrete width from the real embed width (via `GeometryReader`) so the
    /// plain `HStack` lays the two columns out evenly at ANY host width, while the
    /// fixed-width per-surface snapshot stays byte-deterministic.
    private func cellWidth(forContainerWidth containerWidth: CGFloat) -> CGFloat {
        let usable = containerWidth - (Self.gridPadding * 2) - Self.gridGap
        return max(0, usable / 2)
    }

    // MARK: - Footer (載入更多影片... / 已顯示全部影片)
    //
    // Mirrors LBPVideoShop's footer row (widgets.jsx 344-351): a centered footer.
    // While more pages remain → a host-wired「載入更多影片...」load-more affordance
    // (→ onLoadMore); once the last page is reached → the terminal「已顯示全部影片」
    // label (inert). The design auto-loads via a scroll sentinel; this layer forwards
    // the intent to the host-wired closure (no auto-scroll / pagination here).

    @ViewBuilder
    private var footer: some View {
        HStack {
            Spacer(minLength: 0)
            if hasMore {
                if autoLoadOnScroll {
                    // Lazy-load drop-in (wrapper auto-loads on scroll): the footer is a
                    // NON-interactive dim caption — no manual button (`onLoadMore` is fired
                    // by the wrapper's scroll sentinel, not a tap here).
                    Text(Self.loadMoreLabel)
                        .font(.system(size: 12 * theme.fontScale))
                        .foregroundColor(theme.text.opacity(0.5))
                } else {
                    loadMoreAffordance
                }
            } else {
                Text(Self.endOfListLabel)
                    .font(.system(size: 12 * theme.fontScale))
                    .foregroundColor(theme.text.opacity(0.5))
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 14)
        .padding(.bottom, 18)
    }

    /// The「載入更多影片...」load-more affordance — a host-wired exit to `onLoadMore`
    /// (→ host → `requestLoadMore()`). Drawn with `theme.accent` to read as an
    /// actionable link (the design uses a dim caption; here it is an explicit
    /// host-wired button since the reference-ui has no auto-scroll sentinel).
    private var loadMoreAffordance: some View {
        Button(action: { onLoadMore?() }) {
            Text(Self.loadMoreLabel)
                .font(.system(size: 12 * theme.fontScale, weight: .semibold))
                .foregroundColor(theme.accent)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Layout tokens (LBPVideoShop literal spacing)

    /// Outer grid padding (`padding: '12px 12px 8px'`, LBPVideoShop 333).
    static let gridPadding: CGFloat = 12
    /// Inter-cell gap (`gap: 10`, LBPVideoShop 332).
    static let gridGap: CGFloat = 10
    /// FIXED SMALL grid cap — a PLAIN VStack of a bounded N (NEVER lazy / scroll).
    /// The real infinite scroll is host-driven via `onLoadMore`.
    static let maxGridCards = 6

    // MARK: - Fixed presentation strings

    static let loadMoreLabel = "載入更多影片..."
    static let endOfListLabel = "已顯示全部影片"
}

#if DEBUG
struct VideoShopGridView_Previews: PreviewProvider {

    /// A deterministic demo grid: a FIXED SMALL set of demo videos (mixing the LIVE
    /// + VOD card kinds, some with goods overlays), reusing the shared
    /// `CarouselCardView` demo fixtures so the grid stays visually consistent.
    static var demoVideos: [LBVideoItem] {
        [
            .demo(id: "shop-0", title: "週五美妝直播・新品開箱", live: true, goods: .demo()),
            .demo(id: "shop-1", title: "早春保養・限時特賣", live: false, duration: 482,
                  goods: .demo(name: "água玫瑰面膜", price: "390")),
            .demo(id: "shop-2", title: "居家香氛・職人手作", live: false, duration: 1126, goods: nil),
            .demo(id: "shop-3", title: "廚房好物・週年慶", live: false, duration: 738,
                  goods: .demo(name: "鑄鐵鍋 24cm", price: "2,480")),
            .demo(id: "shop-4", title: "親子穿搭・換季出清", live: false, duration: 295, goods: .demo()),
        ]
    }

    static var previews: some View {
        let theme = ReferenceUIThemePalette.minimal
        Group {
            // hasMore — load-more footer (currentPage 0 < lastPage 3).
            VideoShopGridView(
                model: WidgetModel(videos: demoVideos, mode: .grid,
                                   currentPage: 0, lastPage: 3),
                theme: theme)
                .previewDisplayName("grid · load-more footer")

            // end-of-list — 已顯示全部影片 (currentPage == lastPage).
            VideoShopGridView(
                model: WidgetModel(videos: demoVideos, mode: .grid,
                                   currentPage: 3, lastPage: 3),
                theme: theme)
                .previewDisplayName("grid · end-of-list footer")
        }
        .frame(width: 360, height: 760)
        .previewLayout(.sizeThatFits)
    }
}
#endif
