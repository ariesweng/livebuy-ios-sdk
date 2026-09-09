import SwiftUI

// MARK: - MegaphoneGlyph — hand-drawn FontAwesome-style bullhorn silhouette
//                          (design `Icons.megaphone`, viewBox 0 0 576 512)
//
// Spec: `reference-ui-rendering/spec.md` (rb-ios-live-announce-bullhorn-icon)
// Design: `design/shared/icons.jsx` `Icons.megaphone` — a two-subpath fill (outer
//   bullhorn silhouette + an inner notch that carves the "open bell mouth" cutout
//   out via the SAME nonzero-winding fill rule the browser's SVG default uses).
//   Every segment in the design's `d` attribute is a straight line (including the
//   implicit-axis `H`/`V`/lowercase `h`/`v`/`l` shorthands) or a cubic bezier
//   (`C`/absolute) — there is NEITHER a smooth-cubic (`s`) shorthand NOR any
//   elliptical `a`/`A` arc command, so this glyph does NOT need `icon-authoring.md`
//   規則 1's arc→bezier conversion (unlike `LockGlyph` / `ArrowClockwiseGlyph`) and
//   is even simpler to transcribe than `HotFlameGlyph` (which has one `s` shorthand
//   to expand) — the coordinates below are a DIRECT, segment-by-segment transcription
//   of the design's own `d` path, expanded from its relative/absolute mixed commands
//   into absolute MoveTo / CurveTo / LineTo segments (hand-verified once here rather
//   than re-derived per platform).
//
// Non-square viewBox (576×512 — WIDER than tall, the mirror image of `HotFlameGlyph`'s
// 448×512 which is TALLER than wide): scaled uniformly by `size / 576` (576 is the
// LARGER dimension here, so it is the limiting one) and VERTICALLY centered (padding
// added to `dy`, not `dx` — the opposite axis from `HotFlameGlyph`), reproducing the
// browser SVG default `preserveAspectRatio="xMidYMid meet"` the design's shared
// `<Icon>` wrapper relies on. Scaling both axes by `size / 512` instead would stretch
// the bullhorn horizontally past the `size × size` box the design's
// `<svg width={size} height={size}>` actually draws into.
//
// Pure presentation: only `size` / `color`. iOS-14-safe (`Path` / `.fill` / `.frame`).

/// The design's bullhorn (LIVE announce banner icon badge) glyph, hand-drawn to match
/// `Icons.megaphone` (FontAwesome "bullhorn" glyph, viewBox `0 0 576 512`).
public struct MegaphoneGlyph: View {

    /// The glyph box side length (pt). The bullhorn is aspect-fit (scaled by the
    /// limiting 576 dimension) and vertically centered inside a `size × size`
    /// square — see the file header's aspect-fit note.
    public let size: CGFloat

    /// The fill color.
    public let color: Color

    public init(size: CGFloat, color: Color) {
        self.size = size
        self.color = color
    }

    public var body: some View {
        Self.megaphonePath(size: size)
            .fill(color)
            .frame(width: size, height: size)
    }

    /// Builds the bullhorn `Path` at a given box size — extracted as a standalone, pure,
    /// unit-testable function (unit-test-discipline) so the hand-transcribed coordinates'
    /// endpoints / bounding box can be asserted without mounting SwiftUI.
    static func megaphonePath(size: CGFloat) -> Path {
        let scale = size / 576.0
        let dy = (size - 512 * scale) / 2
        // A `let`-bound closure, NOT a nested `func` — see `HotFlameGlyph.flamePath`'s
        // identical note on why this is a closure, not a local function declaration.
        let pt: (CGFloat, CGFloat) -> CGPoint = { x, y in CGPoint(x: x * scale, y: y * scale + dy) }

        return Path { p in
            // Outer bullhorn silhouette — design `d` (first subpath):
            //   M576 240c0-23.63-12.95-44.04-32-55.12V32.01C544 23.26 537.02 0 512 0
            //   c-7.12 0-14.19 2.38-19.98 7.02l-85.03 68.03C364.28 109.19 310.66 128 256 128H64
            //   c-35.35 0-64 28.65-64 64v96c0 35.35 28.65 64 64 64h33.7
            //   c-1.39 10.48-2.18 21.14-2.18 32 0 39.77 9.26 77.35 25.56 110.94
            //   5.19 10.69 16.52 17.06 28.4 17.06h74.28
            //   c26.05 0 41.69-29.84 25.9-50.56-16.4-21.52-26.15-48.36-26.15-77.44
            //   0-11.11 1.62-21.79 4.41-32H256
            //   c54.66 0 108.28 18.81 150.98 52.95l85.03 68.03
            //   C497.68 477.52 504.73 479.99 511.99 480
            //   c24.92 0 32-22.78 32-32V295.13
            //   C563.05 284.04 576 263.63 576 240z
            p.move(to: pt(576, 240))
            p.addCurve(to: pt(544, 184.88), control1: pt(576, 216.37), control2: pt(563.05, 195.96))
            p.addLine(to: pt(544, 32.01))
            p.addCurve(to: pt(512, 0), control1: pt(544, 23.26), control2: pt(537.02, 0))
            p.addCurve(to: pt(492.02, 7.02), control1: pt(504.88, 0), control2: pt(497.81, 2.38))
            p.addLine(to: pt(406.99, 75.05))
            p.addCurve(to: pt(256, 128), control1: pt(364.28, 109.19), control2: pt(310.66, 128))
            p.addLine(to: pt(64, 128))
            p.addCurve(to: pt(0, 192), control1: pt(28.65, 128), control2: pt(0, 156.65))
            p.addLine(to: pt(0, 288))
            p.addCurve(to: pt(64, 352), control1: pt(0, 323.35), control2: pt(28.65, 352))
            p.addLine(to: pt(97.7, 352))
            p.addCurve(to: pt(95.52, 384), control1: pt(96.31, 362.48), control2: pt(95.52, 373.14))
            p.addCurve(to: pt(121.08, 494.94), control1: pt(95.52, 423.77), control2: pt(104.78, 461.35))
            p.addCurve(to: pt(149.48, 512), control1: pt(126.27, 505.63), control2: pt(137.6, 512))
            p.addLine(to: pt(223.76, 512))
            p.addCurve(to: pt(249.66, 461.44), control1: pt(249.81, 512), control2: pt(265.45, 482.16))
            p.addCurve(to: pt(223.51, 384), control1: pt(233.26, 439.92), control2: pt(223.51, 413.08))
            p.addCurve(to: pt(227.92, 352), control1: pt(223.51, 372.89), control2: pt(225.13, 362.21))
            p.addLine(to: pt(256, 352))
            p.addCurve(to: pt(406.98, 404.95), control1: pt(310.66, 352), control2: pt(364.28, 370.81))
            p.addLine(to: pt(492.01, 472.98))
            p.addCurve(to: pt(511.99, 480), control1: pt(497.68, 477.52), control2: pt(504.73, 479.99))
            p.addCurve(to: pt(543.99, 448), control1: pt(536.91, 480), control2: pt(543.99, 457.22))
            p.addLine(to: pt(543.99, 295.13))
            p.addCurve(to: pt(576, 240), control1: pt(563.05, 284.04), control2: pt(576, 263.63))
            p.closeSubpath()

            // Inner notch (the horn's flared open mouth carved out via nonzero winding) —
            // design `d` (second subpath, continues the same `d` string):
            //   M480 381.42l-33.05-26.44C392.95 311.78 325.12 288 256 288v-96
            //   c69.12 0 136.95-23.78 190.95-66.98L480 98.58v282.84z
            p.move(to: pt(480, 381.42))
            p.addLine(to: pt(446.95, 354.98))
            p.addCurve(to: pt(256, 288), control1: pt(392.95, 311.78), control2: pt(325.12, 288))
            p.addLine(to: pt(256, 192))
            p.addCurve(to: pt(446.95, 125.02), control1: pt(325.12, 192), control2: pt(392.95, 168.22))
            p.addLine(to: pt(480, 98.58))
            p.addLine(to: pt(480, 381.42))
            p.closeSubpath()
        }
    }
}
