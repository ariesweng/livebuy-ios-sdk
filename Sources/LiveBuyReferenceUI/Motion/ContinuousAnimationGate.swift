import SwiftUI
import LiveBuySDK

// MARK: - Continuous decorative-animation throttling
//   (ios-power-profile-animation-throttle-reference-ui — Phase 2 C, reference-ui, iOS)
//
// Depends On: ios-power-profile-thermal-core (already committed `616fb0ef`) — this file
// ONLY consumes the existing core `LBPowerProfile` contract; it adds NO core / view-model
// code (dependency direction is one-way `reference-ui → core`).
//
// The two continuous (`repeatForever`) decorative animations in this module — the
// unclaimed-win pulse ring (`WinEntryView`) and the long-title marquee scroll
// (`MarqueeTitleLoopView`) — keep driving Core Animation forever, heating the device
// during long live sessions. This gate lets those views SKIP starting their driver when
// the device is hot (power profile `conservative`/`survival`), when the user enabled
// Reduce Motion, or when the view is off-screen. It ONLY gates the `withAnimation` start —
// the animated sub-views still instantiate and lay out at their RESTING position, so the
// snapshot golden (captured by `ImageRenderer`, which never fires `.onAppear`) is
// byte-identical.

/// Pure policy — whether a continuous decorative animation SHALL run. Zero rendering,
/// deterministically unit-testable on any Simulator/CI (thermalState never escalates on
/// the Simulator; the tier is supplied as a plain argument here).
///
/// STARTING VALUE — tune (needs on-device / UX calibration):
/// - `reduceMotionEnabled == true` → `false` (accessibility preference wins).
/// - `visible == false` (off-screen) → `false` (don't burn GPU off-screen).
/// - `profile` in `.conservative` / `.survival` (the `.serious`+ heat band, aligned with
///   the core-side "start meaningfully load-shedding at serious" quality cap) → `false`.
/// - `profile` in `.full` / `.reduced` → `true`.
func shouldRunContinuousAnimation(
    profile: LBPowerProfile,
    reduceMotionEnabled: Bool,
    visible: Bool
) -> Bool {
    if reduceMotionEnabled { return false }
    if !visible { return false }
    switch profile {
    case .full, .reduced:
        return true
    case .conservative, .survival:
        return false
    }
}

/// Value-semantic gate carried through the SwiftUI environment. Leaf decorative views read
/// it (`@Environment(\.continuousAnimationGate)`) to decide whether to START their
/// continuous animation. `Equatable` so views can `.onChange(of: motionGate)` to
/// re-evaluate when the tier / reduce-motion flag flips (cool-back → resume, heat → stop).
struct ContinuousAnimationGate: Equatable {
    var powerProfile: LBPowerProfile
    var reduceMotionEnabled: Bool

    /// Neutral "animate" default used by the `EnvironmentKey` below (fixed `.full` +
    /// reduce-motion off, NOT read from `UIAccessibility`, so the default never drifts with
    /// CI-machine accessibility settings). Views constructed WITHOUT an injected gate
    /// (snapshot fixtures / previews) fall back to this — and since `ImageRenderer` never
    /// fires `.onAppear`, the resting frame is captured regardless of this value.
    static let animating = ContinuousAnimationGate(powerProfile: .full, reduceMotionEnabled: false)

    /// Whether a continuous decorative animation may run given this gate + a visibility flag.
    func allowsAnimation(visible: Bool) -> Bool {
        shouldRunContinuousAnimation(
            profile: powerProfile,
            reduceMotionEnabled: reduceMotionEnabled,
            visible: visible
        )
    }
}

private struct ContinuousAnimationGateKey: EnvironmentKey {
    static let defaultValue = ContinuousAnimationGate.animating
}

extension EnvironmentValues {
    /// The current continuous-animation throttling gate. Injected once at the player-overlay
    /// root by `PowerProfileMotionEnvironment`; defaults to a neutral "animate" value when
    /// unset (direct-constructed snapshot / preview instances).
    var continuousAnimationGate: ContinuousAnimationGate {
        get { self[ContinuousAnimationGateKey.self] }
        set { self[ContinuousAnimationGateKey.self] = newValue }
    }
}

// MARK: - Wire-name reverse map (reference-ui-local convenience)

extension LBPowerProfile {
    /// Reverse of the core `LBPowerProfile.wireName` getter. The core enum only exposes the
    /// forward getter; this reference-ui-local helper maps the `profile` param of a
    /// `POWER_PROFILE_CHANGED` event back to the enum. An unknown / future wire name maps to
    /// `nil` (the caller conservatively ignores it — no spurious throttle change). This is a
    /// consumer-side convenience and does NOT modify the core contract.
    static func fromWireName(_ wire: String) -> LBPowerProfile? {
        switch wire {
        case "full":         return .full
        case "reduced":      return .reduced
        case "conservative": return .conservative
        case "survival":     return .survival
        default:             return nil
        }
    }
}
