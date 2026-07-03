import SwiftUI
import LiveBuyUI

// MARK: - LoginPromptController — on-demand「請先登入」modal presentation state (triggerAction-driven)
//
// The drop-in container's `PlayerOverlayRootView` does NOT compose the AUTH_REQUIRED-driven
// `GapSurfacesOverlayView` (that surface is for hosts who assemble their own overlay), and the
// core's comment-send path surfaces `chatRequiresLogin` only AFTER a send (reactive). So a
// `guest_comment == 0` live had no proactive login prompt in the turnkey container.
//
// This controller is that presentation state — the login-modal analogue of
// `NicknamePromptController` (rb-ios-live-comment-login-gate, 方案 A). When a guest taps the LIVE
// 留言 pill on a `chatEnabled == false` live, the container's default `onComment` calls `present()`
// and composes `AuthGateModalView(.commentSend)` gated on `isPresented` (default `false` →
// snapshot-neutral). 前往登入 routes to the host's `config.onLogin` (reference-ui NEVER logs in
// itself); 稍後再說 / scrim / a successful login calls `dismiss()`.
//
// iOS-14-safe: `ObservableObject` + `@Published` are iOS-13+.

/// Presentation state for the on-demand「請先登入」modal raised by the LIVE 留言 login gate.
/// `present()` shows the modal; `dismiss()` hides it.
public final class LoginPromptController: ObservableObject {

    /// Whether the「請先登入」modal is currently presented. Default `false` (snapshot-neutral).
    @Published public var isPresented = false

    /// Which interaction raised the modal — drives `AuthGateModalView`'s body copy per kind. The
    /// container sets it via `present(triggerAction:)`; the composed modal reads it dynamically so
    /// ONE controller serves every gate (留言 → `.commentSend`, 訂閱 → `.subscribe`, …). Default
    /// `.commentSend` (the original gate) keeps the existing 留言 gate behaviour unchanged.
    @Published public var triggerAction: LBAuthTriggerAction = .commentSend

    public init() {}

    /// Show the「請先登入」modal for the given trigger. Default `.commentSend` (the 留言 pill's
    /// guest + `guest_comment == 0` branch) so existing call sites need no change; 訂閱 gate passes
    /// `.subscribe`.
    public func present(triggerAction: LBAuthTriggerAction = .commentSend) {
        self.triggerAction = triggerAction
        isPresented = true
    }

    /// Hide the「請先登入」modal (前往登入 hand-off / 稍後再說 / scrim).
    public func dismiss() {
        isPresented = false
    }
}
