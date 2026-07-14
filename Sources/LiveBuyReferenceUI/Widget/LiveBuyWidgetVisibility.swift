import Foundation

// MARK: - LiveBuyWidgetVisibility — opt-in host→SDK cover bridge (ios-refui-widget-host-visibility-pause)
//
// iOS parity of Android `tv.livebuy.referenceui.widget.LiveBuyWidgetVisibility`
// (`android-refui-widget-host-visibility-pause`, commit e3fcfc39).
//
// WHY THIS EXISTS (the residual gap `ios-refui-widget-preview-lifecycle-pause` honestly left open).
// The widget-preview play-gate (`PreviewPlaybackController`, CarouselCardView.swift) already pauses on
// the two axes the SDK can detect on its own: (1) app background
// (`UIApplication.didEnterBackgroundNotification`) and (2) off-screen (`GeometryReader` +
// `.frame(in: .global)` ∩ `UIScreen.main.bounds`). It cannot detect ONE case from the widget layer:
// "tab-cover" — the host keeps the widget-hosting screen mounted, the cards stay laid-out, their global
// frame still overlaps the screen, the app stays active, but another route (most typically a
// full-screen live player overlay) simply COVERS them. In that case `GeometryReader` still reports the
// card on-screen (coordinates are still inside the screen — z-order coverage is invisible to layout),
// and the app never backgrounds — so BOTH self-sufficient gates fail, and the N home previews keep
// decoding at full speed ON TOP OF the full-screen player that is covering them (N+1 simultaneous
// decoders → the same ~150% CPU / heat the background fix removed, now in the foreground). Only the
// host's navigation layer knows it covered the widgets; the embedded view has no self-sufficient
// channel — the same platform/architecture limit as PiP.
//
// This bridge is that opt-in host signal. The host declares whether the widget-hosting screen is
// currently covered; each mounted `LoopingPlayerUIView` subscribes and folds it into the play-gate's
// THIRD axis `notCovered`.
//
//   // Host: when a full-screen player overlay covers the home widgets, and when it is dismissed.
//   LiveBuyWidgetVisibility.setWidgetsCovered(true)   // covered → underlying previews pause
//   LiveBuyWidgetVisibility.setWidgetsCovered(false)  // uncovered → resume (still gated by fg / on-screen)
//
// BACKWARD COMPATIBLE: a host that never calls `setWidgetsCovered` leaves `notCovered == true`, so the
// play-gate degrades to the existing `foreground && onScreen` and behaviour is byte-identical to before
// this bridge existed. The residual "covered but not paused" gap therefore STILL EXISTS when the host
// does not opt in — the SDK only provides the entry point, it does NOT claim to cover this on its own
// (covered detection is the host's responsibility).
//
// STATEFUL LEVEL, NOT A ONE-SHOT EDGE (the key structural difference from a stateless PiP-style edge
// bridge): "covered" is a persistent visibility level. A preview that mounts DURING a covered period
// (e.g. the full-screen player is already open and the home rebuilds a card underneath) must learn the
// CURRENT covered state immediately so it does not start playing. Hence this singleton STORES `covered`
// and `register` REPLAYS the current value to the newly-mounted listener. `setWidgetsCovered` is
// edge-triggered (fan-out only when the value actually changes, never churned).
//
// TOKEN-BASED REGISTRATION (the one iOS-vs-Android structural difference): Swift closures have no
// identity — they cannot go into a `Set` and cannot be removed by `==`. So `register` returns a `UUID`
// token and stores listeners in a `[UUID: (Bool) -> Void]`; `LoopingPlayerUIView` keeps the token and
// `unregister(token)`s on teardown / deinit. (Android stores `(Boolean) -> Unit` in a `Set` and removes
// by reference.)
//
// MAIN-THREAD-ONLY contract (host calls on the main thread; views register/unregister on the main
// thread), so NO locking. Fan-out iterates a snapshot (`Array(listeners.values)`) so a listener that
// registers/unregisters during fan-out cannot mutate the collection mid-iteration.
//
// This is a DISTINCT type from the pre-existing `WidgetVisibility` (which hides urlless lives) — same
// package, different concern, they do not interact.

/// Opt-in host→SDK bridge letting the host declare when the widget-hosting screen is covered by another
/// destination (e.g. a full-screen player overlay), so the underlying widget previews pause even though
/// the SDK's two self-sufficient axes (app-foreground + on-screen) cannot detect the z-order coverage.
public final class LiveBuyWidgetVisibility {

    /// The process-wide shared bridge. Widget previews subscribe to it; the host feeds it.
    public static let shared = LiveBuyWidgetVisibility()

    private init() {}

    /// The current covered level (stateful — replayed to newly-registered listeners).
    private var covered = false

    /// Registered listeners, keyed by an opaque token (Swift closures have no identity → cannot use a
    /// `Set` / `==` removal, unlike Android's `(Boolean) -> Unit` set).
    private var listeners: [UUID: (Bool) -> Void] = [:]

    // MARK: Host-facing API

    /// Host declares whether the screen hosting the LiveBuy widget previews is currently covered
    /// (`true` = covered by another destination / full-screen overlay, invisible to the user). Stateful
    /// + edge-triggered: the value is stored and fanned out to subscribers ONLY when it changes.
    /// Main-thread-only.
    public func setWidgetsCovered(_ covered: Bool) {
        guard self.covered != covered else { return }   // edge-triggered: no churn on same value
        self.covered = covered
        // Snapshot fan-out: a listener may register/unregister during delivery.
        for listener in Array(listeners.values) { listener(covered) }
    }

    /// Convenience static entry so host call sites read `LiveBuyWidgetVisibility.setWidgetsCovered(...)`,
    /// mirroring Android's `object` static call.
    public static func setWidgetsCovered(_ covered: Bool) {
        shared.setWidgetsCovered(covered)
    }

    // MARK: Internal subscription (LoopingPlayerUIView)

    /// Subscribe a listener and IMMEDIATELY replay the current covered level to it (so a widget mounted
    /// during a covered period pauses at once — the stateful-level core invariant that separates this
    /// from a one-shot edge bridge). Returns an opaque token for `unregister`.
    @discardableResult
    func register(_ listener: @escaping (Bool) -> Void) -> UUID {
        let token = UUID()
        listeners[token] = listener
        listener(covered)   // ★ replay current level to the late-mounting widget
        return token
    }

    /// Remove a previously-registered listener. Unknown token → safe no-op.
    func unregister(_ token: UUID) {
        listeners.removeValue(forKey: token)
    }

    /// Test-only reset: drop all listeners and clear covered back to `false`.
    func resetForTesting() {
        listeners.removeAll()
        covered = false
    }
}
