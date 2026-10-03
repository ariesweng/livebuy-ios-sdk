import SwiftUI

// MARK: - SearchAlertGlyph — hand-drawn「找不到影片」glyph (design `LBErrorScreen` notFound icon)
// Spec: `reference-ui-rendering/spec.md` (rb-ios-error-notfound-glyph-parity)
// Design: `design/templates/minimal/moments.jsx` `LBErrorScreen` → `config.notFound.icon`
// (24px viewBox, stroke 2, round cap/join):
//   lens      <circle cx=11 cy=11 r=7/>
//   handle    M21 21 L16.5 16.5
//   ! stem    M11 8 L11 11.5
//   ! dot     M11 14 (zero-length, round cap) → a filled circle r = stroke / 2
// Same shape as Android `IconGlyphs.kt` `SearchAlertGlyph`, Flutter `search_alert_glyph.dart` and
// RN `SearchAlertGlyph.tsx`. Replaces SF Symbol `magnifyingglass` (no exclamation mark) at the
// not-found error badge.
// Pure presentation: only `size` / `color`. iOS-14-safe.

/// The design's not-found glyph (lens + handle + exclamation mark).
public struct SearchAlertGlyph: View {

    /// The glyph box size (pt). The design proportions scale by `size / 24`.
    public let size: CGFloat

    /// The stroke / fill color.
    public let color: Color

    public init(size: CGFloat, color: Color) {
        self.size = size
        self.color = color
    }

    public var body: some View {
        let s = size / 24.0
        ZStack {
            Path { p in
                p.addEllipse(in: CGRect(x: 4 * s, y: 4 * s, width: 14 * s, height: 14 * s))
                p.move(to: CGPoint(x: 21 * s, y: 21 * s))
                p.addLine(to: CGPoint(x: 16.5 * s, y: 16.5 * s))
                p.move(to: CGPoint(x: 11 * s, y: 8 * s))
                p.addLine(to: CGPoint(x: 11 * s, y: 11.5 * s))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2 * s, lineCap: .round, lineJoin: .round))

            Path { p in
                p.addEllipse(in: CGRect(x: 10 * s, y: 13 * s, width: 2 * s, height: 2 * s))
            }
            .fill(color)
        }
        .frame(width: size, height: size)
    }
}
