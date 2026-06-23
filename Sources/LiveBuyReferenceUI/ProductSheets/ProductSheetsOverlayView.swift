import SwiftUI
import LiveBuySDK
import LiveBuyUI

// MARK: - ProductSheetsOverlayView — family-3 product sheet-stack container (SKELETON)
//
// Spec: `reference-ui-rendering/spec.md` (family-3 product + sheets)
// Design: rb-ios-product-sheets design.md D-1 / D-2 / D-3 / D-4 / D-5.
//
// The top-level family-3 container (this is the design's `ProductSheetsView` role;
// the file/type name is `ProductSheetsOverlayView` to read as an overlay
// composited over the player, mirroring `FeedWinOverlayView`). It composes the
// product sheet-stack surfaces over the live video area:
//
//   1. ProductListView        — product list drawer (D-2, `ProductListSheet` +
//                               `LBPProductRow` + `LBPCartCTA`)
//   2. MiniCartView           — floating mini-cart peek (D-4, `LBPMiniCart`)
//   3. ProductDetailSheetView — product detail sheet, presented on demand
//                               (D-3, `ProductDetailSheet` / `AddToCartSheet` +
//                               `LBPVariantPicker` + `LBPQtyStepper`)
//   4. NotifyRestockSheetView — restock-notify sheet, presented WHEN the presented
//                               detail is SOLD OUT (D-5, `NotifyRestockSheet`)
//
// This is the SKELETON: it owns the layout + a `ProductSheetsModel` + the resolved
// `ReferenceUITheme` + the sheet presentation state + the host-wired product-tap
// closure, and composes the four surface sub-views BY TYPE NAME. The four sub-view
// TYPES are produced by the four parallel surface agents that run after this
// skeleton — see the "SUB-VIEW INPUT PATTERN" contract below, which every surface
// agent MUST implement verbatim so the container's call sites match.
//
// Until all four surface sub-views exist, this file will not compile on its own —
// that is expected (the surface agents land the types). The container's job is to
// FIX the layout + the call-site shape + the demo construction recipe so the
// parallel agents converge.
//
// PRESENTATION STATE OWNERSHIP (mirrors `FeedWinOverlayView.claimingWinner`):
//   • `listPresented` — whether the product list drawer is open. Local affordance
//     state only; the list CONTENT (`model.products`) is model-driven.
//   • Which sheet (detail vs restock) is presented is DERIVED from the model's
//     `detail` snapshot, NOT a separate boolean: a non-nil `detail` presents a
//     sheet, and the SOLD-OUT bit (`detail.soldOut == 1`) selects the restock
//     sheet over the plain detail sheet (D-5). The container owns the
//     `presentingDetail` binding that drives `.sheet(item:)`; it is cleared when
//     the model's `detail` goes nil (the template owns detail open/close — this
//     layer only mirrors + dismisses presentation).
//
// iOS-14-safe: `ZStack` / `VStack` / `HStack` / `Spacer` / manual padding are all
// iOS-13+; no `@available` guard needed here. Any surface that reaches for a >14
// API must guard it inside its own sub-view (D §iOS-14-safe).
//
// ─────────────────────────────────────────────────────────────────────────────
// SUB-VIEW INPUT PATTERN — the contract the 4 parallel surface agents MUST follow
// ─────────────────────────────────────────────────────────────────────────────
//
// Every family-3 surface sub-view is a `public struct …: View` whose initializer
// takes, IN THIS ORDER (identical convention to family-1 / family-2):
//
//   1. `theme: ReferenceUITheme`            — the resolved reference-ui theme
//                                             (FIRST positional argument, always).
//   2. its bound SNAPSHOT VALUE(S)          — the read-only state it renders,
//                                             passed BY VALUE from ProductSheetsModel
//                                             (never the model, never the template).
//   3. optional action closures            — trailing, each defaulting to `nil`
//                                             (`onX: (() -> Void)? = nil`, etc.).
//                                             The container does NOT own actions;
//                                             they forward to the model's thin
//                                             forwarders (which hit existing template
//                                             exits) or, for the product-row tap, to
//                                             the host-wired `onProductTap`.
//
// Concretely, the four surface agents implement EXACTLY these initializers:
//
//   ProductListView(
//       theme: ReferenceUITheme,
//       products: [LBProduct],
//       cartCount: Int,
//       onOpenProduct: ((LBProduct) -> Void)? = nil,   // 明細鈕/名 → host → core simulateProductTap (.detail)
//       onQuickAdd: ((LBProduct) -> Void)? = nil,      // 加購鈕 → host → core simulateProductTap (.addToCart)
//       onOpenCart: (() -> Void)? = nil)               // → model.openCart()
//
//   ProductDetailSheetView(
//       theme: ReferenceUITheme,
//       detail: LBProductDetailState,
//       variant: LBVariantState,
//       qty: LBQtyState,
//       cartCount: Int,
//       needsVariantSelection: Bool,
//       addToCartFailed: Bool,
//       onSelectVariant: ((_ groupIndex: Int, _ optionIndex: Int) -> Void)? = nil,
//       onSetQty: ((Int) -> Void)? = nil,
//       onInc: (() -> Void)? = nil,
//       onDec: (() -> Void)? = nil,
//       onAddToCart: (() -> Void)? = nil,
//       onOpenCart: (() -> Void)? = nil,
//       onDismiss: (() -> Void)? = nil)
//
//   MiniCartView(
//       theme: ReferenceUITheme,
//       peek: LBMiniCartPeek,
//       onDismiss: (() -> Void)? = nil,                // → model.dismissMiniCart()
//       onOpenDetail: (() -> Void)? = nil)             // → model.openMiniCartDetail()
//
//   NotifyRestockSheetView(
//       theme: ReferenceUITheme,
//       detail: LBProductDetailState,
//       noticeEnabled: Bool,
//       onToggleNotice: (() -> Void)? = nil,           // → model.toggleNotice(goodsGpn:)
//       onDismiss: (() -> Void)? = nil)
//
// Rules every surface agent honours:
//   • FIRST positional arg is `theme:`. Snapshot values are passed BY VALUE.
//   • Action closures are LAST, each `… = nil` (the container passes the host /
//     model-wired closure or omits it). A surface sub-view MUST render correctly
//     with all actions nil (so demo / snapshot tests construct it action-free).
//   • A surface sub-view reads ONLY its passed-in values — it MUST NOT reach back
//     into ProductSheetsModel or DefaultPlayerTemplate (one-way data flow, D-1).
//   • The sheet shells (ProductListView / ProductDetailSheetView /
//     NotifyRestockSheetView) REUSE the module-internal `TopRoundedRectangle`
//     shape + the grab-handle + LBPSheetHeader styling already established by
//     `VideoInfoPanelView` / `WinClaimModalView` — DO NOT redefine
//     `TopRoundedRectangle` (it already lives in `VideoInfoPanelView.swift`).
//   • `ProductListView` row tap funnels to `onOpenProduct(product)` — NOT to a
//     model intent. The container forwards it to the host-wired `onProductTap`,
//     which the host wires to core `LiveBuyPlayerViewController.simulateProductTap`
//     (reference-ui 永不自行開明細, D-2 — mirrors family-2 ChatFeedView's eventJoin).
//   • `ProductDetailSheetView` add-to-cart funnels to `onAddToCart` →
//     `model.addToCart()` → `template.addToCart()`. reference-ui NEVER calls core
//     addToCart directly (D-3).
//   • `NotifyRestockSheetView` touches goods-tracking ONLY for the NOTICE
//     subscription (`onToggleNotice` → `model.toggleNotice(goodsGpn:)`,
//     `noticeEnabled` read). It MUST NOT render the AWAIT switch (`toggleAwait` /
//     `awaitEnabled`) — that is family-6 (D-5 boundary).
//   • iOS-14-safe SwiftUI only; any >14 API guarded with `@available` /
//     `if #available` inside the sub-view.
// ─────────────────────────────────────────────────────────────────────────────

/// The family-3 product sheet-stack container. Drives layout for the product list
/// drawer + the floating mini-cart peek over the video area, and presents the
/// product-detail sheet (or, when the detail is sold out, the restock-notify
/// sheet) on demand; reads a `ProductSheetsModel` (republished from a live
/// `DefaultPlayerTemplate` or constructed deterministically) and paints with the
/// resolved `ReferenceUITheme`.
/// Which sheet the next product-detail presents — set by which list entry was tapped
/// (rb-ios-product-action-sheet / rb-ios-soldout-row-detail-vs-restock). A local presentation
/// choice, NOT business state: 名稱欄 / 明細鈕 → `.detail`、加購鈕 → `.addToCart`、售完補貨鈴鐺
/// → `.restock`.
enum ProductSheetActionMode { case detail, addToCart, restock }

/// The sheet kind a given `actionMode` presents. Pure mapping (no `soldOut` override) so the
/// entry → sheet routing is unit-testable (rb-ios-soldout-row-detail-vs-restock).
enum ProductSheetKind: Equatable { case detail, addToCart, notifyRestock }

public struct ProductSheetsOverlayView: View {

    /// The republished, read-only product sheet-stack snapshot.
    @ObservedObject public var model: ProductSheetsModel

    /// The resolved reference-ui theme.
    public let theme: ReferenceUITheme

    /// `false` (snapshot / demo) → sheet thumbnails draw deterministic placeholders (baselines
    /// unchanged). `true` (host runtime, real video surface) → product photos load over the
    /// placeholders via `RemoteStillImageView` (rb-ios-product-real-images). Threaded to the
    /// list + the three sheet surfaces.
    public let live: Bool

    /// Host-wired product-row tap → core product-tap exit. The host wires this to
    /// `LiveBuyPlayerViewController.simulateProductTap(product)`; the container
    /// NEVER opens a detail itself (D-2). nil for demo / snapshot instances.
    private let onProductTap: ((LBProduct) -> Void)?

    /// Host-wired 分享 tap from the product-detail footer's 3-slot [收藏][分享][CTA].
    /// Share is a HOST CONCERN — the headless SDK has no share route, so the container
    /// simply forwards the intent to this host-provided closure (passthrough). nil for
    /// demo / snapshot instances; the share button renders correctly action-free.
    private let onShare: (() -> Void)?

    /// Host-wired 商品列表列**縮圖**點擊 → 影片跳轉到該商品介紹時間（`LBProduct.beginTime`）。
    /// 轉發給 `ProductListView.onSeekToIntro`；host 把它接到 core `seek(seconds:)`（issue 5）。
    /// nil for demo / snapshot instances（縮圖點擊 no-op）。
    private let onSeekToProductIntro: ((LBProduct) -> Void)?

    /// Host-wired 商品列表列**分享鈕**點擊 → 系統分享，連結帶該商品介紹時間 `?t=beginTime`。
    /// 轉發給 `ProductListView.onShareProduct`；host 把它接到系統分享（issue 6）。與明細 footer 的
    /// `onShare`（channel-level、`() -> Void`）為**不同**入口。nil for demo / snapshot instances。
    private let onShareProduct: ((LBProduct) -> Void)?

    /// Host-wired「前往登入」CTA for the add-to-cart needs-login gate (cart-needs-login-gate).
    /// When the template's `addToCartNeedsLogin` flips true (route-B add hit the empty-`buy_no`
    /// 401 signal), the overlay presents `AuthGateModalView(.cartAdd)`; its 前往登入 CTA routes
    /// HERE — the HOST's own login flow (`config.onLogin`). reference-ui NEVER logs in itself
    /// (same invariant as the comment login-gate). nil for demo / snapshot instances (the gate
    /// defaults not-presented, so baselines stay byte-identical).
    private let onRequestLogin: (() -> Void)?

    /// The product-detail the sheet is currently presented for, if any. Mirrors
    /// `model.detail` so the sheet binds a non-optional detail inside; the SOLD-OUT
    /// bit selects restock vs plain detail. The template owns detail open/close —
    /// this only governs which detail (if any) is on screen and dismisses it.
    @State private var presentingDetail: LBProductDetailState?

    /// Which presentation the next detail uses (rb-ios-product-action-sheet /
    /// rb-ios-soldout-row-detail-vs-restock): the list 加購鈕 (`onQuickAdd`) sets `.addToCart`
    /// (compact purchase sheet), the 明細鈕 / 商品名 (`onOpenProduct`) sets `.detail` (full browse),
    /// the 售完補貨鈴鐺 (`onNotifyRestock`) sets `.restock` (補貨通知 sheet). A LOCAL presentation
    /// choice only — the detail DATA still loads via the host-wired `onProductTap` (→ core
    /// `simulateProductTap`). 售完商品經名稱 / 明細 → `.detail` → ProductDetailSheetView（自帶售完
    /// CTA 禁用），補貨 sheet 只由專屬鈴鐺入口開啟（不再由 `soldOut` 覆蓋）。
    @State private var actionMode: ProductSheetActionMode = .detail

    /// The product whose image is currently zoomed in the full-frame `ProductZoomOverlayView`,
    /// if any (rb-ios-product-image-zoom-lightbox). A LOCAL presentation-only affordance: a sheet's
    /// zoom badge tap sets it (`onZoomImage`), the lightbox's close clears it. Mounted ABOVE the
    /// `lbBottomSheet` stack so the viewer covers the open sheet. NOT view-model state.
    @State private var zoomedDetail: LBProductDetailState?

    /// Whether the add-to-cart needs-login gate is currently presented. A LOCAL
    /// presentation flag (NOT a model snapshot): set true on the template's
    /// `addToCartNeedsLogin` false→true transition; cleared on 前往登入 hand-off /
    /// 稍後再說 / scrim. Default false → snapshot-neutral (baselines byte-identical).
    /// Using a local flag (not gating directly on `model.addToCartNeedsLogin`) lets
    /// 稍後再說 dismiss the gate even though reference-ui cannot reset the template
    /// flag; the next add attempt re-fires the false→true transition (template resets
    /// then re-sets the flag) and re-presents (cart-needs-login-gate).
    @State private var cartLoginGatePresented = false

    /// Add-to-cart success toast presentation (rb-ios-cart-add-success-toast). A LOCAL
    /// transient flag (NOT a model snapshot): set true by `showCartToast` on a `cartCount`
    /// rise, auto-cleared ~1.8s later. Default false → snapshot-neutral (baselines
    /// byte-identical).
    @State private var cartToastVisible = false

    /// Pending auto-dismiss work for the success toast — cancelled + re-armed on each rise
    /// so rapid successive successes EXTEND the toast rather than truncate it.
    @State private var cartToastDismiss: DispatchWorkItem?

    /// Last observed `model.cartCount`, seeded in `onAppear` so the FIRST real rise (not the
    /// bind-time value) flashes the toast. `-1` = not yet seeded.
    @State private var lastCartCount: Int = -1

    /// CTA loading visibility with a ~320ms anti-flicker floor (cart-add-loading-state D-2):
    /// mirrors `model.addToCartInFlight` but holds the spinner for a minimum display so a fast
    /// resolve (esp. a synchronous dedup) doesn't strobe. Passed to the sheets as their
    /// `addToCartInFlight`. Default false → snapshot-neutral.
    @State private var cartLoadingVisible = false
    @State private var cartLoadingDismiss: DispatchWorkItem?
    /// Monotonic clock stamp of when loading began, for the min-display floor.
    @State private var cartLoadingStart: DispatchTime?

    public init(
        model: ProductSheetsModel,
        theme: ReferenceUITheme,
        live: Bool = false,
        onProductTap: ((LBProduct) -> Void)? = nil,
        onShare: (() -> Void)? = nil,
        onSeekToProductIntro: ((LBProduct) -> Void)? = nil,
        onShareProduct: ((LBProduct) -> Void)? = nil,
        onRequestLogin: (() -> Void)? = nil
    ) {
        self.model = model
        self.theme = theme
        self.live = live
        self.onProductTap = onProductTap
        self.onShare = onShare
        self.onSeekToProductIntro = onSeekToProductIntro
        self.onShareProduct = onShareProduct
        self.onRequestLogin = onRequestLogin
    }

    public var body: some View {
        ZStack {
            sheetStack
            // Product-image lightbox — mounted ABOVE the `lbBottomSheet` sheet stack (the
            // presenter is in-tree, so a sibling drawn AFTER it layers on top), so the zoom
            // viewer covers the open sheet (design `ProductZoomOverlay`, mounted at the player
            // root). Present only while a sheet's zoom badge has set `zoomedDetail`.
            if let zoomed = zoomedDetail {
                ProductZoomOverlayView(
                    theme: theme,
                    detail: zoomed,
                    live: live,
                    onClose: { zoomedDetail = nil })
            }
            // Add-to-cart「需登入」gate (cart-needs-login-gate) — presented TOPMOST (after
            // the sheet stack + lightbox) when the route-B add hit the empty-`buy_no` 401
            // signal (`model.addToCartNeedsLogin`). REUSES the comment login-gate's
            // `AuthGateModalView` surface (no new pixel surface); the modal owns its own
            // scrim. 前往登入 → host `onRequestLogin` (reference-ui NEVER logs in itself);
            // 稍後再說 / scrim → dismiss. The genuine-failure banner is unaffected (it draws
            // only on the orthogonal `addToCartFailed`, never set together with needs-login).
            if cartLoginGatePresented {
                AuthGateModalView(
                    theme: theme,
                    triggerAction: .cartAdd,
                    onLogin: {
                        cartLoginGatePresented = false
                        onRequestLogin?()
                    },
                    onDismiss: { cartLoginGatePresented = false })
            }
            // Add-to-cart success toast (rb-ios-cart-add-success-toast) — flashed ~1.8s above
            // the sheet stack when an add SUCCEEDS (`model.cartCount` ticks up). PURE
            // confirmation: bottom-aligned over the player frame, slides up (`lbp-toast-in`),
            // never eats taps (`allowsHitTesting(false)`). Default-hidden → snapshot-neutral.
            if cartToastVisible {
                CartToastView(theme: theme)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 96)
                    .allowsHitTesting(false)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(100)
            }
        }
        // Present the gate on the template flag's false→true transition (iOS-14-safe
        // `onChange`; mirrors `syncPresentation`). A local flag — not direct gating —
        // so 稍後再說 can dismiss without reference-ui resetting the template flag.
        .presentCartLoginGate(on: model.addToCartNeedsLogin, into: $cartLoginGatePresented)
        // Seed the cartCount watermark once on appear so the first genuine rise (not the
        // bind-time value) flashes the toast (D-1).
        .onAppear { if lastCartCount < 0 { lastCartCount = model.cartCount } }
        // Flash the success toast on each cartCount rise (success → incrementOnAdd). dedup /
        // needsLogin / failure leave the count unchanged → no toast (D-1 known limitation).
        .flashCartToast(onCartCount: model.cartCount, last: $lastCartCount) { showCartToast() }
        // Mirror the template's addToCartInFlight into a floored loading flag (anti-flicker; a
        // synchronous dedup resolves within a frame). The sheets read `cartLoadingVisible` as
        // their CTA loading state (cart-add-loading-state D-2).
        .syncCartLoading(on: model.addToCartInFlight) { syncCartLoading($0) }
    }

    /// The product sheet-stack proper (mini-cart peek + the `lbBottomSheet` list / detail /
    /// restock presenters). Wrapped by `body` so the zoom lightbox can layer above it.
    private var sheetStack: some View {
        ZStack {
            // mini-cart peek surface REMOVED (rb-ios-remove-minicart-peek-surface): the floating
            // peek looked identical to the VOD now-introducing card (same `MiniCartView` component)
            // and duplicated the「current product」(VOD → now-introducing card / LIVE → pinned card);
            // recent-add confirmation is the bag-button badge. A transparent base keeps the ZStack
            // full-size so the `.lbBottomSheet` presenters below anchor correctly.
            Color.clear
        }
        // Product list drawer (surface 1) — shared SheetKit bottom-sheet presenter (dim
        // scrim + grab handle + drag-to-dismiss). Presentation is driven by the SHARED
        // `ProductSheetsModel.listPresented` flag (rb-ios-product-list-slide-sheet): the
        // container's `onOpenProductList` default sets `model.listPresented = true` so the
        // bag tap slides this drawer up — replacing the prior system `.pageSheet` fallback.
        // Dismissed by dragging the handle or tapping the scrim (sets the flag false → slides out).
        .lbBottomSheet(theme: theme, isPresented: $model.listPresented) {
            ProductListView(
                theme: theme,
                products: model.products,
                cartCount: model.cartCount,
                live: live,
                introducingProductId: model.introducingProductId,
                // Playback mode for the row overlay (VOD play / live 介紹中 / replay
                // begin-end window). `rowMode` is nil for a demo model → ProductListView
                // falls back to `live` (baselines byte-identical); a live-bound model
                // supplies the real mode + playback position (rb-ios-product-row-status-overlay).
                mode: model.rowMode,
                playbackPosition: Int(model.position),
                onOpenProduct: { product in
                    // 明細鈕 / 商品名 → full browse sheet. reference-ui NEVER opens the detail
                    // itself — set the LOCAL presentation mode, then forward to the host-wired
                    // core product-tap exit (D-2).
                    actionMode = .detail
                    onProductTap?(product)
                },
                onQuickAdd: { product in
                    // 加購鈕（in-stock）→ compact AddToCart sheet.
                    actionMode = .addToCart
                    onProductTap?(product)
                },
                onNotifyRestock: { product in
                    // 售完列補貨鈴鐺鈕 → 補貨通知 sheet（名稱 / 明細仍走 onOpenProduct 開詳情，
                    // rb-ios-soldout-row-detail-vs-restock）。
                    actionMode = .restock
                    onProductTap?(product)
                },
                // 縮圖點擊 → 影片跳轉到商品介紹時間（issue 5）；分享鈕 → 系統分享帶 `?t=beginTime`（issue 6）。
                onSeekToIntro: { product in onSeekToProductIntro?(product) },
                onShareProduct: { product in onShareProduct?(product) },
                onOpenCart: { model.openCart() },
                // header 右上角關閉 icon → 關抽屜（rb-ios-sheet-header-close-unify；與 scrim /
                // 下拉同為合法關閉入口）。
                onClose: { withAnimation { model.listPresented = false } })
        }
        // Detail / restock sheet (surfaces 3+4) — migrated from the system `.sheet(item:)`
        // to the shared SheetKit `.lbBottomSheet(item:)` (sheetkit-migrate): SAME item-driven
        // presentation + `soldOut` split (`presentedSheet(for:)`), now with the shared dim
        // scrim + grab handle + drag-to-dismiss + content-sized height (iOS-14/15 height
        // control) instead of the system sheet. `onDismiss` clears the local mirror; the
        // template still owns detail open/close (the `syncPresentation` mirror below).
        .lbBottomSheet(theme: theme, item: $presentingDetail, onDismiss: { dismissDetail() }) { detail in
            presentedSheet(for: detail)
        }
        // Keep the presented sheet in lock-step with the model's detail snapshot:
        // the template owns detail open/close, this layer only mirrors it into the
        // local presentation binding. iOS-14-safe `onChange` (iOS 14+; guarded).
        .syncPresentation(detail: model.detail, into: $presentingDetail)
    }

    /// Host affordance: open the product list drawer (surface 1). The presentation flag now
    /// lives on the SHARED `ProductSheetsModel` (`model.listPresented`,
    /// rb-ios-product-list-slide-sheet), so the container's `onOpenProductList` default opens
    /// the drawer by setting it directly; this method stays as a source-compatible convenience.
    public func presentProductList() {
        withAnimation { model.listPresented = true }
    }

    /// Clear the presented detail: drop the local mirror AND ask the template to clear its
    /// `productSheet.detail` (rb-ios-product-action-sheet). The second step is required so
    /// re-tapping the SAME product re-opens it — `openDetail` is diff-then-notify, so if the
    /// template detail stayed set, `onChange(of: model.detail)` would not fire on a same-product
    /// re-tap and the sheet could not reopen until a DIFFERENT product changed it.
    private func dismissDetail() {
        presentingDetail = nil
        model.closeDetail()
    }

    /// Pure mapping of `actionMode` → which sheet to present (rb-ios-soldout-row-detail-vs-restock).
    /// No `soldOut` override: 售完商品經名稱 / 明細 (`.detail`) 仍開 ProductDetailSheetView，補貨
    /// 通知只由 `.restock`（售完補貨鈴鐺）開啟。Unit-tested.
    static func sheetKind(for actionMode: ProductSheetActionMode) -> ProductSheetKind {
        switch actionMode {
        case .restock:   return .notifyRestock
        case .addToCart: return .addToCart
        case .detail:    return .detail
        }
    }

    /// Pick the sheet for `detail` by `actionMode` (via `sheetKind`): 補貨鈴鐺 → restock-notify、
    /// 加購鈕 → compact AddToCartSheetView、明細鈕 / 商品名 → full ProductDetailSheetView（售完時
    /// 自帶 CTA 禁用 + 已售完樣式）— all bind the same detail.
    @ViewBuilder
    private func presentedSheet(for detail: LBProductDetailState) -> some View {
        switch Self.sheetKind(for: actionMode) {
        case .notifyRestock:
            NotifyRestockSheetView(
                theme: theme,
                detail: detail,
                // The model resolves goodsGpn from its products snapshot (D-5:
                // 「goodsGpn 從 product 讀」) — LBProductDetailState carries only
                // productId, and goodsTracking is keyed by goodsGpn.
                noticeEnabled: model.noticeEnabled(forProductId: detail.productId),
                live: live,
                onToggleNotice: { model.toggleNotice(forProductId: detail.productId) },
                onDismiss: { dismissDetail() },
                onZoomImage: { zoomedDetail = detail })
        case .addToCart:
            AddToCartSheetView(
                theme: theme,
                detail: detail,
                variant: model.variant,
                qty: model.qty,
                cartCount: model.cartCount,
                needsVariantSelection: model.needsVariantSelection,
                addToCartFailed: model.addToCartFailed,
                addToCartInFlight: cartLoadingVisible,
                live: live,
                onSelectVariant: { groupIndex, optionIndex in
                    model.selectVariant(groupIndex: groupIndex, optionIndex: optionIndex)
                },
                onSetQty: { model.setQty($0) },
                onInc: { model.incQty() },
                onDec: { model.decQty() },
                onAddToCart: { model.addToCart() },
                onOpenCart: { model.openCart() },
                onDismiss: { dismissDetail() },
                onZoomImage: { zoomedDetail = detail })
        case .detail:
            ProductDetailSheetView(
                theme: theme,
                detail: detail,
                variant: model.variant,
                qty: model.qty,
                cartCount: model.cartCount,
                needsVariantSelection: model.needsVariantSelection,
                addToCartFailed: model.addToCartFailed,
                addToCartInFlight: cartLoadingVisible,
                // 收藏（到貨追蹤 type=1）— model resolves goodsGpn from productId, same
                // as the restock-notify above. The await switch reconciled here from
                // the retired family-6 dual-switch sheet (design 2026-06-06).
                faved: model.favEnabled(forProductId: detail.productId),
                live: live,
                // 商品說明（`brief`）由 products 快照以 productId 解析（問題 4，rb-ios-product-sheet-detail-polish）。
                brief: model.brief(forProductId: detail.productId),
                onSelectVariant: { groupIndex, optionIndex in
                    model.selectVariant(groupIndex: groupIndex, optionIndex: optionIndex)
                },
                onSetQty: { model.setQty($0) },
                onInc: { model.incQty() },
                onDec: { model.decQty() },
                onAddToCart: { model.addToCart() },
                onOpenCart: { model.openCart() },
                onToggleFavorite: { model.toggleFavorite(forProductId: detail.productId) },
                // 分享 is a host concern — forward the container's host passthrough.
                onShare: { onShare?() },
                onDismiss: { dismissDetail() },
                onZoomImage: { zoomedDetail = detail })
        }
    }

    // NOTE on `goodsGpn` for the restock sheet (D-5): `LBProductDetailState` mirrors
    // `LBProduct` but does NOT carry `goodsGpn` — only `productId`. The design says
    // 「`goodsGpn` 從 product 讀」, and `DefaultGoodsTracking` is keyed by `goodsGpn`
    // (the template seeds it via `LBProduct.goodsGpn`), NOT by `productId`. So the
    // container passes `detail.productId` and the MODEL resolves it to the originating
    // `LBProduct.goodsGpn` via its `products` snapshot (`resolveGoodsGpn`) before
    // hitting `goodsTracking` — keying off `productId` directly would query/toggle
    // the wrong subscription at runtime.

    /// Flash the add-to-cart success toast and (re)schedule its ~1.8s auto-dismiss. Mirrors
    /// `PlayerShellView.showMuteToast`: cancel any pending dismiss, animate in (the
    /// `.transition` slides the pill up), re-arm the dismiss so a rapid second success
    /// extends rather than truncates. @State setters are nonmutating, so this stays a plain
    /// method.
    private func showCartToast() {
        cartToastDismiss?.cancel()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
            cartToastVisible = true
        }
        let work = DispatchWorkItem {
            withAnimation(.easeIn(duration: 0.18)) { cartToastVisible = false }
        }
        cartToastDismiss = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: work)
    }

    /// Drive the floored CTA loading flag from the template's `addToCartInFlight`
    /// (cart-add-loading-state D-2). Going in-flight shows immediately; leaving holds the
    /// spinner until a ~320ms minimum so a fast resolve (synchronous dedup) doesn't strobe.
    private func syncCartLoading(_ inFlight: Bool) {
        cartLoadingDismiss?.cancel()
        if inFlight {
            cartLoadingStart = DispatchTime.now()
            cartLoadingVisible = true
            return
        }
        let elapsed = cartLoadingStart.map {
            DispatchTime.now().uptimeNanoseconds &- $0.uptimeNanoseconds
        } ?? CartLoadingFloor.minDisplayNanos
        let remaining = CartLoadingFloor.remainingHoldNanos(elapsedNanos: elapsed)
        if remaining == 0 {
            cartLoadingVisible = false
        } else {
            let work = DispatchWorkItem { cartLoadingVisible = false }
            cartLoadingDismiss = work
            DispatchQueue.main.asyncAfter(deadline: .now() + .nanoseconds(Int(remaining)), execute: work)
        }
    }
}

// MARK: - CartToastTrigger — pure rise-detection for the success toast
//
// The add-to-cart success toast (rb-ios-cart-add-success-toast, D-1) flashes ONLY on a
// STRICT increase of `cartCount` past a seeded watermark (`last >= 0`, set in the
// container's `onAppear`). `cartCount` rises only via `cartCTA.incrementOnAdd()` (add
// success); dedup / needsLogin / failure leave it unchanged → never flash. Extracted as a
// pure function so the trigger rule is unit-testable without a SwiftUI host
// (unit-test-discipline).
enum CartToastTrigger {
    static func shouldFlash(newCount: Int, lastCount: Int) -> Bool {
        lastCount >= 0 && newCount > lastCount
    }
}

// MARK: - CartLoadingFloor — pure anti-flicker min-display for the CTA loading (D-2)
//
// The add-to-cart CTA loading mirrors the template's `addToCartInFlight`, but a fast resolve
// (especially a synchronous dedup) would flip it true→false within a frame and strobe the
// spinner. The floor holds the spinner for a ~320ms minimum (design `ADD_TO_CART_MIN_MS`).
// Pure so the hold computation is unit-testable without a SwiftUI host.
enum CartLoadingFloor {
    static let minDisplayNanos: UInt64 = 320_000_000
    /// Remaining hold (nanos) before the spinner may hide, given elapsed nanos since it began.
    /// `0` = hide immediately (already shown ≥ the floor).
    static func remainingHoldNanos(elapsedNanos: UInt64) -> UInt64 {
        elapsedNanos >= minDisplayNanos ? 0 : minDisplayNanos - elapsedNanos
    }
}

// MARK: - iOS-14-safe presentation sync helper
//
// `onChange(of:)` is iOS-14+; the package floor is iOS 14, so it is in range, but
// we keep the guard local + the call site clean (mirrors `PlayerShellView`'s
// `ignoresSafeAreaCompat`). When the model's `detail` snapshot changes (template
// opened / closed a detail), mirror it into the local `.sheet(item:)` binding.

private extension View {
    @ViewBuilder
    func syncPresentation(
        detail: LBProductDetailState?,
        into binding: Binding<LBProductDetailState?>
    ) -> some View {
        if #available(iOS 14.0, *) {
            self.onChange(of: detail) { newValue in
                binding.wrappedValue = newValue
            }
        } else {
            self
        }
    }

    /// Present the add-to-cart needs-login gate on the template flag's false→true
    /// transition (cart-needs-login-gate). Mirrors `syncPresentation`: iOS-14-safe
    /// `onChange`; only a rising edge sets the local presentation flag (so a 稍後再說
    /// dismiss, which leaves the template flag true, does not re-present until the next
    /// add attempt re-fires false→true).
    @ViewBuilder
    func presentCartLoginGate(on needsLogin: Bool, into binding: Binding<Bool>) -> some View {
        if #available(iOS 14.0, *) {
            self.onChange(of: needsLogin) { newValue in
                if newValue { binding.wrappedValue = true }
            }
        } else {
            self
        }
    }

    /// Flash the add-to-cart success toast on a `cartCount` RISE (cart-add-tier2 success →
    /// `cartCTA.incrementOnAdd()`). Mirrors `presentCartLoginGate`: iOS-14-safe `onChange`;
    /// only a strict increase past the last observed count fires (so bind-time / non-add
    /// refreshes never flash). `last` is seeded by the call site's `onAppear`; dedup /
    /// needsLogin / failure leave the count unchanged so they never trigger (D-1).
    @ViewBuilder
    func flashCartToast(onCartCount cartCount: Int, last: Binding<Int>, _ onRise: @escaping () -> Void) -> some View {
        if #available(iOS 14.0, *) {
            self.onChange(of: cartCount) { newCount in
                defer { last.wrappedValue = newCount }
                guard CartToastTrigger.shouldFlash(newCount: newCount, lastCount: last.wrappedValue) else { return }
                onRise()
            }
        } else {
            self
        }
    }

    /// iOS-14-safe mirror of the template's `addToCartInFlight` into the container's floored
    /// loading flag (cart-add-loading-state D-2). Mirrors `presentCartLoginGate` / `flashCartToast`.
    @ViewBuilder
    func syncCartLoading(on inFlight: Bool, _ onChange: @escaping (Bool) -> Void) -> some View {
        if #available(iOS 14.0, *) {
            self.onChange(of: inFlight) { onChange($0) }
        } else {
            self
        }
    }
}

// MARK: - Identifiable conformance for sheet(item:)
//
// `LBProductDetailState` (template value type) is not `Identifiable`; `.sheet(item:)`
// needs it. We add the conformance HERE in the reference-ui layer (it does NOT
// modify the template type's source — it is an extension in the pixel layer only,
// and `productId` is the stable identity). This keeps the one-way dependency:
// reference-ui adds the presentation affordance, the template stays headless.

extension LBProductDetailState: Identifiable {
    public var id: String { productId }
}

// MARK: - Deterministic demo construction recipe (previews + snapshot tests)
//
// VERIFIED CONSTRUCTION PATHS — the 4 parallel surface agents MUST use these so
// the demo / snapshot fixtures stay consistent and COMPILE (see the compile-error
// caveat below).
//
// ── ⚠️ COMPILE-ERROR CAVEAT — `LBSpecOption` ────────────────────────────────────
// `LBSpecOption` is `public struct LBSpecOption: Decodable { public let name; public
// let child }` with NO explicitly-declared `public init`. Its memberwise init is
// SYNTHESIZED as `internal`, so `LBSpecOption(name:child:)` is NOT callable from
// `LiveBuyReferenceUI` (it lives in `LiveBuySDK`). DO NOT try to construct an
// `LBSpecOption` here — it will fail to compile.
//
// CONSEQUENCE: to get variant chip GROUPS into a snapshot you CANNOT build an
// `LBProduct` with populated `specOptions` and let the template map it. Instead:
//   • For the LIST surface (`ProductListView`), build demo `LBProduct`s with
//     `specOptions: []` (the list does not need variant groups — it draws photo /
//     name / price / sold-out only). `LBProduct` HAS a full public memberwise init
//     (all 23 fields) and `LBSpec` HAS a full public init, so a deterministic
//     product with `specifications` + stock + soldOut + photos + priceShow is
//     straightforward (see `demoProduct` / `demoSoldOutProduct` below).
//   • For the DETAIL / restock surfaces, build the mapped state values DIRECTLY via
//     their public inits — `LBProductDetailState`, `LBVariantState` (+ public
//     `LBVariantGroup(label:options:)`), `LBQtyState`, `LBMiniCartPeek`,
//     `LBCartCTAState`. These all have PUBLIC memberwise inits reachable from
//     reference-ui, so a variant group is constructed as
//     `LBVariantGroup(label: "顏色", options: ["珊瑚橘", "玫瑰棕"])` WITHOUT ever
//     touching `LBSpecOption`. This is the deterministic snapshot path the model's
//     memberwise/demo init already takes (it stores `LBVariantState` directly).
//
// ── The 5 mapped state values (all public inits, reference-ui-reachable) ─────────
//   • LBProductDetailState(productId:name:priceShow:originalPriceShow:price:stock:
//       soldOut:photos:specifications:specOptions:)   — pass `specOptions: []`.
//   • LBVariantState(groups:selection:selectedSpec:selectedSpecificationId:)
//       — `groups: [LBVariantGroup(label:options:)]`, `selection: [0: 0]`,
//         `selectedSpec:` an `LBSpec(...)` (public init) or nil for the「未選規格」case.
//   • LBQtyState(qty:min:max:)                          — sold-out → `(0, 0, 0)`.
//   • LBMiniCartPeek(productId:name:priceShow:soldOut:)
//   • LBCartCTAState(count:)                            — or pass `cartCount: Int`.
//
// The demo seeds below cover: a multi-product list (incl. one sold-out row), a
// detail WITH a variant group + qty, a detail with NO variant group, a mini-cart
// peek, and a sold-out detail for the restock surface.

public extension ProductSheetsModel {

    /// A deterministic demo product (in stock, single photo, no spec groups — the
    /// list does not need variant groups, and `specOptions: []` sidesteps the
    /// `LBSpecOption` internal-init compile barrier). `LBProduct` has a full public
    /// memberwise init (23 fields), used verbatim here.
    static func demoProduct(
        id: String = "demo-prod-001",
        name: String = "Aurora 霧面唇釉 #03 珊瑚橘",
        priceShow: String = "NT$ 390",
        originalPriceShow: String = "NT$ 590",
        stock: Int = 24,
        soldOut: Int = 0
    ) -> LBProduct {
        LBProduct(
            id: id,
            goodsNo: "G-\(id)",
            goodsGpn: "GPN-\(id)",
            name: name,
            price: 390,
            priceShow: priceShow,
            originalPrice: 590,
            originalPriceShow: originalPriceShow,
            stock: stock,
            pic: "",
            photos: [],
            brief: "夏日通勤彩妝主打色",
            soldOut: soldOut,
            isHot: 1,
            isOutSoon: 0,
            narrateStatus: soldOut == 1 ? 0 : 2,
            isAwait: 0,
            isAwaitNotice: 0,
            beginTime: nil,
            endTime: nil,
            diversionUrl: "",
            specifications: [],   // detail builds variant groups via LBVariantGroup directly
            specOptions: [])      // ⚠️ MUST stay [] — LBSpecOption init is internal
    }

    /// A deterministic SOLD-OUT demo product for the list sold-out row + the
    /// restock surface (`soldOut == 1`, stock 0).
    static func demoSoldOutProduct() -> LBProduct {
        demoProduct(
            id: "demo-prod-002",
            name: "Aurora 霧面唇釉 #07 玫瑰棕(完售)",
            priceShow: "NT$ 390",
            originalPriceShow: "NT$ 590",
            stock: 0,
            soldOut: 1)
    }

    /// A deterministic product-detail WITH one variant group (顏色) + a resolved
    /// spec, built via the public mapped-state inits (no `LBSpecOption`). Pair with
    /// `demoVariantWithGroup` / `demoQtyInStock`.
    static func demoDetail(soldOut: Int = 0) -> LBProductDetailState {
        LBProductDetailState(
            productId: "demo-prod-001",
            name: "Aurora 霧面唇釉 #03 珊瑚橘",
            priceShow: "NT$ 390",
            originalPriceShow: "NT$ 590",
            price: 390,
            stock: soldOut == 1 ? 0 : 24,
            soldOut: soldOut,
            photos: [],
            specifications: [],
            specOptions: [])
    }

    /// A demo variant state WITH a chip group (顏色), the first option selected,
    /// resolving a demo `LBSpec` (public init). Covers the variant-chip surface.
    static var demoVariantWithGroup: LBVariantState {
        let spec = LBSpec(
            id: "demo-spec-01",
            name: "珊瑚橘",
            specificationNo: "SKU-CORAL",
            price: 390,
            priceShow: "NT$ 390",
            originalPrice: 590,
            originalPriceShow: "NT$ 590",
            stock: 24,
            photos: [])
        return LBVariantState(
            groups: [LBVariantGroup(label: "顏色", options: ["珊瑚橘", "玫瑰棕", "正紅"])],
            selection: [0: 0],
            selectedSpec: spec,
            selectedSpecificationId: spec.id)
    }

    /// A demo variant state with NO chip group (no-spec product) — covers the
    /// 「無變體群」detail fixture.
    static let demoVariantNoGroup = ProductSheetsModel.emptyVariant

    /// A demo in-stock qty state (`qty 1`, `min 1`, `max 24`).
    static let demoQtyInStock = LBQtyState(qty: 1, min: 1, max: 24)

    /// A demo sold-out qty state (`0, 0, 0`) for the restock surface.
    static let demoQtySoldOut = LBQtyState(qty: 0, min: 0, max: 0)

    /// A demo mini-cart peek (most-recent successful add).
    static var demoMiniCartPeek: LBMiniCartPeek {
        LBMiniCartPeek(
            productId: "demo-prod-001",
            name: "Aurora 霧面唇釉 #03 珊瑚橘",
            priceShow: "NT$ 390",
            soldOut: 0)
    }

    /// A deterministic demo model with a multi-product list (incl. one sold-out
    /// row) + a populated mini-cart peek + a cart count. No bound template — all
    /// forwarders are no-ops, all reads are stable for snapshots.
    static var demoListModel: ProductSheetsModel {
        ProductSheetsModel(
            products: [demoProduct(), demoSoldOutProduct(), demoProduct(id: "demo-prod-003", name: "Aurora 唇刷組")],
            miniCartPeek: demoMiniCartPeek,
            cartCount: 2)
    }
}
