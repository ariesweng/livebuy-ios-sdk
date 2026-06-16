import SwiftUI
import LiveBuySDK
import LiveBuyUI

// MARK: - CarouselRowView — family-5 carousel sub-surface (LBPCarousel card strip)
//
// Spec: `reference-ui-rendering/spec.md` (family-5 widget surfaces — host-scroll
//        embedding 分解子面).
// Design: rb-ios-widget-host-scroll design.md D1 +
//          `design/templates/minimal/widgets.jsx` `LBPCarousel` (lines 220-245).
//
// The CARD STRIP of the carousel surface, extracted as its own public sub-surface
// so a host can wrap it in its OWN `ScrollView(.horizontal)` and actually scroll
// through ALL videos (the design's `overflowX: auto`). `.fixedSize(horizontal:)`
// gives the strip its intrinsic width — exactly what a host horizontal
// `ScrollView` needs to measure its content. `CarouselView` itself recomposes this
// exact view inside its windowed/clipped default rendering (single pixel source —
// the strip is NEVER drawn twice).
//
// HOST EMBEDDING PATTERN (the header stays FIXED outside the host's horizontal
// scroll container — see `CarouselHeaderView`):
//
//   VStack(alignment: .leading, spacing: 0) {
//       CarouselHeaderView(theme: theme, title: "精選影片", onSeeMore: { ... })
//       ScrollView(.horizontal, showsIndicators: false) {     // host-owned
//           CarouselRowView(model: model, theme: theme, live: true,
//                           onTapVideo: { ... })
//       }
//   }
//
// `maxCards` is a CALLER parameter, not a hard-coded cap: `nil` (the default —
// host embedding) renders ALL `model.videos`; `CarouselView` passes its fixed
// small windowed set (4) so the default carousel rendering stays byte-identical.
// ⚠️ The strip's intrinsic width grows LINEARLY with the video count and a plain
// `HStack` has no virtualization — dozens of lightweight cards are fine on
// device, but a genuinely large list belongs in the grid surface.
//
// CARD REUSE: every card is the SHARED `CarouselCardView` primitive — this
// sub-surface MUST NOT re-draw a card from scratch; it only lays a row of them.
//
// One-way data flow: this sub-surface reads ONLY its passed-in `model` (the
// read-only `videos` mirror, observed so a live template update re-renders); it
// never reaches back into `DefaultWidgetTemplate`, holds NO second copy of state,
// and MUST NOT interpret `widgetColor` / `widgetBgcolor` for the native theme
// (theme comes ONLY from `ReferenceUITheme`). Card tap forwards via the
// host-wired `onTapVideo` exit; this layer NEVER scrolls / paginates / opens the
// player itself. An empty list renders NOTHING (the carousel empty-state line
// stays with `CarouselView`).
//
// iOS-14-safe SwiftUI only. `HStack` / `ForEach` / `.fixedSize` / `.padding` are
// all iOS-13+. NO `ScrollView` / `Lazy*` in rendered content (the `ImageRenderer`
// blank-render trap — the scroll container is the HOST's, never this layer's).

/// The carousel card strip (`LBPCarousel` 220-245): a plain `HStack` of shared
/// `CarouselCardView`s with the design's 12pt gap, `.fixedSize(horizontal:)` →
/// intrinsic strip width (embeddable in a host-owned horizontal `ScrollView`).
/// `maxCards == nil` (default) renders ALL `model.videos`; `CarouselView` passes
/// its fixed windowed cap for the unchanged default rendering. Card tap forwards
/// via the host-wired `onTapVideo`; renders NOTHING for an empty list.
public struct CarouselRowView: View {

    /// The read-only widget content snapshot. This sub-surface binds ONLY `videos`
    /// (the strip source). Observed so a live template update re-renders.
    @ObservedObject public var model: WidgetModel

    /// The resolved reference-ui theme, forwarded to every `CarouselCardView`.
    public let theme: ReferenceUITheme

    /// Card width (pt) forwarded to every `CarouselCardView`. Defaults to the
    /// design's `132`; the 9:16 height is derived by the card.
    public let cardWidth: CGFloat

    /// Runtime media gate forwarded to every `CarouselCardView`. `false` (default —
    /// demo / snapshot) → placeholder thumbnails (baselines unchanged); `true` (host
    /// runtime) → cards render `preview → cover → placeholder`.
    public let live: Bool

    /// Leading inset of the strip (pt). Defaults to the design's 16pt page margin.
    public let leadingPadding: CGFloat

    /// Trailing inset of the strip (pt). Defaults to the design's 16pt page margin
    /// (a host-scrolled strip ends with a margin); `CarouselView`'s windowed
    /// rendering passes 0 (the window clips the trailing edge anyway).
    public let trailingPadding: CGFloat

    /// Strip cap. `nil` (default — host embedding) → ALL `model.videos`; non-nil →
    /// the first `maxCards` (CarouselView's fixed windowed set). A caller
    /// parameter, never a hard-coded cap.
    public let maxCards: Int?

    /// Card tap → host-wired exit (`onTapVideo(item)` → host → core open player for
    /// `item.id`). nil for demo / snapshot instances — the strip is inert. This
    /// layer NEVER opens the player / scrolls / paginates itself.
    private let onTapVideo: ((LBVideoItem) -> Void)?

    public init(
        model: WidgetModel,
        theme: ReferenceUITheme,
        cardWidth: CGFloat = 132,
        live: Bool = false,
        leadingPadding: CGFloat = 16,
        trailingPadding: CGFloat = 16,
        maxCards: Int? = nil,
        onTapVideo: ((LBVideoItem) -> Void)? = nil
    ) {
        self.model = model
        self.theme = theme
        self.cardWidth = cardWidth
        self.live = live
        self.leadingPadding = leadingPadding
        self.trailingPadding = trailingPadding
        self.maxCards = maxCards
        self.onTapVideo = onTapVideo
    }

    /// The rendered set: ALL videos when `maxCards == nil` (host embedding), else
    /// the first `maxCards` (CarouselView's unchanged windowed rendering).
    private var cards: [LBVideoItem] {
        if let maxCards = maxCards {
            return Array(model.videos.prefix(maxCards))
        }
        return model.videos
    }

    public var body: some View {
        if !cards.isEmpty {
            strip
        }
    }

    // MARK: - Card strip (PLAIN HStack of shared CarouselCardViews)
    //
    // Mirrors `LBPCarousel`'s scroller content (widgets.jsx 220-245): a horizontal
    // row of `LBPCarouselCard`s with a 12pt gap. Pixels moved VERBATIM from the
    // pre-decomposition `CarouselView.cardWindow` overlay content — plain `HStack`
    // + `.fixedSize(horizontal:)` (intrinsic strip width), NEVER a `ScrollView` /
    // `Lazy*` (the `ImageRenderer` blank-render trap; the scroll container is the
    // host's).

    private var strip: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(cards, id: \.id) { item in
                CarouselCardView(
                    item: item,
                    theme: theme,
                    width: cardWidth,
                    live: live,
                    onTap: { onTapVideo?(item) })
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.leading, leadingPadding)
        .padding(.trailing, trailingPadding)
    }
}

#if DEBUG
struct CarouselRowView_Previews: PreviewProvider {
    static var previews: some View {
        let theme = ReferenceUIThemePalette.minimal
        Group {
            // All videos (maxCards nil) — the host-embedding strip.
            CarouselRowView(
                model: CarouselView.demoModel(),
                theme: theme)
                .previewDisplayName("row · all videos")

            // CarouselView's windowed set (maxCards 4, trailing 0).
            CarouselRowView(
                model: CarouselView.demoModel(),
                theme: theme,
                trailingPadding: 0,
                maxCards: 4)
                .previewDisplayName("row · windowed 4")
        }
        .frame(height: 300)
        .background(theme.background)
        .previewLayout(.sizeThatFits)
    }
}
#endif
