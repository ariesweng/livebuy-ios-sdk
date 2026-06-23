import SwiftUI
import Combine
import LiveBuySDK
import LiveBuyUI

// MARK: - ProductSheetsModel — family-3 product sheet-stack observable snapshot bridge
//
// Spec: `reference-ui-rendering/spec.md` (family-3 product + sheets)
// Design: rb-ios-product-sheets design.md D-1 / D-2 / D-3 / D-4 / D-5.
//
// This is the SKELETON for rb-ios-product-sheets. It bridges the headless template
// view-models exposed by `DefaultPlayerTemplate` (obtained via
// `LiveBuyUI.playerTemplate(for:)`) into a SwiftUI-observable snapshot that the
// four family-3 surface sub-views read. It is a read-only mirror — IDENTICAL
// pattern to `PlayerShellModel` (family-1) / `FeedWinModel` (family-2):
//
//   - It does NOT own a second copy of authoritative state — it republishes
//     SNAPSHOT VALUES taken from the template's own `private(set) public` reads
//     (`productOverlay.products` / `productSheet.detail` / `variantPicker.state` /
//     `qtyStepper.state` / `miniCart.peek` / `cartCTA.state.count` +
//     `needsVariantSelection` / `addToCartFailed`) each time the template fires its
//     single coalesced `onChange` (D-1).
//   - It does NOT add pixels and it does NOT add any accessor to `LiveBuyUI`
//     (that would be a template-layer concern, out of scope here).
//   - It does NOT subscribe to each model's internal `onMutation` (that is a
//     template-internal hook); it observes ONLY the template's single public
//     `onChange` (design §"容器與 view-model 橋接", D-1).
//   - The mutating interactions this layer carries are thin forwarders to the
//     EXISTING public template exits (`selectVariant` / `setQty` / `incQty` /
//     `decQty` / `addToCart` / `miniCart.dismissMiniCart` / `miniCart.openDetail` /
//     `cartCTA.openCart` / `goodsTracking.toggleNotice`). reference-ui NEVER calls
//     core `addToCart` directly — `addToCart()` forwards to `template.addToCart()`,
//     which assembles the route-B `LBCartRequest` internally.
//   - PRODUCT-ROW TAP IS NOT A TEMPLATE FORWARDER. Opening a product detail is the
//     CORE product-tap exit (`LiveBuyPlayerViewController.simulateProductTap`); the
//     reference-ui list row only forwards the tap to a HOST-WIRED closure on the
//     CONTAINER (`ProductSheetsOverlayView.onProductTap`). This model carries NO
//     row-tap forwarder (mirrors family-2 `ChatFeedView`'s eventJoin host-wired
//     exit — the open is the host's / core's job, not this layer's).
//
// iOS-14-safe: `ObservableObject` + `@Published` are available from iOS 13, so
// no `@available` guard is needed here.

/// Observable snapshot of the family-3 product sheet-stack state, republished from
/// a live `DefaultPlayerTemplate` (or constructed deterministically for demos /
/// snapshot tests via the memberwise initializer).
public final class ProductSheetsModel: ObservableObject {

    // MARK: - Published surface snapshots
    //
    // Each group is the read-only value set ONE family-3 surface sub-view needs.
    // The grouping mirrors the surfaces so a surface sub-view binds exactly the
    // snapshot values it needs (see the documented sub-view input pattern in
    // ProductSheetsOverlayView.swift).

    // -- Surface 1: ProductListView ← product list drawer (D-2) ----------------

    /// The core-fed products snapshot, surfaced INTRODUCING-FIRST by the data layer
    /// (`DefaultProductOverlayState.productsIntroducingFirst` — LIVE narrate_status==2 商品排第一,
    /// 其餘維持相對順序; VOD / 無介紹中時等於原序). Already ordered by the data layer — this
    /// layer MUST NOT slice / merge / re-sort (doing so would be a second copy, violating single-truth).
    @Published public private(set) var products: [LBProduct]

    /// The currently-introducing product's id (`DefaultProductOverlayState.introducingProductId`).
    /// The product-list row whose id matches draws the「介紹中」banner (LIVE-only). nil → none.
    @Published public private(set) var introducingProductId: String?

    /// Playback-mode signals for the product-row thumbnail overlay
    /// (rb-ios-product-row-status-overlay). Mirrored from the template
    /// `header.isLive` / `playbackProgress.isReplay` / `playbackProgress.position`.
    @Published public private(set) var isLive: Bool
    @Published public private(set) var isReplay: Bool
    @Published public private(set) var position: Double

    /// Derived playback mode for the product-row overlay (replay takes precedence
    /// over live). `nil` for a demo / snapshot model (no bound template) → the
    /// view falls back to its real-frame `live` flag so baselines stay byte-identical.
    public var rowMode: ProductRowMode? {
        guard template != nil else { return nil }
        if isReplay { return .replay }
        return isLive ? .live : .vod
    }

    /// Whether the product-list drawer is presented (rb-ios-product-list-slide-sheet).
    /// A UI PRESENTATION flag — NOT a core snapshot — so it is publicly writable (unlike
    /// the `private(set)` snapshot fields): the container's `onOpenProductList` default sets
    /// it `true` and `ProductSheetsOverlayView` drives its shared SheetKit `.lbBottomSheet`
    /// slide-up off it (replacing the system `.pageSheet` fallback). MUST NOT be pushed back
    /// to template / core.
    @Published public var listPresented: Bool = false

    // -- Surface 2: ProductDetailSheetView ← detail + variant + qty (D-3) ------

    /// Product-detail sheet snapshot (`DefaultProductSheet.detail`); nil until a
    /// `diversion == 0` product-tap opens a detail. Drives whether the detail (and,
    /// when sold-out, the restock-notify) sheet is presented.
    @Published public private(set) var detail: LBProductDetailState?
    /// Variant-picker snapshot (`DefaultVariantPicker.state`) — chip `groups`,
    /// current `selection`, resolved `selectedSpec` / `selectedSpecificationId`.
    @Published public private(set) var variant: LBVariantState
    /// Qty-stepper snapshot (`DefaultQtyStepper.state`) — `{ qty, min, max }`.
    /// Sold-out / out-of-stock → `min == max == qty == 0`.
    @Published public private(set) var qty: LBQtyState

    // -- Surface 3: MiniCartView ← mini-cart peek (D-4) ------------------------

    /// Mini-cart peek snapshot (`DefaultMiniCart.peek`); nil → no floating peek.
    @Published public private(set) var miniCartPeek: LBMiniCartPeek?

    // -- Surface 1 (CTA): cart CTA count (D-2 / D-4) ---------------------------

    /// Per-session successful-add count (`DefaultCartCTA.state.count`); the cart
    /// CTA badge is drawn when `> 0`.
    @Published public private(set) var cartCount: Int

    // -- Surface 2 (guard flags): add-to-cart prompts (D-3) --------------------

    /// 「請選規格」guard flag (`DefaultPlayerTemplate.needsVariantSelection`) — set
    /// true when `addToCart()` is called with an incomplete spec selection.
    @Published public private(set) var needsVariantSelection: Bool
    /// Add-to-cart failure flag (`DefaultPlayerTemplate.addToCartFailed`) — set true
    /// when the route-B add threw a GENUINE failure; drives the failure banner.
    @Published public private(set) var addToCartFailed: Bool
    /// Add-to-cart「需登入」flag (`DefaultPlayerTemplate.addToCartNeedsLogin`) — set
    /// true when the route-B add threw the core「needs login」signal (empty `buy_no`
    /// → `serverError(code:401)`). Orthogonal to `addToCartFailed`; drives the
    /// `AuthGateModalView(.cartAdd)` login gate instead of the failure banner
    /// (cart-needs-login-gate).
    @Published public private(set) var addToCartNeedsLogin: Bool

    /// Add-to-cart「請求進行中」flag (`DefaultPlayerTemplate.addToCartInFlight`,
    /// cart-add-loading-state-template) — set true while an addcart request is in
    /// flight, false on any outcome. Drives the CTA loading state (spinner +「加入中…」,
    /// locked stepper / variant). Orthogonal to `addToCartFailed` / `addToCartNeedsLogin`.
    @Published public private(set) var addToCartInFlight: Bool

    // MARK: - Live binding

    /// The bound template, when constructed from a live player. nil for demo /
    /// snapshot instances. Held weakly so this model never retains the template
    /// (the player VC owns it; dependency stays one-way UI → core).
    private weak var template: DefaultPlayerTemplate?

    /// The template's `onChange` we installed, so we can restore the previous one
    /// on deinit (we chain rather than clobber — same as the family-1/2 models).
    private var previousOnChange: (() -> Void)?

    // MARK: - Live initializer (D-1)

    /// Bridge a live `DefaultPlayerTemplate`: take an initial snapshot and
    /// subscribe to its single coalesced `onChange` so every product snapshot /
    /// detail open / variant / qty / mini-cart / cart-CTA / goods-tracking change
    /// re-snapshots and republishes to the surface sub-views.
    ///
    /// The host obtains the template via `LiveBuyUI.playerTemplate(for:)` and
    /// passes it here. Returns a model whose published values mirror the template
    /// (read-only). The previous `onChange` (if any host already installed one) is
    /// chained, not replaced.
    public convenience init(template: DefaultPlayerTemplate) {
        self.init(snapshotting: template)
        self.template = template
        self.previousOnChange = template.onChange
        template.onChange = { [weak self] in
            self?.previousOnChange?()
            self?.refresh(from: template)
        }
    }

    /// Take an immediate snapshot of a template (no subscription) — used by the
    /// live convenience init for the seed values.
    private convenience init(snapshotting t: DefaultPlayerTemplate) {
        self.init(
            products: t.productOverlay.productsIntroducingFirst,
            introducingProductId: t.productOverlay.introducingProductId,
            isLive: t.header.isLive,
            isReplay: t.playbackProgress.isReplay,
            position: t.playbackProgress.position,
            detail: t.productSheet.detail,
            variant: t.variantPicker.state,
            qty: t.qtyStepper.state,
            miniCartPeek: t.miniCart.peek,
            cartCount: t.cartCTA.state.count,
            needsVariantSelection: t.needsVariantSelection,
            addToCartFailed: t.addToCartFailed,
            addToCartNeedsLogin: t.addToCartNeedsLogin,
            addToCartInFlight: t.addToCartInFlight
        )
    }

    // MARK: - Memberwise / demo initializer (D-1)

    /// Construct a deterministic instance WITHOUT a live player — for the surface
    /// sub-views' previews and the per-surface snapshot tests. Every value defaults
    /// to the at-attach seed (no products, no detail, empty variant, qty 1/1/0,
    /// no peek, zero cart, no prompts) so a zero-argument call yields a stable
    /// baseline.
    ///
    /// The empty defaults mirror the template models' initial state:
    ///   • `LBVariantState(groups: [], selection: [:], selectedSpec: nil,
    ///     selectedSpecificationId: nil)` == `DefaultVariantPicker` at construction.
    ///   • `LBQtyState(qty: 1, min: 1, max: 0)` == `DefaultQtyStepper` at construction.
    public init(
        products: [LBProduct] = [],
        introducingProductId: String? = nil,
        isLive: Bool = false,
        isReplay: Bool = false,
        position: Double = 0,
        detail: LBProductDetailState? = nil,
        variant: LBVariantState = ProductSheetsModel.emptyVariant,
        qty: LBQtyState = ProductSheetsModel.emptyQty,
        miniCartPeek: LBMiniCartPeek? = nil,
        cartCount: Int = 0,
        needsVariantSelection: Bool = false,
        addToCartFailed: Bool = false,
        addToCartNeedsLogin: Bool = false,
        addToCartInFlight: Bool = false
    ) {
        self.products = products
        self.introducingProductId = introducingProductId
        self.isLive = isLive
        self.isReplay = isReplay
        self.position = position
        self.detail = detail
        self.variant = variant
        self.qty = qty
        self.miniCartPeek = miniCartPeek
        self.cartCount = cartCount
        self.needsVariantSelection = needsVariantSelection
        self.addToCartFailed = addToCartFailed
        self.addToCartNeedsLogin = addToCartNeedsLogin
        self.addToCartInFlight = addToCartInFlight
    }

    deinit {
        // Restore the previous handler so a re-bound template is not left with a
        // dangling closure capturing this (now gone) model.
        template?.onChange = previousOnChange
    }

    // MARK: - Re-snapshot on change (D-1)

    /// Pull the latest values from the bound template into the published mirrors.
    /// Always on the main thread (the template dispatches `onChange` on main; the
    /// live init only installs this from the main-thread `onChange`). `objectWill
    /// Change` fires once per `@Published` write — acceptable for the skeleton;
    /// surface sub-views read final values within one runloop.
    private func refresh(from t: DefaultPlayerTemplate) {
        products = t.productOverlay.productsIntroducingFirst
        introducingProductId = t.productOverlay.introducingProductId
        isLive = t.header.isLive
        isReplay = t.playbackProgress.isReplay
        position = t.playbackProgress.position
        detail = t.productSheet.detail
        variant = t.variantPicker.state
        qty = t.qtyStepper.state
        miniCartPeek = t.miniCart.peek
        cartCount = t.cartCTA.state.count
        needsVariantSelection = t.needsVariantSelection
        addToCartFailed = t.addToCartFailed
        addToCartNeedsLogin = t.addToCartNeedsLogin
        addToCartInFlight = t.addToCartInFlight
    }

    // MARK: - Read-only host intents (pass-through to the bound template)
    //
    // Thin forwarders for the template-owned product sheet-stack intents the
    // family-3 surfaces drive. Each is a no-op for demo instances (no bound
    // template). reference-ui NEVER calls core directly — these route through the
    // EXISTING public template / model exits (design §範圍與不變式):
    //
    //   • selectVariant → `DefaultPlayerTemplate.selectVariant(groupIndex:optionIndex:)`
    //   • setQty / incQty / decQty → `DefaultPlayerTemplate.setQty/incQty/decQty`
    //   • addToCart → `DefaultPlayerTemplate.addToCart()` (template assembles the
    //     route-B `LBCartRequest` + delegates to the injected core requester — the
    //     reference-ui layer NEVER calls `LiveBuy.addToCart` itself).
    //   • dismissMiniCart / openMiniCartDetail → `DefaultMiniCart.dismissMiniCart()`
    //     / `DefaultMiniCart.openDetail()`.
    //   • openCart → `DefaultCartCTA.openCart()` (host passthrough; no checkout page).
    //   • toggleNotice / noticeEnabled → `DefaultGoodsTracking.toggleNotice(_:)` /
    //     `noticeEnabled(for:)` — restock-notify subscription (type=2).
    //   • toggleFavorite / favEnabled → `DefaultGoodsTracking.toggleAwait(_:)` /
    //     `awaitEnabled(for:)` — the product-detail 收藏 / 到貨追蹤 affordance (type=1;
    //     reconciled here from the retired family-6 dual-switch — design 2026-06-06).
    //
    // NOTE — product-row tap is intentionally ABSENT from this list. Opening a
    // product detail is the CORE product-tap exit (`simulateProductTap`); the list
    // row forwards to a host-wired closure on the CONTAINER, never through this
    // model (design §D-2: reference-ui 永不自行開明細).

    /// Forward a variant chip tap (D-3) → `template.selectVariant(...)`. No-op for
    /// demo instances.
    public func selectVariant(groupIndex: Int, optionIndex: Int) {
        template?.selectVariant(groupIndex: groupIndex, optionIndex: optionIndex)
    }

    /// Forward a direct qty set (D-3) → `template.setQty(_:)`. No-op for demo.
    public func setQty(_ value: Int) {
        template?.setQty(value)
    }

    /// Forward a qty `+` tap (D-3) → `template.incQty()`. No-op for demo.
    public func incQty() {
        template?.incQty()
    }

    /// Forward a qty `-` tap (D-3) → `template.decQty()`. No-op for demo.
    public func decQty() {
        template?.decQty()
    }

    /// Forward the 加入購物車 intent (D-3) → `template.addToCart()` (template assembles
    /// route-B `LBCartRequest`; reference-ui NEVER calls core addToCart directly).
    /// No-op for demo instances.
    public func addToCart() {
        template?.addToCart()
    }

    /// Forward a「關閉商品明細 / 加購 / 補貨 sheet」intent → `DefaultPlayerTemplate.closeProductDetail()`
    /// (clears the template's `productSheet.detail`). The container calls this on every sheet
    /// dismiss so re-tapping the SAME product re-opens it — `openDetail` is diff-then-notify, so
    /// without clearing the template detail a closed sheet stays unopenable for the same product
    /// (rb-ios-product-action-sheet / expose-close-product-detail-template). No-op for demo.
    public func closeDetail() {
        template?.closeProductDetail()
    }

    /// Forward a mini-cart dismiss (D-4) → `DefaultMiniCart.dismissMiniCart()`.
    /// No-op for demo instances.
    public func dismissMiniCart() {
        template?.miniCart.dismissMiniCart()
    }

    /// Forward a mini-cart「開明細」(D-4) → `DefaultMiniCart.openDetail()` (template
    /// re-opens the peeked product's detail from its products snapshot). No-op for
    /// demo instances.
    public func openMiniCartDetail() {
        template?.miniCart.openDetail()
    }

    /// Forward a cart-CTA tap (D-2) → `DefaultCartCTA.openCart()` (host passthrough;
    /// the template owns no checkout page). No-op for demo instances.
    public func openCart() {
        template?.cartCTA.openCart()
    }

    /// Forward a restock-notify toggle (D-5) → `DefaultGoodsTracking.toggleNotice(_:)`
    /// (optimistic flip of ONLY the notice flag → core `setNoticeGoods` type=2;
    /// corrected by `NOTICE_GOODS_CHANGED`). No-op for demo instances. This is the
    /// ONLY goods-tracking write family-3 makes — the AWAIT switch is family-6.
    public func toggleNotice(forProductId productId: String) {
        guard let goodsGpn = resolveGoodsGpn(productId: productId) else { return }
        template?.goodsTracking.toggleNotice(goodsGpn)
    }

    /// Read the current restock-notify subscription state for a product detail (D-5)
    /// — `DefaultGoodsTracking.noticeEnabled(for: goodsGpn)`. Returns false for demo
    /// instances (no bound template) or when the product is not in the snapshot.
    /// This is a READ of the notice flag ONLY (the AWAIT flag is family-6, never
    /// read here).
    public func noticeEnabled(forProductId productId: String) -> Bool {
        guard let goodsGpn = resolveGoodsGpn(productId: productId) else { return false }
        return template?.goodsTracking.noticeEnabled(for: goodsGpn) ?? false
    }

    /// Forward a 收藏（到貨追蹤 type=1）toggle → `DefaultGoodsTracking.toggleAwait(_:)`
    /// (optimistic flip of ONLY the await flag → core `setAwaitGoods` type=1; corrected
    /// by `AWAIT_GOODS_CHANGED`). No-op for demo instances. This is the product-detail
    /// 「收藏 / 加入我的最愛」affordance; the restock NOTICE toggle is independent.
    public func toggleFavorite(forProductId productId: String) {
        guard let goodsGpn = resolveGoodsGpn(productId: productId) else { return }
        template?.goodsTracking.toggleAwait(goodsGpn)
    }

    /// Read the current 收藏（await type=1）state for a product detail —
    /// `DefaultGoodsTracking.awaitEnabled(for: goodsGpn)`. Returns false for demo
    /// instances (no bound template) or when the product is not in the snapshot.
    public func favEnabled(forProductId productId: String) -> Bool {
        guard let goodsGpn = resolveGoodsGpn(productId: productId) else { return false }
        return template?.goodsTracking.awaitEnabled(for: goodsGpn) ?? false
    }

    /// 商品說明（`LBProduct.brief`）— 由 `products` 快照以 `productId` 解析（D-4 同模式：
    /// `LBProductDetailState` 不帶 `brief`，只有 `productId`；`brief` 在原始 `LBProduct` 上）。
    /// 無對應商品（或 demo 無 products）回 `""`，呼叫端據此 gate 不畫說明區塊
    /// （rb-ios-product-sheet-detail-polish 問題 4）。
    public func brief(forProductId productId: String) -> String {
        products.first(where: { $0.id == productId })?.brief ?? ""
    }

    /// Resolve the goods-tracking key (`goodsGpn`) for a product detail from the
    /// `products` snapshot (D-5: 「goodsGpn 從 product 讀」). `LBProductDetailState`
    /// carries only `productId`, but `DefaultGoodsTracking` is keyed by `goodsGpn`
    /// (the template seeds it via `LBProduct.goodsGpn`), so the restock toggle MUST
    /// map productId → the originating `LBProduct.goodsGpn` rather than key off the
    /// productId directly. nil when the product is not in the current list.
    private func resolveGoodsGpn(productId: String) -> String? {
        products.first(where: { $0.id == productId })?.goodsGpn
    }

    // MARK: - Deterministic empty seeds (demo / snapshot defaults)

    /// The variant state at attach (no groups, nothing selected) — matches a
    /// freshly-constructed `DefaultVariantPicker.state`.
    public static let emptyVariant = LBVariantState(
        groups: [],
        selection: [:],
        selectedSpec: nil,
        selectedSpecificationId: nil)

    /// The qty state at attach (`qty 1`, `min 1`, `max 0` until bounds recompute) —
    /// matches a freshly-constructed `DefaultQtyStepper.state`.
    public static let emptyQty = LBQtyState(qty: 1, min: 1, max: 0)
}
