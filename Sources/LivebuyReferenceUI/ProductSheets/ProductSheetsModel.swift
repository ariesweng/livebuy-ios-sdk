import SwiftUI
import Combine
import LivebuySDK
import LivebuyUI

// MARK: - ProductSheetsModel — family-3 product sheet-stack observable snapshot bridge
//
// Spec: `reference-ui-rendering/spec.md` (family-3 product + sheets)
// Design: rb-ios-product-sheets design.md D-1 / D-2 / D-3 / D-4 / D-5.
//
// This is the SKELETON for rb-ios-product-sheets. It bridges the headless template
// view-models exposed by `DefaultPlayerTemplate` (obtained via
// `LivebuyUI.playerTemplate(for:)`) into a SwiftUI-observable snapshot that the
// four family-3 surface sub-views read. It is a read-only mirror — IDENTICAL
// pattern to `PlayerShellModel` (family-1) / `FeedWinModel` (family-2):
//
//   - It does NOT own a second copy of authoritative state — it republishes
//     SNAPSHOT VALUES taken from the template's own `private(set) public` reads
//     (`productOverlay.products` / `productSheet.detail` / `variantPicker.state` /
//     `qtyStepper.state` / `miniCart.peek` / `cartCTA.state.count` +
//     `needsVariantSelection` / `addToCartFailed`) each time the template fires its
//     single coalesced `onChange` (D-1).
//   - It does NOT add pixels and it does NOT add any accessor to `LivebuyUI`
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
//     CORE product-tap exit (`LivebuyPlayerViewController.simulateProductTap`); the
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
    /// (`DefaultPlayerTemplate.productsIntroducingFirst` — LIVE narrate_status==2 商品排第一,
    /// VOD/回放依 `vodActiveProducts` 播放進度置頂, 其餘維持相對順序;
    /// vod-product-list-introducing-order-template). Already ordered by the data layer — this
    /// layer MUST NOT slice / merge / re-sort (doing so would be a second copy, violating single-truth).
    @Published public private(set) var products: [LBProduct]

    /// The currently-introducing product's id (`DefaultProductOverlayState.introducingProductId`).
    /// This is core's "first narrating product" convenience — it can only ever name ONE product.
    /// Kept published for source compat; the product-list drawer's badge no longer reads this
    /// directly (see `liveActiveProducts` below, rb-ios-product-bag-multi-narrating).
    @Published public private(set) var introducingProductId: String?

    /// ALL LIVE now-introducing products — mirrors `DefaultPlayerTemplate.liveActiveProducts`
    /// (every `narrate_status == 2` product in the current `products` snapshot; the backend MAY
    /// narrate MULTIPLE simultaneously). Feeds the product-list drawer's multi-badge fix
    /// (rb-ios-product-bag-multi-narrating): `introducingProductId` above only ever carried the
    /// FIRST narrating product, so a second simultaneously-narrating product's row silently drew
    /// no「介紹中」badge. `PlayerShellModel.liveActiveProducts` already consumes the SAME
    /// `DefaultPlayerTemplate` aggregate for the LIVE pinned-card carousel — this is the family-3
    /// (product list) analogue, a second independent reference-ui consumer of an existing
    /// view-model capability (no view-model / core change). Empty for a demo / snapshot instance
    /// with no bound template.
    @Published public private(set) var liveActiveProducts: [LBProduct]

    /// The RAW, backend-order products snapshot (`DefaultPlayerTemplate.productOverlay.products`)
    /// — rb-ios-product-row-number-badge. Deliberately DIFFERENT from `products` above: `products`
    /// is `productsIntroducingFirst` (already reordered so introducing-now products sort first, for
    /// DISPLAY); this property is the UN-reordered order, used ONLY to resolve a row's number-badge
    /// position (`ProductRowNumberBadge.resolveIndex`, `ProductListView.swift`). Reading it from
    /// `products` instead would make every row's number jump whenever the introducing set changes
    /// (the introducing product gets moved to the front) — wrong per the design's "編號＝原始清單序
    /// 號" rule.
    ///
    /// A plain (NOT `@Published`) read-through computed property — same pattern as
    /// `optionAvailability` below: the source itself is a stored value on the template with no
    /// caching needed here, and SwiftUI already re-evaluates this alongside every OTHER `@Published`
    /// write this class makes on `refresh(from:)`, so a second stored/`@Published` copy would just be
    /// a second maintenance path for the same data. This also means NO special-case logic is needed
    /// for "after a LIVE 5s poll replaces `products` wholesale" or "after a product stops
    /// introducing" — every read simply reflects whatever the template holds AT THAT MOMENT.
    /// `template == nil` (demo / snapshot instance) falls back to `products` (same demo-fallback
    /// convention as `products` / `liveActiveProducts` above — a demo has no separate "backend order"
    /// source of its own).
    public var productsBackendOrder: [LBProduct] {
        template?.productOverlay.products ?? products
    }

    /// Playback-mode signals for the product-row thumbnail overlay
    /// (rb-ios-product-row-status-overlay). Mirrored from the template
    /// `header.isLive` / `header.isFinishedLiveReplay` / `playbackProgress.position`.
    ///
    /// `isReplay` here means a **finished-live replay** (`header.isFinishedLiveReplay`,
    /// `type==3 || (type==2 && liveStatus==3)`) — NOT the narrower DVR
    /// behind-live-edge concept `playbackProgress.isReplay` that `PlayerShellModel`
    /// (family-1) separately mirrors for its own, unrelated live-chrome purpose
    /// (`PlayerShellModel.isReplay`). `playbackProgress.isReplay` is only ever `true`
    /// while a stream is ACTIVELY live and the viewer has scrubbed behind the live
    /// edge — for any finished-live replay it is permanently `false`, so reading it
    /// here previously mis-classified finished-live-replay rows as `.vod`
    /// (rb-ios-product-row-replay-flag-fix). MUST NOT revert to
    /// `playbackProgress.isReplay` — see the two assignments below.
    @Published public private(set) var isLive: Bool
    @Published public private(set) var isReplay: Bool
    @Published public private(set) var position: Double

    /// 搶購場旗標（`rb-ios-flash-sale-live-signal-wiring`）— straight mirror of
    /// `DefaultPlayerHeaderState.isFlashSale` (← core `LBChannel.isFlashSale` ← backend
    /// top-level `is_flash_sale`, orthogonal to `type`/`live_status`). Consumed by
    /// `ProductRowView.isFlashSale` (via `ProductListView`, below) to pick「直播價」vs
    /// 「搶購中」for the `mode == .live` name-tag pill ONLY. The narrating-banner text
    /// (`ProductRowView.introducingLabel`) previously ALSO branched on this flag but that
    /// split was reverted per user decision (`rb-ios-narrating-banner-revert-flash-sale-
    /// text`) — the banner is now a constant「介紹中」regardless. Default `false` for a
    /// demo / snapshot instance (no bound template) — same convention as `isLive` /
    /// `isReplay` above.
    @Published public private(set) var isFlashSale: Bool

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
    /// Cascading purchasability snapshot for the CURRENTLY bound template's variant picker
    /// (`DefaultVariantPicker.optionAvailability`, rb-ios-variant-cascading-availability-template)
    /// — one entry per `variant.groups` entry, matched by `groupIndex`. Deliberately NOT
    /// `@Published`: the source itself is a read-through computed property (no caching, matching
    /// `DefaultVariantPicker.state`'s own pattern) — SwiftUI already re-evaluates this alongside
    /// `variant` whenever a `@Published` write in `refresh()` fires `objectWillChange`, so a
    /// second stored/`@Published` copy would just be a second maintenance path for the same data
    /// (rb-ios-variant-cascading-availability-ui). `[]` for a demo / snapshot instance (no bound
    /// template — `template` is nil).
    public var optionAvailability: [LBVariantGroupAvailability] {
        template?.variantPicker.optionAvailability ?? []
    }
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

    /// Backend / merchant-driven REMAINING-STOCK-COUNT gate (rb-ios-show-stock-caption-toggle).
    /// NOT a template-derived snapshot — a per-shell constant sourced from
    /// `LivebuyPlayerConfig.showStock` (default `true`, itself normalized by the host from
    /// `extensions.show_stock` via `LBShowStock.normalized(_:)`), so it is a plain stored property
    /// (not `@Published`): set once at build time, never mutated at runtime, and `refresh(from:)`
    /// MUST NOT touch it. Exactly the shape `PlayerShellModel.showViewerCount` / `.titleScroll` use.
    ///
    /// `ProductSheetsOverlayView` feeds it to BOTH sheet surfaces that draw the「只剩庫存 N 組」
    /// caption (the `.detail` `ProductDetailSheetView` and the `.addToCart` `AddToCartSheetView`);
    /// the `.notifyRestock` branch deliberately does NOT receive it (its「尚無庫存」is a sold-out
    /// state caption, unrelated to this setting).
    public var showStock: Bool = true

    // MARK: - Live binding

    /// The bound template, when constructed from a live player. nil for demo /
    /// snapshot instances. Held weakly so this model never retains the template
    /// (the player VC owns it; dependency stays one-way UI → core).
    private weak var template: DefaultPlayerTemplate?

    /// The independent observer registration token this model holds. Removed on
    /// deinit so this model unsubscribes ONLY itself — never clobbers another
    /// model's subscription (multi-observer registry, same as the family-1/2 models).
    private var observerToken: LBTemplateObserverToken?

    // MARK: - Live initializer (D-1)

    /// Bridge a live `DefaultPlayerTemplate`: take an initial snapshot and
    /// register an observer on its single coalesced change notification so every
    /// product snapshot / detail open / variant / qty / mini-cart / cart-CTA /
    /// goods-tracking change re-snapshots and republishes to the surface sub-views.
    ///
    /// The host obtains the template via `LivebuyUI.playerTemplate(for:)` and
    /// passes it here. Returns a model whose published values mirror the template
    /// (read-only). This registers an INDEPENDENT observer via `addObserver`; it
    /// does NOT chain or replace the template's legacy `onChange`.
    public convenience init(template: DefaultPlayerTemplate) {
        self.init(snapshotting: template)
        self.template = template
        self.observerToken = template.addObserver { [weak self] in
            self?.refresh(from: template)
        }
    }

    /// Take an immediate snapshot of a template (no subscription) — used by the
    /// live convenience init for the seed values.
    private convenience init(snapshotting t: DefaultPlayerTemplate) {
        self.init(
            products: t.productsIntroducingFirst,
            introducingProductId: t.productOverlay.introducingProductId,
            liveActiveProducts: t.liveActiveProducts,
            isLive: t.header.isLive,
            isReplay: t.header.isFinishedLiveReplay,
            position: t.playbackProgress.position,
            isFlashSale: t.header.isFlashSale,
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
        liveActiveProducts: [LBProduct] = [],
        isLive: Bool = false,
        isReplay: Bool = false,
        position: Double = 0,
        isFlashSale: Bool = false,
        detail: LBProductDetailState? = nil,
        variant: LBVariantState = ProductSheetsModel.emptyVariant,
        qty: LBQtyState = ProductSheetsModel.emptyQty,
        miniCartPeek: LBMiniCartPeek? = nil,
        cartCount: Int = 0,
        needsVariantSelection: Bool = false,
        addToCartFailed: Bool = false,
        addToCartNeedsLogin: Bool = false,
        addToCartInFlight: Bool = false,
        // Per-shell CONFIG constant, not a template snapshot (see the property's doc). Kept last so
        // every existing labelled call site is source-compatible.
        showStock: Bool = true
    ) {
        self.products = products
        self.introducingProductId = introducingProductId
        self.liveActiveProducts = liveActiveProducts
        self.isLive = isLive
        self.isReplay = isReplay
        self.position = position
        self.isFlashSale = isFlashSale
        self.detail = detail
        self.variant = variant
        self.qty = qty
        self.miniCartPeek = miniCartPeek
        self.cartCount = cartCount
        self.needsVariantSelection = needsVariantSelection
        self.addToCartFailed = addToCartFailed
        self.addToCartNeedsLogin = addToCartNeedsLogin
        self.addToCartInFlight = addToCartInFlight
        self.showStock = showStock
    }

    deinit {
        // Remove ONLY this model's own observer so a re-bound template is not left
        // with a dangling closure capturing this (now gone) model — other models'
        // subscriptions are untouched (no chain to restore, no clobber).
        if let token = observerToken { template?.removeObserver(token) }
    }

    // MARK: - Re-snapshot on change (D-1)

    /// Pull the latest values from the bound template into the published mirrors.
    /// Always on the main thread (the template dispatches `onChange` on main; the
    /// live init only installs this from the main-thread `onChange`). `objectWill
    /// Change` fires once per `@Published` write — acceptable for the skeleton;
    /// surface sub-views read final values within one runloop.
    private func refresh(from t: DefaultPlayerTemplate) {
        products = t.productsIntroducingFirst
        introducingProductId = t.productOverlay.introducingProductId
        liveActiveProducts = t.liveActiveProducts
        isLive = t.header.isLive
        isReplay = t.header.isFinishedLiveReplay
        position = t.playbackProgress.position
        isFlashSale = t.header.isFlashSale
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
    //     reference-ui layer NEVER calls `Livebuy.addToCart` itself).
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

    /// 商品說明（`LBProduct.brief`）— PRIMARY 由 `products` 快照以 `productId` 解析（D-4 同模式：
    /// `LBProductDetailState` 不帶 `brief`，只有 `productId`；`brief` 在原始 `LBProduct` 上）。
    /// PRIMARY 查找落空（`""`）時，退回 `recommendationResolvedProducts` 快取
    /// （rb-ios-recommendation-product-intro-carry-through，見該屬性文件）——涵蓋「更多商品」推薦卡
    /// 解析自 `channel.otherGoods`、本就不在 `products` 快照裡的情境。兩者皆無對應商品回 `""`，
    /// 呼叫端據此 gate 不畫說明區塊（rb-ios-product-sheet-detail-polish 問題 4）。
    public func brief(forProductId productId: String) -> String {
        let fromSnapshot = products.first(where: { $0.id == productId })?.brief ?? ""
        return fromSnapshot.isEmpty ? (recommendationResolvedProducts[productId]?.brief ?? "") : fromSnapshot
    }

    /// 商品介紹（`LBProduct.description`，`add-product-description-core-ios`）— 與
    /// `brief(forProductId:)` 同一 PRIMARY-then-FALLBACK 模式（`LBProductDetailState` 不帶
    /// `description`，只有 `productId`；`description` 在原始 `LBProduct` 上；FALLBACK 同樣讀
    /// `recommendationResolvedProducts`，見該屬性文件）。兩者皆無對應商品、或該商品的 `description`
    /// 本身就是空字串，皆回 `""`——呼叫端（`ProductDetailSheetView.productIntroSection`）收到 `""`
    /// 時 MUST NOT 顯示整個區塊（含標題），不存在任何 fallback 文案
    /// （`rb-ios-product-intro-bgcolor-and-hide-empty` 對 `rb-ios-product-intro-real-data`
    /// 「恆顯示 + fallback 文案」決定的明確反轉）。
    public func description(forProductId productId: String) -> String {
        let fromSnapshot = products.first(where: { $0.id == productId })?.description ?? ""
        return fromSnapshot.isEmpty ? (recommendationResolvedProducts[productId]?.description ?? "") : fromSnapshot
    }

    // MARK: - Recommendation-resolved product cache (rb-ios-recommendation-product-intro-carry-through)

    /// productId → the REAL `LBProduct` resolved via a host-wired `onResolveProduct` closure when
    /// `ProductSheetsOverlayView.openRecommendation(_:mode:)` opens a「更多商品」推薦卡 (sourced
    /// from core `channel.otherGoods`). Populated there (via `cacheRecommendationResolvedProduct`)
    /// at resolve time; consulted as a FALLBACK by `brief(forProductId:)` / `description(forProductId:)`
    /// above when the PRIMARY `products` snapshot lookup misses — a recommendation resolved from
    /// `channel.otherGoods` is never in `products` (== `template.productsIntroducingFirst`,
    /// scoped to the CURRENT VIDEO's own `goods`), so without this fallback its `brief`/`description`
    /// always resolved to `""` even when the backend genuinely sent real values.
    ///
    /// Deliberately a PLAIN (non-`@Published`) stored property, NOT merged into the `products`
    /// snapshot itself: `products` backs `ProductListView` / other family-3 surfaces that read it,
    /// and widening ITS search scope to include `otherGoods` would be a broader, harder-to-audit
    /// change than this narrowly-scoped fallback cache (see the change's design.md Decision).
    ///
    /// Lives on this class — rather than as `@State` on `ProductSheetsOverlayView` — as a
    /// CORRECTNESS requirement, not a style choice: `@State`'s persistent-identity storage is only
    /// reliably installed once SwiftUI mounts a view into a live rendering graph; a bare
    /// `ProductSheetsOverlayView(...)` constructed directly (every unit test in this module does
    /// this) never reaches that installation step, so a `@State`-held cache does not reliably
    /// survive across the two separate calls this fallback needs (`openRecommendation` writing,
    /// then a later `brief`/`description` read) — confirmed empirically by a failing test attempt
    /// during this change's implementation. This class is a single, already-retained,
    /// class-based, per-player-session instance (owned by the host's coordinator and shared by
    /// reference across every call), so a plain stored property here has no such caveat: a write
    /// is visible to every subsequent read, unconditionally, in both tests and live rendering.
    ///
    /// `internal` (module-scoped, NOT `public`): only `ProductSheetsOverlayView` (same
    /// `LivebuyReferenceUI` module) reads/writes it via `cacheRecommendationResolvedProduct`; it is
    /// not part of this class's public API surface, and MUST NOT be read directly by any other
    /// family-3 surface (the ONLY sanctioned readers are `brief(forProductId:)` /
    /// `description(forProductId:)` above). Unbounded for this instance's lifetime (accepted
    /// trade-off — bounded by realistic distinct-recommendation-taps-per-session, see design.md
    /// Risks / Trade-offs).
    var recommendationResolvedProducts: [String: LBProduct] = [:]

    /// Cache a real `LBProduct` resolved for a「更多商品」推薦卡
    /// (rb-ios-recommendation-product-intro-carry-through) — called by
    /// `ProductSheetsOverlayView.openRecommendation(_:mode:)` at resolve time, BEFORE forwarding
    /// through `onProductTap`. See `recommendationResolvedProducts`'s doc for the full rationale.
    /// Safe to call with a presentation-only `asDisplayProduct` degradation too (its `brief`/
    /// `description` are always `""`, so caching it is a harmless no-op for the fallback).
    func cacheRecommendationResolvedProduct(_ product: LBProduct) {
        recommendationResolvedProducts[product.id] = product
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
