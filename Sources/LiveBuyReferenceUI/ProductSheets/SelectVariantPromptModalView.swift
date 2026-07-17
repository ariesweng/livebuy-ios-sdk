import SwiftUI
import LivebuySDK
import LivebuyUI

// MARK: - SelectVariantPromptModalView — family-3「請選規格」acknowledge modal (LBPAlertModal)
//
// Spec: `reference-ui-rendering/spec.md` (family-3 product + sheets —「請選規格」prompt).
// Design: `design/templates/minimal/sdk-components.jsx` `LBPAlertModal` (centered card over a
//          black-0.55 scrim, 18pt corner card) — single-CTA acknowledge variant.
//
// The add-to-cart guard's「請選規格」prompt. The template's `addToCart()` sets
// `DefaultPlayerTemplate.needsVariantSelection = true` when a spec product is added without a
// complete variant selection; the CONTAINER (`ProductSheetsOverlayView`) presents THIS modal at
// the player overlay root (above the sheet stack, with its OWN full-bleed scrim — same overlay-root
// idiom as `AuthGateModalView` for the cart-needs-login gate). It is a full-frame centered modal,
// NOT nested inside the bottom-sheet card: a full-bleed scrim mounted INSIDE the sheet card distorts
// the card's `GeometryReader` height measurement and breaks the sheet layout (the bug this fixes).
//
// Acknowledge-only: a single primary「我知道了」(and a scrim tap) dismisses the prompt via the
// container's LOCAL presentation flag (`onDismiss`) so the user can reach the variant chips and
// complete the selection. `needsVariantSelection` itself is template-owned read-only state (cleared
// by `selectVariant` once a spec resolves) — reference-ui never flips it.
//
// SUB-VIEW INPUT PATTERN (family convention): `theme:` first; then the action closure (LAST, `= nil`).
// There is no bound snapshot value — the copy is fixed. It reads NOTHING back from the model (one-way
// data flow) and renders correctly with the action nil (so demo / preview construct it action-free).
//
// iOS-14-safe SwiftUI only. `ZStack` / `VStack` / `Text` / `Button` / `RoundedRectangle` / `Color`
// are all iOS-13+. NO ScrollView / Lazy* (they render BLANK under the `ImageRenderer` snapshot path).

/// The family-3「請選規格」acknowledge modal (`LBPAlertModal`, single-CTA). Renders a centered card
/// (title「請選規格」/ body「請先選擇商品規格，再加入購物車。」/ full-width「我知道了」) over a
/// black-0.55 scrim. `onDismiss` (the「我知道了」CTA or a scrim tap) closes the prompt.
public struct SelectVariantPromptModalView: View {

    /// The resolved reference-ui theme (FIRST positional argument, always).
    public let theme: ReferenceUITheme

    /// 「我知道了」/ scrim tap → dismiss the prompt (the container clears its local presentation
    /// flag). nil for demo / preview instances — the button is inert.
    private let onDismiss: (() -> Void)?

    public init(
        theme: ReferenceUITheme,
        onDismiss: (() -> Void)? = nil
    ) {
        self.theme = theme
        self.onDismiss = onDismiss
    }

    public var body: some View {
        ZStack {
            // Full-bleed dim scrim (LBPAlertModal backdrop). Tap = dismiss. edgesIgnoringSafeArea
            // so it covers the whole player frame behind the centered card — and, mounted at the
            // overlay root, it does NOT distort any sheet card's height (the bug this fixes).
            Color.black.opacity(0.55)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture { onDismiss?() }

            // Centered alert card (LBPAlertModal): title + body + single full-width primary CTA.
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

                // Primary「我知道了」(LBPButton primary) — full width. Acknowledging dismisses the
                // prompt so the user can reach the variant chips (the prompt's whole point).
                Button(action: { onDismiss?() }) {
                    Text(Self.primaryLabel)
                        .font(.system(size: 15 * theme.fontScale, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            // 統一按鈕圓角 → theme.cornerRadius（rb-ios-button-corner-radius-unify）。
                            RoundedRectangle(cornerRadius: theme.cornerRadius)
                                .fill(theme.accent))
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.top, 22)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 22)
            .frame(maxWidth: 300)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(theme.background))
            .shadow(color: Color.black.opacity(0.3), radius: 30, x: 0, y: 20)
            .padding(.horizontal, 28)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(LBAccessibilityID.variantPrompt)
    }

    // MARK: - Decorative design tokens (literal minimal hex via Color(hex:))

    /// `theme.surface.textDim` (body / caption text). Matches `ContactMerchantModalView` /
    /// `AuthGateModalView`.
    static let textDim = Color(hex: "#6B6775") ?? Color.gray

    // MARK: - Fixed localized copy (static presentation strings, 繁中)

    static let title = "請選規格"
    static let body = "請先選擇商品規格，再加入購物車。"
    static let primaryLabel = "我知道了"
}

// MARK: - Deterministic demo seed (previews)

public extension SelectVariantPromptModalView {

    /// A deterministic, action-free demo prompt. Renders correctly with the action nil.
    static func demo(theme: ReferenceUITheme) -> SelectVariantPromptModalView {
        SelectVariantPromptModalView(theme: theme)
    }
}

#if DEBUG
struct SelectVariantPromptModalView_Previews: PreviewProvider {
    static var previews: some View {
        let theme = ReferenceUIThemePalette.minimal
        ZStack {
            Color(hex: "#2A2730") ?? .gray
            SelectVariantPromptModalView.demo(theme: theme)
        }
        .frame(width: 393, height: 520)
        .previewLayout(.sizeThatFits)
        .previewDisplayName("select-variant prompt")
    }
}
#endif
