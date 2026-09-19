import SwiftUI
import LivebuyUI

// MARK: - GestureSeekToastView — half-screen gradient double-tap-seek feedback
//         (`rb-ios-double-tap-seek-feedback`)
//
// Spec: `reference-ui-rendering/spec.md`
//   § "LivebuyReferenceUI PlayerShellView 手勢二度重寫：短擊切換乾淨模式，長按（僅 VOD/回放）
//      2 倍速快轉，雙擊（僅 VOD/回放）seek ±10 秒" — 「雙擊 seek 的半螢幕漸層視覺回饋」段落.
// Design: `design/templates/minimal/sdk-components.jsx` `LBPGestureToast`'s `seekFwd`/`seekBack`
//   branch (~line 504-534) + `LBPSeekHorn` helper (~line 498-502), design R46 (2026-09-18).
//
// Double-tap-to-seek (±10s) is a shipped gesture (`rb-ios-gesture-clean-mode-v2`) that, until
// this change, had NO visual feedback at all — the user only saw the progress bar jump. This
// view is the ENTIRE new visual for it: a dark gradient pinned to the tapped edge (right for
// `.fastForward`, left for `.rewind`), spanning the full video-area height, with a "10" readout
// + three fading play-arrows near the edge.
//
// PURE 呈現: reads only `theme` / `zone`. Owns NO timer — `PlayerShellView` drives its
// presentation (transient `@State`, auto-dismiss), mirroring the sibling `GestureMuteToastView`
// (center mute toast) exactly. Renders correctly standalone (demo / snapshot).
//
// iOS-14-safe SwiftUI only: `GeometryReader` / `HStack` / `VStack` / `ZStack` / `Spacer` /
// `LinearGradient` / a plain `Shape`. No Lazy* / ScrollView / AsyncImage / .foregroundStyle /
// .tint / iOS-15+-only APIs.

/// The half-screen dark-gradient + "10" + fading-arrows toast shown for ~0.7s after a
/// double-tap-seek commit. `zone == .fastForward` → pinned to the right edge (arrows point
/// right); `.rewind` → pinned to the left edge, entire content mirrored horizontally (arrows
/// point left).
public struct GestureSeekToastView: View {

    /// The resolved reference-ui theme (FIRST positional argument, always).
    public let theme: ReferenceUITheme

    /// Which half was double-tapped — reuses `PlayerShellView`'s existing `TapZone` (design.md
    /// D1: same concept, no reason for a second enum naming the same fact).
    public let zone: PlayerShellView.TapZone

    public init(theme: ReferenceUITheme, zone: PlayerShellView.TapZone) {
        self.theme = theme
        self.zone = zone
    }

    /// `true` for `.fastForward` (pinned right edge, arrows point right); `false` for `.rewind`
    /// (pinned left edge, content mirrored).
    private var isForward: Bool { zone == .fastForward }

    /// The gradient block's width as a fraction of the container — design `width: '44%'`.
    private static let widthFraction: CGFloat = 0.44
    /// Inset between the pinned edge and the "10" / arrows content — design `padding: '0 28px'`.
    private static let contentInset: CGFloat = 28
    /// Vertical gap between the "10" text and the arrow row — design `gap: 6`.
    private static let contentGap: CGFloat = 6
    /// Horizontal gap between each arrow — design `gap: 4`.
    private static let hornGap: CGFloat = 4
    /// Each arrow's size (width; height derives from the 8:11 aspect ratio) — design
    /// `LBPSeekHorn size={8}`.
    private static let hornSize: CGFloat = 8

    public var body: some View {
        // GeometryReader used SOLELY to read the container's width for the 44%-width block
        // (design.md D2) — mirrors this module's existing `handleDragChanged`/`handleDragEnded`
        // gesture-layer convention (PlayerShellView.swift) of reading `proxy.size.width` without
        // relying on GeometryReader's proposed size as the view's own primary sizing mechanism;
        // the block's actual frame comes from the explicit `.frame(width:height:)` below.
        GeometryReader { proxy in
            HStack(spacing: 0) {
                if isForward { Spacer(minLength: 0) }
                ZStack(alignment: isForward ? .trailing : .leading) {
                    LinearGradient(
                        gradient: Gradient(colors: [Color.black.opacity(0.8), Color.black.opacity(0)]),
                        startPoint: isForward ? .trailing : .leading,
                        endPoint: isForward ? .leading : .trailing)
                    content
                        .padding(isForward ? .trailing : .leading, Self.contentInset)
                }
                .frame(width: proxy.size.width * Self.widthFraction, height: proxy.size.height)
                if !isForward { Spacer(minLength: 0) }
            }
        }
    }

    private var content: some View {
        VStack(spacing: Self.contentGap) {
            Text("10")
                .font(.system(size: 24 * theme.fontScale, weight: .heavy))
                .foregroundColor(.white)
            HStack(spacing: Self.hornGap) {
                SeekHornShape().fill(Color.white.opacity(0.3))
                    .frame(width: Self.hornSize, height: Self.hornSize * 11 / 8)
                SeekHornShape().fill(Color.white.opacity(0.5))
                    .frame(width: Self.hornSize, height: Self.hornSize * 11 / 8)
                SeekHornShape().fill(Color.white)
                    .frame(width: Self.hornSize, height: Self.hornSize * 11 / 8)
            }
            .scaleEffect(x: isForward ? 1 : -1, y: 1)
        }
    }
}

/// A plain rightward-pointing triangle — the "play arrow" glyph behind the fading 3-arrow row.
/// Design source `LBPSeekHorn` is an exact SVG bezier path; this module's own precedent for a
/// design-specified bespoke glyph (`DetailGlyph.swift`) is a hand-drawn `Shape`, not the nearest
/// SF Symbol — but the design's own comment explicitly permits NOT reproducing the exact path
/// here ("可用等效 SwiftUI Shape...不必逐 path 複製"), so this is a plain, unrounded triangle
/// rather than a bezier reconstruction (design.md D3).
private struct SeekHornShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

#if DEBUG
struct GestureSeekToastView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            ZStack {
                Color.gray
                GestureSeekToastView(theme: ReferenceUIThemePalette.minimal, zone: .fastForward)
            }
            .frame(width: 300, height: 200)
            ZStack {
                Color.gray
                GestureSeekToastView(theme: ReferenceUIThemePalette.minimal, zone: .rewind)
            }
            .frame(width: 300, height: 200)
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
#endif
