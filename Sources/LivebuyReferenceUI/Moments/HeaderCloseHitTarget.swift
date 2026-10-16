import SwiftUI

// MARK: - HeaderCloseHitTarget (fix-ios-error-screen-close-button-blocked)
//
// livebuy-flutter-sdk issue #2: the error moment's full-bleed scrim (a hit-testable `Color`) blocks
// every touch, including the header's top-right ✕ underneath it. The header button reports its
// on-screen frame (global coordinates) here; the error scrim forwards a tap that lands inside that
// frame to `onClose` (the container's close exit), so the ✕ works while every other control stays
// blocked. A plain reference holder (not observed): read only at tap time, never drives drawing.

final class HeaderCloseHitTarget {
    var frameInGlobal: CGRect?
    var onClose: (() -> Void)?

    /// PURE: whether a tap at `point` (global) hits the header close button `frame`. A tap that
    /// moved more than `maxMovement` points is a drag, not a tap.
    static func isHit(point: CGPoint, translation: CGSize, frame: CGRect?,
                      maxMovement: CGFloat = 10) -> Bool {
        guard let frame = frame else { return false }
        guard abs(translation.width) <= maxMovement, abs(translation.height) <= maxMovement else { return false }
        return frame.contains(point)
    }
}

private struct HeaderCloseHitTargetKey: EnvironmentKey {
    static let defaultValue: HeaderCloseHitTarget? = nil
}

extension EnvironmentValues {
    /// Provided by `PlayerOverlayRootView`; `nil` (previews / snapshots) → no forwarding.
    var headerCloseHitTarget: HeaderCloseHitTarget? {
        get { self[HeaderCloseHitTargetKey.self] }
        set { self[HeaderCloseHitTargetKey.self] = newValue }
    }
}

/// Zero-pixel background that reports the host view's global frame into the environment target.
struct HeaderCloseFrameReporter: View {
    @Environment(\.headerCloseHitTarget) private var target

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear { target?.frameInGlobal = geo.frame(in: .global) }
                .onChange(of: geo.frame(in: .global)) { target?.frameInGlobal = $0 }
        }
    }
}
