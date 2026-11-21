import SwiftUI

// MARK: - StorefrontFillGlyph — hand-drawn filled storefront (design `Icons.storefrontFill`)
//
// Spec: `reference-ui-rendering/spec.md` (rb-ios-flash-sale-bid)
// Design: `design/shared/icons.jsx` `Icons.storefrontFill` (24px viewBox, filled, no stroke).
// The bid-won popup's merchant-logo fallback (`moments.jsx:LBBidWonModal`, `size 30`, accent).
// Two filled sub-paths, straight lines + cubic béziers (no arc — `icon-authoring.md` rule 1).
// The awning's relative `c` / smooth `S` segments are transcribed to absolute coordinates
// (each `S` first control point = reflection of the previous second control point):
//   awning M4 3 H20 L22 8
//          C22 9.4 20.9 10.5 19.5 10.5  C18.1 10.5 17 9.4 17 8
//          C17 9.4 15.9 10.5 14.5 10.5  C13.1 10.5 12 9.4 12 8
//          C12 9.4 10.9 10.5 9.5 10.5   C8.1 10.5 7 9.4 7 8
//          C7 9.4 5.9 10.5 4.5 10.5     C3.1 10.5 2 9.4 2 8   L4 3 Z
//   body   M4.5 12 H19.5 V21.5 H14 V16 H10 V21.5 H4.5 Z
//
// Pure presentation: only `size` / `color`. iOS-14-safe (`Path` / `.fill` / `.frame`).

/// The design's filled storefront glyph, hand-drawn to match `Icons.storefrontFill`.
public struct StorefrontFillGlyph: View {

    /// The glyph box size (pt). The design proportions scale by `size / 24`.
    public let size: CGFloat

    /// The fill color.
    public let color: Color

    public init(size: CGFloat, color: Color) {
        self.size = size
        self.color = color
    }

    public var body: some View {
        let s = size / 24.0
        Path { p in
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
            // Awning: flat top, right slope, four scallops right → left, left slope.
            p.move(to: pt(4, 3))
            p.addLine(to: pt(20, 3))
            p.addLine(to: pt(22, 8))
            for x in [22.0, 17.0, 12.0, 7.0] as [CGFloat] {
                p.addCurve(to: pt(x - 2.5, 10.5), control1: pt(x, 9.4), control2: pt(x - 1.1, 10.5))
                p.addCurve(to: pt(x - 5, 8), control1: pt(x - 3.9, 10.5), control2: pt(x - 5, 9.4))
            }
            p.addLine(to: pt(4, 3))
            p.closeSubpath()
            // Body with the door cut-out.
            p.move(to: pt(4.5, 12))
            p.addLine(to: pt(19.5, 12))
            p.addLine(to: pt(19.5, 21.5))
            p.addLine(to: pt(14, 21.5))
            p.addLine(to: pt(14, 16))
            p.addLine(to: pt(10, 16))
            p.addLine(to: pt(10, 21.5))
            p.addLine(to: pt(4.5, 21.5))
            p.closeSubpath()
        }
        .fill(color)
        .frame(width: size, height: size)
    }
}
