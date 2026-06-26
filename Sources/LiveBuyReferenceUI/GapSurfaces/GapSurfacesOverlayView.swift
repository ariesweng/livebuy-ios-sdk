import SwiftUI
import LiveBuySDK
import LiveBuyUI

// MARK: - GapSurfacesOverlayView — family-6 gap-surfaces container (SKELETON)
//
// Spec: `reference-ui-rendering/spec.md` (family-6 gap-surfaces — the LAST iOS
//        Phase-1 family closing out the four "gap" surfaces).
// Design: rb-ios-gap-surfaces design.md §"渲染計畫" + §"守住的不變式".
//
// The top-level family-6 container. After the 2026-06-06 design reconcile it
// composites only TWO gap surfaces over the live video area:
//
//   1. AuthGateModalView      —「請先登入」alert modal (auth-gate-template-state,
//                               `LBPAuthGate`). Presented when a pending un-intercepted
//                               `AUTH_REQUIRED` exists AND the user is not logged in.
//   2. GuestNameEditModalView — guest 改名 modal (auth-gate-template-state,
//                               `LiveNicknameModal`). Forwards the passthrough
//                               「請求改名」intent; the actual rename is host-
//                               fulfilled via `LiveBuySDK.setUser`.
//
// REMOVED in the reconcile (design 2026-06-06): the goods-tracking dual-switch sheet
// (到貨追蹤 → family-3 商品明細 收藏 toggle; 補貨通知 → family-3 售完補貨通知 sheet)
// and the standalone 公告分頁 panel (公告 content → family-1 VideoInfoPanel 公告 tab).
//
// This is the SKELETON: it owns the layout + a `GapSurfacesModel` + the resolved
// `ReferenceUITheme` + local sheet presentation state + the host-wired login /
// guest-name-submit closures, and composes the four surface sub-views BY TYPE NAME.
// The four sub-view TYPES are produced by the four parallel surface agents that run
// after this skeleton — see the "SUB-VIEW INPUT PATTERN" contract below, which every
// surface agent MUST implement verbatim so the container's call sites match.
//
// Until all four surface sub-views exist, this file will not compile on its own —
// that is expected (the surface agents land the types). The container's job is to
// FIX the layout + the call-site shape + the demo construction recipe so the
// parallel agents converge.
//
// PRESENTATION STATE OWNERSHIP (mirrors `ProductSheetsOverlayView`):
//   • Whether the auth-gate modal is presented is DERIVED from the model
//     (`model.authGateVisible` + a non-nil `model.authGateTriggerAction`), NOT a
//     separate boolean — the template owns auth-gate open/clear; this layer only
//     mirrors + dismisses presentation.
//   • `guestEditPresented` — whether the guest-name-edit modal is on screen. Local
//     affordance state; the displayed name / logged-in bit are model-driven reads.
//
// iOS-14-safe: `ZStack` / `VStack` / `HStack` / `Spacer` / manual padding are all
// iOS-13+; no `@available` guard needed here. Any surface that reaches for a >14
// API must guard it inside its own sub-view (D §iOS-14-safe).
//
// ─────────────────────────────────────────────────────────────────────────────
// SUB-VIEW INPUT PATTERN — the contract the 4 parallel surface agents MUST follow
// ─────────────────────────────────────────────────────────────────────────────
//
// Every family-6 surface sub-view is a `public struct …: View` whose initializer
// takes, IN THIS ORDER (identical convention to family-1 / -2 / -3 / -4):
//
//   1. `theme: ReferenceUITheme`            — the resolved reference-ui theme
//                                             (FIRST positional argument, always).
//   2. its bound SNAPSHOT VALUE(S)          — the read-only state it renders,
//                                             passed BY VALUE from GapSurfacesModel
//                                             (primitives / enums — never the model,
//                                             never the template).
//   3. optional action closures            — trailing, each defaulting to `nil`
//                                             (`onX: (() -> Void)? = nil`, etc.).
//                                             The container does NOT own the writes;
//                                             they forward to the model's thin
//                                             forwarders (which hit existing template
//                                             exits) or, for the login CTA / guest
//                                             rename submit, to the host-wired
//                                             container closures.
//
// Concretely, the four surface agents implement EXACTLY these initializers:
//
//   AuthGateModalView(
//       theme: ReferenceUITheme,
//       triggerAction: LBAuthTriggerAction,
//       onLogin: (() -> Void)? = nil,                  // → host login flow (container)
//       onDismiss: (() -> Void)? = nil)                // → model.dismissAuthGate()
//
//   GuestNameEditModalView(
//       theme: ReferenceUITheme,
//       displayName: String,
//       isLoggedIn: Bool,
//       onRequestEdit: (() -> Void)? = nil,            // → model.requestGuestNameEdit()
//       onSubmit: ((String) -> Void)? = nil,           // → host setUser flow (container)
//       onDismiss: (() -> Void)? = nil)                // → dismiss the modal
//
// Rules every surface agent honours:
//   • FIRST positional arg is `theme:`. Snapshot values are passed BY VALUE
//     (primitives / enums).
//   • Action closures are LAST, each `… = nil` (the container passes the host /
//     model-wired closure or omits it). A surface sub-view MUST render correctly
//     with all actions nil (so demo / snapshot tests construct it action-free), and
//     MUST provide a `static func demo(theme:)` action-free constructor.
//   • A surface sub-view reads ONLY its passed-in values — it MUST NOT reach back
//     into GapSurfacesModel or DefaultPlayerTemplate (one-way data flow).
//   • The modal shells (AuthGateModalView / GuestNameEditModalView) REUSE the
//     centered-card recipe: black-0.55 scrim + centered card
//     `RoundedRectangle(cornerRadius: 18).fill(theme.background)` + shadow.
//     (AuthGateModalView additionally overhangs an accent lock badge per `LBPAuthGate`.)
//   • Secondary design colors are NOT in `ReferenceUITheme` (it has only accent /
//     background / text / cornerRadius / fontScale). Lift them as per-struct static
//     `Color` constants via `Color(hex:)` EXACTLY like `ProductDetailSheetView` does
//     (textDim / textFaint / stroke / strokeStrong / bgSunken).
//   • The dual-switch / notice toggle MUST be a CUSTOM pill switch (Capsule track +
//     Circle knob) — NOT a SwiftUI `Toggle` (it uses `.tint` and renders unreliably
//     under the ImageRenderer snapshot path).
//   • NO ScrollView / LazyVStack / LazyHStack / LazyVGrid anywhere (they render BLANK
//     under the ImageRenderer snapshot path) — plain VStack / HStack only.
//   • iOS-14-safe SwiftUI only; any >14 API guarded with `@available` /
//     `if #available` inside the sub-view.
// ─────────────────────────────────────────────────────────────────────────────

/// The family-6 gap-surfaces container. Drives layout + presentation for the four
/// deferred gap surfaces (請先登入 modal / goods-tracking dual switch / 公告分頁 panel
/// / guest 改名 modal) over the video area; reads a `GapSurfacesModel` (a read-only
/// bridge over a live `DefaultPlayerTemplate`, or a deterministic demo instance) and
/// paints with the resolved `ReferenceUITheme`. Writes route through the model's thin
/// forwarders (existing template exits) or the host-wired login / rename closures.
public struct GapSurfacesOverlayView: View {

    /// The read-only gap-surface bridge (republished from a live `DefaultPlayerTemplate`
    /// or constructed deterministically for demos / snapshot tests).
    @ObservedObject public var model: GapSurfacesModel

    /// The resolved reference-ui theme.
    public let theme: ReferenceUITheme

    /// Host-wired auth-gate「登入」CTA. Performing the login is the host's job (it
    /// wires its own login flow + calls `LiveBuySDK.setUser`); the container NEVER
    /// logs in itself. nil for demo / snapshot instances.
    private let onRequestLogin: (() -> Void)?

    /// Host-wired guest-name SUBMIT. The actual new display name is host-fulfilled
    /// via `LiveBuySDK.setUser`; the container NEVER renames itself. The passthrough
    /// 「請求改名」intent (separate) still routes through the template via
    /// `model.requestGuestNameEdit()`. nil for demo / snapshot instances.
    private let onSubmitGuestName: ((String) -> Void)?

    /// Whether the guest-name-edit modal is currently on screen. Local affordance
    /// state — the displayed name / logged-in bit are model-driven reads.
    @State private var guestEditPresented: Bool = false

    public init(
        model: GapSurfacesModel,
        theme: ReferenceUITheme,
        onRequestLogin: (() -> Void)? = nil,
        onSubmitGuestName: ((String) -> Void)? = nil
    ) {
        self.model = model
        self.theme = theme
        self.onRequestLogin = onRequestLogin
        self.onSubmitGuestName = onSubmitGuestName
    }

    public var body: some View {
        ZStack {
            // NOTE (design reconcile 2026-06-06): family-6 no longer owns the
            // goods-tracking dual-switch sheet nor a standalone 公告分頁 panel.
            //   • 到貨追蹤（await type=1）moved to the family-3 商品明細 收藏 toggle.
            //   • 補貨通知（notice type=2）stays in the family-3 售完補貨通知 sheet.
            //   • 公告 content is rendered IN the family-1 VideoInfoPanel 公告 tab.
            // family-6 now composes only the auth-gate + guest-name-edit modals.

            // Surface 1 —「請先登入」alert modal, centered over its own scrim. Shown
            // when a pending un-intercepted AUTH_REQUIRED exists AND not logged in.
            if model.authGateVisible, let triggerAction = model.authGateTriggerAction {
                AuthGateModalView(
                    theme: theme,
                    triggerAction: triggerAction,
                    // 登入 is the HOST's job (host wires its own flow + setUser) — forward
                    // the optional AS-IS (no extra dismiss here) so an unwired
                    // `config.onLogin` reaches the modal as nil and the「前往登入」CTA is
                    // hidden rather than dead (dropin-hide-unwired-affordances).
                    onLogin: onRequestLogin,
                    onDismiss: { model.dismissAuthGate() })
            }

            // Surface 4 — guest 改名 modal, centered over its own scrim. Shown when
            // the host opens it (`guestEditPresented`); the displayed name /
            // logged-in bit are model-driven reads.
            if guestEditPresented {
                GuestNameEditModalView(
                    theme: theme,
                    displayName: model.displayName,
                    isLoggedIn: model.isLoggedIn,
                    // Passthrough「請求改名」intent → template exit (emits
                    // GUEST_NAME_EDIT_REQUEST). Distinct from the actual rename.
                    onRequestEdit: { model.requestGuestNameEdit() },
                    // The actual new name is host-fulfilled via LiveBuySDK.setUser —
                    // the container forwards to the host-wired closure, never renames
                    // itself, then dismisses.
                    onSubmit: { newName in
                        onSubmitGuestName?(newName)
                        guestEditPresented = false
                    },
                    onDismiss: { guestEditPresented = false })
            }
        }
    }

    /// Host affordance: present the guest-name-edit modal. Exposed so the host /
    /// a parent surface can open the rename modal from a name-tap affordance.
    public func presentGuestNameEdit() {
        guestEditPresented = true
    }
}

