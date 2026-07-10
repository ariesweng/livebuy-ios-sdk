import SwiftUI
import LiveBuySDK
import LiveBuyUI

// MARK: - ProductDetailSheetView — family-3 product sheet-stack surface 2 (detail + variant + qty + add-to-cart)
//
// Spec: `reference-ui-rendering/spec.md` (family-3 product + sheets)
// Design: rb-ios-product-sheets design.md D-3 +
//          `design/templates/minimal/screens.jsx` `ProductDetailSheet` (597-686) /
//          `AddToCartSheet` (688-764) +
//          `design/templates/minimal/sdk-components.jsx` `LBPVariantPicker` (916) /
//          `LBPQtyStepper` (945) / `LBPButton` (969) / `LBPCartCTA` (993) /
//          `LBPAlertModal` (1009) / `LBPBottomSheet` (751) / `LBPSheetHeader` (787).
//
// The product-DETAIL sheet for ONE `LBProductDetailState`. It is the second of the
// four family-3 surface sub-views composed by `ProductSheetsOverlayView`, and it
// implements the agreed SUB-VIEW INPUT PATTERN documented in
// `ProductSheetsOverlayView.swift`:
//
//   1. `theme: ReferenceUITheme`            — FIRST positional argument, always.
//   2. bound SNAPSHOT VALUES               — `detail: LBProductDetailState`,
//      `variant: LBVariantState`, `qty: LBQtyState`, `cartCount: Int`,
//      `needsVariantSelection: Bool`, `addToCartFailed: Bool` — passed BY VALUE
//      from `ProductSheetsModel` (never the model, never the template).
//   3. action closures (LAST, each `= nil`) — `onSelectVariant` (chip tap →
//      `template.selectVariant`), `onSetQty` / `onInc` / `onDec` (qty stepper →
//      `template.setQty/incQty/decQty`), `onAddToCart` (加入購物車 →
//      `template.addToCart()`), `onOpenCart` (cart CTA → `template.cartCTA.openCart`),
//      `onDismiss` (close → clears the container's presentation binding).
//
// This sub-view reads ONLY its passed-in values; it never reaches back into
// `ProductSheetsModel` / `DefaultPlayerTemplate` (one-way data flow, D-1). It also
// renders correctly with all actions nil (so demo / snapshot tests construct it
// action-free).
//
// reference-ui NEVER builds HTTP nor calls core `addToCart` — the 加入購物車 CTA
// funnels to `onAddToCart`, which the container wires to `model.addToCart()` →
// `template.addToCart()` (the template assembles the route-B `LBCartRequest` and
// delegates to the injected core requester). D-3.
//
// Variant / qty / add-to-cart guards (D-3):
//   • `LBPVariantPicker` is drawn once per `variant.groups`; the selected chip is
//     `variant.selection[groupIndex]`. Chip tap → `onSelectVariant(group, option)`.
//   • `LBPQtyStepper` is bound to `qty.qty` within `[qty.min, qty.max]`; it is
//     DISABLED when `qty.max == 0` (sold out). `-`/value/`+` → `onDec`/`onSetQty`/`onInc`.
//   • The primary 加入購物車 CTA is DISABLED when sold out (`qty.max == 0`).
//   • `needsVariantSelection` is retained as an input but the「請選規格」prompt is NO
//     LONGER rendered here — it is hoisted to the CONTAINER (`ProductSheetsOverlayView`)
//     as a full-frame centered modal at the player overlay root (`SelectVariantPromptModalView`,
//     same overlay-root idiom as the cart-needs-login `AuthGateModalView`). Mounting its
//     full-bleed scrim INSIDE this sheet card distorted the card's `GeometryReader` height
//     measurement and broke the sheet layout (ios-variant-prompt-overlay-fix).
//   • When `addToCartFailed` is true, a retryable error banner is shown.
//
// iOS-14-safe SwiftUI only. `VStack` / `HStack` / `ZStack` / `Text` / `Button` /
// `RoundedRectangle` / `Color` / `LinearGradient` are all iOS-13+. The sheet top
// reuses the iOS-14-safe `TopRoundedRectangle` shape + the grab handle /
// `LBPBottomSheet` / centered-header styling established by `VideoInfoPanelView`
// (D-3 "reuse the TopRoundedRectangle + LBPBottomSheet styling") — `TopRounded
// Rectangle` is NOT redefined here (it lives in `VideoInfoPanelView.swift`). No
// `.task` / `AsyncImage` / `NavigationStack` / `.foregroundStyle` / `.tint`.

/// The family-3 product-detail sheet for one `LBProductDetailState`. Renders the
/// product photo / name / price (with strike-through original), the variant chip
/// picker (one `LBPVariantPicker` per group), the qty stepper, and the primary
/// 加入購物車 CTA — plus the「請選規格」prompt and the retryable add-to-cart failure
/// banner when their guard flags are set.
public struct ProductDetailSheetView: View {

    /// How this sheet presents the same product-detail state (rb-ios-product-action-sheet):
    /// `.detail` = full browse (header「商品明細」+ 3-slot `[收藏][分享][CTA]` footer);
    /// `.addToCart` = compact purchase (header「加入購物車」+ CTA-only footer, no 收藏/分享),
    /// the design's `AddToCartSheet`. `AddToCartSheetView` is the thin wrapper that picks
    /// `.addToCart`. Defaults to `.detail` so existing call sites / baselines are unchanged.
    public enum Presentation { case detail, addToCart }

    /// The resolved reference-ui theme (FIRST positional argument, always).
    public let theme: ReferenceUITheme

    /// The product-detail this sheet renders (`DefaultProductSheet.detail`). Read-only.
    public let detail: LBProductDetailState
    /// Variant-picker snapshot (`DefaultVariantPicker.state`). Read-only.
    public let variant: LBVariantState
    /// Qty-stepper snapshot (`DefaultQtyStepper.state`) — `{ qty, min, max }`. Read-only.
    public let qty: LBQtyState
    /// Per-session successful-add count (`DefaultCartCTA.state.count`). The cart CTA
    /// badge is drawn when `> 0`. Read-only.
    public let cartCount: Int
    /// 「請選規格」guard flag (`DefaultPlayerTemplate.needsVariantSelection`). Read-only.
    public let needsVariantSelection: Bool
    /// Add-to-cart failure flag (`DefaultPlayerTemplate.addToCartFailed`). Read-only.
    public let addToCartFailed: Bool
    /// Add-to-cart「請求進行中」flag (`addToCartInFlight`, cart-add-loading-state). When true the
    /// CTA shows a spinner +「加入中…」(keeping the accent fill) and the qty stepper / variant
    /// chips lock. Read-only; default false → snapshot-neutral.
    public let addToCartInFlight: Bool
    /// 收藏（到貨追蹤 type=1）旗標（`DefaultGoodsTracking.awaitEnabled(for: goodsGpn)`）. Read-only.
    public let faved: Bool
    /// Presentation mode (`.detail` browse vs `.addToCart` compact purchase). Read-only.
    public let presentation: Presentation
    /// `false` (snapshot / demo) → the photo draws the deterministic gradient placeholder only
    /// (baselines unchanged). `true` (host runtime) → load `detail.photos[0]` over it via
    /// `RemoteStillImageView` (rb-ios-product-real-images).
    public let live: Bool
    /// Genuinely-live signal (rb-ios-live-hide-product-share, design R12) — `ProductSheetsModel.isLive`
    /// (`DefaultPlayerHeaderState.isLive` republish, `liveStatus == 1`). DISTINCT from `live` above
    /// (that one only gates real-photo loading; this one gates the share button). `.detail`
    /// presentation's 分享 (share) button in the 3-slot `[收藏][分享][CTA]` footer is hidden when
    /// `isLive == true` — a genuinely-live product has no settled "start time" a share link could
    /// carry (unlike VOD / a finished-live replay, which have a real `beginTime`). 收藏 (favorite) is
    /// unaffected. Default `false` → existing call sites / snapshots byte-identical.
    public let isLive: Bool
    /// 商品說明（`LBProduct.brief`）— `.detail` 呈現在價格下方畫一段說明（對齊設計 `ProductDetailSheet`
    /// 的說明文字）。`LBProductDetailState` 不帶 `brief`，故由容器 / `ProductSheetsModel` 從
    /// `productOverlay.products` 快照以 `detail.productId` 解析後傳入（`brief(forProductId:)`）。空字串
    /// → 不畫（使既有無 brief 的 demo / baseline byte-identical）。`.addToCart` 呈現不畫。Read-only.
    public let brief: String

    /// Host-wired variant chip tap → `model.selectVariant(...)` → `template.selectVariant`.
    /// nil for demo / snapshot instances.
    private let onSelectVariant: ((_ groupIndex: Int, _ optionIndex: Int) -> Void)?
    /// Host-wired direct qty set → `model.setQty(_:)` → `template.setQty(_:)`.
    private let onSetQty: ((Int) -> Void)?
    /// Host-wired qty `+` → `model.incQty()` → `template.incQty()`.
    private let onInc: (() -> Void)?
    /// Host-wired qty `-` → `model.decQty()` → `template.decQty()`.
    private let onDec: (() -> Void)?
    /// Host-wired 加入購物車 → `model.addToCart()` → `template.addToCart()`. reference-ui
    /// NEVER calls core addToCart directly (D-3). nil for demo / snapshot instances.
    private let onAddToCart: (() -> Void)?
    /// Host-wired cart-CTA tap → `model.openCart()` → `template.cartCTA.openCart()`.
    private let onOpenCart: (() -> Void)?
    /// Host-wired 收藏 toggle → `model.toggleFavorite()` → `DefaultGoodsTracking.toggleAwait(goodsGpn)`.
    /// reference-ui NEVER calls core directly. nil for demo / snapshot instances.
    private let onToggleFavorite: (() -> Void)?
    /// Host-wired 分享 tap (the design's 3-slot footer middle slot). Share is a HOST
    /// CONCERN — the headless SDK exposes no share route, so reference-ui simply
    /// FORWARDS the intent to this closure (the container provides it as a host
    /// passthrough). reference-ui NEVER builds share logic / calls core / template.
    /// nil for demo / snapshot instances (the button renders correctly action-free).
    private let onShare: (() -> Void)?
    /// Host-wired close / dismiss (clears the container's presentation binding).
    private let onDismiss: (() -> Void)?
    /// Host-wired product-image zoom badge tap → container opens the full-frame
    /// `ProductZoomOverlayView` (rb-ios-product-image-zoom-lightbox). nil for demo /
    /// snapshot instances (the badge renders byte-identical to the prior decorative
    /// badge; tap is a no-op).
    private let onZoomImage: (() -> Void)?

    public init(
        theme: ReferenceUITheme,
        detail: LBProductDetailState,
        variant: LBVariantState,
        qty: LBQtyState,
        cartCount: Int,
        needsVariantSelection: Bool,
        addToCartFailed: Bool,
        addToCartInFlight: Bool = false,
        faved: Bool = false,
        presentation: Presentation = .detail,
        live: Bool = false,
        isLive: Bool = false,
        brief: String = "",
        onSelectVariant: ((_ groupIndex: Int, _ optionIndex: Int) -> Void)? = nil,
        onSetQty: ((Int) -> Void)? = nil,
        onInc: (() -> Void)? = nil,
        onDec: (() -> Void)? = nil,
        onAddToCart: (() -> Void)? = nil,
        onOpenCart: (() -> Void)? = nil,
        onToggleFavorite: (() -> Void)? = nil,
        onShare: (() -> Void)? = nil,
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
        self.addToCartInFlight = addToCartInFlight
        self.faved = faved
        self.presentation = presentation
        self.live = live
        self.isLive = isLive
        self.brief = brief
        self.onSelectVariant = onSelectVariant
        self.onSetQty = onSetQty
        self.onInc = onInc
        self.onDec = onDec
        self.onAddToCart = onAddToCart
        self.onOpenCart = onOpenCart
        self.onToggleFavorite = onToggleFavorite
        self.onShare = onShare
        self.onDismiss = onDismiss
        self.onZoomImage = onZoomImage
    }

    // MARK: - Derived presentation (pure)

    /// Sold-out / out-of-stock (`qty.max == 0`, set by `DefaultQtyStepper`'s bounds
    /// rule when `soldOut == 1 || stock <= 0`). Drives the disabled qty stepper +
    /// disabled CTA + the「已售完」price treatment.
    private var isSoldOut: Bool { qty.max == 0 }

    /// Whether an original (was) price worth striking through exists.
    private var hasOriginalPrice: Bool {
        !detail.originalPriceShow.isEmpty && detail.originalPriceShow != detail.priceShow
    }

    public var body: some View {
        // Content only — the shared `.lbBottomSheet(item:)` presenter (SheetKit) draws the
        // grab handle + `theme.background` + `TopRoundedRectangle(20)` + shadow + dim scrim +
        // drag-to-dismiss (sheetkit-migrate, replacing the prior system `.sheet(item:)`).
        // 「請選規格」prompt is NOT rendered here: it is hoisted to the CONTAINER
        // (`ProductSheetsOverlayView`) as a full-frame centered modal at the player overlay root
        // (`SelectVariantPromptModalView`, same idiom as the cart-needs-login `AuthGateModalView`).
        // Mounting its full-bleed scrim INSIDE this sheet card distorted the card's GeometryReader
        // height measurement and broke the sheet layout (ios-variant-prompt-overlay-fix). The
        // `needsVariantSelection` input is retained (wrapper / call-site / test signatures unchanged);
        // the container reads `model.needsVariantSelection` to drive the hoisted prompt.
        sheetContent
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(LBAccessibilityID.productDetail)
    }

    // MARK: - Sheet content (header + scrollable body + sticky footer)

    private var sheetContent: some View {
        // Pinned header + scrollable body + pinned footer (rb-ios-sheet-pinned-header-footer):
        // the 商品明細 title / close pin at top, the 加入購物車 CTA pins at bottom, only the
        // photo / variant / qty body scrolls (within the ½-screen cap). Snapshot path stays
        // content-sized (byte-identical) via `LBSheetScaffold`'s `lbSheetHeightUncapped` branch.
        // `.addToCart`（精簡購買 sheet）固定填滿到 cap，與 NotifyRestock 同高（對齊設計稿
        // rb-ios-addtocart-sheet-height-align-restock）；`.detail` 維持 content-sized。
        LBSheetScaffold(fillToCap: presentation == .addToCart) {
            header
        } bodyContent: {
            VStack(alignment: .leading, spacing: 0) {
                // `.addToCart` (購買) uses the design's compact 96×96 product card (aligned with
                // NotifyRestockSheetView); `.detail` (瀏覽) keeps the 4:3 large photo.
                if presentation == .addToCart {
                    compactProductCard
                } else {
                    productPhoto
                    productName
                        .padding(.top, 12)
                    priceRow
                        .padding(.top, 10)
                    // 商品說明（`brief`）— 只在 `.detail`、且 brief 非空時畫（對齊設計 `ProductDetailSheet`
                    // 的說明文字：12pt / textDim / 多行；rb-ios-product-sheet-detail-polish 問題 4）。
                    if !brief.isEmpty {
                        briefDescription
                            .padding(.top, 10)
                    }
                }

                if !variant.groups.isEmpty {
                    hairline.padding(.vertical, 18)
                    variantPickers
                }

                hairline.padding(.vertical, 18)
                qtyRow

                // Add-to-cart failure banner (retryable), only when the route-B
                // add threw (D-3). Sits above the footer so it reads as feedback.
                if addToCartFailed {
                    failureBanner.padding(.top, 16)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 12)
        } footer: {
            footer
        }
    }

    // MARK: - Sheet header (LBPSheetHeader — centered title + trailing close)
    //
    // DELIBERATE DEVIATION (data gap — rb-align-ios-product-sheets): the design's
    // ProductDetailSheet header is a LEFT-aligned HOST-BADGE row (host avatar + host
    // name + trailing close; screens.jsx:615-640). reference-ui's product-detail
    // view-model `LBProductDetailState` carries NO host data (name / avatar live in
    // the channel / show, not the product detail), so a faithful host-badge header
    // would need a template/core model field → cross-layer, out of this reference-ui
    // change's scope. We keep the centered「商品明細」title (LBPSheetHeader) and record
    // the gap here. Likewise the design's product sub-line (`product.sub`) and a
    // 「已選: <variant labels>」caption are NOT drawn: `LBProductDetailState` has no
    // `sub` field, and the current selection is already conveyed by the highlighted
    // variant chip — both are documented data-gap deviations, not oversights.

    private var header: some View {
        ZStack {
            // 標題只在 .detail 呈現畫「商品明細」；`.addToCart` 呈現 MUST NOT 畫標題——只留右上角
            // 關閉鈕（對齊設計 `AddToCartSheet` header 的 `flex-end` close-only，rb-ios-product-sheet-detail-polish）。
            if presentation == .detail {
                Text(Self.headerTitle)
                    .font(.system(size: 15 * theme.fontScale, weight: .bold))
                    .foregroundColor(theme.text)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            HStack {
                Spacer(minLength: 0)
                // Shared transparent close (rb-ios-sheet-header-close-unify) — was a
                // `Circle(bgSunken) + xmark 11pt`; now aligned to ProductListView / design.
                // Behavior unchanged: tap → `onDismiss` → container `dismissDetail()`.
                SheetHeaderCloseButton(theme: theme, onTap: onDismiss)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    // MARK: - Product photo (AddToCartSheet 4:3 thumb — deterministic placeholder)
    //
    // `photos` are remote URLs; reference-ui keeps snapshots deterministic (no
    // network / AsyncImage), so it draws a 4:3 gradient placeholder chip with a
    // monogram (host can swap in a real image). Mirrors the design's rounded media.

    private var productPhoto: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(hex: "#FFD7A8") ?? .orange,
                    Color(hex: "#E27D5A") ?? .orange,
                ]),
                startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(Self.monogram(for: detail.name))
                .font(.system(size: 26 * theme.fontScale, weight: .heavy))
                .foregroundColor(.white.opacity(0.92))
            // `live` + a real photo → the product image loads over the gradient placeholder
            // (rb-ios-product-real-images). Snapshot / demo (`live == false`) keeps the gradient.
            if live, let url = Self.photoURL(detail) {
                RemoteStillImageView(url: url, contentMode: .scaleAspectFill)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 168)
        // Zoom affordance (design `screens.jsx:644-647`: right:10 bottom:10, 32×32,
        // white@0.85 disc, zoom glyph #15131a). Decorative (pinch-to-zoom is a host
        // concern); paints the design's media-zoom badge over the photo.
        .overlay(zoomBadge, alignment: .bottomTrailing)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// Media-zoom badge pinned to the photo's bottom-trailing corner (design's
    /// `Icons.zoom` disc). TAPPABLE → `onZoomImage` opens the full-frame lightbox
    /// (rb-ios-product-image-zoom-lightbox). `PlainButtonStyle` keeps the disc /
    /// glyph pixels byte-identical to the prior decorative badge.
    private var zoomBadge: some View {
        Button(action: { onZoomImage?() }) {
            ZStack {
                Circle().fill(Color.white.opacity(0.85))
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color(hex: "#15131A") ?? .black)
            }
            .frame(width: 32, height: 32)
        }
        .buttonStyle(PlainButtonStyle())
        .padding(10)
        .accessibilityIdentifier(LBAccessibilityID.zoomBadge)
    }

    // MARK: - Compact product card (AddToCartSheet 96×96 thumb + name + price — design AddToCartSheet)
    //
    // The `.addToCart` presentation uses the design's horizontal product card (96×96 縮圖 + 名 + 價),
    // aligned with `NotifyRestockSheetView.productBlock` — NOT the `.detail` 4:3 large photo.

    private var compactProductCard: some View {
        HStack(alignment: .top, spacing: 14) {
            // 96×96 rounded thumbnail (mirrors NotifyRestockSheetView): bgSunken placeholder,
            // `live` real image (.scaleAspectFill, clipped), bottom-trailing zoom badge.
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Self.bgSunken)
                if live, let url = Self.photoURL(detail) {
                    RemoteStillImageView(url: url, contentMode: .scaleAspectFill)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 24, weight: .regular))
                        .foregroundColor(Self.textFaint)
                }
            }
            .frame(width: 96, height: 96)
            .overlay(compactZoomBadge, alignment: .bottomTrailing)

            VStack(alignment: .leading, spacing: 6) {
                Text(detail.name)
                    .font(.system(size: 15 * theme.fontScale, weight: .bold))
                    .foregroundColor(theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                priceRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Compact-card zoom badge (mirrors NotifyRestockSheetView: black@0.55 24×24 disc, white glyph).
    /// TAPPABLE → `onZoomImage` opens the full-frame lightbox; `PlainButtonStyle` keeps pixels
    /// byte-identical to the prior decorative badge.
    private var compactZoomBadge: some View {
        Button(action: { onZoomImage?() }) {
            ZStack {
                Circle().fill(Color.black.opacity(0.55))
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
            }
            .frame(width: 24, height: 24)
        }
        .buttonStyle(PlainButtonStyle())
        .padding(6)
    }

    // MARK: - Product name (ProductDetailSheet title)

    private var productName: some View {
        Text(detail.name)
            .font(.system(size: 16 * theme.fontScale, weight: .bold))
            .foregroundColor(theme.text)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Product description (商品說明 — design ProductDetailSheet 說明文字)
    //
    // `.detail` 呈現的商品說明，資料 = `LBProduct.brief`（由容器從 products 快照解析後傳入）。
    // 對齊設計 `screens.jsx` ProductDetailSheet 的說明段：`12pt` / `theme.surface.textDim` /
    // `lineHeight 1.6`（多行，`lineSpacing` 約略）。空字串時不畫（呼叫端已 gate）。

    private var briefDescription: some View {
        Text(brief)
            .font(.system(size: 12 * theme.fontScale))
            .foregroundColor(Self.textDim)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Price row (priceShow accent + originalPriceShow strike-through)
    //
    // Sold out → 已售完 in the sold-out color (mirrors AddToCartSheet's sold branch).
    // In stock → accent priceShow + dim strike-through originalPriceShow.

    private var priceRow: some View {
        Group {
            if isSoldOut {
                Text(Self.soldOutLabel)
                    .font(.system(size: 15 * theme.fontScale, weight: .bold))
                    .foregroundColor(Self.soldOutColor)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(detail.priceShow)
                        .font(.system(size: 20 * theme.fontScale, weight: .heavy))
                        .foregroundColor(theme.accent)
                    if hasOriginalPrice {
                        StrikeText(
                            detail.originalPriceShow,
                            font: .system(size: 13 * theme.fontScale),
                            color: Self.textDim)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Variant pickers (one LBPVariantPicker per LBVariantState.group)
    //
    // Chip group: label + flex-wrapped pill chips; the selected chip (selection[gi]) is
    // accent-outlined + accent-tinted (LBPVariantPicker). Chip tap →
    // onSelectVariant(gi, oi). `WrapChips` flex-wraps by natural width via `ChipFlowLayout`
    // (iOS 16+ `Layout`, no `GeometryReader`), falling back to chunked-3 on iOS 14/15 —
    // aligned with the design's `LBPVariantPicker` `flexWrap:'wrap'` and Android `FlowRow`.

    private var variantPickers: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(variant.groups.enumerated()), id: \.offset) { gi, group in
                VStack(alignment: .leading, spacing: 10) {
                    Text(group.label)
                        .font(.system(size: 13 * theme.fontScale, weight: .semibold))
                        .foregroundColor(theme.text)
                    WrapChips(
                        groupIndex: gi,
                        options: group.options,
                        selected: variant.selection[gi],
                        theme: theme,
                        disabled: addToCartInFlight,
                        onSelect: { oi in onSelectVariant?(gi, oi) })
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Qty row (數量 label + stock caption + LBPQtyStepper)
    //
    // Bound to `qty.qty` within `[qty.min, qty.max]`. The stepper is DISABLED when
    // sold out (`qty.max == 0`); `-` is also disabled at `qty.min`, `+` at `qty.max`.

    private var qtyRow: some View {
        HStack(spacing: 12) {
            Text(Self.qtyLabel)
                .font(.system(size: 14 * theme.fontScale, weight: .semibold))
                .foregroundColor(theme.text)
            Spacer(minLength: 0)
            if !isSoldOut {
                Text(stockCaption)
                    .font(.system(size: 12 * theme.fontScale))
                    .foregroundColor(Self.textDim)
            }
            qtyStepper
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// LBPQtyStepper: `-`  value  `+`. Disabled entirely when sold out.
    private var qtyStepper: some View {
        HStack(spacing: 10) {
            stepButton(systemName: "minus", enabled: !isSoldOut && qty.qty > qty.min && !addToCartInFlight) {
                onDec?()
            }
            .accessibilityIdentifier(LBAccessibilityID.qtyMinus)
            Text("\(qty.qty)")
                .font(.system(size: 16 * theme.fontScale, weight: .bold))
                .foregroundColor(qty.qty > 0 ? theme.accent : Self.textFaint)
                .frame(minWidth: 22)
                .multilineTextAlignment(.center)
            stepButton(systemName: "plus", enabled: !isSoldOut && qty.qty < qty.max && !addToCartInFlight) {
                onInc?()
            }
            .accessibilityIdentifier(LBAccessibilityID.qtyPlus)
        }
    }

    /// One stepper button — 28×28 rounded square, dimmed + non-tappable when off.
    private func stepButton(systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: { guard enabled else { return }; action() }) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(enabled ? Self.bgSunken : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Self.strokeStrong, lineWidth: 1))
                Image(systemName: systemName)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(enabled ? theme.text : Self.textFaint)
            }
            .frame(width: 28, height: 28)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!enabled)
    }

    private var stockCaption: String {
        "\(Self.stockCaptionPrefix)\(qty.max)\(Self.stockCaptionSuffix)"
    }

    // MARK: - Footer (sticky 加入購物車 CTA + cart-CTA badge)
    //
    // Primary 加入購物車 (LBPButton primary). DISABLED when sold out (qty.max == 0) —
    // disabled fill = strokeStrong (mirrors LBPButton's disabled style). When the
    // session has successful adds (cartCount > 0), a slim cart-CTA row (LBPCartCTA)
    // sits below so the user can jump to the cart.

    private var footer: some View {
        VStack(spacing: 10) {
            // Bottom action row: the design's 3-slot footer [收藏][分享][CTA]
            // (ProductDetailSheet footer / LBPFavButton). 收藏 toggle + 分享 are the
            // two width-56 secondary slots left of the flexible primary CTA. 分享 is a
            // HOST CONCERN — the headless SDK exposes no share route, so reference-ui
            // only forwards the intent to the host-wired `onShare` passthrough.
            HStack(spacing: 12) {
                // `.addToCart` (compact purchase) drops 收藏 / 分享 — just the CTA (design's
                // AddToCartSheet). `.detail` keeps the 3-slot `[收藏][分享][CTA]` footer, EXCEPT
                // 分享 is additionally hidden while genuinely live (rb-ios-live-hide-product-share,
                // design R12) — 收藏 is unaffected.
                if presentation == .detail {
                    favButton
                    if !isLive {
                        shareButton
                    }
                }
                addToCartButton
            }

            // 商品明細 footer 收斂為設計 `ProductDetailSheet` 的 3-slot `[收藏][分享][CTA]`：
            // 設計並無額外的「查看購物車」CTA，且 `cartCount`（= `DefaultCartCTA.state.count`，
            // per-session 成功加購計數）非真實購物車件數、數據不準，故 footer MUST NOT 畫查看購物車
            // CTA（rb-ios-product-sheet-cart-cta-cleanup 問題 2）。`cartCTA` computed 與 `cartCount`
            // / `onOpenCart` 參數保留（不動建構子簽章 / 外部接線），body 不再引用。
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .overlay(Rectangle().fill(Self.stroke).frame(height: 1), alignment: .top)
    }

    /// Primary 加入購物車 CTA (LBPButton primary). DISABLED when sold out (qty.max == 0)
    /// — disabled fill = strokeStrong (mirrors LBPButton's disabled style).
    private var addToCartButton: some View {
        Button(action: { guard !isSoldOut && !addToCartInFlight else { return }; onAddToCart?() }) {
            HStack(spacing: 8) {
                if addToCartInFlight {
                    // 請求中（cart-add-loading-state）：spinner 取代 cart glyph、文字「加入中…」、
                    // 背景仍維持 accent（不退灰），對齊設計 `LBPButton.loading` / `LBPSpinner`。
                    SpinnerRingView(size: 18, lineWidth: 2, color: .white)
                    Text(Self.addingLabel)
                        .font(.system(size: 15 * theme.fontScale, weight: .bold))
                        .foregroundColor(.white)
                } else {
                    // glyph size 18 對齊補貨 CTA bell glyph 與設計 `LBPButton` `Icons size 18`，
                    // 使加購 CTA 與補貨 CTA 等高（rb-ios-product-sheet-detail-polish 問題 2）。
                    Image(systemName: "cart")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                    Text(Self.addToCartLabel)
                        .font(.system(size: 15 * theme.fontScale, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                // 統一按鈕圓角 → theme.cornerRadius（= 設計稿 LBPButton radius 12，rb-ios-button-corner-radius-unify）。
                // in-flight 維持 accent（只有售完退灰）→ 對齊設計「loading 保品牌色」。
                RoundedRectangle(cornerRadius: theme.cornerRadius)
                    .fill(isSoldOut ? Self.strokeStrong : theme.accent))
        }
        .buttonStyle(PlainButtonStyle())
        // 只在售完時 `.disabled`（退灰）。in-flight 不用 `.disabled`（否則 SwiftUI 會把整顆鈕連 accent
        // 底一起退成淡粉，違背設計「loading 保品牌色」）— 點擊已由 action 內 `guard !addToCartInFlight`
        // 擋住，故 in-flight 維持全 accent 填色 + 設計的 `opacity 0.96`（LBPButton.loading）。
        .disabled(isSoldOut)
        .opacity(addToCartInFlight ? 0.96 : 1)
        .accessibilityIdentifier(LBAccessibilityID.addToCartCta)
    }

    /// 收藏（到貨追蹤 type=1）toggle — LBPFavButton (vertical icon+label, width 56).
    /// Empty `heart` = not faved; filled `heart.fill` + accent = faved. Reads
    /// `faved` (= `DefaultGoodsTracking.awaitEnabled(for:)`); tap → host-wired
    /// `onToggleFavorite` → `toggleAwait(goodsGpn)`. reference-ui never flips it itself.
    private var favButton: some View {
        Button(action: { onToggleFavorite?() }) {
            VStack(spacing: 4) {
                Image(systemName: faved ? "heart.fill" : "heart")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundColor(faved ? theme.accent : theme.text)
                Text(faved ? Self.favedLabel : Self.favLabel)
                    .font(.system(size: 11 * theme.fontScale, weight: faved ? .bold : .medium))
                    .foregroundColor(faved ? theme.accent : Self.textDim)
            }
            .frame(width: 56)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier(LBAccessibilityID.favButton)
    }

    /// 分享 button — the design's 3-slot footer middle slot (between 收藏 and the CTA).
    /// Width-56 vertical icon+label secondary button, mirroring `favButton` /
    /// `LBPFavButton` chrome (hand-drawn `ShareGlyph` = design `Icons.share` size 20 + 「分享」
    /// label, rb-ios-share-icon-design-align — no longer SF `square.and.arrow.up`). Share is a
    /// HOST CONCERN: the tap only forwards to the host-wired `onShare` (the headless SDK has no
    /// share route) — reference-ui never builds share logic nor calls core / template. Hidden
    /// entirely (not rendered) by the `footer`'s `!isLive` gate while genuinely live
    /// (rb-ios-live-hide-product-share, design R12).
    private var shareButton: some View {
        Button(action: { onShare?() }) {
            VStack(spacing: 4) {
                ShareGlyph(size: 20, color: theme.text)
                Text(Self.shareLabel)
                    .font(.system(size: 11 * theme.fontScale, weight: .medium))
                    .foregroundColor(Self.textDim)
            }
            .frame(width: 56)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier(LBAccessibilityID.shareButton)
    }

    /// LBPCartCTA — accent bag button with the per-session add count.
    /// 保留但**目前未被 `footer` 引用**：明細 footer 收斂為設計 3-slot `[收藏][分享][CTA]`，
    /// 不再畫「查看購物車」CTA（rb-ios-product-sheet-cart-cta-cleanup 問題 2）。此 computed 保留
    /// 以免動建構子簽章 / 外部接線，日後若要恢復可一鍵接回 `footer`。
    private var cartCTA: some View {
        Button(action: { onOpenCart?() }) {
            HStack(spacing: 10) {
                Image(systemName: "bag")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                Text(Self.viewCartLabel)
                    .font(.system(size: 14 * theme.fontScale, weight: .bold))
                    .foregroundColor(.white)
                Text("(\(cartCount))")
                    .font(.system(size: 13 * theme.fontScale, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                // 統一按鈕圓角 → theme.cornerRadius（原 14，rb-ios-button-corner-radius-unify）。
                RoundedRectangle(cornerRadius: theme.cornerRadius)
                    .fill(theme.accent))
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Add-to-cart failure banner (retryable — LBPButton danger feel)

    private var failureBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(theme.accent)
            Text(Self.failureTitle)
                .font(.system(size: 13 * theme.fontScale, weight: .semibold))
                .foregroundColor(theme.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: { guard !isSoldOut else { return }; onAddToCart?() }) {
                Text(Self.retryLabel)
                    .font(.system(size: 13 * theme.fontScale, weight: .bold))
                    .foregroundColor(theme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 999)
                            .stroke(theme.accent, lineWidth: 1))
                    // Whole pill taps (outlined → stroke-only, padding ring would be dead).
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(theme.accent.opacity(0.08)))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(LBAccessibilityID.addToCartRetry)
    }

    // 「請選規格」prompt (LBPAlertModal) is no longer a sub-view here — it is hoisted to the
    // container's player overlay root as `SelectVariantPromptModalView` (ios-variant-prompt-overlay-fix).

    // MARK: - Hairline divider (AddToCartSheet section divider)

    private var hairline: some View {
        Rectangle().fill(Self.stroke).frame(height: 1)
    }

    // MARK: - Decorative design tokens (literal minimal hex via Color(hex:))
    //
    // accent / text / background come from the resolved theme. These are FIXED
    // decorative colors lifted verbatim from the design's `theme.surface.*` /
    // `theme.soldOut` — design-literal, NOT theme-resolved. Kept consistent with
    // `VideoInfoPanelView` / `WinClaimModalView` so the family reads as one.

    /// `theme.surface.textDim` (secondary / caption text).
    static let textDim = Color(hex: "#6B6775") ?? Color.gray
    /// `theme.surface.textFaint` (disabled stepper digit / off control).
    static let textFaint = Color(hex: "#B6B2BE") ?? Color.gray.opacity(0.5)
    /// `theme.surface.stroke` (hairline divider).
    static let stroke = Color(hex: "#ECEAF0") ?? Color.gray.opacity(0.2)
    /// `theme.surface.strokeStrong` (chip outline / stepper border / disabled fill).
    static let strokeStrong = Color(hex: "#D8D5DE") ?? Color.gray.opacity(0.35)
    /// `theme.surface.bgSunken` (sunken control fill — close circle / stepper btn).
    static let bgSunken = Color(hex: "#F4F4F6") ?? Color.gray.opacity(0.08)
    /// `theme.soldOut` (sold-out copy color — design `#9A96A3`).
    static let soldOutColor = Color(hex: "#9A96A3") ?? Color.gray

    // MARK: - Fixed localized copy (static presentation strings)

    static let headerTitle = "商品明細"
    static let soldOutLabel = "已售完"
    static let qtyLabel = "數量"
    static let stockCaptionPrefix = "只剩庫存 "
    static let stockCaptionSuffix = " 組"
    static let addToCartLabel = "加入購物車"
    /// CTA label while an addcart request is in flight (cart-add-loading-state). Design
    /// `LBPButton.loading` fallback「加入中…」.
    static let addingLabel = "加入中…"
    static let viewCartLabel = "查看購物車"
    static let favLabel = "收藏"
    static let favedLabel = "已收藏"
    static let shareLabel = "分享"
    static let retryLabel = "重試"
    static let failureTitle = "加入購物車失敗,請稍後再試"
    // 「請選規格」copy moved to `SelectVariantPromptModalView` (prompt hoisted to the container's
    // overlay root — ios-variant-prompt-overlay-fix).

    /// First product photo as a non-empty URL, or nil (empty / whitespace → placeholder).
    static func photoURL(_ detail: LBProductDetailState) -> URL? {
        guard let s = detail.photos.first?.trimmingCharacters(in: .whitespacesAndNewlines),
              !s.isEmpty else { return nil }
        return URL(string: s)
    }

    /// Up-to-2-char monogram from the product name (deterministic, pure).
    static func monogram(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "LB" }
        return String(trimmed.prefix(2)).uppercased()
    }
}

// MARK: - WrapChips — flex-wrap chip layout (LBPVariantPicker chips)
//
// Chips flow by NATURAL width and wrap to the next line when a row is full, aligning
// with the design source `LBPVariantPicker` (`flexWrap:'wrap'; gap:8`) and Android's
// `FlowRow`. iOS 16+ uses a hand-rolled `ChipFlowLayout` (`Layout` protocol — synchronous
// measure, NO `GeometryReader`, so it stays snapshot-deterministic); iOS 14/15 (where the
// `Layout` protocol is unavailable) falls back to the prior fixed `perRow`-wide chunked
// rows. Each chip mirrors `LBPVariantPicker`'s pill: accent-outlined + accent-tinted when
// selected, neutral stroke otherwise. Option text is never truncated (no `.lineLimit`),
// so a single option wider than a row wraps to multiple lines with its full text visible.

private struct WrapChips: View {
    let groupIndex: Int
    let options: [String]
    let selected: Int?
    let theme: ReferenceUITheme
    /// Locked while an addcart request is in flight (cart-add-loading-state) — chips dim and
    /// stop accepting taps so the payload can't change mid-send. Default false → unchanged.
    var disabled: Bool = false
    let onSelect: (Int) -> Void

    /// Chips per row for the iOS 14/15 fallback path only — fixed so the chunked layout
    /// is deterministic. 3 reads well at 393pt. (iOS 16+ uses `ChipFlowLayout` instead.)
    private let perRow = 3

    var body: some View {
        Group {
            if #available(iOS 16.0, *) {
                // iOS 16+: real flex-wrap — each chip at its natural width, wrapping to the
                // next line when the row is full (design `flexWrap:'wrap'`; Android `FlowRow`).
                ChipFlowLayout(hSpacing: 8, vSpacing: 8) {
                    ForEach(options.indices, id: \.self) { i in
                        chip(index: i)
                    }
                }
            } else {
                // iOS 14/15 fallback: fixed `perRow`-wide chunked rows (unchanged behavior).
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(rows, id: \.self) { row in
                        HStack(spacing: 8) {
                            ForEach(row, id: \.self) { i in
                                chip(index: i)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
        .opacity(disabled ? 0.5 : 1)
    }

    /// Index rows, chunked `perRow` wide (pure).
    private var rows: [[Int]] {
        let indices = Array(options.indices)
        var out: [[Int]] = []
        var i = 0
        while i < indices.count {
            out.append(Array(indices[i..<Swift.min(i + perRow, indices.count)]))
            i += perRow
        }
        return out
    }

    private func chip(index i: Int) -> some View {
        let isSelected = (selected == i)
        return Button(action: { onSelect(i) }) {
            Text(options[i])
                .font(.system(size: 13 * theme.fontScale, weight: isSelected ? .bold : .medium))
                .foregroundColor(isSelected ? theme.accent : theme.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 999)
                        .fill(isSelected ? theme.accent.opacity(0.08) : Color.clear))
                .overlay(
                    RoundedRectangle(cornerRadius: 999)
                        .stroke(isSelected ? theme.accent : ProductDetailSheetView.strokeStrong,
                                lineWidth: 1.5))
                // Whole chip taps — unselected fill is Color.clear (un-hittable interior).
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(disabled)
        .accessibilityIdentifier(LBAccessibilityID.variantChip(groupIndex, i))
    }
}

// MARK: - ChipFlowLayout — iOS-16+ flex-wrap layout (natural-width chips, wrap on full row)
//
// A synchronous `Layout` (iOS 16+) that lays chips left-to-right at their natural width
// and wraps to the next line when the next chip would exceed the available width — the
// native equivalent of the design's `flexWrap:'wrap'` and Android's `FlowRow`. It measures
// each subview directly (NO `GeometryReader`), so it renders deterministically for headless
// snapshots. A single chip wider than the row is proposed the row width, so its `Text`
// (no `.lineLimit`) wraps to multiple lines — the full option text stays visible.

@available(iOS 16.0, *)
private struct ChipFlowLayout: Layout {
    var hSpacing: CGFloat = 8
    var vSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = measure(subview, maxWidth: maxWidth)
            if x > 0 && x + size.width > maxWidth {
                // wrap to next line
                y += rowHeight + vSpacing
                x = 0
                rowHeight = 0
            }
            x += size.width + hSpacing
            widest = max(widest, x - hSpacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let maxWidth = bounds.width
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = measure(subview, maxWidth: maxWidth)
            if x > bounds.minX && (x - bounds.minX) + size.width > maxWidth {
                x = bounds.minX
                y += rowHeight + vSpacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: size.width, height: size.height))
            x += size.width + hSpacing
            rowHeight = max(rowHeight, size.height)
        }
    }

    /// Natural size, capped to the row width so an over-long single chip wraps its text
    /// (multi-line) instead of overflowing the container.
    private func measure(_ subview: LayoutSubview, maxWidth: CGFloat) -> CGSize {
        let natural = subview.sizeThatFits(.unspecified)
        let capped = min(natural.width, maxWidth)
        return subview.sizeThatFits(ProposedViewSize(width: capped, height: nil))
    }
}

// MARK: - StrikeText — iOS-14-safe strike-through label
//
// `.strikethrough()` exists on iOS 13+ for `Text`, but to keep the original-price
// treatment explicit + deterministic we draw the label with the modifier (no
// iOS-16 `AttributedString`). Kept tiny + reusable.

private struct StrikeText: View {
    let value: String
    let font: Font
    let color: Color

    init(_ value: String, font: Font, color: Color) {
        self.value = value
        self.font = font
        self.color = color
    }

    var body: some View {
        Text(value)
            .font(font)
            .foregroundColor(color)
            .strikethrough(true, color: color)
    }
}

// MARK: - Deterministic demo seed (previews + snapshot tests)
//
// A fully-populated detail + variant + qty so previews / the snapshot test render
// the sheet's "happy path" deterministically (no live player). Reuses the
// container's documented demo recipe (`ProductSheetsModel.demoDetail` /
// `demoVariantWithGroup` / `demoQtyInStock`) — those build the mapped state via the
// public inits WITHOUT touching the internal-init `LBSpecOption` (compile barrier).

public extension ProductDetailSheetView {

    /// A deterministic demo detail sheet WITH a variant group (顏色) + in-stock qty,
    /// pre-add (no guards tripped). Renders correctly action-free.
    static func demo(theme: ReferenceUITheme) -> ProductDetailSheetView {
        ProductDetailSheetView(
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
struct ProductDetailSheetView_Previews: PreviewProvider {
    static var previews: some View {
        let theme = ReferenceUIThemePalette.minimal
        Group {
            // Detail WITH a variant group, in stock, cart has items.
            ProductDetailSheetView.demo(theme: theme)
                .previewDisplayName("variant + qty")

            // Detail with NO variant group.
            ProductDetailSheetView(
                theme: theme,
                detail: ProductSheetsModel.demoDetail(),
                variant: ProductSheetsModel.demoVariantNoGroup,
                qty: ProductSheetsModel.demoQtyInStock,
                cartCount: 0,
                needsVariantSelection: false,
                addToCartFailed: false)
                .previewDisplayName("no variant group")

            // 「請選規格」prompt is now a container overlay-root modal — see
            // `SelectVariantPromptModalView` previews (ios-variant-prompt-overlay-fix).

            // Add-to-cart failure banner (retryable).
            ProductDetailSheetView(
                theme: theme,
                detail: ProductSheetsModel.demoDetail(),
                variant: ProductSheetsModel.demoVariantWithGroup,
                qty: ProductSheetsModel.demoQtyInStock,
                cartCount: 0,
                needsVariantSelection: false,
                addToCartFailed: true)
                .previewDisplayName("add-to-cart failed")
        }
        .frame(width: 393, height: 640)
        .previewLayout(.sizeThatFits)
    }
}
#endif
