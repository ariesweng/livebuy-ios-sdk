import SwiftUI
import LivebuyUI

// MARK: - CartToastView — family-3 add-to-cart success toast (~1.8s confirmation)
//
// Spec: `reference-ui-rendering/spec.md` § "加入購物車成功提示 toast（iOS reference-ui）".
// Design: `design/templates/minimal/sdk-components.jsx` `LBPCartToast`.
//
// A small dark-glass pill flashed for ~1.8s after an add-to-cart SUCCEEDS (the bound
// template's `cartCount` ticks up via `cartCTA.incrementOnAdd()`). It is PURE呈現: it
// reads only `theme` (accent ring) + a label, owns NO timer, NO business state, and NO
// trigger logic — `ProductSheetsOverlayView` drives its presentation (transient @State,
// auto-dismiss, slide-in transition). The accent-ringed checkmark springs in on appear
// (`LBPCartToast` `lbp-toast-check`); the pill's slide-up (`lbp-toast-in`) is the
// container's `.transition`.
//
// `allowsHitTesting(false)` is applied by the container so the toast never eats taps.
//
// iOS-14-safe SwiftUI only: `HStack` / `ZStack` / `Circle` / `Image(systemName:)` /
// `Text` / `Capsule` / `scaleEffect` / `withAnimation`. No Lazy* / AsyncImage /
// .foregroundStyle / .tint.

/// The add-to-cart success toast: a dark-glass pill with an accent-ringed checkmark + a
/// confirmation label ("已加入購物車").
public struct CartToastView: View {
    /// Observed so a runtime language switch re-renders this view's localized copy
    /// (`rb-ios-i18n-string-table`; see `ReferenceUILanguage`).
    @ObservedObject var l10n = ReferenceUILanguage.shared

    /// The resolved reference-ui theme (FIRST positional argument, always). The accent
    /// drives the checkmark ring (design `LBPCartToast` `background: accent`).
    public let theme: ReferenceUITheme

    /// The confirmation label (design default 「已加入購物車」).
    public let label: String

    /// The default confirmation label in the current reference-ui language (string table key
    /// `cart_added_toast`, `rb-ios-i18n-string-table`; zh-TW 「已加入購物車」).
    public static var defaultLabel: String { ReferenceUIStrings.text("cart_added_toast") }

    /// Checkmark entrance scale. Initialised to the RESTING value (1.0) so a snapshot
    /// (no `onAppear` under `ImageRenderer`, mirrors `ProductZoomOverlayView`) captures
    /// the final state byte-stably; `onAppear` resets it small and springs it back at
    /// runtime for the `lbp-toast-check` bounce.
    @State private var checkScale: CGFloat

    /// `true` → the add-to-cart FAILURE variant (rb-ios-cart-add-failure-toast, design
    /// `LBPCartToast variant='error'`): danger `#EB6E5F` circle with ✕ + 「加入購物車失敗，請稍後再試」.
    public let isError: Bool

    /// The failure label in the current reference-ui language (`detail_add_failed`).
    public static var errorLabel: String { ReferenceUIStrings.text("detail_add_failed") }

    /// Failure badge color — design danger `#EB6E5F` (same as `ErrorScreenView`).
    static let danger = Color(hex: "#EB6E5F") ?? .red

    public init(theme: ReferenceUITheme, label: String? = nil, isError: Bool = false) {
        self.theme = theme
        self.isError = isError
        self.label = label ?? (isError ? CartToastView.errorLabel : CartToastView.defaultLabel)
        self._checkScale = State(initialValue: 1.0)
    }

    public var body: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(isError ? Self.danger : theme.accent)
                    .frame(width: 24, height: 24)
                Image(systemName: isError ? "xmark" : "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
            }
            .scaleEffect(checkScale)
            Text(label)
                .font(.system(size: 13.5 * theme.fontScale, weight: .bold))
                .foregroundColor(.white)
        }
        .padding(.leading, 12)
        .padding(.trailing, 16)
        .padding(.vertical, 10)
        .background(
            Capsule().fill(Self.glass))
        .accessibilityIdentifier(LBAccessibilityID.cartToast)
        .onAppear {
            // Runtime bounce (lbp-toast-check): start small, spring back to resting with a
            // low damping fraction so it overshoots (~1.15) then settles. Snapshot path
            // never runs onAppear, so the resting initial value above is what it captures.
            checkScale = 0.4
            withAnimation(.spring(response: 0.34, dampingFraction: 0.55).delay(0.06)) {
                checkScale = 1.0
            }
        }
    }

    /// Dark-glass pill surface (design `LBPCartToast` rgba(20,20,24,0.86)).
    static let glass = (Color(hex: "#141418") ?? .black).opacity(0.86)
}

#if DEBUG
struct CartToastView_Previews: PreviewProvider {
    static var previews: some View {
        CartToastView(theme: ReferenceUIThemePalette.minimal)
            .padding()
            .background(Color.black)
            .previewLayout(.sizeThatFits)
    }
}
#endif
