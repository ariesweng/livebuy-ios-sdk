import SwiftUI

// MARK: - HourglassGlyph — hand-drawn hourglass (design `Icons.hourglass`)
//
// Spec: `reference-ui-rendering/spec.md` (rb-ios-flash-sale-bid)
// Design: `design/shared/icons.jsx` `Icons.hourglass` (24px viewBox, stroke-based, round caps /
// joins). Used by the flash-sale「正在等待結果...」banner (`screens.jsx:LBPBidWaitingBanner`,
// `size 14`, `stroke 2`, white). Three sub-paths, all straight lines / cubic béziers (no arc —
// `icon-authoring.md` rule 1), transcribed to absolute coordinates:
//   frame      M6 3h12  M6 21h12                                   (stroked)
//   left wall  M7.5 3 V5.5 C7.5 7.7 9.3 9.2 12 12 C9.3 14.8 7.5 16.3 7.5 18.5 V21   (stroked)
//   right wall M16.5 3 V5.5 C16.5 7.7 14.7 9.2 12 12 C14.7 14.8 16.5 16.3 16.5 18.5 V21 (stroked)
//   sand       M9.3 18.6 H14.7 C14.7 17.3 13.4 16.1 12 14.8 C10.6 16.1 9.3 17.3 9.3 18.6 Z (filled)
//
// Pure presentation: only `size` / `color` / `lineWidth`. iOS-14-safe (`Path` / `.stroke` /
// `.fill` / `ZStack` / `.frame`).

/// The design's hourglass glyph, hand-drawn to match `Icons.hourglass`.
public struct HourglassGlyph: View {

    /// The glyph box size (pt). The design proportions scale by `size / 24`.
    public let size: CGFloat

    /// The stroke / fill color.
    public let color: Color

    /// Stroke width in the 24-unit design space (design call site passes `stroke={2}`).
    public let lineWidth: CGFloat

    public init(size: CGFloat, color: Color, lineWidth: CGFloat = 2) {
        self.size = size
        self.color = color
        self.lineWidth = lineWidth
    }

    public var body: some View {
        let s = size / 24.0
        ZStack {
            Path { p in
                // Top / bottom bars.
                p.move(to: CGPoint(x: 6 * s, y: 3 * s))
                p.addLine(to: CGPoint(x: 18 * s, y: 3 * s))
                p.move(to: CGPoint(x: 6 * s, y: 21 * s))
                p.addLine(to: CGPoint(x: 18 * s, y: 21 * s))
                // Left wall.
                p.move(to: CGPoint(x: 7.5 * s, y: 3 * s))
                p.addLine(to: CGPoint(x: 7.5 * s, y: 5.5 * s))
                p.addCurve(to: CGPoint(x: 12 * s, y: 12 * s),
                           control1: CGPoint(x: 7.5 * s, y: 7.7 * s),
                           control2: CGPoint(x: 9.3 * s, y: 9.2 * s))
                p.addCurve(to: CGPoint(x: 7.5 * s, y: 18.5 * s),
                           control1: CGPoint(x: 9.3 * s, y: 14.8 * s),
                           control2: CGPoint(x: 7.5 * s, y: 16.3 * s))
                p.addLine(to: CGPoint(x: 7.5 * s, y: 21 * s))
                // Right wall.
                p.move(to: CGPoint(x: 16.5 * s, y: 3 * s))
                p.addLine(to: CGPoint(x: 16.5 * s, y: 5.5 * s))
                p.addCurve(to: CGPoint(x: 12 * s, y: 12 * s),
                           control1: CGPoint(x: 16.5 * s, y: 7.7 * s),
                           control2: CGPoint(x: 14.7 * s, y: 9.2 * s))
                p.addCurve(to: CGPoint(x: 16.5 * s, y: 18.5 * s),
                           control1: CGPoint(x: 14.7 * s, y: 14.8 * s),
                           control2: CGPoint(x: 16.5 * s, y: 16.3 * s))
                p.addLine(to: CGPoint(x: 16.5 * s, y: 21 * s))
            }
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth * s, lineCap: .round, lineJoin: .round))

            // Sand pile (filled, no stroke).
            Path { p in
                p.move(to: CGPoint(x: 9.3 * s, y: 18.6 * s))
                p.addLine(to: CGPoint(x: 14.7 * s, y: 18.6 * s))
                p.addCurve(to: CGPoint(x: 12 * s, y: 14.8 * s),
                           control1: CGPoint(x: 14.7 * s, y: 17.3 * s),
                           control2: CGPoint(x: 13.4 * s, y: 16.1 * s))
                p.addCurve(to: CGPoint(x: 9.3 * s, y: 18.6 * s),
                           control1: CGPoint(x: 10.6 * s, y: 16.1 * s),
                           control2: CGPoint(x: 9.3 * s, y: 17.3 * s))
                p.closeSubpath()
            }
            .fill(color)
        }
        .frame(width: size, height: size)
    }
}
