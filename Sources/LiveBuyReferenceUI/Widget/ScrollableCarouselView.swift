import SwiftUI
import LiveBuySDK
import LiveBuyUI

// MARK: - ScrollableCarouselView — family-5 wrapper tier (drop-in scrolling carousel)
//
// Spec: `reference-ui-rendering/spec.md` (wrapper 子層 — 零新像素、drop-in 可捲 widget).
// Design: rb-ios-widget-scroll-wrappers design.md D1 +
//          `design/templates/minimal/widgets.jsx` `LBPCarousel` (`overflowX: auto`).
//
// The DROP-IN scrolling carousel a host actually uses (user decision 2026-06-10:
// 「要讓 host app 可以簡單的使用 SDK」). Place it, wire two closures, done:
//
//   ScrollableCarouselView(
//       model: widgetModel,                       // from widgetTemplate
//       theme: theme,
//       onSeeMore: { /* host list navigation */ },
//       onTapVideo: { item in /* host opens player for item.id */ })
//
// It owns the composition recipe the host would otherwise need to know:
// `CarouselHeaderView` stays FIXED above a wrapper-owned horizontal `ScrollView`
// around `CarouselRowView` rendering ALL `model.videos` (the design's
// `overflowX: auto` strip — the header must never live inside the scroll
// container or it scrolls away with the cards).
//
// WRAPPER TIER RULES (the narrowed no-ScrollView invariant):
//   • This tier MAY own `ScrollView` — it is NEVER snapshot-rendered via
//     `ImageRenderer` (scroll containers render BLANK there — the family-3
//     lesson; a wrapper snapshot would be a stable blank false-green, so
//     wrappers are covered by BEHAVIOR tests instead and MUST NOT get a
//     baseline).
//   • ZERO NEW PIXELS: the body composes the existing snapshot-baselined
//     sub-surfaces (`CarouselHeaderView` / `CarouselRowView`) plus layout
//     modifiers ONLY — no new Text / Image / shape / fill. Visual correctness
//     stays pinned by the sub-surfaces' own baselines.
//   • Interactions pass through UNTOUCHED as host-wired closures (nil → inert,
//     demo-constructible). `onSeeMore` goes STRAIGHT to the host (no
//     `videos.first` proxy — this is the host's real see-all entry point).
//     This layer NEVER calls core `simulate*` / template internals, never
//     paginates, never opens the player.
//   • MUST NOT be composed into `WidgetOverlayView` (snapshot-composed
//     container — its baseline would go blank).
//
// ESCAPE HATCH: a host needing a custom header placement / scroll behavior
// composes the sub-surfaces directly (the `rb-ios-widget-host-scroll` recipe):
// `CarouselHeaderView` fixed above its OWN `ScrollView(.horizontal) {
// CarouselRowView }`.
//
// iOS-14-safe SwiftUI only (`ScrollView(showsIndicators:)` is iOS-13+).

/// The drop-in scrolling carousel (wrapper tier — zero new pixels): the
/// `CarouselHeaderView` FIXED above a wrapper-owned
/// `ScrollView(.horizontal, showsIndicators: false)` around a `CarouselRowView`
/// rendering ALL `model.videos`. Host wires `onSeeMore` / `onTapVideo`; nil
/// closures render an inert demo form. Never snapshot-baselined — behavior-tested.
public struct ScrollableCarouselView: View {

    /// The read-only widget content snapshot, passed through to the sub-surfaces.
    @ObservedObject public var model: WidgetModel

    /// The resolved reference-ui theme, passed through to the sub-surfaces.
    public let theme: ReferenceUITheme

    /// Section title, forwarded to `CarouselHeaderView`. Defaults to「精選影片」.
    public let title: String

    /// Optional section subtitle, forwarded to `CarouselHeaderView`.
    public let subtitle: String?

    /// Card width (pt), forwarded to `CarouselRowView`. Defaults to the design's 132.
    public let cardWidth: CGFloat

    /// Runtime media gate, forwarded to `CarouselRowView` (`true` → cards render
    /// `preview → cover → placeholder`).
    public let live: Bool

    /// 「查看更多 ›」→ host-wired exit, passed through UNTOUCHED to
    /// `CarouselHeaderView` (the host's real see-all / list-navigation entry —
    /// no `videos.first` proxy here). nil → inert.
    private let onSeeMore: (() -> Void)?

    /// Card tap → host-wired exit, passed through UNTOUCHED to `CarouselRowView`
    /// (→ host → core open player for `item.id`). nil → inert.
    private let onTapVideo: ((LBVideoItem) -> Void)?

    public init(
        model: WidgetModel,
        theme: ReferenceUITheme,
        title: String = "精選影片",
        subtitle: String? = nil,
        cardWidth: CGFloat = 132,
        live: Bool = false,
        onSeeMore: (() -> Void)? = nil,
        onTapVideo: ((LBVideoItem) -> Void)? = nil
    ) {
        self.model = model
        self.theme = theme
        self.title = title
        self.subtitle = subtitle
        self.cardWidth = cardWidth
        self.live = live
        self.onSeeMore = onSeeMore
        self.onTapVideo = onTapVideo
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // FIXED header — outside the scroll container by construction.
            CarouselHeaderView(
                theme: theme,
                title: title,
                subtitle: subtitle,
                onSeeMore: onSeeMore)

            // Wrapper-owned horizontal scroll around the FULL strip
            // (`maxCards: nil` → ALL videos; intrinsic width via the row's
            // `.fixedSize(horizontal:)` is exactly what the ScrollView measures).
            ScrollView(.horizontal, showsIndicators: false) {
                CarouselRowView(
                    model: model,
                    theme: theme,
                    cardWidth: cardWidth,
                    live: live,
                    onTapVideo: onTapVideo)
            }
        }
    }
}

#if DEBUG
struct ScrollableCarouselView_Previews: PreviewProvider {
    static var previews: some View {
        let theme = ReferenceUIThemePalette.minimal
        ScrollableCarouselView(
            model: CarouselView.demoModel(),
            theme: theme,
            subtitle: "本週最熱門的直播與影片")
            .frame(width: 393, height: 340)
            .background(theme.background)
            .previewDisplayName("scrollable carousel · drop-in")
            .previewLayout(.sizeThatFits)
    }
}
#endif
