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
// ─────────────────────────────────────────────────────────────────────────────
// `errorMessage` / `isSubmitting` (rb-ios-nickname-taken-inline-error)
// ─────────────────────────────────────────────────────────────────────────────
// The drop-in container's turnkey nickname flow (`LivebuyPlayer.swift`'s `onNicknameSubmit`)
// fixed a real gap: the old fire-and-forget `Livebuy.setGuestNickname` never surfaced a
// duplicate-name rejection — it only showed up later, on the guest's NEXT chat send. That
// container now round-trips core's verified `LivebuyPlayerViewController.setGuestNicknameVerified(_:)`
// and feeds the result back here as TWO bound snapshot values (same by-value pattern as
// `displayName` / `isLoggedIn` — the CONTROLLER is the source of truth, this view never mutates
// them):
//   • `errorMessage: String?` — non-nil after a failed submit (either「暱稱被取走」or a generic
//     retryable failure); renders an inline red row below the input. `nil` (the default) → no row,
//     byte-identical to before this change.
//   • `isSubmitting: Bool` — `true` while the verified set is in flight; LOCKS the 送出 CTA against
//     a double-submit (via the action-level `guard`, NOT `.disabled` — see `submitButton` for the
//     measured reason) and swaps its label/glyph for a spinner + "送出中…". `false` (the default) →
//     unchanged from before this change.
// Both default to their "nothing happening" value so every EXISTING call site (the family-6
// `GapSurfacesOverlayView` rename flow, the Example hosts, `demo(theme:)`) keeps compiling and
// rendering byte-identical output without passing them.
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

    /// Non-nil when the last submit attempt failed (rb-ios-nickname-taken-inline-error) — either
    /// the name was taken (`LBError.guestNameTaken`) or some other error (network etc.) prevented
    /// validation. Read-only; the container (`NicknamePromptController.errorMessage`) owns the
    /// value, this view only renders it as an inline red row below the input. `nil` (default) →
    /// no row, byte-identical to before this change. Cleared automatically the next time the
    /// container calls `beginSubmit()` / the modal is re-presented.
    public let errorMessage: String?

    /// Whether a `setGuestNicknameVerified` round-trip is currently in flight
    /// (rb-ios-nickname-taken-inline-error). `true` → the 送出 CTA is LOCKED (its action `guard`
    /// refuses a second submit) and shows a spinner + "送出中…" instead of the normal label, while
    /// keeping the brand fill per design `LBPButton.loading` (see `submitButton` for why this is a
    /// guard rather than `.disabled`). Read-only; owned by `NicknamePromptController.isSubmitting`.
    /// `false` (default) → unchanged from before this change.
    public let isSubmitting: Bool

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
        errorMessage: String? = nil,
        isSubmitting: Bool = false,
        onRequestEdit: (() -> Void)? = nil,
        onSubmit: ((String) -> Void)? = nil,
        onDismiss: (() -> Void)? = nil,
        editable: Bool = true
    ) {
        self.theme = theme
        self.displayName = displayName
        self.isLoggedIn = isLoggedIn
        self.errorMessage = errorMessage
        self.isSubmitting = isSubmitting
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

    /// Whether the CTA paints its BRAND (accent) fill rather than the grey length-gate fill
    /// (rb-ios-nickname-taken-inline-error).
    ///
    /// `isSubmitting` deliberately WINS over `canSubmit`: the user can still edit the field while a
    /// submit is in flight (the field is not locked — see the modal's KDoc), so clearing it mid-flight
    /// would otherwise flip the CTA to the grey length-gate fill. Grey there communicates「你的輸入有
    /// 問題」when the truth is「請求進行中」—— and the user cannot submit during that window anyway
    /// (the action `guard` already refuses), so the length gate has nothing left to warn about.
    /// Resolves the otherwise-conflicting「送出中保品牌色」/「字數閘退灰」pair in favour of the former,
    /// for the duration of the request only.
    private var ctaShowsBrandFill: Bool { isSubmitting || canSubmit }

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
            // Inline error row (rb-ios-nickname-taken-inline-error): a plain `if` (no `else`)
            // contributes NOTHING to the VStack's layout when `errorMessage == nil` — verified
            // empirically (no phantom spacing slot) — so the `errorMessage == nil` case (every
            // EXISTING call site) renders byte-identical to before this change.
            if let errorMessage = errorMessage {
                errorRow(errorMessage)
            }
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

    // MARK: - Inline error row (rb-ios-nickname-taken-inline-error)
    //
    // Shown ONLY when `errorMessage != nil` (a failed `setGuestNicknameVerified` attempt — either
    // the name was taken, or some other error blocked validation). Danger-red centered caption,
    // matching the existing `#EB6E5F` danger token already used by `WinClaimModalView` /
    // `ErrorScreenView` so this reads as the same family, not a one-off color.

    private func errorRow(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 12 * theme.fontScale, weight: .semibold))
            .foregroundColor(Self.dangerColor)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(LBAccessibilityID.guestNameError)
    }

    // MARK: - 送出 CTA (LBPButton primary — length gate + in-flight lock)
    //
    // Enabled (1...10 trimmed) → accent fill / #fff fg. Length-gate disabled (empty / too long) →
    // strokeStrong fill / textFaint fg, exactly as before this change.
    //
    // ── 送出中為何用「guard + opacity」而不是 `.disabled(isSubmitting)` ──────────────────
    // 設計來源 `design/templates/minimal/sdk-components.jsx` 的 `LBPButton` 對 `loading` 態的契約
    // 逐字寫著：loading「locks (no clicks) but — unlike `disabled` — KEEPS its brand fill so the
    // action still reads as active/committed」，且 `opacity: loading ? 0.96 : 1`。也就是「鎖住但保
    // 品牌色、只微調 0.96 透明度」，**不是**退成灰/淡色。
    //
    // 但 SwiftUI 的 `.disabled(true)` 會把**整顆鈕**（含 accent 底、白字、spinner）一起淡化——本
    // change 以 `ImageRenderer` 實測過同一條 reference-ui 算圖路徑：accent `#F03246` 在
    // `.disabled(true)` 下量到 premultiplied rgba(120, 25, 35, 128)，即整顆鈕被套上 α0.5；
    // `.opacity(0.96)` 則量到 rgba(230, 48, 67, 245)，維持品牌色。因此「`.disabled(isSubmitting)`」
    // 與「loading 保品牌色」兩者不可兼得。
    //
    // 故此處鏡射**同一套設計系統下的姊妹 CTA** `ProductDetailSheetView.addToCartButton` 的既有做
    // 法（它的註解也明載同一個理由）：`.disabled` **只**吃長度閘，送出中改由 action 內的
    // `guard !isSubmitting` 擋住點擊（真正的 lock），視覺則走設計指定的 `.opacity(0.96)`。兩顆
    // CTA 因此在 loading 態長得一致，且都忠於 `LBPButton.loading`。
    //
    // 點擊後把 trimmed 後的暱稱交給 `onSubmit`（容器以
    // `LivebuyPlayerViewController.setGuestNicknameVerified` 履行）。`.buttonStyle(PlainButtonStyle())`。

    private var submitButton: some View {
        Button(action: { guard canSubmit && !isSubmitting else { return }; onSubmit?(trimmed) }) {
            HStack(spacing: 8) {
                if isSubmitting {
                    // Reuses the existing `SpinnerRingView` (cart-add-loading-state's spinner) —
                    // same in-flight idiom as `ProductDetailSheetView.addToCartButton`, not a new one.
                    SpinnerRingView(size: 16, lineWidth: 2, color: .white)
                }
                Text(isSubmitting ? Self.submittingLabel : Self.submitLabel)
                    .font(.system(size: 15 * theme.fontScale, weight: .bold))
                    .foregroundColor(ctaShowsBrandFill ? .white : Self.textFaint)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(ctaShowsBrandFill ? theme.accent : Self.strokeStrong))
        }
        .buttonStyle(PlainButtonStyle())
        // `.disabled` 只在**非**送出中的長度閘不成立時才套用（沿用改動前行為）。送出中一律不套
        // `.disabled` —— 點擊已由 action 內 `guard canSubmit && !isSubmitting` 擋住，不需要它再擋一次；
        // 而且送出中若使用者把輸入清空（`canSubmit` 轉 false），套上 `.disabled` 會再砍一半 alpha，
        // 抵銷決策 I 刻意維持的品牌色。實測（同決策 F 的 `ImageRenderer` 量測法，accent `#F03246`）：
        //   送出中 + 已清空，`.disabled(!canSubmit)`         → premultiplied (115, 24, 34, 122) ≈ α0.48
        //   送出中 + 已清空，`.disabled(!canSubmit && !isSubmitting)` → (230, 48, 67, 245) 品牌色維持
        // 非送出中的兩態（valid / invalid）在兩種寫法下量到的像素完全相同 → 既有 baseline 不受影響。
        .disabled(!canSubmit && !isSubmitting)
        // 設計 `LBPButton` loading 態的 `opacity: 0.96`；非送出中恆為 1 → 既有 baseline byte-identical。
        .opacity(isSubmitting ? 0.96 : 1)
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
    /// Danger / error red (rb-ios-nickname-taken-inline-error) — same `#EB6E5F` token already
    /// used by `WinClaimModalView.dangerColor` / `ErrorScreenView.danger`, kept as a local literal
    /// (this file's existing convention: every color here is its own `static let`, not shared
    /// across files) so the family reads as one without a cross-file dependency.
    static let dangerColor = Color(hex: "#EB6E5F") ?? Color.red

    // MARK: - Fixed localized copy (static presentation strings, 繁中)

    static let titleText = "設定暱稱"
    static let subtitleText = "請輸入直播留言的暱稱"
    static let inputPlaceholder = "暱稱字數上限 10 個字"
    static let submitLabel = "送出"
    /// CTA label while `isSubmitting` (rb-ios-nickname-taken-inline-error) — same "…中" convention
    /// / exact string as `WinClaimModalView.submittingLabel`.
    static let submittingLabel = "送出中…"
    /// `errorMessage` text for `LBError.guestNameTaken` (rb-ios-nickname-taken-inline-error) —
    /// verbatim identical to core's own `zh-Hant-TW` i18n string for `guest_existing`
    /// (`ios/Sources/LivebuySDK/Resources/zh-Hant-TW.lproj/Localizable.strings`), kept as a
    /// reference-ui-owned literal (this layer hardcodes copy, does not read the core bundle) so the
    /// wording matches what the SAME error already says elsewhere (chat send's existing checkName
    /// precheck) rather than inventing a second phrasing for the same failure.
    static let takenErrorText = "此暱稱已被使用，請換一個"
    /// `errorMessage` text for any OTHER thrown error (network / server failures — validation
    /// could not complete, distinct from "taken"). Same "OOO失敗，請稍後再試" convention as
    /// `ProductDetailSheetView.failureTitle` ("加入購物車失敗,請稍後再試").
    static let retryableErrorText = "暱稱設定失敗，請稍後再試"
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
        Group {
            ZStack {
                (Color(hex: "#2A2730") ?? .gray).edgesIgnoringSafeArea(.all)
                GuestNameEditModalView.demo(theme: theme)
            }
            .previewDisplayName("idle")

            // rb-ios-nickname-taken-inline-error previews (NOT wired to any snapshot baseline).
            ZStack {
                (Color(hex: "#2A2730") ?? .gray).edgesIgnoringSafeArea(.all)
                GuestNameEditModalView(
                    theme: theme, displayName: "Guest_8F3A", isLoggedIn: false,
                    errorMessage: GuestNameEditModalView.takenErrorText, editable: false)
            }
            .previewDisplayName("taken error")

            // NOTE: `editable: false` never seeds the `@State` nickname buffer (no runtime
            // `onAppear` prefill on the static path), so `canSubmit` reads `false` here. The CTA
            // still paints its BRAND fill because `ctaShowsBrandFill` lets `isSubmitting` win over
            // the length gate — which is exactly the in-flight behaviour this preview is meant to
            // show. Not a snapshot baseline.
            ZStack {
                (Color(hex: "#2A2730") ?? .gray).edgesIgnoringSafeArea(.all)
                GuestNameEditModalView(
                    theme: theme, displayName: "Guest_8F3A", isLoggedIn: false,
                    isSubmitting: true, editable: false)
            }
            .previewDisplayName("submitting")
        }
        .frame(width: 393, height: 520)
        .previewLayout(.sizeThatFits)
    }
}
#endif
