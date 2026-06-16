import SwiftUI
import LiveBuySDK
import LiveBuyUI

// MARK: - ReferenceUITheme — reference-ui resolved palette + tokens
//
// Spec: `reference-ui-rendering/spec.md`
//   § "Reference-UI 主題解析合併序 sdkConfig.theme > host options > minimal palette"
// Design: rb-ios-scaffold design.md D-E.
//
// This is the reference-ui (pixel layer) resolved theme. It is INDEPENDENT of
// core's `widget_color` / `widget_bgcolor` (web-embed colors, raw passthrough) —
// those two are a SEPARATE concern carried verbatim by core; reference-ui MUST
// NOT interpret them here (D-E).
//
// The minimal-palette fallback values are sourced from the design reference
// `design/templates/minimal/*.jsx` (see `ReferenceUIThemePalette.minimal`).

/// Resolved reference-ui theme: the palette a reference-ui SwiftUI view paints
/// with, plus a couple of layout tokens. Produced by `ReferenceUIThemeResolver`.
public struct ReferenceUITheme: Equatable {

    /// Brand / action accent (e.g. the LIVE badge, primary CTA). Resolved from
    /// `sdkConfig.theme.primaryColor` > `LBUIOptions.theme.primaryColor` >
    /// minimal palette accent.
    public let accent: Color

    /// Page / surface background.
    public let background: Color

    /// Primary foreground text color.
    public let text: Color

    /// Card / surface corner radius token (pt).
    public let cornerRadius: CGFloat

    /// Global font scale (1.0 = unscaled). Resolved from
    /// `sdkConfig.theme.fontScale` > `LBUIOptions.theme.fontScale` > 1.0.
    public let fontScale: CGFloat

    public init(accent: Color,
                background: Color,
                text: Color,
                cornerRadius: CGFloat,
                fontScale: CGFloat) {
        self.accent = accent
        self.background = background
        self.text = text
        self.cornerRadius = cornerRadius
        self.fontScale = fontScale
    }
}

// MARK: - Minimal palette fallback (design source)

/// The fallback palette. Color values are lifted from the design reference
/// `design/templates/minimal/*.jsx`:
///   - accent      `#F03246`  (LIVE badge / brand action red — `live-chrome.jsx`)
///   - text        `#15131A`  (primary text color — `live-chrome.jsx`)
///   - background  `#FFFFFF`  (on-accent / surface white — `live-chrome.jsx`)
///   - cornerRadius `12`      (most common card radius — `widgets.jsx`)
public enum ReferenceUIThemePalette {

    /// Accent hex from the minimal design (`#F03246`).
    public static let minimalAccentHex = "#F03246"
    /// Primary text hex from the minimal design (`#15131A`).
    public static let minimalTextHex = "#15131A"
    /// Surface / background hex from the minimal design (`#FFFFFF`).
    public static let minimalBackgroundHex = "#FFFFFF"
    /// Default card corner radius from the minimal design (`12pt`).
    public static let minimalCornerRadius: CGFloat = 12
    /// Unscaled font scale.
    public static let minimalFontScale: CGFloat = 1.0

    /// The fully-resolved minimal fallback theme (lowest-priority source).
    public static let minimal = ReferenceUITheme(
        accent: Color(hex: minimalAccentHex) ?? .red,
        background: Color(hex: minimalBackgroundHex) ?? .white,
        text: Color(hex: minimalTextHex) ?? .black,
        cornerRadius: minimalCornerRadius,
        fontScale: minimalFontScale
    )
}

// MARK: - Hex parsing (iOS-14-safe)

extension Color {
    /// Parse a `#RRGGBB` / `RRGGBB` (or `#RGB`) hex string into a SwiftUI Color.
    /// Returns nil on malformed input so the resolver can fall through to the
    /// next source. iOS-14-safe (uses the RGB initializer, not iOS-17 mixers).
    init?(hex rawValue: String) {
        var s = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }

        // Expand 3-digit shorthand (#RGB → #RRGGBB).
        if s.count == 3 {
            s = s.map { "\($0)\($0)" }.joined()
        }
        guard s.count == 6 else { return nil }

        var rgb: UInt64 = 0
        guard Scanner(string: s).scanHexInt64(&rgb) else { return nil }

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
    }
}
