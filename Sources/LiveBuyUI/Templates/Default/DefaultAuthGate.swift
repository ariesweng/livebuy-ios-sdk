import LiveBuySDK

// MARK: - DefaultAuthGate / DefaultIdentityLabel — auth host-bindable exposure
//
// Spec: `ui-template-foundation/spec.md`
//   § "Default Template Auth-Gate 狀態暴露"
//   § "Default Template Identity-Label 狀態暴露"
// Design: design.md Decision 2 / Decision 3.
//
// Behaviour / view-model layer ONLY (no pixels). core stays headless: it owns
// `AUTH_REQUIRED` / `AUTH_STATE_CHANGED`, the `PendingAuthStore`, and the 30s
// replay. These models map the two events into host-bindable state so the host
// can draw its own login prompt / identity label. The template renders nothing.

/// Host-bindable trigger category behind an un-intercepted `AUTH_REQUIRED`.
/// The host picks copy per kind. `other` is the forward-compatible bucket for
/// any future `trigger_action` string (NEVER throws).
public enum LBAuthTriggerAction: Equatable {
    case cartAdd
    case commentSend
    case couponClaim
    case other
}

/// One host-bindable「請先登入」snapshot. nil until the first un-intercepted
/// `AUTH_REQUIRED`. `productId` / `videoId` are nil when the wire omits them.
public struct LBAuthGateState: Equatable {
    public let triggerAction: LBAuthTriggerAction
    public let productId: String?
    public let videoId: String?

    public init(triggerAction: LBAuthTriggerAction, productId: String?, videoId: String?) {
        self.triggerAction = triggerAction
        self.productId = productId
        self.videoId = videoId
    }
}

/// Maps the core's un-intercepted `AUTH_REQUIRED` → host-bindable auth-gate
/// state. Single value (latest overwrites; not a queue). Cleared on login or
/// host-dismiss. The owning `DefaultPlayerTemplate` feeds `recordRequired`
/// (from the aux listener) and `clearOnLogin` (on `AUTH_STATE_CHANGED`).
public final class DefaultAuthGate {

    /// Current「請先登入」snapshot, or nil when no prompt is pending.
    private(set) public var current: LBAuthGateState?

    /// Internal coalesced "auth-gate mutated" hook → owning template's single
    /// host-facing `onChange`. NOT public (host observes via `onChange`).
    var onMutation: (() -> Void)?

    public init() {}

    /// Pure `trigger_action` → `LBAuthTriggerAction` (forward compatible).
    public static func triggerAction(from raw: String) -> LBAuthTriggerAction {
        switch raw {
        case "cart_add":     return .cartAdd
        case "comment_send": return .commentSend
        case "coupon_claim": return .couponClaim
        default:             return .other
        }
    }

    /// Record an un-intercepted `AUTH_REQUIRED` as the latest auth-gate state.
    /// `hostIntercepted == true` (host primary returned true) → EXCLUDE: no
    /// state. Latest single value overwrites the prior one (not a queue).
    func recordRequired(params: [String: Any], hostIntercepted: Bool) {
        guard !hostIntercepted else { return }
        current = LBAuthGateState(
            triggerAction: Self.triggerAction(from: params["trigger_action"] as? String ?? ""),
            productId: params["product_id"] as? String,
            videoId: params["video_id"] as? String)
        onMutation?()
    }

    /// Login succeeded (`AUTH_STATE_CHANGED.state == logged_in`) → prompt gone.
    func clearOnLogin() {
        guard current != nil else { return }
        current = nil
        onMutation?()
    }

    /// Host-dismiss the prompt (symmetric with `DefaultErrorState.clear()`).
    public func clear() {
        guard current != nil else { return }
        current = nil
        onMutation?()
    }

    /// Named alias for `clear()` per spec OQ1 (`clearAuthGate`).
    public func clearAuthGate() { clear() }
}

// MARK: - DefaultIdentityLabel

/// One host-bindable identity snapshot for `PlayerHeader` / `ChatView`. nil
/// until the first `AUTH_STATE_CHANGED` (template MUST NOT seed from configure).
public struct LBIdentityLabel: Equatable {
    public let displayName: String
    public let isLoggedIn: Bool

    public init(displayName: String, isLoggedIn: Bool) {
        self.displayName = displayName
        self.isLoggedIn = isLoggedIn
    }
}

/// Maps the core's `AUTH_STATE_CHANGED` → host-bindable identity-label state.
/// `resumed_action` is NEVER stored (Non-Goal). The owning template feeds
/// `update(state:displayName:)` from the aux listener.
public final class DefaultIdentityLabel {

    /// Current identity snapshot, nil until the first `AUTH_STATE_CHANGED`.
    private(set) public var current: LBIdentityLabel?

    /// Internal coalesced "identity-label mutated" hook → owning template's
    /// single host-facing `onChange`. NOT public.
    var onMutation: (() -> Void)?

    public init() {}

    /// `logged_in` → `{displayName, true}`; `logged_out` → `{displayName, false}`
    /// (fallback "" when `display_name` absent); any other state → isLoggedIn=false.
    func update(state: String, displayName: String?) {
        let name = displayName ?? ""
        current = LBIdentityLabel(displayName: name, isLoggedIn: state == "logged_in")
        onMutation?()
    }
}
