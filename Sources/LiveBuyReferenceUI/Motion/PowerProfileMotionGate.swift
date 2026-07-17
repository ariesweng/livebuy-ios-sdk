import SwiftUI
import UIKit
import LivebuySDK

// MARK: - PowerProfileMotionGate — reference-ui consumption of the power-profile signal
//   (ios-power-profile-animation-throttle-reference-ui — Phase 2 C, reference-ui, iOS)
//
// Depends On: ios-power-profile-thermal-core (committed `616fb0ef`). This subscribes to the
// EXISTING core signal — it adds NO core / view-model code:
//   - pulls `LivebuySDK.currentPowerProfile` at attach (late-subscriber seed),
//   - subscribes to the notification-type `POWER_PROFILE_CHANGED` unified event via the
//     core `Player`'s existing public `addEventListener(_:)` (an AUXILIARY listener that
//     coexists with the host's primary `setEventListener`),
//   - tracks `UIAccessibility` Reduce Motion,
// and republishes a value-semantic `ContinuousAnimationGate` into the SwiftUI environment.

/// Injectable Reduce-Motion source (keeps the gate unit-testable — the Simulator can't be
/// asked to flip system Reduce Motion deterministically from a test).
protocol ReduceMotionProviding {
    var isReduceMotionEnabled: Bool { get }
}

/// Default source — reads the live `UIAccessibility` flag.
struct SystemReduceMotionProvider: ReduceMotionProviding {
    var isReduceMotionEnabled: Bool { UIAccessibility.isReduceMotionEnabled }
}

/// Auxiliary `LivebuyEventListener` that maps `POWER_PROFILE_CHANGED`'s `profile` wire name
/// back to `LBPowerProfile`. Mirrors the `livebuy-ui` `TemplateAuxListener` precedent: it is
/// a NON-primary listener, so it returns `false` (the host's primary listener still sees the
/// event and core default semantics stay intact). Held STRONGLY by `PowerProfileMotionGate`
/// (the core holds aux listeners weakly — the caller must retain).
final class PowerProfileAuxListener: NSObject, LivebuyEventListener {

    /// Invoked (on the dispatcher's thread — possibly off-main) with the new committed tier.
    var onProfile: ((LBPowerProfile) -> Void)?

    func onEventTriggered(
        eventName: String,
        params: [String: Any],
        cartCallback: LBCartResultCallback?,
        shareContext: LBShareContext?
    ) -> Bool {
        if eventName == LBEvent.powerProfileChanged,
           let wire = params["profile"] as? String,
           let profile = LBPowerProfile.fromWireName(wire) {
            onProfile?(profile)
        }
        // Non-primary aux listener: never intercept.
        return false
    }
}

/// Observable that owns the reference-ui-side power-profile + reduce-motion state and
/// republishes it as a `ContinuousAnimationGate`. One instance per player overlay (held by
/// `PowerProfileMotionEnvironment`'s `@StateObject`), so it registers the aux listener once
/// and tears it down on `deinit`.
final class PowerProfileMotionGate: ObservableObject {

    @Published private(set) var gate: ContinuousAnimationGate

    private let reduceMotion: ReduceMotionProviding
    private let notificationCenter: NotificationCenter
    /// Weak — used only to `removeEventListener` on teardown (never to extend VC lifetime).
    private weak var player: LivebuyPlayerViewController?
    private let auxListener = PowerProfileAuxListener()
    private var listenerToken: LBListenerToken?
    private var reduceMotionObserver: NSObjectProtocol?

    init(
        player: LivebuyPlayerViewController?,
        reduceMotion: ReduceMotionProviding = SystemReduceMotionProvider(),
        notificationCenter: NotificationCenter = .default
    ) {
        self.player = player
        self.reduceMotion = reduceMotion
        self.notificationCenter = notificationCenter
        // Late-subscriber pull: seed from the current committed tier + live Reduce Motion.
        // NB: the public SDK entry type is `Livebuy` (the `LivebuySDK` name is the MODULE);
        // reference-ui references every core static through `Livebuy.` (e.g. `Livebuy.sdkConfig`).
        self.gate = ContinuousAnimationGate(
            powerProfile: Livebuy.currentPowerProfile,
            reduceMotionEnabled: reduceMotion.isReduceMotionEnabled
        )
        // Aux (non-primary) subscription to POWER_PROFILE_CHANGED — coexists with the host's
        // primary listener. The core holds it weakly, so `auxListener` is retained by `self`.
        auxListener.onProfile = { [weak self] profile in self?.updateProfile(profile) }
        self.listenerToken = player?.addEventListener(auxListener)
        // Reduce Motion changes.
        self.reduceMotionObserver = notificationCenter.addObserver(
            forName: UIAccessibility.reduceMotionStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.updateReduceMotion() }
    }

    deinit {
        if let token = listenerToken { player?.removeEventListener(token) }
        if let obs = reduceMotionObserver { notificationCenter.removeObserver(obs) }
    }

    // MARK: - State updates

    /// The thermal notification may arrive off-main (core dispatches from the thermal
    /// callback); hop to main before mutating `@Published`. De-dupe when the tier is unchanged.
    private func updateProfile(_ profile: LBPowerProfile) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.gate.powerProfile != profile else { return }
            self.gate.powerProfile = profile
        }
    }

    /// Reduce-Motion notification already delivers on `.main`.
    private func updateReduceMotion() {
        let enabled = reduceMotion.isReduceMotionEnabled
        guard gate.reduceMotionEnabled != enabled else { return }
        gate.reduceMotionEnabled = enabled
    }
}

// MARK: - Environment injection wrapper

/// Wraps the player overlay so its leaf decorative views receive the live throttling gate via
/// `@Environment(\.continuousAnimationGate)`. Owns the `PowerProfileMotionGate` as a
/// `@StateObject` (one instance for the hosting controller's lifetime → registers the aux
/// listener exactly once). Re-renders — and thus re-injects the environment — whenever the
/// published gate changes, which re-triggers the leaf views' `.onChange(of: motionGate)`.
struct PowerProfileMotionEnvironment<Content: View>: View {
    @StateObject private var motionGate: PowerProfileMotionGate
    private let content: Content

    init(player: LivebuyPlayerViewController?, @ViewBuilder content: () -> Content) {
        _motionGate = StateObject(wrappedValue: PowerProfileMotionGate(player: player))
        self.content = content()
    }

    var body: some View {
        content.environment(\.continuousAnimationGate, motionGate.gate)
    }
}
