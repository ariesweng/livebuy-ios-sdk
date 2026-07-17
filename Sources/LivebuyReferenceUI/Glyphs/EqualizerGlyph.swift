import SwiftUI

// MARK: - EqualizerGlyph — hand-drawn 3-bar equalizer (design「介紹中」mark)
//
// Spec: `reference-ui-rendering/spec.md` (rb-ios-product-list-introducing-banner)
// Design: `design/templates/minimal/live-chrome.jsx` `LBLivePinnedCard` +
//   `sdk-components.jsx` `LBPProductRow` introBadge —
//   <rect x3   y14 w3 h7  rx0.5/>
//   <rect x10.5 y9 w3 h12 rx0.5/>
//   <rect x18  y4  w3 h17 rx0.5/>   (24px viewBox, fill)
//
// Three bottom-aligned, ascending-height filled bars — the「介紹中」(now-introducing)
// vocabulary shared by the LIVE pinned card tag and the product-list banner. SF Symbols
// has no faithful equalizer of this exact shape, so we hand-draw it (as with ShareGlyph),
// scaled by `size / 24`.
//
// Pure presentation: only `size` / `color`. iOS-14-safe (`Path` / `.fill` / `.frame`).

/// The design's 3-bar equalizer mark, hand-drawn to match the「介紹中」badge.
public struct EqualizerGlyph: View {

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
        // (x, y, w, h) per the design svg — all bars bottom at y21.
        let bars: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (3, 14, 3, 7),
            (10.5, 9, 3, 12),
            (18, 4, 3, 17),
        ]
        Path { p in
            for b in bars {
                let rect = CGRect(x: b.0 * s, y: b.1 * s, width: b.2 * s, height: b.3 * s)
                p.addRoundedRect(in: rect, cornerSize: CGSize(width: 0.5 * s, height: 0.5 * s))
            }
        }
        .fill(color)
        .frame(width: size, height: size)
    }
}
