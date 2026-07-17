import SwiftUI

// MARK: - NicknamePromptController — on-demand 設定暱稱 modal presentation state
//
// The reference-ui `GuestNameEditModalView` (family-6 gap-surface) is a complete pixel
// surface but was only ever composed by `GapSurfacesOverlayView` — the drop-in container's
// `PlayerOverlayRootView` never included it, so the LIVE bottom bar's暱稱 button (and the
// 留言 pill's "set a nickname first" flow) had no modal to present.
//
// This controller is that presentation state — the nickname-modal analogue of
// `ChatComposerController`. The container composes `GuestNameEditModalView` gated on
// `isPresented` (default `false` → snapshot-neutral); the bottom bar's暱稱 tap and the
// 留言 pill's未設定-暱稱 branch call `present(...)`; a scrim tap / submit calls `dismiss()`.
//
// `composeAfterSubmit` carries the ENTRY intent: when the modal is opened FROM the 留言 pill
// (the guest must set a nickname before commenting), submitting should hand off to the chat
// composer; when opened from the暱稱 button directly, it should just dismiss. The container
// reads this flag in its default `onNicknameSubmit` to decide whether to open the composer.
//
// iOS-14-safe: `ObservableObject` + `@Published` are iOS-13+.

/// Presentation state for the on-demand 設定暱稱 modal. `present(composeAfter:)` shows the
/// modal and records whether to open the chat composer after a successful submit;
/// `dismiss()` hides it.
public final class NicknamePromptController: ObservableObject {

    /// Whether the 設定暱稱 modal is currently presented. Default `false` (snapshot-neutral).
    @Published public var isPresented = false

    /// Whether a successful submit should hand off to the chat composer. `true` when the
    /// modal was opened from the 留言 pill (set-a-nickname-then-comment); `false` when opened
    /// from the暱稱 button directly. Read by the container's default `onNicknameSubmit`.
    public private(set) var composeAfterSubmit = false

    public init() {}

    /// Show the 設定暱稱 modal. `composeAfter == true` → after a successful submit the
    /// container opens the chat composer (the 留言 pill entry); `false` → submit just dismisses.
    public func present(composeAfter: Bool) {
        composeAfterSubmit = composeAfter
        isPresented = true
    }

    /// Hide the 設定暱稱 modal (scrim tap / close / after submit).
    public func dismiss() {
        isPresented = false
    }
}
