import LivebuySDK

// MARK: - DefaultErrorState — Player error-state host-bindable exposure
//
// Spec: `ui-template-foundation/spec.md`
//   § "Default Template Player Error-State 暴露"
// Design: design.md Decision 3 / Decision 4.
//
// Behaviour / view-model layer ONLY (no pixels). core stays headless: it owns
// the player state machine, the `LBError` classification, and the 3×/3s HLS
// retry. This model maps the core's `error(LBError)` + `stateChange(error)`
// into a host-bindable `{ kind, phase }` so the host can draw `moments.jsx`'s
// `LBPErrorScreen`. The template never renders the error screen itself.

/// Host-bindable error category for `LBPErrorScreen`. Mirrors the design's three
/// error visuals; the host picks copy / artwork per kind.
public enum LBPlayerErrorKind: Equatable {
    /// Stream / playback failure — also the GENERIC bucket for any `LBError`
    /// not otherwise mapped (`.networkError` / `.restricted` / `.invalidSignature` / …).
    case stream
    /// `.videoNotFound` — the video does not exist / was removed.
    case notFound
    /// `.sdkVersionUnsupported` — this SDK build is no longer accepted (426).
    case outdated
}

/// Error lifecycle phase. Only `failed` (terminal) is in scope for this
/// capability — `retrying` is NOT exposed by core (retries stay `buffering`),
/// so it is deferred to a follow-up core change (see proposal Follow-up).
public enum LBPlayerErrorPhase: Equatable {
    case failed
}

/// One host-bindable error snapshot. nil when the player is not in `error`.
public struct LBPlayerErrorState: Equatable {
    public let kind: LBPlayerErrorKind
    public let phase: LBPlayerErrorPhase

    public init(kind: LBPlayerErrorKind, phase: LBPlayerErrorPhase) {
        self.kind = kind
        self.phase = phase
    }
}

/// Maps core player error → host-bindable error-state. The owning
/// `DefaultPlayerTemplate` feeds it `recordError` (from `vc.onError`) and
/// `handleStateChange` (from `vc.onStateChange`); the host reads `current` and
/// observes the template's `onChange`.
public final class DefaultErrorState {

    /// Current error snapshot, or nil when the player is not in `error`.
    private(set) public var current: LBPlayerErrorState?

    /// Internal coalesced "error-state mutated" hook → owning template's single
    /// host-facing `onChange`. NOT public (host observes via `onChange`).
    var onMutation: (() -> Void)?

    public init() {}

    /// Record a terminal player error (driven by core `error(LBError)`). Always
    /// `phase = .failed`; `kind` per the mapping table.
    func recordError(_ error: LBError) {
        current = LBPlayerErrorState(kind: Self.kind(for: error), phase: .failed)
        onMutation?()
    }

    /// React to a player state change (canonical name). When an error is shown
    /// and the player LEAVES `error` (host called `Player.load(videoId)` → core
    /// transitions out of error), clear the error-state and notify so the host
    /// dismisses `LBPErrorScreen`. No-op while not in error / still in error.
    func handleStateChange(_ canonicalName: String) {
        guard current != nil, canonicalName != "error" else { return }
        current = nil
        onMutation?()
    }

    /// Explicit reset (e.g. release / new video). One mutation, one notify.
    public func clear() {
        guard current != nil else { return }
        current = nil
        onMutation?()
    }

    /// Pure mapping `LBError` → `kind` (design Decision 3 / spec table).
    /// `.signatureExpired` was removed from core in the backend-contract fix
    /// batch, so it is no longer mapped. Anything not listed falls back to
    /// `.stream` (generic playback failure).
    static func kind(for error: LBError) -> LBPlayerErrorKind {
        switch error {
        case .videoNotFound:
            return .notFound
        case .sdkVersionUnsupported:
            return .outdated
        case .networkError, .restricted, .invalidSignature:
            return .stream
        default:
            return .stream
        }
    }
}
