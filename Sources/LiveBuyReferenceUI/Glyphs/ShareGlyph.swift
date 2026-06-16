import SwiftUI

// MARK: - ShareGlyph — hand-drawn share icon (design `Icons.share`)
//
// Spec: `reference-ui-rendering/spec.md` (rb-ios-share-icon-design-align)
// Design: `design/shared/icons.jsx` `Icons.share` —
//   <circle cx=6  cy=12 r=2.5/> <circle cx=18 cy=6 r=2.5/> <circle cx=18 cy=18 r=2.5/>
//   <path d="M8 11 l8 -4  M8 13 l8 4"/>   (24px viewBox, strokeWidth 1.8, round cap, fill none)
//
// Every share icon in the reference-ui surface previously drew SF Symbol `square.and.arrow.up`
// (the iOS native box-with-arrow), which diverges from the design's THREE-NODE share glyph.
// SF Symbols has no faithful three-connected-circles share, so — as with the zoom glyph — we
// hand-draw it: three stroked circles connected by two lines, scaled by `size / 24`.
//
// Pure presentation: only `size` / `color`. The share BEHAVIOR (onShare / onShareProduct /
// performShare) is unchanged at every call site.
//
// iOS-14-safe: `Path` / `.stroke(_:style:)` / `.frame` are all iOS-13+.

/// The design's three-node share glyph, hand-drawn to match `Icons.share` (three stroked
/// circles + two connecting lines). Replaces SF Symbol `square.and.arrow.up` everywhere.
public struct ShareGlyph: View {

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
            // Three r=2.5 stroked nodes at (6,12) / (18,6) / (18,18).
            for c in [(6.0, 12.0), (18.0, 6.0), (18.0, 18.0)] {
                let r = 2.5 * s
                p.addEllipse(in: CGRect(x: CGFloat(c.0) * s - r,
                                        y: CGFloat(c.1) * s - r,
                                        width: r * 2, height: r * 2))
            }
            // Two connecting lines: M8 11 l8 -4  and  M8 13 l8 4.
            p.move(to: CGPoint(x: 8 * s, y: 11 * s))
            p.addLine(to: CGPoint(x: 16 * s, y: 7 * s))
            p.move(to: CGPoint(x: 8 * s, y: 13 * s))
            p.addLine(to: CGPoint(x: 16 * s, y: 17 * s))
        }
        .stroke(color, style: StrokeStyle(lineWidth: 1.8 * s, lineCap: .round, lineJoin: .round))
        .frame(width: size, height: size)
    }
}
