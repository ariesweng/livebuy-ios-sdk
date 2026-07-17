import SwiftUI
import LivebuyUI

// MARK: - GestureMuteToastView — family-1 center mute toast (0.7s tap feedback)
//
// Spec: `reference-ui-rendering/spec.md`
//   § "LivebuyReferenceUI PlayerShellView 提供點擊靜音手勢，轉發 onToggleMute"
//     (0.7s 中央靜音 toast).
// Design: `design/templates/minimal/sdk-components.jsx` `LBPGestureHint`「點擊靜音」.
//
// The small centred toast shown for ~0.7s after a video-area TAP toggles mute. It is
// PURE呈現: it reads only `muted` (the resulting mute state, read from
// `PlayerShellModel.muted`) and paints a speaker glyph + label on a dark-glass pill.
// It owns NO timer — `PlayerShellView` drives its presentation (transient @State,
// auto-dismiss). Renders correctly standalone (demo / snapshot).
//
// iOS-14-safe SwiftUI only: `ZStack` / `HStack` / `Image(systemName:)` / `Text` /
// `Capsule`. No Lazy* / ScrollView / AsyncImage / .foregroundStyle / .tint.

/// The centred mute toast: a dark-glass pill with a speaker glyph + a state label.
/// `muted == true` → 靜音 (speaker.slash); `false` → 聲音開啟 (speaker.wave.2).
public struct GestureMuteToastView: View {

    /// The resolved reference-ui theme (FIRST positional argument, always).
    public let theme: ReferenceUITheme

    /// The resulting mute state to reflect (read from `PlayerShellModel.muted`).
    public let muted: Bool

    public init(theme: ReferenceUITheme, muted: Bool) {
        self.theme = theme
        self.muted = muted
    }

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 18 * theme.fontScale, weight: .semibold))
                .foregroundColor(.white)
            Text(muted ? Self.mutedLabel : Self.unmutedLabel)
                .font(.system(size: 14 * theme.fontScale, weight: .semibold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule().fill(Self.glass))
    }

    static let mutedLabel = "靜音"
    static let unmutedLabel = "聲音開啟"
    /// Dark-glass pill surface (rgba(20,20,24,0.78)).
    static let glass = (Color(hex: "#141418") ?? .black).opacity(0.78)
}

#if DEBUG
struct GestureMuteToastView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            GestureMuteToastView(theme: ReferenceUIThemePalette.minimal, muted: true)
            GestureMuteToastView(theme: ReferenceUIThemePalette.minimal, muted: false)
        }
        .padding()
        .background(Color.black)
        .previewLayout(.sizeThatFits)
    }
}
#endif
