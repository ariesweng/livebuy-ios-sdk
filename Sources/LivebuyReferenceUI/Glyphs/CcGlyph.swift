import SwiftUI

// MARK: - CcGlyph — Font Awesome closed-captioning glyph, two states (design `ccOn`/`ccOff`)
//
// Spec: `reference-ui-rendering/spec.md` (`rb-ios-cc-icon-availability-redesign`, MODIFIES the
// "LivebuyReferenceUI 渲染 OperationPanel 側欄 rail，綁 DefaultOperationRail" +
// "LivebuyReferenceUI 渲染 LIVE 底部 bar（LiveBottomBarView），綁 bagCount / isReplay" Requirements)
// Design: `design/shared/icons.jsx` `ccOn` / `ccOff` (design R42, 2026-09-10) — each a 512×512
// viewBox FILL path (FontAwesome "closed-captioning" glyph, solid vs outline), replacing the
// retired `Icons.cc` (single hand-drawn STROKE badge + twin "c" curves).
//
// `ccOn` is a single filled outer badge silhouette with two carved-out "C" holes (drawn via the
// SAME nonzero-winding fill rule the browser's SVG default uses — the hole subpaths wind
// opposite the outer badge, exactly like `MegaphoneGlyph`'s inner-notch cutout). `ccOff` adds a
// THIRD carved hole (an inner rounded-rect outline, giving the badge itself an outline look) on
// top of the same two "C" holes. Every segment in both `d` strings is a cubic bezier (`C`/`c`) or
// a straight line (`H`/`V`/`h`/`v`/`l`, including relative shorthands) — there is neither a
// smooth-cubic (`S`) shorthand nor any elliptical arc (`a`/`A`) command, so — like
// `MegaphoneGlyph` — this does NOT need `icon-authoring.md` 規則 1's arc→bezier conversion.
//
// The absolute-coordinate `move(to:)` / `addLine(to:)` / `addCurve(to:control1:control2:)` /
// `closeSubpath()` sequences below were generated mechanically from the design's literal `d`
// path strings via a standalone Python SVG-path parser (relative→absolute, S-shorthand
// expansion) — NOT hand arithmetic — with each subpath's bounding box verified to land inside
// the declared 512×512 viewBox before transcription, mirroring the documented discipline behind
// `GiftGlyph` / `MegaphoneGlyph`.
//
// Pure presentation: only `size` / `color` / `state`. The subtitle-toggle BEHAVIOR
// (`onTapItem(.subtitle)` / `onToggleCC`) — including the NEW "unavailable state swallows the
// tap, shows a tooltip instead" branch — lives at the two call sites
// (`OperationRailView.pillButton(for:)` / `LiveBottomBarView.trailingAction`), driven by
// `CcIconState`, not here.
//
// iOS-14-safe: `Path` / `.fill(_:)` / `.frame` are all iOS-13+ (same primitives `MegaphoneGlyph`
// already relies on).

/// The design's Font Awesome closed-captioning glyph (`ccOn` filled / `ccOff` outlined),
/// replacing the retired hand-drawn `Icons.cc` badge at the VOD side-rail `.subtitle` pill and
/// the LIVE bottom bar's `chatClosed`-variant CC toggle.
public struct CcGlyph: View {

    /// Which of the two filled silhouettes to draw. The THIRD visual state
    /// (`ccUnavailable` — no caption source at all) is a distinct, non-square glyph drawn by
    /// `CcUnavailableGlyph`, not a third case here.
    public enum State: Equatable {
        /// Captions available AND currently on — solid badge, matches design `ccOn`.
        case on
        /// Captions available but currently off — outlined badge (inner rounded-rect hole),
        /// matches design `ccOff`.
        case off
    }

    /// The glyph box size (pt). The design proportions scale by `size / 512`.
    public let size: CGFloat

    /// The fill color.
    public let color: Color

    /// Which silhouette to draw.
    public let state: State

    public init(size: CGFloat, color: Color, state: State) {
        self.size = size
        self.color = color
        self.state = state
    }

    public var body: some View {
        Self.path(state: state, size: size)
            .fill(color)
            .frame(width: size, height: size)
    }

    /// Builds the glyph `Path` at a given box size and state — extracted as a standalone, pure,
    /// unit-testable function (unit-test-discipline) so the transcribed coordinates' bounding
    /// box can be asserted without mounting SwiftUI.
    static func path(state: State, size: CGFloat) -> Path {
        let scale = size / 512.0
        let pt: (CGFloat, CGFloat) -> CGPoint = { x, y in CGPoint(x: x * scale, y: y * scale) }
        switch state {
        case .on: return onPath(pt: pt)
        case .off: return offPath(pt: pt)
        }
    }

    /// `ccOn` — outer rounded badge + two carved "C" holes (nonzero-winding fill).
    private static func onPath(pt: (CGFloat, CGFloat) -> CGPoint) -> Path {
        Path { p in
            // Outer badge.
            p.move(to: pt(464, 64))
            p.addLine(to: pt(48, 64))
            p.addCurve(to: pt(0, 112), control1: pt(21.5, 64), control2: pt(0, 85.5))
            p.addLine(to: pt(0, 400))
            p.addCurve(to: pt(48, 448), control1: pt(0, 426.5), control2: pt(21.5, 448))
            p.addLine(to: pt(464, 448))
            p.addCurve(to: pt(512, 400), control1: pt(490.5, 448), control2: pt(512, 426.5))
            p.addLine(to: pt(512, 112))
            p.addCurve(to: pt(464, 64), control1: pt(512, 85.5), control2: pt(490.5, 64))
            p.closeSubpath()

            // Left "C" hole.
            p.move(to: pt(218.1, 287.7))
            p.addCurve(to: pt(227.3, 288.6), control1: pt(220.9, 285.2), control2: pt(225.2, 285.6))
            p.addLine(to: pt(246.8, 316.3))
            p.addCurve(to: pt(246.3, 324), control1: pt(248.5, 318.7), control2: pt(248.3, 321.9))
            p.addCurve(to: pt(73.5, 256.1), control1: pt(192.7, 380.8), control2: pt(73.5, 356.1))
            p.addCurve(to: pt(246, 186), control1: pt(73.5, 158.8), control2: pt(195.2, 136.6))
            p.addCurve(to: pt(247, 191.7), control1: pt(248.1, 188), control2: pt(248.5, 189.2))
            p.addLine(to: pt(229.5, 222.2))
            p.addCurve(to: pt(220.4, 223.9), control1: pt(227.6, 225.3), control2: pt(223.3, 226.2))
            p.addCurve(to: pt(125.8, 255.1), control1: pt(179.6, 191.9), control2: pt(125.8, 209))
            p.addCurve(to: pt(218.1, 287.7), control1: pt(125.9, 303.1), control2: pt(176.9, 325.6))
            p.closeSubpath()

            // Right "C" hole (mirrors the left one, shifted +190.4 in x).
            p.move(to: pt(408.5, 287.7))
            p.addCurve(to: pt(417.7, 288.6), control1: pt(411.3, 285.2), control2: pt(415.6, 285.6))
            p.addLine(to: pt(437.2, 316.3))
            p.addCurve(to: pt(436.7, 324), control1: pt(438.9, 318.7), control2: pt(438.7, 321.9))
            p.addCurve(to: pt(264, 256.1), control1: pt(383.2, 380.9), control2: pt(264, 356.1))
            p.addCurve(to: pt(436.5, 186), control1: pt(264, 158.8), control2: pt(385.7, 136.6))
            p.addCurve(to: pt(437.5, 191.7), control1: pt(438.6, 188), control2: pt(439, 189.2))
            p.addLine(to: pt(420, 222.2))
            p.addCurve(to: pt(410.9, 223.9), control1: pt(418.1, 225.3), control2: pt(413.8, 226.2))
            p.addCurve(to: pt(316.3, 255.1), control1: pt(370.1, 191.9), control2: pt(316.3, 209))
            p.addCurve(to: pt(408.5, 287.7), control1: pt(316.3, 303.1), control2: pt(367.3, 325.6))
            p.closeSubpath()
        }
    }

    /// `ccOff` — outer rounded badge + inner rounded-rect outline hole + the same two carved
    /// "C" holes (nonzero-winding fill; the "C" hole coordinates differ from `ccOn` by a small
    /// vertical shift — the design's own outline variant is not a byte-for-byte reuse of the
    /// filled one's hole geometry).
    private static func offPath(pt: (CGFloat, CGFloat) -> CGPoint) -> Path {
        Path { p in
            // Outer badge.
            p.move(to: pt(464, 64))
            p.addLine(to: pt(48, 64))
            p.addCurve(to: pt(0, 112), control1: pt(21.5, 64), control2: pt(0, 85.5))
            p.addLine(to: pt(0, 400))
            p.addCurve(to: pt(48, 448), control1: pt(0, 426.5), control2: pt(21.5, 448))
            p.addLine(to: pt(464, 448))
            p.addCurve(to: pt(512, 400), control1: pt(490.5, 448), control2: pt(512, 426.5))
            p.addLine(to: pt(512, 112))
            p.addCurve(to: pt(464, 64), control1: pt(512, 85.5), control2: pt(490.5, 64))
            p.closeSubpath()

            // Inner rounded-rect outline hole (what makes this the "outline" badge).
            p.move(to: pt(458, 400))
            p.addLine(to: pt(54, 400))
            p.addCurve(to: pt(48, 394), control1: pt(50.7, 400), control2: pt(48, 397.3))
            p.addLine(to: pt(48, 118))
            p.addCurve(to: pt(54, 112), control1: pt(48, 114.7), control2: pt(50.7, 112))
            p.addLine(to: pt(458, 112))
            p.addCurve(to: pt(464, 118), control1: pt(461.3, 112), control2: pt(464, 114.7))
            p.addLine(to: pt(464, 394))
            p.addCurve(to: pt(458, 400), control1: pt(464, 397.3), control2: pt(461.3, 400))
            p.closeSubpath()

            // Left "C" hole.
            p.move(to: pt(246.9, 314.3))
            p.addCurve(to: pt(246.4, 322), control1: pt(248.6, 316.7), control2: pt(248.4, 319.9))
            p.addCurve(to: pt(73.6, 254.1), control1: pt(192.8, 378.8), control2: pt(73.6, 354.1))
            p.addCurve(to: pt(246.1, 184), control1: pt(73.6, 156.8), control2: pt(195.3, 134.6))
            p.addCurve(to: pt(247.1, 189.7), control1: pt(248.2, 186), control2: pt(248.6, 187.2))
            p.addLine(to: pt(229.6, 220.2))
            p.addCurve(to: pt(220.5, 221.9), control1: pt(227.7, 223.3), control2: pt(223.4, 224.2))
            p.addCurve(to: pt(125.9, 253.1), control1: pt(179.7, 189.9), control2: pt(125.9, 207))
            p.addCurve(to: pt(218.1, 285.7), control1: pt(125.9, 301.1), control2: pt(176.9, 323.6))
            p.addCurve(to: pt(227.3, 286.6), control1: pt(220.9, 283.2), control2: pt(225.2, 283.6))
            p.addLine(to: pt(246.9, 314.3))
            p.closeSubpath()

            // Right "C" hole (mirrors the left one, shifted +190.4 in x).
            p.move(to: pt(437.3, 314.3))
            p.addCurve(to: pt(436.8, 322), control1: pt(439, 316.7), control2: pt(438.8, 319.9))
            p.addCurve(to: pt(264, 254.1), control1: pt(383.2, 378.9), control2: pt(264, 354.1))
            p.addCurve(to: pt(436.5, 184), control1: pt(264, 156.8), control2: pt(385.7, 134.6))
            p.addCurve(to: pt(437.5, 189.7), control1: pt(438.6, 186), control2: pt(439, 187.2))
            p.addLine(to: pt(420, 220.2))
            p.addCurve(to: pt(410.9, 221.9), control1: pt(418.1, 223.3), control2: pt(413.8, 224.2))
            p.addCurve(to: pt(316.3, 253.1), control1: pt(370.1, 189.9), control2: pt(316.3, 207))
            p.addCurve(to: pt(408.5, 285.7), control1: pt(316.3, 301.1), control2: pt(367.3, 323.6))
            p.addCurve(to: pt(417.7, 286.6), control1: pt(411.3, 283.2), control2: pt(415.6, 283.6))
            p.addLine(to: pt(437.3, 314.3))
            p.closeSubpath()
        }
    }
}
