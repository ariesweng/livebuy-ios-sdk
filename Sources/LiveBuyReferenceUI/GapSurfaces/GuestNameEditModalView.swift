import SwiftUI
import LivebuySDK
import LivebuyUI

// MARK: - GuestNameEditModalView — family-6 gap-surface 4 (guest nickname-edit modal)
//
// Spec: `reference-ui-rendering/spec.md` (family-6 gap-surfaces — the LAST iOS
//        Phase-1 family closing out the four "gap" surfaces).
// Design: `design/templates/minimal/live-chrome.jsx` `LiveNicknameModal`
//          (≈388-443) + `design/templates/minimal/sdk-components.jsx`
//          `LBPAlertModal` (centered card + 0.55 scrim + soft shadow) /
//          `LBPButton` primary.
//
// The guest nickname-edit modal — the guest 態 rename affordance. It reads the
// identity label (current display name + whether the user is logged in) bridged by
// `GapSurfacesModel` and lets a guest set a留言暱稱 (≤ 10 chars). It is the fourth
// of the four family-6 gap-surface sub-views composed by `GapSurfacesOverlayView`,
// and it implements the agreed SUB-VIEW INPUT PATTERN (shared with every family
// surface — see `ProductDetailSheetView.swift` / `GapSurfacesModel.swift`):
//
//   1. `theme: ReferenceUITheme`            — FIRST positional argument, always.
//   2. bound SNAPSHOT VALUES               — `displayName: String`,
//      `isLoggedIn: Bool` — passed BY VALUE from `GapSurfacesModel` (never the
//      model, never the template).
//   3. action closures (LAST, each `= nil`) — `onRequestEdit` (the core rename
//      ENTRY exit → `model.requestGuestNameEdit()` → `template.requestGuestNameEdit()`,
//      emits `GUEST_NAME_EDIT_REQUEST`; the CONTAINER wires the ENTRY — e.g.
//      tapping the current name elsewhere — so this stored closure is kept even
//      though it is not visually triggered INSIDE the modal), `onSubmit` (送出 →
//      host-wired new-name fulfilment via `LivebuySDK.setUser`), `onDismiss`
//      (scrim tap / close → clears the container's presentation binding).
//
// This sub-view reads ONLY its passed-in values; it never reaches back into
// `GapSurfacesModel` / `DefaultPlayerTemplate` (one-way data flow). It also renders
// correctly with all actions nil (so demo / snapshot tests construct it
// action-free).
//
// reference-ui NEVER calls core directly: the 送出 CTA funnels to `onSubmit`, which
// the container fulfils via `LivebuySDK.setUser`; the「請求改名」passthrough intent
// funnels to `onRequestEdit`, which the container wires to
// `model.requestGuestNameEdit()`.
//
// iOS-14-safe SwiftUI only. `VStack` / `HStack` / `ZStack` / `Text` / `Button` /
// `RoundedRectangle` / `Circle` / `Color` / `Image(systemName:)` / `TextField` are
// all iOS-13+. NO `ScrollView` / `LazyVStack` / `LazyHStack` / `LazyVGrid` — the
// reference-ui snapshot path (SwiftUI `ImageRenderer`) renders those BLANK. No
// `.task` / `AsyncImage` / `NavigationStack` / `.foregroundStyle` / `.tint` /
// SwiftUI `Toggle`.

/// The family-6 guest nickname-edit modal. Renders a full-bleed dim scrim, a
/// centered card with a floating logo badge, the「設定暱稱」title + subtitle, a
/// nickname input row (clamped to 10 chars), and a 送出 CTA that is enabled only
/// while the trimmed buffer is 1...10. The `displayName` / `isLoggedIn` binds give
/// the modal its prefill / context; the actual rename is host-fulfilled via
/// `onSubmit`, and the passthrough「請求改名」entry routes through `onRequestEdit`.
public struct GuestNameEditModalView: View {

    /// The resolved reference-ui theme (FIRST positional argument, always).
    public let theme: ReferenceUITheme

    /// Current display name (`GapSurfacesModel.displayName` ←
    /// `template.identityLabel.current?.displayName`). Read-only — used as
    /// prefill / placeholder context (a guest's `Guest_XXXX` default). The input
    /// buffer is a presentation-only local `@State` (empty on open).
    public let displayName: String
    /// Whether the user is logged in (`GapSurfacesModel.isLoggedIn`). Read-only — a
    /// logged-in user does not need the guest rename affordance; the container only
    /// presents this modal for guests. Kept on the value contract for parity /
    /// context. Read-only.
    public let isLoggedIn: Bool

    /// Whether the nickname field is a LIVE editable `TextField` (runtime default,
    /// `true`) or a STATIC read-only placeholder display (`false`). SwiftUI's
    /// `ImageRenderer` (the reference-ui snapshot path) CANNOT render a live
    /// `TextField` — it paints a yellow「unsupported control」placeholder — so the
    /// `demo(theme:)` snapshot/preview seed sets `editable: false` to render the
    /// design's empty-field placeholder state deterministically. Hosts using the
    /// drop-in at runtime keep the default `true` (a real, typeable field).
    private let isEditable: Bool

    /// Host-wired passthrough「請求改名」ENTRY → `model.requestGuestNameEdit()` →
    /// `template.requestGuestNameEdit()` (emits `GUEST_NAME_EDIT_REQUEST`). The
    /// CONTAINER wires the ENTRY (e.g. tapping the current name elsewhere); this is
    /// stored even though the modal does not visually trigger it from INSIDE, so the
    /// surface keeps the full interaction contract. nil for demo / snapshot instances.
    private let onRequestEdit: (() -> Void)?
    /// Host-wired 送出 → the container fulfils the new name via `LivebuySDK.setUser`.
    /// reference-ui NEVER calls core directly (one-way data flow). Passes the trimmed
    /// nickname. nil for demo / snapshot instances.
    private let onSubmit: ((String) -> Void)?
    /// Host-wired scrim tap / close (clears the container's presentation binding).
    /// nil for demo / snapshot instances.
    private let onDismiss: (() -> Void)?

    public init(
        theme: ReferenceUITheme,
        displayName: String,
        isLoggedIn: Bool,
        onRequestEdit: (() -> Void)? = nil,
        onSubmit: ((String) -> Void)? = nil,
        onDismiss: (() -> Void)? = nil,
        editable: Bool = true
    ) {
        self.theme = theme
        self.displayName = displayName
        self.isLoggedIn = isLoggedIn
        self.onRequestEdit = onRequestEdit
        self.onSubmit = onSubmit
        self.onDismiss = onDismiss
        self.isEditable = editable
    }

    // MARK: - Presentation-only input buffer
    //
    // The nickname text-field buffer is a LOCAL `@State` (not bound view-model state)
    // — the new name is presentation-only until 送出, when it is handed to the host
    // via `onSubmit`. NOTE: SwiftUI `ImageRenderer` cannot render a live `TextField`,
    // so the snapshot path uses the `editable: false` static rendering (see
    // `inputRow`); this buffer drives only the runtime editable path.

    @State private var nickname: String = ""

    /// Max nickname length (design `slice(0, 10)`).
    private static let maxLength = 10

    /// Trimmed nickname buffer (pure).
    private var trimmed: String {
        nickname.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 送出 enabled only while the trimmed buffer is 1...10 (design `canSubmit`).
    private var canSubmit: Bool {
        let count = trimmed.count
        return count >= 1 && count <= Self.maxLength
    }

    public var body: some View {
        ZStack {
            scrim
            card
        }
        .onAppear {
            // 預設帶入（問題 3）：已設定留言暱稱時，再次開啟 modal（改名）應從現有暱稱開始，
            // 而非空白。`displayName` 對未設名的訪客為 ""（`PlayerShellModel`：設名前為空），
            // 故只會帶入「真正設過」的名字。僅 runtime 可編輯路徑帶入（`isEditable`）；靜態
            // snapshot demo（`editable: false`）維持空欄 placeholder，baseline byte-identical。
            // 守 `nickname.isEmpty` 避免覆蓋使用者已輸入的內容（onAppear 若重觸發）。
            if isEditable, nickname.isEmpty, !displayName.isEmpty {
                nickname = String(displayName.prefix(Self.maxLength))
            }
        }
    }

    // MARK: - Full-bleed dim scrim (tap → dismiss)
    //
    // A transparent plain `Button` over the whole area (iOS-14-safe; an
    // `onTapGesture` on a `Color` renders unreliably headless) so a scrim tap
    // dismisses. Renders correctly with `onDismiss` nil (no-op tap).

    private var scrim: some View {
        Button(action: { onDismiss?() }) {
            Color.black.opacity(0.55)
                .edgesIgnoringSafeArea(.all)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(LBAccessibilityID.guestNameScrim)
    }

    // MARK: - Centered card (LBPAlertModal — card + floating logo badge)
    //
    // The card is a RoundedRectangle(18) filled with the theme background, padded
    // 22 horizontal / 26 top / 20 bottom, max-width ~300, with a soft shadow. The
    // logo badge floats ABOVE the card's top edge via a negative top padding inside
    // the card's leading VStack (mirrors the design's `marginTop: -52`).

    private var card: some View {
        VStack(spacing: 16) {
            logoBadge
            title
            subtitle
            inputRow
            submitButton
        }
        .padding(.horizontal, 22)
        .padding(.top, 26)
        .padding(.bottom, 20)
        // Card width 320 (rb-align-ios-gap-surfaces): matches the design's
        // `LiveNicknameModal` (live-chrome.jsx:400 maxWidth 320) + the sibling
        // `AuthGateModalView` (was 300, an off-by-20 nit).
        .frame(maxWidth: 320)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(theme.background))
        .shadow(color: Color.black.opacity(0.3), radius: 30, x: 0, y: 20)
        .padding(.horizontal, 28)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(LBAccessibilityID.guestNameModal)
    }

    // MARK: - Floating logo badge (44×44 white circle, accent monogram, soft shadow)
    //
    // Pops above the card via a negative top offset (`-52` ≈ design `marginTop`). A
    // 44×44 white circle with a 4pt inset, a hairline stroke, and a small accent
    // glyph. iOS-14-safe (`Image(systemName:)` + `Circle`).

    private var logoBadge: some View {
        ZStack {
            Circle().fill(Color.white)
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 26 * theme.fontScale, weight: .semibold))
                .foregroundColor(theme.accent)
                .padding(4)
        }
        .frame(width: 44, height: 44)
        .overlay(Circle().stroke(Self.stroke, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.1), radius: 12, x: 0, y: 4)
        // Float ABOVE the card top edge (design `marginTop: -52`). The negative top
        // padding consumes the badge's own height + the card's top inset so the rest
        // of the column flows below as if the badge sat on the card's top edge.
        .padding(.top, -52)
    }

    // MARK: - Title「設定暱稱」(17 bold, centered)

    private var title: some View {
        Text(Self.titleText)
            .font(.system(size: 17 * theme.fontScale, weight: .bold))
            .foregroundColor(theme.text)
            .multilineTextAlignment(.center)
    }

    // MARK: - Subtitle「請輸入直播留言的暱稱」(13 dim, centered)

    private var subtitle: some View {
        Text(Self.subtitleText)
            .font(.system(size: 13 * theme.fontScale))
            .foregroundColor(Self.textDim)
            .multilineTextAlignment(.center)
    }

    // MARK: - Input row (person icon + field, sunken pill with hairline stroke)
    //
    // Runtime (`isEditable == true`): a live `TextField` clamped to 10 chars. Snapshot
    // / preview (`isEditable == false`, set by `demo`): a STATIC placeholder `Text` —
    // SwiftUI's `ImageRenderer` cannot render a live `TextField` (it paints a yellow
    // 「unsupported control」box), so the read-only rendering reproduces the design's
    // empty-field placeholder state deterministically.

    private var inputRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "person")
                .font(.system(size: 16 * theme.fontScale))
                .foregroundColor(Self.textDim)
            if isEditable {
                clampedTextField
            } else {
                staticFieldDisplay
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Self.bgSunken))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Self.stroke, lineWidth: 1))
    }

    /// The nickname `TextField`, clamped to `maxLength` chars on every change
    /// (runtime path). `onChange(of:)` is iOS-14+, so it is guarded.
    @ViewBuilder
    private var clampedTextField: some View {
        if #available(iOS 14.0, *) {
            TextField(Self.inputPlaceholder, text: $nickname)
                .font(.system(size: 13 * theme.fontScale))
                .foregroundColor(theme.text)
                .onChange(of: nickname) { newValue in
                    if newValue.count > Self.maxLength {
                        nickname = String(newValue.prefix(Self.maxLength))
                    }
                }
                .accessibilityIdentifier(LBAccessibilityID.guestNameField)
        } else {
            TextField(Self.inputPlaceholder, text: $nickname)
                .font(.system(size: 13 * theme.fontScale))
                .foregroundColor(theme.text)
                .accessibilityIdentifier(LBAccessibilityID.guestNameField)
        }
    }

    /// Static read-only field rendering (snapshot / preview path). Shows the typed
    /// buffer if any, else the placeholder in `textFaint` — matching the design's
    /// empty-field state. ImageRenderer-safe (plain `Text`, no live control).
    private var staticFieldDisplay: some View {
        Text(nickname.isEmpty ? Self.inputPlaceholder : nickname)
            .font(.system(size: 13 * theme.fontScale))
            .foregroundColor(nickname.isEmpty ? Self.textFaint : theme.text)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 送出 CTA (LBPButton primary — enabled only when canSubmit)
    //
    // Enabled (1...10 trimmed) → accent fill / #fff fg. Disabled → strokeStrong fill /
    // textFaint fg. Tap guards `canSubmit`, then forwards the trimmed name to
    // `onSubmit` (host fulfils via `LivebuySDK.setUser`). `.buttonStyle(PlainButtonStyle())`.

    private var submitButton: some View {
        Button(action: { guard canSubmit else { return }; onSubmit?(trimmed) }) {
            Text(Self.submitLabel)
                .font(.system(size: 15 * theme.fontScale, weight: .bold))
                .foregroundColor(canSubmit ? .white : Self.textFaint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(canSubmit ? theme.accent : Self.strokeStrong))
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!canSubmit)
        .accessibilityIdentifier(LBAccessibilityID.guestNameSubmit)
    }

    // MARK: - Decorative design tokens (literal minimal hex via Color(hex:))
    //
    // accent / text / background come from the resolved theme. These are FIXED
    // decorative colors lifted verbatim from the design's `theme.surface.*` —
    // design-literal, NOT theme-resolved. Kept consistent with `ProductDetailSheetView`
    // / `VideoInfoPanelView` so the family reads as one.

    /// `theme.surface.textDim` (secondary / caption text).
    static let textDim = Color(hex: "#6B6775") ?? Color.gray
    /// `theme.surface.textFaint` (disabled CTA label).
    static let textFaint = Color(hex: "#B6B2BE") ?? Color.gray.opacity(0.5)
    /// `theme.surface.stroke` (hairline — badge ring / input outline).
    static let stroke = Color(hex: "#ECEAF0") ?? Color.gray.opacity(0.2)
    /// `theme.surface.strokeStrong` (disabled CTA fill / off-switch track).
    static let strokeStrong = Color(hex: "#D8D5DE") ?? Color.gray.opacity(0.35)
    /// `theme.surface.bgSunken` (sunken input fill).
    static let bgSunken = Color(hex: "#F4F4F6") ?? Color.gray.opacity(0.08)

    // MARK: - Fixed localized copy (static presentation strings, 繁中)

    static let titleText = "設定暱稱"
    static let subtitleText = "請輸入直播留言的暱稱"
    static let inputPlaceholder = "暱稱字數上限 10 個字"
    static let submitLabel = "送出"
}

// MARK: - Deterministic demo seed (previews + snapshot tests)
//
// A guest-mode modal (not logged in) with a `Guest_XXXX` default display name so
// previews / the snapshot test render the modal deterministically (no live player).
// Renders correctly action-free (the empty `@State` placeholder is the expected
// snapshot).

public extension GuestNameEditModalView {

    /// A deterministic demo guest nickname-edit modal (guest 態, `Guest_8F3A`).
    /// `editable: false` → static placeholder field so `ImageRenderer` renders the
    /// design's empty-field state (a live `TextField` paints an unsupported-control
    /// box). Renders correctly action-free.
    static func demo(theme: ReferenceUITheme) -> GuestNameEditModalView {
        GuestNameEditModalView(theme: theme, displayName: "Guest_8F3A", isLoggedIn: false, editable: false)
    }
}

#if DEBUG
struct GuestNameEditModalView_Previews: PreviewProvider {
    static var previews: some View {
        let theme = ReferenceUIThemePalette.minimal
        ZStack {
            (Color(hex: "#2A2730") ?? .gray).edgesIgnoringSafeArea(.all)
            GuestNameEditModalView.demo(theme: theme)
        }
        .frame(width: 393, height: 520)
        .previewLayout(.sizeThatFits)
    }
}
#endif
