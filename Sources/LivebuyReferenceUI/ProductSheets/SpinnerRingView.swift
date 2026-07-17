import SwiftUI

// MARK: - SpinnerRingView — iOS-14-safe inline spinner (faint ring + bright arc)
//
// Spec: `reference-ui-rendering/spec.md` § "加購 CTA 請求中 loading（iOS reference-ui）".
// Design: `design/templates/minimal/sdk-components.jsx` `LBPSpinner`.
//
// A small spinning ring used inside the add-to-cart CTA's loading state (replaces the cart
// glyph). Mirrors `StartScreenView.spinnerRing`: a faint full ring + a bright quarter arc,
// driven by a local `@State` + `.onAppear` `rotationEffect` (NOT `ProgressView`, for iOS-14
// + deterministic snapshots — `onAppear` never runs under `ImageRenderer`, so a snapshot
// captures the resting 0° frame). `color` defaults to white (the CTA is accent-filled).
struct SpinnerRingView: View {

    var size: CGFloat = 18
    var lineWidth: CGFloat = 2
    var color: Color = .white
    /// Faint same-colour track behind the bright arc (design `LBPSpinner` track ≈
    /// rgba(255,255,255,0.35) on the accent CTA).
    var trackOpacity: Double = 0.35

    @State private var spinning = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(trackOpacity), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: 0.25)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(spinning ? 360 : 0))
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.linear(duration: 0.7).repeatForever(autoreverses: false)) {
                spinning = true
            }
        }
    }
}
