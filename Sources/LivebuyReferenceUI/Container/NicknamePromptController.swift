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
// `isSubmitting` / `errorMessage` (rb-ios-nickname-taken-inline-error): the drop-in container's
// `onNicknameSubmit` now round-trips core's verified `setGuestNicknameVerified(_:)` (async
// `checkName` against this video's chat namespace) INSTEAD OF the old fire-and-forget
// `Livebuy.setGuestNickname` — so a duplicate name can be rejected INLINE, at set time, instead of
// silently accepted (the user problem this solves: "暱稱重複沒有出現錯誤，後續留言才會報錯"). These
// two published fields are the「送出中 / 這次失敗了嗎、失敗原因」snapshot values
// `GuestNameEditModalView` reads BY VALUE (same SUB-VIEW INPUT PATTERN as `displayName` /
// `isLoggedIn`) — this controller is the "view-model" that owns them; the view itself never
// mutates them. `beginSubmit()` / `failSubmit(message:)` are the only mutators the container calls;
// `present(...)` / `dismiss()` always reset both (`resetSubmitState()`) so a fresh open, or leaving
// the modal, never leaks a stale error / spinner into the next presentation.
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

    /// A pending「加入活動」(event-join) intent the NICKNAME gate deferred (rb-ios-event-join-gate):
    /// when a未設名訪客 taps 加入活動, the container records the join's `(eid, keyword)` HERE and
    /// presents this modal; a successful submit then completes that ONE join (bypassing the gate).
    /// `nil` when the modal was NOT opened for a pending join (直接暱稱編輯 / 留言 pill). Cleared by
    /// `dismiss()` (取消 / 關閉 → 不 join) and by `present(composeAfter:)` (mutually-exclusive entry).
    /// NOT `@Published` (like `composeAfterSubmit`) → never triggers a re-render → snapshot-neutral.
    public private(set) var pendingJoinEvent: (eid: Int, keyword: String)?

    /// Whether a `setGuestNicknameVerified` round-trip is currently in flight
    /// (rb-ios-nickname-taken-inline-error). Drives `GuestNameEditModalView.isSubmitting`
    /// (locks the CTA + shows a spinner). Mutated only by `beginSubmit()` / `failSubmit(message:)`
    /// / `resetSubmitState()`.
    @Published public private(set) var isSubmitting = false

    /// Monotonically-increasing PRESENTATION GENERATION (rb-ios-nickname-taken-inline-error).
    ///
    /// The verified set is an async round-trip, so its continuation can land AFTER the presentation
    /// it belongs to is already over. Without a generation stamp the continuation would mutate
    /// whatever state happens to be current, which is a REAL, reproducible defect:
    ///
    ///     送出（in-flight）→ 使用者點 scrim dismiss() → 使用者重新開啟 modal → 舊請求這時才完成
    ///
    /// …would let the stale request (a) `dismiss()` a modal the user is actively typing in,
    /// (b) read the NEW presentation's `composeAfterSubmit` and open the composer unasked,
    /// (c) CONSUME the NEW presentation's `pendingJoinEvent` and forward a join the user never
    /// submitted, or (d) `failSubmit` a stale error onto a brand-new presentation — exactly the
    /// picture the「每次重新呈現皆從乾淨的送出狀態開始」requirement exists to prevent. It would also
    /// let a stale failure clear a NEWER in-flight submit's `isSubmitting`, unlocking the CTA early.
    ///
    /// Every `present(...)` AND `dismiss()` bumps this counter, so any submit that started in an
    /// earlier generation is detectably stale. `beginSubmit()` returns the generation its submit
    /// belongs to; the continuation MUST gate on `isCurrentGeneration(_:)` and abandon the WHOLE
    /// continuation (no dismiss, no failSubmit, no pendingJoin consumption, no composer) on mismatch.
    ///
    /// NOT `@Published` — it never affects rendering, so bumping it MUST NOT trigger a re-render.
    public private(set) var presentationGeneration: Int = 0

    /// The most recent submit failure's user-facing message, or `nil` when there is none — either
    /// nothing has been submitted yet, or the last submit succeeded (rb-ios-nickname-taken-inline-error).
    /// Drives `GuestNameEditModalView.errorMessage` (an inline red row below the input). Set by
    /// `failSubmit(message:)`; cleared by `beginSubmit()` / `resetSubmitState()`.
    @Published public private(set) var errorMessage: String?

    public init() {}

    /// Show the 設定暱稱 modal. `composeAfter == true` → after a successful submit the
    /// container opens the chat composer (the 留言 pill entry); `false` → submit just dismisses.
    /// Clears any pending event-join intent — the 留言 pill / 暱稱鈕 entry is mutually exclusive
    /// with the 加入活動 entry (rb-ios-event-join-gate). Also resets any leftover submit-in-flight /
    /// error state from a PREVIOUS presentation (rb-ios-nickname-taken-inline-error) — a fresh open
    /// always starts clean, never showing a stale error from an earlier attempt.
    public func present(composeAfter: Bool) {
        composeAfterSubmit = composeAfter
        pendingJoinEvent = nil
        resetSubmitState()
        presentationGeneration &+= 1
        isPresented = true
    }

    /// Show the 設定暱稱 modal to satisfy a PENDING「加入活動」join gate (rb-ios-event-join-gate):
    /// records the join's `eid` / `keyword` so a successful submit completes that ONE join; sets
    /// `composeAfterSubmit = false` (this entry does NOT hand off to the composer). Also resets
    /// submit-in-flight / error state (see `present(composeAfter:)`).
    public func present(pendingJoin eid: Int, keyword: String) {
        composeAfterSubmit = false
        pendingJoinEvent = (eid, keyword)
        resetSubmitState()
        presentationGeneration &+= 1
        isPresented = true
    }

    /// Hide the 設定暱稱 modal (scrim tap / close / after a successful submit). Also clears any
    /// pending event-join intent so a cancelled / closed modal NEVER joins after the fact
    /// (rb-ios-event-join-gate); the submit continuation reads `pendingJoinEvent` BEFORE calling
    /// `dismiss()`. Also resets submit-in-flight / error state (rb-ios-nickname-taken-inline-error)
    /// so the NEXT presentation never inherits a stale spinner / error from this one.
    public func dismiss() {
        isPresented = false
        pendingJoinEvent = nil
        resetSubmitState()
        // Bump too: leaving the modal ENDS this presentation, so an in-flight submit started before
        // the dismiss MUST NOT be allowed to act on whatever comes next (see `presentationGeneration`).
        presentationGeneration &+= 1
    }

    /// Mark a `setGuestNicknameVerified` attempt as in-flight (rb-ios-nickname-taken-inline-error):
    /// locks the modal's CTA and clears any error left over from a PREVIOUS attempt in the SAME
    /// presentation (a retry should not show the old message while the new attempt is running). The
    /// container calls this synchronously, right before starting the async submit.
    ///
    /// Returns the PRESENTATION GENERATION this submit belongs to; the container MUST carry that
    /// value into the async continuation and gate on `isCurrentGeneration(_:)` before touching any
    /// state (see `presentationGeneration` for the defect this prevents).
    @discardableResult
    public func beginSubmit() -> Int {
        isSubmitting = true
        errorMessage = nil
        return presentationGeneration
    }

    /// Whether `generation` (captured by `beginSubmit()`) is still the CURRENT presentation — i.e.
    /// whether an async submit continuation is still allowed to act. `false` once the modal has been
    /// dismissed or re-presented since that submit started.
    public func isCurrentGeneration(_ generation: Int) -> Bool {
        generation == presentationGeneration
    }

    /// Record a `setGuestNicknameVerified` attempt's failure (rb-ios-nickname-taken-inline-error):
    /// clears the in-flight flag and sets the message the modal should show. Does NOT dismiss — the
    /// guest stays in the modal, free to edit the field and retry. The container computes `message`
    /// via the pure `nicknameSubmitErrorMessage(for:)` (distinguishes `LBError.guestNameTaken` from
    /// any other error — see `LivebuyPlayer.swift`) so this controller stays copy-agnostic.
    public func failSubmit(message: String) {
        isSubmitting = false
        errorMessage = message
    }

    /// Shared reset for `isSubmitting` / `errorMessage` — called by every entry/exit point
    /// (`present(...)` / `dismiss()`) so the two fields can never drift out of sync with each other.
    private func resetSubmitState() {
        isSubmitting = false
        errorMessage = nil
    }
}
