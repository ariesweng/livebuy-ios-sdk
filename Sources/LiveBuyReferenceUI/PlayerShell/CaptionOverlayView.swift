import SwiftUI
import LivebuySDK
import LivebuyUI

// MARK: - CaptionOverlayView — family-1 VOD closed-caption line (rb-ios-vod-player-chrome)
//
// Spec: `reference-ui-rendering/spec.md` (family-1 VOD chrome).
// Design: design/templates/minimal/sdk-components.jsx `LBPCaptionOverlay` — a centered
//         caption line near the bottom, shown only while CC is ON.
//
// A centered closed-caption line. There is NO public core source for the active
// subtitle TEXT today (only `subtitle.{available,enabled}` booleans), so the text is
// HOST-SUPPLIED; the shell gates this view's presence on `subtitleEnabled` and passes
// the host's caption string. Pure presentation — renders nothing for empty text.
//
// iOS-14-safe: `Text` / `Capsule` only.

/// A centered VOD closed-caption line. Renders `EmptyView` for empty `text`
/// (the shell only shows it while CC is on with a host-supplied caption).
public struct CaptionOverlayView: View {

    public let theme: ReferenceUITheme
    /// Host-supplied caption text (core exposes no active-caption text). Empty → nothing.
    public let text: String

    public init(theme: ReferenceUITheme, text: String) {
        self.theme = theme
        self.text = text
    }

    public var body: some View {
        if text.isEmpty {
            EmptyView()
        } else {
            Text(text)
                .font(.system(size: 13 * theme.fontScale, weight: .medium))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(Color.black.opacity(0.55)))
        }
    }
}
