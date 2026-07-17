import SwiftUI

// MARK: - ShopBagGlyph — hand-drawn outline shopping-bag glyph (design `Icons.shopBag`)
//
// Spec: `reference-ui-rendering/spec.md` (rb-ios-bag-cart-stroke-align)
// Design: `design/shared/icons.jsx` `Icons.shopBag` (24px viewBox, fill none, stroke):
//   body   M6 8h12l-1 12a2 2 0 01-2 2H9a2 2 0 01-2-2L6 8z   (bag body, rounded bottom)
//   handle M9 8V6a3 3 0 016 0v2                              (∩ handle, open bottom)
//   mouth  M9 12h6                                           (horizontal bag-mouth line)
//
// iOS parity of Android `IconGlyphs.D_SHOP_BAG_*` / RN `ShopBagGlyph` (View-drawn). The
// product-list 「查看購物車」 footer CTA previously drew the FILLED SF Symbol `bag.fill`,
// diverging from the design's STROKED shop-bag. SF Symbols has no shop-bag-with-mouth-line,
// so — exactly as with `ShareGlyph` / `PersonEditGlyph` — we hand-draw it, scaled by
// `size / 24`. The FULL handle ring + horizontal mouth line are precisely what distinguish
// `shopBag` from the simple `bag`.
//
// Pure presentation: only `size` / `color`. The cart BEHAVIOR (onOpenCart) is unchanged.
// iOS-14-safe: `Path` / `.stroke(_:style:)` / `.frame` are all iOS-13+.

/// The design's stroked shop-bag glyph, hand-drawn to match `Icons.shopBag` (bag body + ∩
/// handle + bag-mouth line). Replaces the filled SF Symbol `bag.fill` at the product-list
/// 「查看購物車」 footer CTA.
public struct ShopBagGlyph: View {

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
            // Bag body — M6 8 h12 l-1 12 a2 2 0 01-2 2 H9 a2 2 0 01-2-2 L6 8 z
            // (`a2 2` bottom corners approximated by quad curves through the sharp corner).
            p.move(to: CGPoint(x: 6 * s, y: 8 * s))
            p.addLine(to: CGPoint(x: 18 * s, y: 8 * s))          // h12
            p.addLine(to: CGPoint(x: 17 * s, y: 20 * s))         // l-1 12 (right side, slight taper)
            p.addQuadCurve(to: CGPoint(x: 15 * s, y: 22 * s),    // a2 2 (bottom-right round)
                           control: CGPoint(x: 17 * s, y: 22 * s))
            p.addLine(to: CGPoint(x: 9 * s, y: 22 * s))          // H9
            p.addQuadCurve(to: CGPoint(x: 7 * s, y: 20 * s),     // a2 2 (bottom-left round)
                           control: CGPoint(x: 7 * s, y: 22 * s))
            p.addLine(to: CGPoint(x: 6 * s, y: 8 * s))           // L6 8
            p.closeSubpath()                                     // z

            // Handle ∩ — M9 8 V6 a3 3 0 016 0 v2 (top arch via two quad curves, open bottom).
            p.move(to: CGPoint(x: 9 * s, y: 8 * s))
            p.addLine(to: CGPoint(x: 9 * s, y: 6 * s))           // V6
            p.addQuadCurve(to: CGPoint(x: 12 * s, y: 3 * s),     // up-over to apex
                           control: CGPoint(x: 9 * s, y: 3 * s))
            p.addQuadCurve(to: CGPoint(x: 15 * s, y: 6 * s),     // apex down to right side
                           control: CGPoint(x: 15 * s, y: 3 * s))
            p.addLine(to: CGPoint(x: 15 * s, y: 8 * s))          // v2

            // Mouth line — M9 12 h6 (the shopBag-distinguishing horizontal hairline).
            p.move(to: CGPoint(x: 9 * s, y: 12 * s))
            p.addLine(to: CGPoint(x: 15 * s, y: 12 * s))
        }
        .stroke(color, style: StrokeStyle(lineWidth: 1.8 * s, lineCap: .round, lineJoin: .round))
        .frame(width: size, height: size)
    }
}
