import SwiftUI
import LiveBuySDK
import LiveBuyUI

// MARK: - ContactMerchantModalView — family-1「聯絡商家」confirm modal (LBPAlertModal)
//
// Spec: `reference-ui-rendering/spec.md` (family-1 player-shell —「聯絡商家」確認 modal).
// Design: `design/templates/minimal/sdk-components.jsx` `LBPAlertModal` (centered
//          card over a black-0.55 scrim, 18pt corner card, HORIZONTAL two-button
//          footer [plain secondary][primary]) + `screens.jsx` `contact_merchant`
//          state (title「聯繫商家」/ body「確定要開啟商城指定的客服連結嗎?」/ 確定 / 取消).
//
// A presentation-only CONFIRM before opening the shop's customer-service link. The
// rail `serviceLink` tap and the VideoInfoPanel footer「與商家一對一對話」used to call
// `model.openServiceLink()` directly; now `PlayerShellView` presents THIS modal first
// and only the「確定」CTA proceeds to that existing exit (per the design's
// `contact_merchant` flow). It owns NO link logic — it just forwards `onConfirm` /
// `onDismiss` (the host-wired service-link exit stays in the model).
//
// SUB-VIEW INPUT PATTERN (family convention): `theme:` first; then action closures
// (LAST, each `= nil`). There is no bound snapshot value — the copy is fixed (the
// confirm question is static; the actual link is the host's). It reads NOTHING back
// from the model (one-way data flow) and renders correctly with all actions nil
// (so demo / snapshot tests construct it action-free).
//
// iOS-14-safe SwiftUI only. `ZStack` / `VStack` / `HStack` / `Text` / `Button` /
// `RoundedRectangle` / `Color` are all iOS-13+. NO ScrollView / Lazy* (they render
// BLANK under the `ImageRenderer` snapshot path); plain stacks only. The two footer
// buttons use `.buttonStyle(PlainButtonStyle())` (mirrors `LBPButton`).

/// The family-1「聯絡商家」confirm modal (`LBPAlertModal`). Renders a centered card
/// (title「聯繫商家」/ body「確定要開啟商城指定的客服連結嗎?」/ horizontal [取消][確定]
/// footer) over a black-0.55 scrim. `onConfirm` proceeds to the host-wired service-link
/// exit; `onDismiss` (or a scrim tap) just closes the modal.
public struct ContactMerchantModalView: View {

    /// The resolved reference-ui theme (FIRST positional argument, always).
    public let theme: ReferenceUITheme

    /// 「確定」CTA → proceed to open the customer-service link. `PlayerShellView` wires
    /// this to the existing `model.openServiceLink()` exit (the host then opens the
    /// link). nil for demo / snapshot instances — the button is inert.
    private let onConfirm: (() -> Void)?

    /// 「取消」/ scrim tap → dismiss the modal WITHOUT opening the link. nil for demo /
    /// snapshot instances.
    private let onDismiss: (() -> Void)?

    public init(
        theme: ReferenceUITheme,
        onConfirm: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.theme = theme
        self.onConfirm = onConfirm
        self.onDismiss = onDismiss
    }

    public var body: some View {
        ZStack {
            // Full-bleed dim scrim (LBPAlertModal backdrop). Tap = dismiss (design
            // `lbp-fade-in` backdrop). edgesIgnoringSafeArea so it covers the whole
            // video area behind the centered card.
            Color.black.opacity(0.55)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture { onDismiss?() }

            // Centered alert card (LBPAlertModal): title + body + horizontal 2-button row.
            VStack(spacing: 0) {
                Text(Self.title)
                    .font(.system(size: 17 * theme.fontScale, weight: .bold))
                    .foregroundColor(theme.text)
                    .multilineTextAlignment(.center)

                Text(Self.body)
                    .font(.system(size: 13 * theme.fontScale))
                    .foregroundColor(Self.textDim)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)

                footer
                    .padding(.top, 22)
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 18)
            .frame(maxWidth: 320)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(theme.background))
            .shadow(color: Color.black.opacity(0.3), radius: 30, x: 0, y: 20)
            .padding(.horizontal, 36)
        }
    }

    // MARK: - Horizontal two-button footer (LBPAlertModal row: [plain][primary])
    //
    // Left「取消」plain (transparent fill, strokeStrong 1px border, theme.text). Right
    // 「確定」primary (accent fill, #fff fg). Equal width, 12pt corner, 13pt vertical
    // padding, `gap: 10` (design `flex` row).

    private var footer: some View {
        HStack(spacing: 10) {
            // Plain「取消」(LBPButton plain).
            Button(action: { onDismiss?() }) {
                Text(Self.cancelLabel)
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

            // Primary「確定」(LBPButton primary).
            Button(action: { onConfirm?() }) {
                Text(Self.confirmLabel)
                    .font(.system(size: 15 * theme.fontScale, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(theme.accent))
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    // MARK: - Decorative design tokens (literal minimal hex via Color(hex:))

    /// `theme.surface.textDim` (body text). Matches `AuthGateModalView`.
    static let textDim = Color(hex: "#6B6775") ?? Color.gray
    /// `theme.surface.strokeStrong` (plain-button outline). Matches `AuthGateModalView`.
    static let strokeStrong = Color(hex: "#D8D5DE") ?? Color.gray.opacity(0.35)

    // MARK: - Fixed localized copy (static presentation strings, 繁中 — verbatim 設計稿)

    static let title = "聯繫商家"
    static let body = "確定要開啟商城指定的客服連結嗎?"
    static let cancelLabel = "取消"
    static let confirmLabel = "確定"
}

// MARK: - Deterministic demo seed (previews + snapshot tests)

public extension ContactMerchantModalView {

    /// A deterministic, action-free demo confirm modal. Renders correctly with all
    /// actions nil.
    static func demo(theme: ReferenceUITheme) -> ContactMerchantModalView {
        ContactMerchantModalView(theme: theme)
    }
}

#if DEBUG
struct ContactMerchantModalView_Previews: PreviewProvider {
    static var previews: some View {
        let theme = ReferenceUIThemePalette.minimal
        ZStack {
            Color(hex: "#2A2730") ?? .gray
            ContactMerchantModalView.demo(theme: theme)
        }
        .frame(width: 393, height: 520)
        .previewLayout(.sizeThatFits)
        .previewDisplayName("contact-merchant confirm")
    }
}
#endif
