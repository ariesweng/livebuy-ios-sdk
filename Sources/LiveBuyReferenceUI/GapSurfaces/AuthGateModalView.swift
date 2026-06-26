import SwiftUI
import LiveBuySDK
import LiveBuyUI

// MARK: - AuthGateModalView — family-6 gap-surfaces surface 1 (「請先登入」alert modal)
//
// Spec: `reference-ui-rendering/spec.md` (family-6 gap-surfaces — the LAST iOS
//        Phase-1 family, closing out the four deferred "gap" surfaces).
// Design: `design/templates/minimal/sdk-components.jsx` `LBPAuthGate` (centered
//          card over a black-0.55 scrim, 18pt corner card, overhanging accent lock
//          badge, trigger-specific body, VERTICAL two-button footer) + `LBPButton`
//          (primary「前往登入」/ plain「稍後再說」) + `LBP_AUTH_COPY` (trigger copy).
//
// The「請先登入」alert modal for ONE pending un-intercepted `AUTH_REQUIRED`. It is
// the first of the four family-6 surface sub-views composed by
// `GapSurfacesOverlayView`, and it implements the agreed SUB-VIEW INPUT PATTERN
// documented verbatim in `GapSurfacesOverlayView.swift`:
//
//   1. `theme: ReferenceUITheme`            — FIRST positional argument, always.
//   2. bound SNAPSHOT VALUE                 — `triggerAction: LBAuthTriggerAction`,
//      passed BY VALUE from `GapSurfacesModel` (an enum — never the model, never the
//      template). It drives the body copy per trigger kind.
//   3. action closures (LAST, each `= nil`) — `onLogin` (「登入」CTA → the HOST's own
//      login flow wired by the container; reference-ui NEVER logs in itself) and
//      `onDismiss` (「返回」→ `model.dismissAuthGate()`).
//
// This sub-view reads ONLY its passed-in `triggerAction`; it never reaches back into
// `GapSurfacesModel` / `DefaultPlayerTemplate` (one-way data flow). It also renders
// correctly with all actions nil (so demo / snapshot tests construct it action-free).
//
// PRESENTATION GATING (container-owned, NOT branched here): the modal is presented
// by `GapSurfacesOverlayView` ONLY when a pending un-intercepted `AUTH_REQUIRED`
// exists AND the user is a guest (the container gates on `model.authGateVisible`).
// So this view ALWAYS draws the modal — the "logged-in → not drawn" rule is enforced
// upstream by the container; this view need not branch on it.
//
// iOS-14-safe SwiftUI only. `ZStack` / `VStack` / `HStack` / `Text` / `Button` /
// `RoundedRectangle` / `Color` are all iOS-13+; no `@available` guard needed here.
// NO ScrollView / LazyVStack / LazyHStack / LazyVGrid anywhere — they render BLANK
// under the reference-ui snapshot path (SwiftUI `ImageRenderer`); only plain
// `VStack` / `HStack`. No `.task` / `AsyncImage` / `NavigationStack` /
// `.foregroundStyle` / `.tint` / SwiftUI `Toggle`. The two footer buttons use
// `.buttonStyle(PlainButtonStyle())` (mirrors `LBPButton`).

// MARK: - Login-CTA optional forwarding (dropin-hide-unwired-affordances, design D2.5)

/// Forwards a host login closure through a gate that ALSO dismisses itself, while
/// PRESERVING optional-ness: `nil → nil` (so `AuthGateModalView` hides the「前往登入」
/// CTA instead of showing a dead button), non-nil → a closure that runs `dismiss`
/// FIRST, then the host login. Used by the gates that wrap their own dismissal
/// (`MinimalDesign` 留言閘 / `ProductSheetsOverlayView` cart-needs-login). Without this
/// the container would wrap the optional into an always-non-nil closure and the
/// modal could never tell that the host left `config.onLogin` unwired. Pure +
/// `internal` so the container and unit tests share one implementation.
func lbForwardLogin(
    _ onRequestLogin: (() -> Void)?,
    dismiss: @escaping () -> Void
) -> (() -> Void)? {
    onRequestLogin.map { hostLogin in { dismiss(); hostLogin() } }
}

/// The family-6「請先登入」alert modal for one pending `AUTH_REQUIRED`. Renders a
/// centered `LBPAuthGate` card (overhanging accent lock badge / title /
/// trigger-specific body / vertical two-button footer) over a black-0.55 scrim.
/// `triggerAction` drives the body copy; `onLogin` / `onDismiss` are host-wired.
public struct AuthGateModalView: View {

    /// The resolved reference-ui theme (FIRST positional argument, always).
    public let theme: ReferenceUITheme

    /// Which interaction tripped the auth-gate (`LBAuthGateState.triggerAction`).
    /// Read-only — drives the body copy per kind. Passed BY VALUE.
    public let triggerAction: LBAuthTriggerAction

    /// Host-wired「登入」CTA. Performing the login is the HOST's job (it wires its own
    /// login flow + calls `LiveBuySDK.setUser`); reference-ui NEVER logs in itself.
    /// nil for demo / snapshot instances.
    private let onLogin: (() -> Void)?
    /// Host-wired「返回」/ dismiss → `model.dismissAuthGate()` (clears the template's
    /// auth-gate state). nil for demo / snapshot instances.
    private let onDismiss: (() -> Void)?

    public init(
        theme: ReferenceUITheme,
        triggerAction: LBAuthTriggerAction,
        onLogin: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.theme = theme
        self.triggerAction = triggerAction
        self.onLogin = onLogin
        self.onDismiss = onDismiss
    }

    // MARK: - Derived presentation (pure)

    /// Trigger-specific body copy (`LBAuthTriggerAction` → 繁中 reason line). `.other`
    /// is the forward-compatible bucket (a generic「繼續操作」line).
    private var bodyCopy: String {
        switch triggerAction {
        case .cartAdd:     return Self.bodyCartAdd
        case .commentSend: return Self.bodyCommentSend
        case .couponClaim: return Self.bodyCouponClaim
        case .other:       return Self.bodyOther
        }
    }

    public var body: some View {
        ZStack {
            // Full-bleed dim scrim (LBPAuthGate backdrop). Tap = dismiss (mirrors the
            // design's `onClick={onDismiss}`). edgesIgnoringSafeArea so the scrim
            // covers the whole video area behind the centered card.
            Color.black.opacity(0.55)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture { onDismiss?() }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(LBAccessibilityID.authGateScrim)

            // Centered alert card (LBPAuthGate) with an overhanging accent lock badge.
            VStack(spacing: 0) {
                Text(Self.title)
                    .font(.system(size: 18 * theme.fontScale, weight: .bold))
                    .foregroundColor(theme.text)
                    .multilineTextAlignment(.center)

                Text(bodyCopy)
                    .font(.system(size: 13 * theme.fontScale))
                    .foregroundColor(Self.textDim)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)

                footer
                    .padding(.top, 22)
            }
            .padding(.horizontal, 22)
            // top padding clears the overhanging lock badge (design `34px` top).
            .padding(.top, 34)
            .padding(.bottom, 20)
            .frame(maxWidth: 320)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(theme.background))
            // Accent lock badge overhangs the card top (design `top: -30`).
            .overlay(lockBadge.offset(y: -30), alignment: .top)
            .shadow(color: Color.black.opacity(0.3), radius: 30, x: 0, y: 20)
            .padding(.horizontal, 36)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(LBAccessibilityID.authGateModal)
        }
    }

    // MARK: - Overhanging accent lock badge (LBPAuthGate brand badge)
    //
    // accent fill + white `lock.fill` SF Symbol + `theme.background` ring + soft
    // accent shadow. Reads instantly as "login required" and keeps it on-brand.

    private var lockBadge: some View {
        ZStack {
            Circle().fill(theme.accent)
            Image(systemName: "lock.fill")
                .font(.system(size: 24 * theme.fontScale, weight: .semibold))
                .foregroundColor(.white)
        }
        .frame(width: 60, height: 60)
        .overlay(Circle().stroke(theme.background, lineWidth: 4))
        .shadow(color: theme.accent.opacity(0.33), radius: 10, x: 0, y: 8)
    }

    // MARK: - Vertical two-button footer (LBPButton primary over plain)
    //
    // Primary「前往登入」(accent fill, #fff fg) → onLogin, on TOP. Plain「稍後再說」
    // (transparent fill, strokeStrong 1px border, theme.text) → onDismiss, BELOW.
    // Full width, 12pt corner, 13pt vertical padding, `gap: 10` (design `column`).

    private var footer: some View {
        VStack(spacing: 10) {
            // Primary「前往登入」(LBPButton primary). Rendered ONLY when the host wired
            // login (`onLogin != nil`) — reference-ui NEVER logs in itself, so an unwired
            // CTA would be a dead button. When `nil`, the modal degrades to inform +
            // 「稍後再說」(dropin-hide-unwired-affordances). The container forwards the
            // host's `config.onLogin` optional-ness down to here (design D2.5).
            if let onLogin = onLogin {
                Button(action: onLogin) {
                    Text(Self.loginLabel)
                        .font(.system(size: 15 * theme.fontScale, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(theme.accent))
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityIdentifier(LBAccessibilityID.authGateLogin)
            }

            // Plain「稍後再說」(LBPButton plain).
            Button(action: { onDismiss?() }) {
                Text(Self.dismissLabel)
                    .font(.system(size: 15 * theme.fontScale, weight: .bold))
                    .foregroundColor(theme.text)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Self.strokeStrong, lineWidth: 1))
                    // Whole pill taps (outlined → stroke-only border, interior would be dead).
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityIdentifier(LBAccessibilityID.authGateLater)
        }
    }

    // MARK: - Decorative design tokens (literal minimal hex via Color(hex:))
    //
    // accent / text / background come from the resolved theme. These are FIXED
    // decorative colors lifted verbatim from the design's `theme.surface.*` —
    // design-literal, NOT theme-resolved. Kept consistent with
    // `ProductDetailSheetView` so the family reads as one.

    /// `theme.surface.textDim` (secondary / body reason text).
    static let textDim = Color(hex: "#6B6775") ?? Color.gray
    /// `theme.surface.textFaint` (disabled / off control).
    static let textFaint = Color(hex: "#B6B2BE") ?? Color.gray.opacity(0.5)
    /// `theme.surface.stroke` (hairline divider).
    static let stroke = Color(hex: "#ECEAF0") ?? Color.gray.opacity(0.2)
    /// `theme.surface.strokeStrong` (plain-button outline — secondary「返回」border).
    static let strokeStrong = Color(hex: "#D8D5DE") ?? Color.gray.opacity(0.35)
    /// `theme.surface.bgSunken` (sunken control fill / input bg).
    static let bgSunken = Color(hex: "#F4F4F6") ?? Color.gray.opacity(0.08)

    // MARK: - Fixed localized copy (static presentation strings, 繁中)

    static let title = "請先登入"
    static let dismissLabel = "稍後再說"
    static let loginLabel = "前往登入"
    // Trigger-specific body copy — verbatim from the design's `LBP_AUTH_COPY`.
    static let bodyCartAdd = "登入後即可將商品加入購物車"
    static let bodyCommentSend = "登入後即可參與留言互動"
    static let bodyCouponClaim = "登入後即可領取優惠與獎品"
    static let bodyOther = "登入後即可使用完整功能"
}

// MARK: - Deterministic demo seed (previews + snapshot tests)

public extension AuthGateModalView {

    /// A deterministic, action-free demo auth-gate modal (the `.cartAdd` trigger —
    /// the most common gate). Renders correctly with all actions nil.
    static func demo(theme: ReferenceUITheme) -> AuthGateModalView {
        AuthGateModalView(theme: theme, triggerAction: .cartAdd)
    }
}

#if DEBUG
struct AuthGateModalView_Previews: PreviewProvider {
    static var previews: some View {
        let theme = ReferenceUIThemePalette.minimal
        Group {
            // 加入購物車 gate (the demo / default).
            ZStack {
                Color(hex: "#2A2730") ?? .gray
                AuthGateModalView.demo(theme: theme)
            }
            .previewDisplayName("cartAdd")

            // 直播留言 gate.
            ZStack {
                Color(hex: "#2A2730") ?? .gray
                AuthGateModalView(theme: theme, triggerAction: .commentSend)
            }
            .previewDisplayName("commentSend")

            // 領取優惠 gate.
            ZStack {
                Color(hex: "#2A2730") ?? .gray
                AuthGateModalView(theme: theme, triggerAction: .couponClaim)
            }
            .previewDisplayName("couponClaim")

            // 其他 (forward-compatible bucket).
            ZStack {
                Color(hex: "#2A2730") ?? .gray
                AuthGateModalView(theme: theme, triggerAction: .other)
            }
            .previewDisplayName("other")
        }
        .frame(width: 393, height: 520)
        .previewLayout(.sizeThatFits)
    }
}
#endif
