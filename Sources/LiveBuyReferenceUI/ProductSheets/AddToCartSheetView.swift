import SwiftUI
import LiveBuySDK
import LiveBuyUI

// MARK: - AddToCartSheetView — family-3 compact purchase sheet (design `AddToCartSheet`)
//
// Spec: `reference-ui-rendering/spec.md` (family-3 product + sheets, 商品明細 sheet —
//        `.addToCart` 呈現) — rb-ios-product-action-sheet.
// Design: `design/templates/minimal/screens.jsx` `AddToCartSheet` (699-775).
//
// The product LIST 加購鈕 (in-stock cart glyph) opens THIS compact purchase sheet — the
// design's `AddToCartSheet`: 縮圖 + 名 + 價 + 變體 picker + 數量 stepper + 加入購物車 CTA,
// header「加入購物車」, and crucially NO 收藏 / 分享 footer (that 3-slot footer belongs to the
// full ProductDetailSheet, opened from the 明細鈕 / 商品名). To avoid duplicating the
// variant / qty / CTA / 請選規格 / 加購失敗 logic, this is a THIN WRAPPER over
// `ProductDetailSheetView` with `presentation: .addToCart` (which switches the header title
// and drops 收藏 / 分享). It carries no faved / onToggleFavorite / onShare inputs (those are
// detail-only). The shared SheetKit presenter draws the chrome (grab handle + scrim + slide).

/// The compact「加入購物車」purchase sheet for one in-stock `LBProductDetailState`. Renders the
/// product photo / name / price + variant chips + qty stepper + 加入購物車 CTA (no 收藏 / 分享),
/// reusing `ProductDetailSheetView`'s `.addToCart` presentation so there is no logic duplication.
public struct AddToCartSheetView: View {

    public let theme: ReferenceUITheme
    public let detail: LBProductDetailState
    public let variant: LBVariantState
    public let qty: LBQtyState
    public let cartCount: Int
    public let needsVariantSelection: Bool
    public let addToCartFailed: Bool
    /// `false` (snapshot / demo) → gradient placeholder; `true` (runtime) → real photo.
    public let live: Bool

    private let onSelectVariant: ((_ groupIndex: Int, _ optionIndex: Int) -> Void)?
    private let onSetQty: ((Int) -> Void)?
    private let onInc: (() -> Void)?
    private let onDec: (() -> Void)?
    private let onAddToCart: (() -> Void)?
    private let onOpenCart: (() -> Void)?
    private let onDismiss: (() -> Void)?
    /// Host-wired zoom badge tap → container opens the full-frame lightbox. Forwarded
    /// to the inner `ProductDetailSheetView` (rb-ios-product-image-zoom-lightbox).
    private let onZoomImage: (() -> Void)?

    public init(
        theme: ReferenceUITheme,
        detail: LBProductDetailState,
        variant: LBVariantState,
        qty: LBQtyState,
        cartCount: Int,
        needsVariantSelection: Bool,
        addToCartFailed: Bool,
        live: Bool = false,
        onSelectVariant: ((_ groupIndex: Int, _ optionIndex: Int) -> Void)? = nil,
        onSetQty: ((Int) -> Void)? = nil,
        onInc: (() -> Void)? = nil,
        onDec: (() -> Void)? = nil,
        onAddToCart: (() -> Void)? = nil,
        onOpenCart: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil,
        onZoomImage: (() -> Void)? = nil
    ) {
        self.theme = theme
        self.detail = detail
        self.variant = variant
        self.qty = qty
        self.cartCount = cartCount
        self.needsVariantSelection = needsVariantSelection
        self.addToCartFailed = addToCartFailed
        self.live = live
        self.onSelectVariant = onSelectVariant
        self.onSetQty = onSetQty
        self.onInc = onInc
        self.onDec = onDec
        self.onAddToCart = onAddToCart
        self.onOpenCart = onOpenCart
        self.onDismiss = onDismiss
        self.onZoomImage = onZoomImage
    }

    public var body: some View {
        ProductDetailSheetView(
            theme: theme,
            detail: detail,
            variant: variant,
            qty: qty,
            cartCount: cartCount,
            needsVariantSelection: needsVariantSelection,
            addToCartFailed: addToCartFailed,
            presentation: .addToCart,
            live: live,
            onSelectVariant: onSelectVariant,
            onSetQty: onSetQty,
            onInc: onInc,
            onDec: onDec,
            onAddToCart: onAddToCart,
            onOpenCart: onOpenCart,
            onDismiss: onDismiss,
            onZoomImage: onZoomImage)
    }
}

// MARK: - Deterministic demo seed (previews + snapshot tests)

public extension AddToCartSheetView {

    /// A deterministic demo add-to-cart sheet WITH a variant group (顏色) + in-stock qty,
    /// pre-add (no guards). Mirrors `ProductDetailSheetView.demo`'s fixtures, action-free.
    static func demo(theme: ReferenceUITheme) -> AddToCartSheetView {
        AddToCartSheetView(
            theme: theme,
            detail: ProductSheetsModel.demoDetail(),
            variant: ProductSheetsModel.demoVariantWithGroup,
            qty: ProductSheetsModel.demoQtyInStock,
            cartCount: 1,
            needsVariantSelection: false,
            addToCartFailed: false)
    }
}

#if DEBUG
struct AddToCartSheetView_Previews: PreviewProvider {
    static var previews: some View {
        let theme = ReferenceUIThemePalette.minimal
        AddToCartSheetView.demo(theme: theme)
            .previewDisplayName("add-to-cart · variant + qty")
            .frame(width: 393, height: 560)
            .previewLayout(.sizeThatFits)
    }
}
#endif
