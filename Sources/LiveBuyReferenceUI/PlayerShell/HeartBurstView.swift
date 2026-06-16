import SwiftUI

// MARK: - HeartBurstView — shared floating-hearts burst (`LBPHeartBurst`)
//
// Spec: `reference-ui-rendering/spec.md` (rb-ios-live-bottom-heart-burst)
// Design: `design/templates/minimal/sdk-components.jsx` `LBPHeartBurst` +
//          `live-chrome.jsx` `LBLiveBottomBar onLike → spawnHeart`.
//
// A `tick`-driven burst: each time `tick` INCREASES, one accent heart spawns at the origin and
// flies up (offset -90), fading + shrinking + rotating, then self-removes after the flight so
// repeated ticks never accumulate state. Pure presentation — never calls core.
//
// Extracted from `OperationRailView`'s inline burst so BOTH the VOD side rail (driven by the
// core `heartBurstTick`) and the LIVE bottom bar (driven by `PlayerShellView`'s local
// `liveHeartTick`, bumped on the like tap) share one implementation.
//
// Snapshot-neutral: at rest `bursts` is empty → nothing is drawn. `allowsHitTesting(false)`.
//
// iOS-14-safe: `onChange(of:)` is iOS-14+; `withAnimation` / `Image` / `ForEach` are iOS-13+.

/// One in-flight heart for the burst animation. `active == false` is the spawned (at-origin)
/// state; flipping to `true` under `withAnimation` drives the fly-up.
private struct HeartBurst: Identifiable, Equatable {
    let id = UUID()
    let dx: CGFloat
    let rotation: Double
    var active: Bool = false
}

/// The shared floating-hearts burst. Spawns one heart each time `tick` increases.
struct HeartBurstView: View {

    /// Monotonic trigger — each increase spawns one burst.
    let tick: Int

    /// Heart tint (accent).
    let color: Color

    /// Heart glyph size (design `Icons.heartFill` size 26).
    var glyphSize: CGFloat = 26

    @State private var bursts: [HeartBurst] = []

    var body: some View {
        ZStack {
            ForEach(bursts) { burst in
                Image(systemName: "heart.fill")
                    .font(.system(size: glyphSize))
                    .foregroundColor(color)
                    .opacity(burst.active ? 0 : 1)
                    .scaleEffect(burst.active ? 0.7 : 1.0)
                    .offset(
                        x: burst.active ? burst.dx : 0,
                        y: burst.active ? Self.flyDistance : 0)
                    .rotationEffect(.degrees(burst.active ? burst.rotation : 0))
            }
        }
        .frame(width: glyphSize, height: glyphSize)
        .allowsHitTesting(false)
        // Observe the monotonic tick; each increase spawns one burst (iOS-14-safe `onChange`).
        .onChange(of: tick) { _ in spawnBurst() }
    }

    /// Spawn one heart and animate it. The burst self-removes after the flight so repeated
    /// ticks do not accumulate state. Pure presentation — no core call.
    private func spawnBurst() {
        let burst = HeartBurst(
            dx: CGFloat.random(in: Self.dxRange),
            rotation: Double.random(in: Self.rotationRange))
        bursts.append(burst)

        withAnimation(.easeOut(duration: Self.flyDuration)) {
            if let idx = bursts.firstIndex(where: { $0.id == burst.id }) {
                bursts[idx].active = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.flyDuration) {
            bursts.removeAll { $0.id == burst.id }
        }
    }

    // MARK: - Design tokens (lifted from `LBPHeartBurst` / `lbp-heart-fly`)

    static let flyDistance: CGFloat = -90                          // upward travel
    static let flyDuration: Double = 2.4                           // lbp-heart-fly 2.4s
    static let dxRange: ClosedRange<CGFloat> = -22 ... 22          // --dx jitter
    static let rotationRange: ClosedRange<Double> = -28 ... 28     // --rot jitter
}
