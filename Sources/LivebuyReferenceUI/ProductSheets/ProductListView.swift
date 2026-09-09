import SwiftUI
import LivebuySDK
import LivebuyUI

// MARK: - ProductListView — family-3 product sheet-stack surface 1 (product list drawer)
//
// Spec: `reference-ui-rendering/spec.md` (family-3 product + sheets, surface 1)
// Design: rb-ios-product-sheets design.md D-2 +
//          `design/templates/minimal/screens.jsx` `ProductListSheet` (lines 505-595) +
//          `design/templates/minimal/sdk-components.jsx` `LBPBottomSheet` (751) /
//          `LBPSheetHeader` (787) / `LBPProductRow` `layout:'row'` (816-912) /
//          `LBPCartCTA` (993-1006).
//
// The bag-opened product LIST drawer. It is the first of the four family-3 surface
// sub-views composed by `ProductSheetsOverlayView`, and it implements the agreed
// SUB-VIEW INPUT PATTERN documented in `ProductSheetsOverlayView.swift`:
//
//   1. `theme: ReferenceUITheme`            — FIRST positional argument, always.
//   2. bound SNAPSHOT VALUES               — `products: [LBProduct]` (the core-fed,
//      already-ordered list — this layer MUST NOT slice / merge / re-sort) +
//      `cartCount: Int` (per-session successful-add count for the CTA badge), passed
//      BY VALUE from `ProductSheetsModel` (never the model, never the template).
//   3. action closures (LAST, each `= nil`):
//      • `onOpenProduct: ((LBProduct) -> Void)?` — a product-row tap funnels HERE,
//        NOT to a template intent. The container forwards it to the host-wired
//        `onProductTap`, which the host wires to core
//        `LivebuyPlayerViewController.simulateProductTap(product)`. reference-ui
//        NEVER opens the detail itself (D-2 — mirrors family-2 ChatFeedView's
//        eventJoin forwarder).
//      • `onOpenCart: (() -> Void)?` — the bottom-pinned cart CTA tap forwards to
//        `model.openCart()` → `DefaultCartCTA.openCart()` (host passthrough; the
//        template owns no checkout page).
//
// This sub-view reads ONLY its passed-in values; it never reaches back into
// `ProductSheetsModel` / `DefaultPlayerTemplate` (one-way data flow, D-1). It also
// renders correctly with all actions nil (so demo / snapshot tests construct it
// action-free).
//
// SHELL REUSE: the sheet shell REUSES the module-internal `TopRoundedRectangle`
// shape (defined in `PlayerShell/VideoInfoPanelView.swift` — NOT redefined here) +
// the grab-handle + centered `LBPSheetHeader` styling established by
// `VideoInfoPanelView` / `WinClaimModalView` (`LBPBottomSheet` `borderRadius:
// 20px 20px 0 0` + `theme.surface.shadow`).
//
// iOS-14-safe SwiftUI only. `VStack` / `HStack` / `ZStack` / `ScrollView` / `Text`
// / `Button` / `RoundedRectangle` / `Image` are all iOS-13+. No `.task` /
// `AsyncImage` / `NavigationStack` / `.foregroundStyle` / `.tint` — any >14 API
// would be guarded with `@available` / `if #available`, but none is reached here.

/// The family-3 product LIST drawer. Renders the core-fed `products` as a scroll of
/// product rows (thumbnail + name + price/original-price strike + 加購 / 缺貨 state)
/// inside a bottom-sheet shell with the「商品清單」header, plus a bottom-pinned cart
/// CTA badged with `cartCount`. A row tap forwards to `onOpenProduct` (→ host → core
/// `simulateProductTap`); the CTA forwards to `onOpenCart`. This layer NEVER opens
/// the detail itself.
public struct ProductListView: View {

    /// The resolved reference-ui theme (FIRST positional argument, always).
    public let theme: ReferenceUITheme

    /// The core-fed products snapshot (`DefaultProductOverlayState.products`).
    /// Already merged / ordered by the data layer — this layer MUST NOT slice /
    /// merge / re-sort. Read-only.
    public let products: [LBProduct]

    /// Per-session successful-add count (`DefaultCartCTA.state.count`) — the cart
    /// CTA shows the count badge when `> 0`. Read-only.
    public let cartCount: Int

    /// `false` (snapshot / demo) → row thumbnails draw the deterministic placeholder only
    /// (baselines unchanged). `true` (host runtime) → load each `product.photos[0]` over the
    /// placeholder via `RemoteStillImageView` (rb-ios-product-real-images).
    public let live: Bool

    /// The set of product ids CURRENTLY being introduced live (LIVE narrate_status==2 — the
    /// backend MAY narrate MULTIPLE products simultaneously). Every row whose `product.id` is a
    /// member draws the「介紹中」bottom banner (rb-ios-product-bag-multi-narrating — the prior
    /// single `introducingProductId: String?` could only ever flag ONE row, so a second
    /// simultaneously-narrating product silently drew no badge); in LIVE the play/seek affordance
    /// is hidden (live has no timeline to scrub). Sourced from `ProductSheetsModel
    /// .liveActiveProducts` (← `DefaultPlayerTemplate.liveActiveProducts`, the SAME view-model
    /// aggregate `PlayerShellModel.liveActiveProducts` already consumes for the pinned-card
    /// carousel). The data layer surfaces this list introducing-FIRST (`productsIntroducingFirst`)
    /// — this layer MUST NOT re-sort. Empty (VOD / demo / nothing introducing) → no banner, play
    /// shown.
    public let introducingProductIds: Set<String>

    /// The RAW, backend-order products snapshot (`ProductSheetsModel.productsBackendOrder`,
    /// rb-ios-product-row-number-badge) — used ONLY to resolve each row's number-badge position
    /// (`ProductRowNumberBadge.resolveIndex`, below). Deliberately NOT the same array as `products`
    /// above (which is introducing-first reordered for DISPLAY) — see that property's doc on
    /// `ProductSheetsModel` for why reading the reordered array would make numbers jump. Default `[]`
    /// (existing call sites / snapshots — none currently pass this) → every row resolves `nil` (no
    /// badge), keeping every existing baseline byte-identical.
    public let productsBackendOrder: [LBProduct]

    /// Playback mode for the thumbnail overlay (rb-ios-product-row-status-overlay):
    /// VOD → play icon; active-live → 介紹中 on the narrating row; replay → 介紹中 on the
    /// product whose `[beginTime, endTime]` contains `playbackPosition`, else play icon.
    /// `nil` (existing call sites / snapshots) falls back to deriving from the real-frame
    /// `live` flag (`live ? .live : .vod`) so baselines stay byte-identical; the production
    /// container passes an explicit mode. Orthogonal to `live` (which gates photo loading).
    private let mode: ProductRowMode?

    /// Current playback position in seconds (replay only) — compared to each product's
    /// `[beginTime, endTime]` to decide「介紹中」. From `DefaultPlaybackProgressState.position`.
    private let playbackPosition: Int

    /// 搶購場旗標（`rb-ios-flash-sale-live-signal-wiring`）— `ProductSheetsModel.isFlashSale`
    /// ← `header.isFlashSale`. Passed straight through to every row's `ProductRowView
    /// .isFlashSale` — drives ONLY the `mode == .live` name-tag pill's「直播價」vs「搶購中」
    /// variant. The narrating banner text no longer branches on this flag (reverted per
    /// `rb-ios-narrating-banner-revert-flash-sale-text` — it is now a constant「介紹中」).
    /// Default `false` (existing call sites, which predate this flag) → every row renders
    /// byte-identical to before.
    public let isFlashSale: Bool

    /// Host-wired product-row tap → core product-tap exit. The container forwards
    /// this to its host-wired `onProductTap`, which the host wires to core
    /// `LivebuyPlayerViewController.simulateProductTap(product)`. nil for demo /
    /// snapshot instances — the drawer renders correctly action-free (D-2).
    private let onOpenProduct: ((LBProduct) -> Void)?

    /// Host-wired 加購鈕 tap (in-stock cart glyph) → the compact AddToCart sheet
    /// (rb-ios-product-action-sheet). Distinct from `onOpenProduct` (明細鈕 / 商品名 → full
    /// browse) so the container can pick the compact purchase sheet vs the full detail sheet.
    /// Both still funnel to core `simulateProductTap` via the container. nil → falls back to
    /// `onOpenProduct` (a quick-add then reads as a plain open). nil for demo / snapshot.
    private let onQuickAdd: ((LBProduct) -> Void)?

    /// Host-wired 售完列**補貨鈴鐺鈕** tap → 補貨通知 sheet（`NotifyRestockSheetView`）。與
    /// `onOpenProduct`（名稱 / 明細 → 商品詳情）分流：售完商品的名稱 / 明細仍走 `onOpenProduct`
    /// 開詳情，只有此專屬鈴鐺鈕走補貨通知（rb-ios-soldout-row-detail-vs-restock）。nil → 退回
    /// `onOpenProduct`（demo / snapshot inert）。
    private let onNotifyRestock: ((LBProduct) -> Void)?

    /// Host-wired 縮圖點擊 → 影片跳轉到該商品介紹時間（`LBProduct.beginTime`，秒）。對齊設計
    /// `LBPProductRow` 的 `onSeek`（縮圖 `onClick`）。容器轉發到 host-wired `onSeekToProductIntro`，
    /// 預設呼 core `LivebuyPlayerViewController.seek(seconds:)`（VOD / replay；live 由 core 略過）。
    /// nil → 縮圖點擊 no-op（demo / snapshot）。issue 5（rb-ios-product-row-deeplink）。
    private let onSeekToIntro: ((LBProduct) -> Void)?

    /// Host-wired 列分享鈕點擊 → 系統分享，連結帶該商品介紹時間 `?t=beginTime`。對齊設計
    /// `LBPProductRow` 的 `onShare`（精簡圓形分享 icon，與商品明細 footer 的直式分享為**不同**元件）。
    /// 容器轉發到 host-wired `onShareProduct`。nil → 分享鈕 no-op（demo / snapshot）。
    /// issue 6（rb-ios-product-row-deeplink）。
    private let onShareProduct: ((LBProduct) -> Void)?

    /// Host-wired cart-CTA tap → `model.openCart()` (host passthrough). nil for
    /// demo / snapshot instances.
    private let onOpenCart: (() -> Void)?

    /// Host-wired header close-icon tap → close the drawer. The container forwards this to
    /// `model.listPresented = false` (rb-ios-sheet-header-close-unify — the close icon was
    /// previously DECORATIVE). nil for demo / snapshot → tap is a no-op.
    private let onClose: (() -> Void)?

    /// Local search UI state (rb-ios-product-list-search) — a USER-DRIVEN display filter over the
    /// `products` snapshot, NOT a view-model. `searchOpen` toggles the header's collapsed/expanded
    /// state; `query` filters the displayed rows by `LBProduct.name`. Seeded from init (default
    /// collapsed / empty → existing baselines byte-identical; snapshot tests seed the open state).
    @State private var searchOpen: Bool
    @State private var query: String

    public init(
        theme: ReferenceUITheme,
        products: [LBProduct],
        cartCount: Int,
        live: Bool = false,
        introducingProductIds: Set<String> = [],
        productsBackendOrder: [LBProduct] = [],
        mode: ProductRowMode? = nil,
        playbackPosition: Int = 0,
        isFlashSale: Bool = false,
        onOpenProduct: ((LBProduct) -> Void)? = nil,
        onQuickAdd: ((LBProduct) -> Void)? = nil,
        onNotifyRestock: ((LBProduct) -> Void)? = nil,
        onSeekToIntro: ((LBProduct) -> Void)? = nil,
        onShareProduct: ((LBProduct) -> Void)? = nil,
        onOpenCart: (() -> Void)? = nil,
        onClose: (() -> Void)? = nil,
        searchOpenInitial: Bool = false,
        queryInitial: String = ""
    ) {
        self.theme = theme
        self.products = products
        self.cartCount = cartCount
        self.live = live
        self.introducingProductIds = introducingProductIds
        self.productsBackendOrder = productsBackendOrder
        self.mode = mode
        self.playbackPosition = playbackPosition
        self.isFlashSale = isFlashSale
        self.onOpenProduct = onOpenProduct
        self.onQuickAdd = onQuickAdd
        self.onNotifyRestock = onNotifyRestock
        self.onSeekToIntro = onSeekToIntro
        self.onShareProduct = onShareProduct
        self.onOpenCart = onOpenCart
        self.onClose = onClose
        _searchOpen = State(initialValue: searchOpenInitial)
        _query = State(initialValue: queryInitial)
    }

    /// User-driven display filter (rb-ios-product-list-search) — case-insensitive `name` contains.
    /// A PRESENTATION filter only: it never mutates the `products` snapshot, never re-orders, never
    /// holds a second list (so it does NOT violate「MUST NOT 自行 slice」, which targets data-layer
    /// re-slicing, not user UI filtering).
    private var displayedProducts: [LBProduct] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return q.isEmpty ? products : products.filter { $0.name.lowercased().contains(q) }
    }

    public var body: some View {
        // Content only — the shared `.lbBottomSheet` presenter (SheetKit) draws the grab
        // handle + `theme.background` + `TopRoundedRectangle(20)` + shadow + dim scrim +
        // drag-to-dismiss (sheetkit-foundation). The leaf carries just the drawer content.
        // Pinned header (商品清單 title) + scrollable rows body + pinned cart CTA footer, within
        // the ½-screen cap (rb-ios-sheet-pinned-header-footer): a long product list now scrolls
        // between the pinned header and the always-visible 查看購物車 CTA.
        LBSheetScaffold {
            header
        } bodyContent: {
            rows
        } footer: {
            cartCTA
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 18)
                .background(
                    // Top hairline over the CTA footer (LBPCartCTA footer
                    // `borderTop: 1px solid theme.surface.stroke`).
                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(Self.stroke)
                            .frame(height: 1)
                        Spacer(minLength: 0)
                    }
                )
                // E2E: bottom 查看購物車 CTA footer (cart-cta-footer).
                .accessibilityIdentifier(LBAccessibilityID.cartCtaFooter)
        }
        // E2E: the product list drawer root (visual-only container).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(LBAccessibilityID.productList)
    }

    // MARK: - Sheet header (LBPSheetHeader / ProductListSheet — search two-state)
    //
    // Mirrors `ProductListSheet` (screens.jsx): COLLAPSED = a leading 32pt search button +
    // centered count title + trailing close button; EXPANDED = a bgSunken search pill (glyph +
    // TextField + clear) and a trailing 取消 button (rb-ios-product-list-search). The leading
    // search glyph — previously decorative — now toggles the expanded state.

    @ViewBuilder
    private var header: some View {
        if searchOpen {
            searchHeader
        } else {
            collapsedHeader
        }
    }

    /// Collapsed header — search button · centered title · close (byte-identical to the prior
    /// baseline except the search glyph is now a Button toggling `searchOpen`).
    private var collapsedHeader: some View {
        HStack(spacing: 8) {
            // Leading 32pt search button — toggles the expanded search state.
            Button(action: { searchOpen = true }) {
                ZStack {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundColor(theme.text)
                }
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            // E2E: tap to open/trigger search (product-search-button).
            .accessibilityIdentifier(LBAccessibilityID.productSearchButton)

            Text(headerTitle)
                .font(.system(size: 15 * theme.fontScale, weight: .bold))
                .foregroundColor(theme.text)
                .frame(maxWidth: .infinity, alignment: .center)

            // Trailing close button — shared `SheetHeaderCloseButton` (rb-ios-sheet-header-close-unify).
            SheetHeaderCloseButton(theme: theme, onTap: onClose)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 14)
    }

    /// Expanded search header — a bgSunken pill (search glyph + TextField) + 取消 button
    /// (design `ProductListSheet` search-open state; the clear/"x" button is intentionally
    /// omitted — 取消 already collapses the bar AND clears `query` in one tap,
    /// rb-search-bar-cancel-only). iOS-14-safe: `TextField` (iOS 13+); no
    /// `@FocusState` (iOS 15+) — autofocus omitted.
    private var searchHeader: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(Self.textDim)
                TextField(Self.searchPlaceholder, text: $query)
                    .font(.system(size: 14 * theme.fontScale))
                    .foregroundColor(theme.text)
                    .disableAutocorrection(true)
                    // E2E: the search input field (sheet-search-field).
                    .accessibilityIdentifier(LBAccessibilityID.sheetSearchField)
                // Clear ("xmark") button removed — 取消 already collapses the search bar AND
                // clears `query` in one tap, making a separate clear affordance redundant
                // (rb-search-bar-cancel-only).
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 18).fill(Self.bgSunken)
            )

            Button(action: { searchOpen = false; query = "" }) {
                Text(Self.searchCancel)
                    .font(.system(size: 14 * theme.fontScale, weight: .semibold))
                    .foregroundColor(theme.accent)
            }
            .buttonStyle(PlainButtonStyle())
            // E2E: cancel/close search (sheet-search-cancel).
            .accessibilityIdentifier(LBAccessibilityID.sheetSearchCancel)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    /// Header title — count-suffixed when populated (LBPSheetHeader / ProductListSheet).
    /// Always the FULL `products` count (collapsed state), independent of the search filter.
    private var headerTitle: String {
        products.isEmpty ? Self.title : "\(Self.title) (\(products.count))"
    }

    // MARK: - Rows (scroll of LBPProductRow layout:'row')

    @ViewBuilder
    private var rows: some View {
        if displayedProducts.isEmpty {
            // Empty-state line. Distinguish「no products at all」(目前沒有商品) from「search
            // matched nothing」(找不到符合『…』的商品, mirrors ProductListSheet's empty filtered
            // message — rb-ios-product-list-search).
            VStack {
                Spacer(minLength: 0)
                Text(products.isEmpty ? Self.emptyLabel : String(format: Self.noResultsFormat, query))
                    .font(.system(size: 13 * theme.fontScale))
                    .foregroundColor(Self.textDim)
                    .multilineTextAlignment(.center)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else {
            // Plain VStack — NOT ScrollView/LazyVStack. The reference-ui snapshot
            // path (SwiftUI `ImageRenderer`) does NOT materialize ScrollView / lazy
            // content — it renders BLANK (the same class of「snapshot 綠 ≠ 畫對」trap
            // the scaffold's drawHierarchy bug taught us). A plain VStack renders all
            // rows. The drop-in list is typically short; a very long list overflowing
            // the sheet is a documented follow-up (the host can wrap in its own scroll).
            // `displayedProducts` applies the user search filter (rb-ios-product-list-search) —
            // a presentation filter only; the underlying `products` snapshot is untouched.
            // Resolved once for the whole list (not per-row) — shared by both the existing
            // `mode:` argument below AND the new number-badge resolution
            // (`ProductRowNumberBadge.resolveIndex`, rb-ios-product-row-number-badge).
            let effectiveMode = mode ?? (live ? .live : .vod)
            VStack(spacing: 0) {
                ForEach(Array(displayedProducts.enumerated()), id: \.element.id) { index, product in
                    ProductRowView(
                        theme: theme,
                        product: product,
                        index: index,
                        live: live,
                        // `layout` defaults `.row`, `hideSub` defaults `false`, `onPlayClick`
                        // defaults `nil` (→ falls back to `onSeekToIntro`) — this call site is
                        // therefore BYTE-IDENTICAL to the pre-extraction `productRow(_:index:)`
                        // (rb-ios-product-detail-recommendations §1).
                        mode: effectiveMode,
                        isNarrating: ProductBagNarratingBadge.isNarrating(
                            productId: product.id, narratingIds: introducingProductIds),
                        playbackPosition: playbackPosition,
                        isFlashSale: isFlashSale,
                        badgeIndex: ProductRowNumberBadge.resolveIndex(
                            product: product, backendOrder: productsBackendOrder, mode: effectiveMode),
                        onOpenProduct: { onOpenProduct?(product) },
                        onQuickAdd: { (onQuickAdd ?? onOpenProduct)?(product) },
                        onNotifyRestock: { (onNotifyRestock ?? onOpenProduct)?(product) },
                        onSeekToIntro: { onSeekToIntro?(product) },
                        onShareProduct: { onShareProduct?(product) })
                }
            }
        }
    }

    // MARK: - Bottom cart CTA (LBPCartCTA — cartFill glyph + label + count)
    //
    // `CartFillGlyph`（design `Icons.cartFill`）取代已退役的 `ShopBagGlyph`（`Icons.bag`
    // 在此 footer 尺寸下不易辨識，見 `design/contract/icon-authoring.md`，rb-ios-icon-parity）。

    private var cartCTA: some View {
        Button(action: { onOpenCart?() }) {
            HStack(spacing: 10) {
                CartFillGlyph(size: 20, color: .white)
                Text(Self.cartLabel)
                    .font(.system(size: 16 * theme.fontScale, weight: .bold))
                    .foregroundColor(.white)
                // 「查看購物車」CTA 不顯示加購數量 `(n)`：`cartCount`（= `DefaultCartCTA.state.count`，
                // per-session 成功加購計數）非真實購物車件數、數據不準，MUST NOT 對外呈現
                // （rb-ios-product-sheet-cart-cta-cleanup 問題 6）。`cartCount` 參數保留（仍流入、
                // 不渲染數量），按鈕仍為開購物車入口（`onOpenCart` 轉發不變）。
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                // 統一按鈕圓角 → theme.cornerRadius（原 14，rb-ios-button-corner-radius-unify）。
                RoundedRectangle(cornerRadius: theme.cornerRadius)
                    .fill(theme.accent))
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Decorative design tokens (literal minimal hex via Color(hex:))
    //
    // accent / text / background come from the resolved theme. These are FIXED
    // decorative colors lifted verbatim from the design's `theme.surface.*` /
    // `theme.sale` / `theme.soldOut` (light mode, `design/brands/livebuy/tokens.jsx`)
    // — design-literal, NOT theme-resolved. Kept consistent with `WinClaimModalView`
    // / `VideoInfoPanelView` so the family-3 sheets read as one family.

    /// `theme.surface.textDim` (secondary / caption / strike text).
    static let textDim = Color(hex: "#6B6775") ?? Color.gray
    /// `theme.surface.stroke` (hairline row / footer border).
    static let stroke = Color(hex: "#ECEAF0") ?? Color.gray.opacity(0.2)
    /// `theme.surface.strokeStrong` (grab handle).
    static let strokeStrong = Color(hex: "#D8D5DE") ?? Color.gray.opacity(0.35)
    /// `theme.surface.bgSunken` (search-pill background — light mode).
    static let bgSunken = Color(hex: "#F4F4F6") ?? Color.gray.opacity(0.08)

    // MARK: - Fixed localized copy (static presentation strings)

    static let title = "銷售商品"
    static let cartLabel = "查看購物車"
    static let emptyLabel = "目前沒有商品"
    // 搜尋（rb-ios-product-list-search，對齊設計 ProductListSheet）
    static let searchPlaceholder = "搜尋商品名稱"
    static let searchCancel = "取消"
    static let noResultsFormat = "找不到符合「%@」的商品"
}

// MARK: - ProductBagNarratingBadge — pure multi-product narrating-badge decision
//
// Whether a given product row should draw the「介紹中」badge, given the LIVE set of currently-
// narrating product ids (rb-ios-product-bag-multi-narrating). The backend MAY narrate MULTIPLE
// products simultaneously — this membership test (rather than a single-id equality check) is
// what lets EVERY simultaneously-narrating row draw the badge, not just the first. Extracted as
// a pure function (unit-test-discipline) so the multi-id rule is unit-testable without mounting
// SwiftUI, mirroring `ProductSheetsOverlayView.swift`'s `CartToastTrigger` /
// `VariantPromptTrigger` / `CartLoadingFloor` pattern.
enum ProductBagNarratingBadge {
    static func isNarrating(productId: String, narratingIds: Set<String>) -> Bool {
        narratingIds.contains(productId)
    }
}

// MARK: - ProductRowNumberBadge — pure row number-badge index resolution
//
// Resolves the 1-based position a product-list row's thumbnail number badge should show
// (rb-ios-product-row-number-badge, design R35 `sdk-components.jsx:LBPProductRow`
// `numberBadge`). Extracted as a pure function (unit-test-discipline) so the VOD-exclusion
// + lookup rule is unit-testable without mounting SwiftUI, mirroring `ProductBagNarratingBadge`
// above. `backendOrder` MUST be the UN-reordered snapshot (`ProductSheetsModel
// .productsBackendOrder`) — NOT the introducing-first `products` this file's `rows` also holds
// (see that property's doc on `ProductSheetsModel` for why).
enum ProductRowNumberBadge {
    /// `nil` for `.vod` (the badge never shows there); otherwise the product's 1-based position
    /// in `backendOrder`, or `nil` if the product isn't found there (a defensive fallback — the
    /// row simply draws no badge rather than a stale / wrong number).
    static func resolveIndex(product: LBProduct, backendOrder: [LBProduct], mode: ProductRowMode) -> Int? {
        guard mode != .vod else { return nil }
        guard let i = backendOrder.firstIndex(where: { $0.id == product.id }) else { return nil }
        return i + 1
    }
}

// MARK: - Deterministic demo seed (previews + snapshot tests)
//
// A deterministic populated drawer (multi-product list incl. one sold-out row +
// a cart count) so previews / the snapshot test render the drawer's "happy path"
// deterministically (no live player). Built via the skeleton's documented demo
// recipe (`ProductSheetsModel.demoProduct` / `demoSoldOutProduct` — `LBProduct`
// has a full public memberwise init; `specOptions: []` sidesteps the `LBSpecOption`
// internal-init barrier, and the list surface needs no variant groups).

public extension ProductListView {

    /// A deterministic demo drawer: three products (one sold-out) + a cart count
    /// of 2, action-free. Mirrors `ProductSheetsModel.demoListModel`'s product set.
    static func demo(theme: ReferenceUITheme) -> ProductListView {
        ProductListView(
            theme: theme,
            products: [
                ProductSheetsModel.demoProduct(),
                ProductSheetsModel.demoSoldOutProduct(),
                ProductSheetsModel.demoProduct(
                    id: "demo-prod-003",
                    name: "Aurora 唇刷組",
                    priceShow: "NT$ 280",
                    originalPriceShow: "NT$ 280")
            ],
            cartCount: 2)
    }
}

#if DEBUG
struct ProductListView_Previews: PreviewProvider {
    static var previews: some View {
        let theme = ReferenceUIThemePalette.minimal
        Group {
            // Populated drawer (multi-product, one sold-out row, cart count badge).
            ProductListView.demo(theme: theme)
                .previewDisplayName("populated · sold-out row · cart 2")

            // Empty drawer (no products, no cart badge).
            ProductListView(theme: theme, products: [], cartCount: 0)
                .previewDisplayName("empty")
        }
        .frame(width: 393, height: 560)
        .previewLayout(.sizeThatFits)
    }
}
#endif
