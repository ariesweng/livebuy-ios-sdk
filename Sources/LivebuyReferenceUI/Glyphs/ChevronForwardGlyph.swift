import SwiftUI

// MARK: - ChevronForwardGlyph — hand-drawn skip / fast-forward chevrons (design skip glyph)
//
// Spec: `reference-ui-rendering/spec.md` (rb-ios-fill-stroke-align)
// Design: `design/shared/icons.jsx` skip path + `design/templates/minimal/moments.jsx`
//   `LBPSkipIntroButton` — <svg fill="none" stroke="#fff" strokeWidth="2.2"
//   strokeLinecap/Linejoin="round"><path d="M5 4l8 8-8 8M14 4l6 8-6 8"/></svg>
//   = two OPEN `>` chevrons (NOT filled triangles).
//
// The「略過介紹」skip button previously drew SF Symbol `forward.fill` (two SOLID filled
// triangles ▶▶), which contradicts the explicit `fill="none"` stroke spec and breaks the
// stroke-based icon set. SF `forward` (non-fill) is still a triangle, not an open chevron, so —
// as with ShareGlyph / ShopBagGlyph — we hand-draw the open double-chevron, scaled by `size / 24`.
// Geometry mirrors Android `moments/MomentGlyphs.kt` `ChevronForwardGlyph`.
//
// Pure presentation: only `size` / `color`. The skip BEHAVIOR (`onSkip`) is unchanged.
//
// iOS-14-safe: `Path` / `.stroke(_:style:)` / `.frame` are all iOS-13+.

/// The design's open double-chevron skip glyph, hand-drawn to match the `M5 4l8 8-8 8M14 4l6 8-6 8`
/// path (two stroked `>` chevrons). Replaces SF Symbol `forward.fill` at the skip-intro button.
public struct ChevronForwardGlyph: View {

    /// The glyph box size (pt). The design proportions scale by `size / 24`.
    public let size: CGFloat

    /// The stroke color.
    public let color: Color

    public init(size: CGFloat, color: Color) {
        self.size = size
        self.color = color
    }

    public var body: some View {
        let s = size / 24.0
        Path { p in
            // Chevron 1: M5 4 l8 8 -8 8  → (5,4) → (13,12) → (5,20)
            p.move(to: CGPoint(x: 5 * s, y: 4 * s))
            p.addLine(to: CGPoint(x: 13 * s, y: 12 * s))
            p.addLine(to: CGPoint(x: 5 * s, y: 20 * s))
            // Chevron 2: M14 4 l6 8 -6 8  → (14,4) → (20,12) → (14,20)
            p.move(to: CGPoint(x: 14 * s, y: 4 * s))
            p.addLine(to: CGPoint(x: 20 * s, y: 12 * s))
            p.addLine(to: CGPoint(x: 14 * s, y: 20 * s))
        }
        .stroke(color, style: StrokeStyle(lineWidth: 2.2 * s, lineCap: .round, lineJoin: .round))
        .frame(width: size, height: size)
    }
}
