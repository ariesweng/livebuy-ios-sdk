import SwiftUI

// MARK: - On-demand chat-send input bar (turnkey composer, promoted from Example)
//
// The reference-ui `ChatFeedView` only DISPLAYS the merged chat/activity feed; it has
// no composer, and the design's `LBLiveBottomBar`「留言...」pill is a TAP-TARGET that
// is meant to OPEN a composer (not an inline field). This bar is that composer: hidden
// until the pill raises `onComment` → `ChatComposerController.open()`, which presents +
// focuses it. It forwards a sent message to `onSend` (the container wires this to the
// bound template's `sendChat(_:)` → core `sendChat`); a guest send that needs login
// surfaces AUTH_REQUIRED, which the host listener handles (and the SDK replays the chat
// on setUser). It adds no core/template code — only this pixel composer.
//
// It is a TRUE reference-ui pixel surface (design D-5): the「留言...」pill's input panel.
// It lived in the Example only by historical accident; `introduce-dropin-player-container`
// promotes it into the package so the drop-in container is turnkey.
//
// iOS-14-safe focus: SwiftUI `TextField` can't be focused programmatically before iOS 15 /
// `@FocusState`, so the field is a `FocusableTextField` (UIViewRepresentable over
// `UITextField`) that becomes first responder when `controller.focusToken` changes.

/// Presentation + focus state for the on-demand chat composer. `open()` shows the bar
/// and bumps `focusToken` (→ the field becomes first responder); `close()` hides it.
///
/// Public because it is the parameter type of the public `LivebuyPlayerConfig.onComment`
/// override: a host that customizes「留言...」still receives this controller so it can
/// drive (or defer to) the same composer presentation.
public final class ChatComposerController: ObservableObject {
    @Published public var isPresented = false
    /// Monotonic focus request counter — `FocusableTextField` focuses when it changes.
    @Published public var focusToken = 0

    public init() {}

    /// Show the composer and request focus (the LIVE「留言...」pill's default action).
    public func open() {
        isPresented = true
        focusToken += 1
    }

    /// Hide the composer (e.g. after a send / when the field ends editing).
    public func close() {
        isPresented = false
    }
}

/// The on-demand「留言...」input bar. Internal: the container composes it inside
/// `PlayerOverlayRootView`; hosts drive it via `ChatComposerController` rather than
/// instantiating the bar directly.
public struct ChatComposerBar: View {

    /// Presentation/focus state — driven by the LIVE「留言...」pill's `onComment`.
    @ObservedObject var controller: ChatComposerController
    /// Resolved reference-ui theme (accent for the send glyph / caret).
    let theme: ReferenceUITheme
    /// Forward the trimmed comment to the host (→ `template.sendChat`). The field is
    /// cleared and the bar hidden after a send.
    let onSend: (String) -> Void

    @State private var text = ""

    /// Public init — same shape as the synthesized memberwise init (so the internal
    /// composition keeps compiling), exposed so a host / QA gallery can mount the
    /// composer like the public reference-ui surfaces.
    public init(controller: ChatComposerController,
                theme: ReferenceUITheme,
                onSend: @escaping (String) -> Void) {
        self._controller = ObservedObject(wrappedValue: controller)
        self.theme = theme
        self.onSend = onSend
    }

    /// Non-empty (after trimming) → the send button is enabled / return submits.
    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var body: some View {
        // On-demand: shown only after the design's「留言...」pill opens it. VOD has no
        // pill (side rail), so the composer never opens there.
        // QA / demo hook: launch with `SIMCTL_CHILD_LB_QA_FORCE_CHAT_BAR=1` to force the
        // bar visible for headless screenshot verification (no on-device tap automation).
        if controller.isPresented || ProcessInfo.processInfo.environment["LB_QA_FORCE_CHAT_BAR"] == "1" {
            VStack(spacing: 0) {
                // Tap-to-dismiss layer (mirrors the modals' scrim-tap): while the composer
                // is presented, tapping ABOVE the bar resigns the keyboard and closes the
                // bar WITHOUT sending — the "不留言返回" exit. Transparent (no dim) so the
                // video stays visible. Capturing these taps while typing is intended (you
                // should not toggle mute mid-type); when NOT presented the whole body is
                // `EmptyView`, so chrome taps fall through normally (no regression).
                Button(action: dismissWithoutSending) {
                    Color.clear.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier(LBAccessibilityID.chatComposerDismiss)
                composer
            }
        }
    }

    private var composer: some View {
        HStack(spacing: 8) {
            // Live editable composer — dark translucent pill + accent send glyph.
            FocusableTextField(
                text: $text,
                placeholder: "留言...",
                accent: UIColor(theme.accent),
                focusToken: controller.focusToken,
                onSubmit: send,
                onEndEditing: { controller.close() })
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14)
                .frame(height: 36)
                // Solid input field on the opaque bar (was a 0.55 translucent pill that
                // let the video show through) — rb-ios-chat-composer-opaque-hide-bottom-bar.
                .background(Capsule().fill(Self.inputFieldFill))
                .accessibilityIdentifier(LBAccessibilityID.chatComposer)

            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundColor(canSend ? theme.accent : Color.white.opacity(0.35))
            }
            .disabled(!canSend)
            .accessibilityIdentifier(LBAccessibilityID.chatSend)
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 10)
        // Opaque solid bar (was a 0.55→clear gradient scrim that let the video show
        // through). Reuses the chrome's `rgba(20,20,24)` charcoal at full opacity so the
        // composer reads as a solid input bar (rb-ios-chat-composer-opaque-hide-bottom-bar).
        .background(Self.barFill.edgesIgnoringSafeArea(.bottom))
    }

    /// Opaque composer bar fill (chrome charcoal `rgb(20,20,24)`, no透明度).
    private static let barFill = Color(.sRGB, red: 20 / 255, green: 20 / 255, blue: 24 / 255, opacity: 1)
    /// Solid input-field fill — a lighter shade so the field reads clearly on the opaque bar.
    private static let inputFieldFill = Color(white: 0.18)

    private func send() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSend(trimmed)
        text = ""
        // Dismiss the keyboard; the field's end-editing callback then hides the bar.
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    /// "不留言返回": resign the keyboard and close the bar WITHOUT sending. The field's
    /// `onEndEditing` also calls `close()` when it resigns, but we call it directly too so
    /// the no-focus (QA-force) path still hides the bar (idempotent). `onSend` is never
    /// called, so no message is sent.
    private func dismissWithoutSending() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        controller.close()
    }
}

// MARK: - FocusableTextField (iOS-14-safe programmatic focus)
//
// SwiftUI `TextField` cannot be focused programmatically before iOS 15 (`@FocusState`),
// so the on-demand composer wraps a `UITextField`. It becomes first responder whenever
// `focusToken` changes (the pill's `onComment` bumps it), submits on return, and reports
// end-editing so the host can hide the bar.
struct FocusableTextField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let accent: UIColor
    /// Bumped by the controller to request focus; a change triggers `becomeFirstResponder`.
    let focusToken: Int
    let onSubmit: () -> Void
    let onEndEditing: () -> Void

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.font = .systemFont(ofSize: 13)
        field.textColor = .white
        field.tintColor = accent
        field.returnKeyType = .send
        field.autocorrectionType = .no
        field.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: UIColor.white.withAlphaComponent(0.5)])
        field.addTarget(context.coordinator,
                        action: #selector(Coordinator.editingChanged(_:)),
                        for: .editingChanged)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        if field.text != text { field.text = text }
        field.tintColor = accent
        // Focus only when a NEW focus request arrived (token changed to a positive value).
        if focusToken > 0 && context.coordinator.lastFocusToken != focusToken {
            context.coordinator.lastFocusToken = focusToken
            DispatchQueue.main.async { field.becomeFirstResponder() }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        private let parent: FocusableTextField
        var lastFocusToken = 0
        init(_ parent: FocusableTextField) { self.parent = parent }

        @objc func editingChanged(_ field: UITextField) { parent.text = field.text ?? "" }

        func textFieldShouldReturn(_ field: UITextField) -> Bool {
            parent.onSubmit()
            return false
        }

        func textFieldDidEndEditing(_ field: UITextField) { parent.onEndEditing() }
    }
}
