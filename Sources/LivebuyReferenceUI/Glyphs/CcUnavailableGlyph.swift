import SwiftUI

// MARK: - CcUnavailableGlyph — fixed-grey "no caption source" glyph (design `ccUnavailable`)
//
// Spec: `reference-ui-rendering/spec.md` (`rb-ios-cc-icon-availability-redesign`)
// Design: `design/shared/icons.jsx` `ccUnavailable` (design R42, 2026-09-10) — a 24×22 viewBox
// FILL path, fixed color `#A0A0A0` (not overridable by `theme.accent` or any caller-supplied
// color — the design's own call sites never pass a `color` prop for this icon, unlike `ccOn`/
// `ccOff`). Drawn when `CcIconState == .unavailable` (no caption source at all), replacing the
// prior "omit the pill entirely" behavior.
//
// Non-square viewBox+viewport (24×22 path inside an 18×16 rendered box — the design's own call
// sites hardcode `<Icons.ccUnavailable width={18} height={16} />`, NOT the shared `<Icon>`
// wrapper's default square `size×size` box every other rail/bottom-bar glyph uses). Rather than
// a second magic-number `height` parameter that could drift from the design's literal 18:16
// ratio at a call site, `size` here is interpreted as the box WIDTH and height is DERIVED
// (`size * 16 / 18`) — every existing call site already passes a single `pillGlyphSize` /
// `iconGlyphSize` constant (`18`) to the OTHER glyphs sharing that slot, so
// `CcUnavailableGlyph(size: Self.pillGlyphSize)` reproduces the exact 18×16 box without a new
// parameter. The path is then aspect-fit (uniform scale, centered) inside that derived
// width×height box — the same technique `MegaphoneGlyph` uses for ITS own non-square viewBox
// (letterboxed within a square there; here the box itself is non-square, so only one axis ends
// up with margin — see `path(size:)`).
//
// Every segment in the design's `d` string is a cubic bezier (`C`) or a straight line — no arc,
// no smooth-cubic shorthand — transcribed via the same standalone Python SVG-path parser used
// for `CcGlyph`'s `ccOn`/`ccOff`, with the resulting bounding box (x∈[0,24], y∈[1.375,20.625])
// verified to land inside the declared 24×22 viewBox before transcription.
//
// Pure presentation: only `size`. iOS-14-safe (`Path` / `.fill` / `.frame`).

/// The design's fixed-grey "no caption source" glyph, drawn when `CcIconState == .unavailable`.
/// Deliberately NOT themeable (no `color` init param) — the design never tints this one icon,
/// unlike every other glyph in this module.
public struct CcUnavailableGlyph: View {

    /// The glyph box WIDTH (pt) — height is derived (`size * 16 / 18`), reproducing the design's
    /// literal non-square 18×16 box. See the file header for why this is a single parameter
    /// rather than an explicit `width`/`height` pair.
    public let size: CGFloat

    public init(size: CGFloat) {
        self.size = size
    }

    /// The fixed `#A0A0A0` fill — not derived from `theme.accent` or any caller input by design.
    static let color = Color(.sRGB, red: 160 / 255, green: 160 / 255, blue: 160 / 255, opacity: 1)

    public var body: some View {
        let box = Self.boxSize(forWidth: size)
        Self.path(size: size)
            .fill(Self.color)
            .frame(width: box.width, height: box.height)
    }

    /// PURE FUNCTION: the derived non-square box (`size` wide, `size * 16/18` tall) — the
    /// design's literal 18×16 ratio, reproduced from a single `size` input. Extracted for direct
    /// unit-test coverage (unit-test-discipline) without mounting SwiftUI.
    static func boxSize(forWidth size: CGFloat) -> CGSize {
        CGSize(width: size, height: size * 16.0 / 18.0)
    }

    /// Builds the aspect-fit `Path` for a given box width — the 24×22 viewBox path is uniformly
    /// scaled (never stretched non-uniformly) to fit inside the derived `boxSize(forWidth:)` box
    /// and centered, matching the browser SVG default `preserveAspectRatio="xMidYMid meet"`.
    static func path(size: CGFloat) -> Path {
        let box = boxSize(forWidth: size)
        let scale = min(box.width / 24.0, box.height / 22.0)
        let dx = (box.width - 24 * scale) / 2
        let dy = (box.height - 22 * scale) / 2
        let pt: (CGFloat, CGFloat) -> CGPoint = { x, y in CGPoint(x: x * scale + dx, y: y * scale + dy) }

        return Path { p in
            // Outer rounded-rect badge outline (fill, not stroke — the "outline" look is a
            // carved inner-rect hole via nonzero winding, same technique as `CcGlyph`'s `ccOff`).
            p.move(to: pt(21.3333, 1.375))
            p.addLine(to: pt(2.66667, 1.375))
            p.addCurve(to: pt(0, 4.125), control1: pt(1.19375, 1.375), control2: pt(0, 2.60605))
            p.addLine(to: pt(0, 17.875))
            p.addCurve(to: pt(2.66667, 20.625), control1: pt(0, 19.3939), control2: pt(1.19375, 20.625))
            p.addLine(to: pt(21.3333, 20.625))
            p.addCurve(to: pt(24, 17.875), control1: pt(22.8063, 20.625), control2: pt(24, 19.3939))
            p.addLine(to: pt(24, 4.125))
            p.addCurve(to: pt(21.3333, 1.375), control1: pt(24, 2.60605), control2: pt(22.8042, 1.375))
            p.closeSubpath()

            // Inner carved rounded-rect hole.
            p.move(to: pt(22, 17.875))
            p.addCurve(to: pt(21.3333, 18.5625), control1: pt(22, 18.2541), control2: pt(21.7009, 18.5625))
            p.addLine(to: pt(2.66667, 18.5625))
            p.addCurve(to: pt(2, 17.875), control1: pt(2.29908, 18.5625), control2: pt(2, 18.2541))
            p.addLine(to: pt(2, 4.125))
            p.addCurve(to: pt(2.66667, 3.4375), control1: pt(2, 3.74593), control2: pt(2.29908, 3.4375))
            p.addLine(to: pt(21.3333, 3.4375))
            p.addCurve(to: pt(22, 4.125), control1: pt(21.7009, 3.4375), control2: pt(22, 3.74593))
            p.addLine(to: pt(22, 17.875))
            p.closeSubpath()

            // Left "C" hole.
            p.move(to: pt(9.85417, 9.54336))
            p.addCurve(to: pt(11.2683, 9.54336), control1: pt(10.2448, 9.94619), control2: pt(10.8775, 9.94619))
            p.addCurve(to: pt(11.2683, 8.085), control1: pt(11.659, 9.14053), control2: pt(11.659, 8.48805))
            p.addCurve(to: pt(5.61417, 8.085), control1: pt(9.70833, 6.47625), control2: pt(7.17208, 6.47625))
            p.addCurve(to: pt(4.4375, 11), control1: pt(4.85417, 8.86016), control2: pt(4.4375, 9.9))
            p.addCurve(to: pt(5.60917, 13.9167), control1: pt(4.4375, 12.1), control2: pt(4.81667, 13.1377))
            p.addCurve(to: pt(8.43708, 15.1233), control1: pt(6.38917, 14.7211), control2: pt(7.4125, 15.1233))
            p.addCurve(to: pt(11.265, 13.9167), control1: pt(9.46167, 15.1233), control2: pt(10.4854, 14.7211))
            p.addCurve(to: pt(11.265, 12.4584), control1: pt(11.6556, 13.5139), control2: pt(11.6556, 12.8614))
            p.addCurve(to: pt(9.85083, 12.4584), control1: pt(10.8744, 12.0555), control2: pt(10.2417, 12.0555))
            p.addCurve(to: pt(7.02292, 12.4584), control1: pt(9.07208, 13.2627), control2: pt(7.80125, 13.2627))
            p.addCurve(to: pt(6.4375, 11), control1: pt(6.64583, 12.0699), control2: pt(6.4375, 11.55))
            p.addCurve(to: pt(7.02333, 9.54164), control1: pt(6.4375, 10.45), control2: pt(6.64583, 9.93094))
            p.addCurve(to: pt(9.85417, 9.54336), control1: pt(7.80417, 8.73555), control2: pt(9.075, 8.73555))
            p.closeSubpath()

            // Right "C" hole.
            p.move(to: pt(17.8542, 9.54336))
            p.addCurve(to: pt(19.2683, 9.54336), control1: pt(18.2448, 9.94619), control2: pt(18.8775, 9.94619))
            p.addCurve(to: pt(19.2683, 8.085), control1: pt(19.659, 9.14053), control2: pt(19.659, 8.48805))
            p.addCurve(to: pt(13.6142, 8.085), control1: pt(17.7083, 6.47625), control2: pt(15.1721, 6.47625))
            p.addCurve(to: pt(12.4375, 11), control1: pt(12.8542, 8.86016), control2: pt(12.4375, 9.9))
            p.addCurve(to: pt(13.6092, 13.9167), control1: pt(12.4375, 12.1), control2: pt(12.8167, 13.1377))
            p.addCurve(to: pt(16.4371, 15.1233), control1: pt(14.3892, 14.7211), control2: pt(15.4125, 15.1233))
            p.addCurve(to: pt(19.265, 13.9167), control1: pt(17.4617, 15.1233), control2: pt(18.4854, 14.7211))
            p.addCurve(to: pt(19.265, 12.4584), control1: pt(19.6556, 13.5139), control2: pt(19.6556, 12.8614))
            p.addCurve(to: pt(17.8508, 12.4584), control1: pt(18.8744, 12.0555), control2: pt(18.2417, 12.0555))
            p.addCurve(to: pt(15.0229, 12.4584), control1: pt(17.0721, 13.2627), control2: pt(15.8012, 13.2627))
            p.addCurve(to: pt(14.4375, 11), control1: pt(14.6458, 12.0699), control2: pt(14.4375, 11.55))
            p.addCurve(to: pt(15.0233, 9.54164), control1: pt(14.4375, 10.45), control2: pt(14.6458, 9.93094))
            p.addCurve(to: pt(17.8542, 9.54336), control1: pt(15.8042, 8.73555), control2: pt(17.075, 8.73555))
            p.closeSubpath()
        }
    }
}
