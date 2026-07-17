import SwiftUI
import LivebuyUI

// MARK: - GesturePauseIconView — family-1 center pause icon (hold-to-pause feedback)
//
// Spec: `reference-ui-rendering/spec.md`
//   § "LivebuyReferenceUI PlayerShellView 提供長按暫停手勢 + 中央 pause icon".
// Design: `design/templates/minimal/sdk-components.jsx` `LBPGestureHint`「長按畫面 = 暫停 / 繼續」.
//
// The centred pause glyph shown WHILE the viewer holds the video area (hold-to-pause).
// PURE呈現: it reads only `theme` and paints a translucent dark circle + a pause glyph.
// It owns NO state — `PlayerShellView` shows it conditionally on its transient
// `isHolding` @State. Renders correctly standalone (demo / snapshot).
//
// iOS-14-safe SwiftUI only: `ZStack` / `Circle` / `Image(systemName:)`. No Lazy* /
// ScrollView / AsyncImage / .foregroundStyle / .tint.

/// The centred hold-to-pause icon: a translucent dark circle with a white pause glyph.
public struct GesturePauseIconView: View {

    /// The resolved reference-ui theme (FIRST positional argument, always).
    public let theme: ReferenceUITheme

    public init(theme: ReferenceUITheme) {
        self.theme = theme
    }

    public var body: some View {
        ZStack {
            Circle()
                .fill(Self.glass)
                .frame(width: 72, height: 72)
            Image(systemName: "pause.fill")
                .font(.system(size: 30 * theme.fontScale, weight: .heavy))
                .foregroundColor(.white)
        }
    }

    /// Translucent dark circle surface (rgba(20,20,24,0.62)).
    static let glass = (Color(hex: "#141418") ?? .black).opacity(0.62)
}

#if DEBUG
struct GesturePauseIconView_Previews: PreviewProvider {
    static var previews: some View {
        GesturePauseIconView(theme: ReferenceUIThemePalette.minimal)
            .padding()
            .background(Color.gray)
            .previewLayout(.sizeThatFits)
    }
}
#endif
