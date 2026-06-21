import SwiftUI
import LiveBuySDK
import LiveBuyUI

// MARK: - CarouselView — family-5 widget surface 1 (LBPCarousel, horizontal card row)
//
// Spec: `reference-ui-rendering/spec.md` (family-5 widget surfaces).
// Design: rb-ios-widget design.md §"渲染計畫" +
//          `design/templates/minimal/widgets.jsx` `LBPCarousel` (lines 163-248).
//
// The first of the four family-5 widget surfaces composed by `WidgetOverlayView`
// (selected when `model.mode == .carousel`). It reproduces `LBPCarousel`'s
// structure:
//
//   • a HEADER ROW (widgets.jsx 208-219): the section `title` (heavy) with an
//     optional `subtitle` (dim) on the leading side, and a「查看更多 ›」accent link
//     on the trailing side — only shown when `title` or `subtitle` is non-empty,
//   • a horizontal ROW of `CarouselCardView`s (widgets.jsx 220-245) built from
//     `model.videos`.
//
// ⚠️ The design's row is HORIZONTALLY SCROLLABLE (`overflowX: 'auto'`, drag-to
// -scroll). The reference-ui snapshot path uses `ImageRenderer`, which renders
// `ScrollView` / `Lazy*` containers BLANK (the verified family-3 lesson). So this
// surface lays a FIXED SMALL SET (first `maxCards`) of cards in a PLAIN `HStack`
// (NO ScrollView / Lazy*). The real horizontal scroll / "查看更多" navigation is a
// HOST concern — the「查看更多 ›」link and each card tap forward via the host-wired
// `onTapVideo` exit (the design wires the header link to the same item / list
// navigation the host owns; here the link forwards `videos.first` as the「查看更多」
// proxy when available — see `header`). This layer NEVER scrolls / paginates
// / opens the player itself.
//
// HOST-SCROLL DECOMPOSITION (rb-ios-widget-host-scroll): the header and the card
// strip are extracted as the public sub-surfaces `CarouselHeaderView` /
// `CarouselRowView`, which THIS view recomposes (single pixel source). A host that
// wants the design's real horizontal scroll keeps the header FIXED and wraps ONLY
// the strip in its own scroll container:
//
//   VStack(alignment: .leading, spacing: 0) {
//       CarouselHeaderView(theme: theme, title: "精選影片", onSeeMore: { ... })
//       ScrollView(.horizontal, showsIndicators: false) {     // host-owned
//           CarouselRowView(model: model, theme: theme, live: true,
//                           onTapVideo: { ... })               // ALL videos
//       }
//   }
//
// This default surface keeps the pre-decomposition windowed/clipped 4-card
// rendering byte-identical (existing baselines unchanged).
//
// CARD REUSE: every card is the SHARED `CarouselCardView` primitive (the family-5
// `LBPCarouselCard`) — this surface MUST NOT re-draw a card from scratch. The card
// owns the 9:16 thumbnail placeholder + LIVE / VOD kind badge + product overlay +
// title; this surface only arranges a row of them under a header.
//
// One-way data flow: this surface reads ONLY its passed-in `model` (the read-only
// `videos` mirror) + the `title` / `subtitle` / `cardWidth` inputs; it never
// reaches back into `DefaultWidgetTemplate`, holds NO second copy of state, and
// MUST NOT interpret `widgetColor` / `widgetBgcolor` for the native theme (those
// are a SEPARATE raw-passthrough track — the theme comes ONLY from
// `ReferenceUITheme`). It renders correctly with `onTapVideo` nil (so demo /
// snapshot tests construct it action-free).
//
// iOS-14-safe SwiftUI only. `VStack` / `HStack` / `Text` / `Button` /
// `Image(systemName:)` / `.kerning` are all iOS-13+. NO `AsyncImage` / `.task` /
// `ScrollView` / `Lazy*` / `.foregroundStyle` / `.tint`.

/// The family-5 `LBPCarousel` surface: a header row (title + optional subtitle +
/// 「查看更多 ›」accent link) above a PLAIN `HStack` of a FIXED SMALL set of shared
/// `CarouselCardView`s built from `model.videos`. Card tap (and the「查看更多」link)
/// forward via the host-wired `onTapVideo` exit; this layer never scrolls /
/// paginates / opens the player itself.
public struct CarouselView: View {

    /// The read-only widget content snapshot. This surface binds ONLY `videos`
    /// (the card-row source). Observed so a live template update re-renders.
    @ObservedObject public var model: WidgetModel

    /// The resolved reference-ui theme. The header title uses `theme.text`, the
    /// subtitle a dim variant, and the「查看更多 ›」link `theme.accent`.
    public let theme: ReferenceUITheme

    /// Section title (heavy, leading). Defaults to the design's「精選影片」. An empty
    /// title AND a nil subtitle hide the entire header row (mirrors widgets.jsx 208).
    public let title: String

    /// Optional section subtitle (dim, below the title). nil → no subtitle line.
    public let subtitle: String?

    /// Card width (pt) forwarded to every `CarouselCardView`. Defaults to the
    /// design's `132`; the 9:16 height is derived by the card.
    public let cardWidth: CGFloat

    /// Runtime media gate forwarded to every `CarouselCardView`. `false` (default —
    /// demo / snapshot) → placeholder thumbnails (baselines unchanged); `true` (host
    /// runtime) → cards render `preview → cover → placeholder`.
    public let live: Bool

    /// Card tap (and the「查看更多」header link proxy) → host-wired exit
    /// (`onTapVideo(item)` → host → core open player for `item.id` / list nav). nil
    /// for demo / snapshot instances — the row is inert. This layer NEVER opens the
    /// player / scrolls / paginates itself.
    private let onTapVideo: ((LBVideoItem) -> Void)?

    public init(
        model: WidgetModel,
        theme: ReferenceUITheme,
        title: String = "精選影片",
        subtitle: String? = nil,
        cardWidth: CGFloat = 132,
        live: Bool = false,
        onTapVideo: ((LBVideoItem) -> Void)? = nil
    ) {
        self.model = model
        self.theme = theme
        self.title = title
        self.subtitle = subtitle
        self.cardWidth = cardWidth
        self.live = live
        self.onTapVideo = onTapVideo
    }

    /// Whether the header row shows — `title` non-empty OR a `subtitle` exists
    /// (mirrors `LBPCarousel`'s `(title || subtitle) && (...)`, widgets.jsx 208).
    private var showsHeader: Bool {
        !title.isEmpty || (subtitle?.isEmpty == false)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsHeader {
                header
            }
            cardRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(LBAccessibilityID.widgetCarousel)
    }

    // MARK: - Header row (title + subtitle + 查看更多 ›)
    //
    // Recomposes the extracted `CarouselHeaderView` sub-surface (single pixel
    // source — rb-ios-widget-host-scroll D1; pixels live in the sub-surface, this
    // surface never draws the header twice). `onSeeMore` keeps the pre-decomposition
    // behavior: a host-wired `onTapVideo(videos.first)` see-all proxy when a video
    // exists (the host owns the actual list navigation), inert when `videos` is
    // empty.

    private var header: some View {
        CarouselHeaderView(
            theme: theme,
            title: title,
            subtitle: subtitle,
            onSeeMore: { if let first = model.videos.first { onTapVideo?(first) } })
    }

    // MARK: - Card row (PLAIN HStack of shared CarouselCardViews)
    //
    // Mirrors `LBPCarousel`'s scroller (widgets.jsx 220-245): a horizontal row of
    // `LBPCarouselCard`s with a 12pt gap. The design scrolls horizontally; this
    // surface renders a FIXED SMALL set in a PLAIN `HStack` (NEVER lazy / scroll —
    // the `ImageRenderer` blank-render trap). The real scroll / "查看更多" is a host
    // concern forwarded via `onTapVideo`.

    @ViewBuilder
    private var cardRow: some View {
        if cards.isEmpty {
            emptyRow
        } else {
            cardWindow
                .padding(.bottom, 6)
        }
    }

    /// A width-following window that LEFT-anchors the (intentionally over-wide) card
    /// strip and CLIPS the overflow to a peek. A `.hidden()` single card sets the
    /// window height to exactly one card's height; `.frame(maxWidth: .infinity)`
    /// makes the window follow the proposed (host) width instead of the strip's
    /// intrinsic width — the fixed-width cards have a hard MIN width, so a plain
    /// `HStack` would otherwise widen the parent `VStack` to the full strip width and
    /// push the header's「查看更多」link off the trailing edge. The window keeps the
    /// header full-width and stops the row from overdrawing the host's surrounding
    /// content. The strip itself is the extracted `CarouselRowView` sub-surface
    /// (single pixel source — rb-ios-widget-host-scroll D1) with the SAME windowed
    /// parameters as before the decomposition (`maxCards` 4, leading 16, trailing 0
    /// — the window clips the trailing edge anyway), so the default rendering stays
    /// byte-identical. A host that wants REAL horizontal scroll composes
    /// `CarouselHeaderView` + its own `ScrollView(.horizontal) { CarouselRowView }`
    /// instead — NEVER a `ScrollView` / `Lazy*` in here (the `ImageRenderer`
    /// blank-render trap). `.overlay(_:alignment:)` / `.fixedSize` / `.hidden` are
    /// all iOS-13+.
    private var cardWindow: some View {
        CarouselCardView(item: cards[0], theme: theme, width: cardWidth)
            .hidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(
                CarouselRowView(
                    model: model,
                    theme: theme,
                    cardWidth: cardWidth,
                    live: live,
                    leadingPadding: 16,
                    trailingPadding: 0,
                    maxCards: Self.maxCards,
                    onTapVideo: onTapVideo),
                alignment: .leading
            )
            .clipped()
    }

    /// The FIXED SMALL set actually rendered (first `maxCards`), so the PLAIN
    /// `HStack` stays bounded and snapshot-stable (the design's horizontal scroll
    /// shows the rest — a host concern, not rendered here).
    private var cards: [LBVideoItem] {
        Array(model.videos.prefix(Self.maxCards))
    }

    /// Empty-state line (no videos in the carousel content).
    private var emptyRow: some View {
        HStack {
            Spacer(minLength: 0)
            Text(Self.emptyLabel)
                .font(.system(size: 13 * theme.fontScale))
                .foregroundColor(theme.text.opacity(0.45))
            Spacer(minLength: 0)
        }
        .padding(.vertical, 40)
        .padding(.horizontal, 16)
    }

    // MARK: - Fixed presentation constants

    /// FIXED SMALL card cap — a PLAIN `HStack` of a bounded N (NEVER lazy / scroll).
    /// At `cardWidth` 132 + 12 gap, ~2.5 cards fit a 393pt frame; 4 keeps the
    /// snapshot row bounded while exercising the off-edge overflow visually.
    static let maxCards = 4

    // MARK: - Fixed localized copy (static presentation strings)
    //
    // 「查看更多 ›」moved to `CarouselHeaderView.seeMoreLabel` with the header
    // decomposition (rb-ios-widget-host-scroll).

    static let emptyLabel = "目前沒有影片"
}

// MARK: - Deterministic demo seed (previews + snapshot tests)
//
// A deterministic `WidgetModel` (carousel mode) whose `videos` reuse the SHARED
// `LBVideoItem.demo(...)` fixtures from `CarouselCardView.swift`, so the carousel
// surface's preview / snapshot render a stable, consistent row without a live
// widget. The surface agents share these fixtures for cross-surface consistency.

public extension CarouselView {

    /// A deterministic carousel-mode `WidgetModel`: a small fixed set of demo
    /// videos (a LIVE card + VOD cards, some with a product overlay) so the row
    /// exercises both kind badges + the product overlay in one frame.
    static func demoModel() -> WidgetModel {
        WidgetModel(
            videos: [
                .demo(id: "carousel-1", title: "早春保養 LIVE", live: true, goods: .demo()),
                .demo(id: "carousel-2", title: "週五美妝直播・新品開箱", duration: 754, goods: .demo()),
                .demo(id: "carousel-3", title: "夏日新品開箱", duration: 312,
                      goods: .demo(name: "保濕妝前乳", price: "520")),
                .demo(id: "carousel-4", title: "彩妝師示範教學", duration: 728, goods: nil),
            ],
            mode: .carousel)
    }
}

#if DEBUG
struct CarouselView_Previews: PreviewProvider {
    static var previews: some View {
        let theme = ReferenceUIThemePalette.minimal
        Group {
            // Header (title + subtitle + 查看更多) + a row of mixed-kind cards.
            CarouselView(
                model: CarouselView.demoModel(),
                theme: theme,
                title: "精選影片",
                subtitle: "本週最熱門的直播與影片")
                .previewDisplayName("carousel · header + row")

            // Title only (no subtitle) — header still shows the 查看更多 link.
            CarouselView(
                model: CarouselView.demoModel(),
                theme: theme,
                title: "精選影片")
                .previewDisplayName("carousel · title only")
        }
        .frame(width: 393, height: 340)
        .background(theme.background)
        .previewLayout(.sizeThatFits)
    }
}
#endif
