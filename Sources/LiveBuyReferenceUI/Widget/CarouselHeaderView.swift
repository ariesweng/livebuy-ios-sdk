import SwiftUI
import LiveBuySDK
import LiveBuyUI

// MARK: - CarouselHeaderView — family-5 carousel sub-surface (LBPCarousel header row)
//
// Spec: `reference-ui-rendering/spec.md` (family-5 widget surfaces — host-scroll
//        embedding 分解子面).
// Design: rb-ios-widget-host-scroll design.md D1 +
//          `design/templates/minimal/widgets.jsx` `LBPCarousel` (lines 208-219).
//
// The HEADER ROW of the carousel surface, extracted as its own public sub-surface
// so a host can keep it FIXED above its own `ScrollView(.horizontal)` — the design
// (`LBPCarousel`, `overflowX: auto`) scrolls only the card strip, never the header.
// `CarouselView` itself recomposes this exact view (single pixel source — the
// header is NEVER drawn twice).
//
// HOST EMBEDDING PATTERN (the header must NOT live inside the host's horizontal
// scroll container, or it scrolls away with the cards):
//
//   VStack(alignment: .leading, spacing: 0) {
//       CarouselHeaderView(theme: theme, title: "精選影片", onSeeMore: { ... })
//       ScrollView(.horizontal, showsIndicators: false) {     // host-owned
//           CarouselRowView(model: model, theme: theme, live: true,
//                           onTapVideo: { ... })
//       }
//   }
//
// 「查看更多 ›」forwards via the host-wired `onSeeMore` closure (nil → inert); this
// layer NEVER navigates / opens the player itself. An empty `title` AND a nil /
// empty `subtitle` render NOTHING (mirrors `LBPCarousel`'s `(title || subtitle) &&
// (...)` gate, widgets.jsx 208).
//
// One-way data flow: this surface reads ONLY its passed-in values; it MUST NOT
// interpret `widgetColor` / `widgetBgcolor` for the native theme (theme comes ONLY
// from `ReferenceUITheme`). iOS-14-safe SwiftUI only — `VStack` / `HStack` /
// `Text` / `Button` are all iOS-13+; NO `ScrollView` / `Lazy*` (the
// `ImageRenderer` blank-render trap).

/// The carousel header row (`LBPCarousel` 208-219): the section `title` (heavy)
/// with an optional `subtitle` (dim) leading, and the「查看更多 ›」accent link
/// trailing.「查看更多」forwards via the host-wired `onSeeMore` (nil → inert).
/// Renders NOTHING when `title` is empty and `subtitle` is nil / empty. A host
/// places it FIXED above its own horizontal `ScrollView { CarouselRowView }`.
public struct CarouselHeaderView: View {

    /// The resolved reference-ui theme. The title uses `theme.text`, the subtitle
    /// a dim variant, and the「查看更多 ›」link `theme.accent`.
    public let theme: ReferenceUITheme

    /// Section title (heavy, leading). Defaults to the design's「精選影片」. An empty
    /// title AND a nil subtitle render NOTHING (mirrors widgets.jsx 208).
    public let title: String

    /// Optional section subtitle (dim, below the title). nil → no subtitle line.
    public let subtitle: String?

    /// 「查看更多 ›」tap → host-wired exit (the host owns the actual list
    /// navigation). nil for demo / snapshot instances — the link is inert. This
    /// layer NEVER navigates / opens the player itself.
    private let onSeeMore: (() -> Void)?

    public init(
        theme: ReferenceUITheme,
        title: String = "精選影片",
        subtitle: String? = nil,
        onSeeMore: (() -> Void)? = nil
    ) {
        self.theme = theme
        self.title = title
        self.subtitle = subtitle
        self.onSeeMore = onSeeMore
    }

    /// Whether the header shows — `title` non-empty OR a `subtitle` exists
    /// (mirrors `LBPCarousel`'s `(title || subtitle) && (...)`, widgets.jsx 208).
    private var showsHeader: Bool {
        !title.isEmpty || (subtitle?.isEmpty == false)
    }

    public var body: some View {
        if showsHeader {
            headerRow
        }
    }

    // MARK: - Header row (title + subtitle + 查看更多 ›)
    //
    // Mirrors `LBPCarousel`'s header block (widgets.jsx 208-219): a baseline-aligned
    // row with the title / subtitle stack leading and the「查看更多 ›」accent link
    // trailing. Pixels moved VERBATIM from the pre-decomposition `CarouselView.header`.

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                // Section title (`fontSize 16 / weight 800`), painted with `theme.text`.
                Text(title)
                    .font(.system(size: 16 * theme.fontScale, weight: .heavy))
                    .foregroundColor(theme.text)
                    .lineLimit(1)
                // Optional subtitle (`fontSize 11`, dim). The resolved `ReferenceUITheme`
                // exposes a flat `text` token (no separate dim color), so the dim variant
                // is approximated as `theme.text.opacity(0.55)`.
                if let subtitle = subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11 * theme.fontScale))
                        .foregroundColor(theme.text.opacity(0.55))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            seeMoreLink
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }

    /// 「查看更多 ›」accent link (widgets.jsx 217). Forwards to the host-wired
    /// `onSeeMore` (nil → inert).
    private var seeMoreLink: some View {
        Button(action: { onSeeMore?() }) {
            Text(Self.seeMoreLabel)
                .font(.system(size: 12 * theme.fontScale, weight: .semibold))
                .foregroundColor(theme.accent)
                .lineLimit(1)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier(LBAccessibilityID.widgetSeeMore)
    }

    // MARK: - Fixed localized copy (static presentation strings)

    static let seeMoreLabel = "查看更多 ›"
}

#if DEBUG
struct CarouselHeaderView_Previews: PreviewProvider {
    static var previews: some View {
        let theme = ReferenceUIThemePalette.minimal
        Group {
            CarouselHeaderView(
                theme: theme,
                title: "精選影片",
                subtitle: "本週最熱門的直播與影片")
                .previewDisplayName("header · title + subtitle")

            CarouselHeaderView(theme: theme, title: "精選影片")
                .previewDisplayName("header · title only")
        }
        .frame(width: 393)
        .background(theme.background)
        .previewLayout(.sizeThatFits)
    }
}
#endif
