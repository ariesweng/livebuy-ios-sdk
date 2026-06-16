import SwiftUI

// MARK: - PersonEditGlyph — hand-drawn person-edit (head + pencil badge) nickname icon
//
// Spec: `reference-ui-rendering/spec.md` (rb-align-nickname-icon-person-edit)
// Design: `design/templates/minimal/live-chrome.jsx` `LBLiveBottomBar` 設定暱稱 button (≈224) —
//   <circle cx=10 cy=8 r=3.2/>             head
//   <path d="M3 21c0-4 3-6 7-6"/>          shoulders
//   <path d="M14 18l5-5 2 2-5 5h-2v-2z"/>  pencil badge (bottom-right)
//   (24px viewBox, strokeWidth 1.8, round cap/join, fill none, stroke white)
//
// The LIVE bottom bar's nickname button previously drew the SF Symbol `person.fill` (a single
// head), which diverges from the design's person-EDIT composite (head + a pencil badge). As with
// `ShareGlyph` / the zoom glyph, we hand-draw it so all four platforms render the SAME composite.
//
// Pure presentation: only `size` / `color`. The nickname BEHAVIOR (`onNickname`) is unchanged.
//
// iOS-14-safe: `Path` / `.stroke(_:style:)` / `.frame` are all iOS-13+.

/// The design's person-edit glyph (head circle + shoulders curve + pencil badge), hand-drawn to
/// match the `LBLiveBottomBar` 設定暱稱 button. Replaces SF Symbol `person.fill` in the LIVE bar.
public struct PersonEditGlyph: View {

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
            // Head: stroked circle cx=10 cy=8 r=3.2.
            let r = 3.2 * s
            p.addEllipse(in: CGRect(x: 10 * s - r, y: 8 * s - r, width: r * 2, height: r * 2))
            // Shoulders: M3 21 c0 -4 3 -6 7 -6  → cubic (3,21) → ctrl (3,17),(6,15) → (10,15).
            p.move(to: CGPoint(x: 3 * s, y: 21 * s))
            p.addCurve(to: CGPoint(x: 10 * s, y: 15 * s),
                       control1: CGPoint(x: 3 * s, y: 17 * s),
                       control2: CGPoint(x: 6 * s, y: 15 * s))
            // Pencil: M14 18 l5 -5 l2 2 l-5 5 h-2 v-2 z  (closed outline, bottom-right).
            p.move(to: CGPoint(x: 14 * s, y: 18 * s))
            p.addLine(to: CGPoint(x: 19 * s, y: 13 * s))
            p.addLine(to: CGPoint(x: 21 * s, y: 15 * s))
            p.addLine(to: CGPoint(x: 16 * s, y: 20 * s))
            p.addLine(to: CGPoint(x: 14 * s, y: 20 * s))
            p.closeSubpath()
        }
        .stroke(color, style: StrokeStyle(lineWidth: 1.8 * s, lineCap: .round, lineJoin: .round))
        .frame(width: size, height: size)
    }
}

#if DEBUG
struct PersonEditGlyph_Previews: PreviewProvider {
    static var previews: some View {
        PersonEditGlyph(size: 48, color: .white)
            .padding(40)
            .background(Color.black)
            .previewLayout(.sizeThatFits)
    }
}
#endif
