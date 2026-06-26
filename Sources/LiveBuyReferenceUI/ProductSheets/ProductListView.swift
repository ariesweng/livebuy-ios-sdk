import SwiftUI
import LiveBuySDK
import LiveBuyUI

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
//        `LiveBuyPlayerViewController.simulateProductTap(product)`. reference-ui
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

    /// The currently-introducing product's id (`DefaultProductOverlayState.introducingProductId`,
    /// LIVE narrate_status==2). The row whose `product.id` matches draws the「介紹中」bottom
    /// banner; in LIVE the play/seek affordance is hidden (live has no timeline to scrub). The
    /// data layer surfaces this list introducing-FIRST (`productsIntroducingFirst`) — this layer
    /// MUST NOT re-sort. nil (VOD / demo / nothing introducing) → no banner, play shown.
    public let introducingProductId: String?

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

    /// Host-wired product-row tap → core product-tap exit. The container forwards
    /// this to its host-wired `onProductTap`, which the host wires to core
    /// `LiveBuyPlayerViewController.simulateProductTap(product)`. nil for demo /
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
    /// 預設呼 core `LiveBuyPlayerViewController.seek(seconds:)`（VOD / replay；live 由 core 略過）。
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
        introducingProductId: String? = nil,
        mode: ProductRowMode? = nil,
        playbackPosition: Int = 0,
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
        self.introducingProductId = introducingProductId
        self.mode = mode
        self.playbackPosition = playbackPosition
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

    /// Expanded search header — a bgSunken pill (search glyph + TextField + clear) + 取消 button
    /// (design `ProductListSheet` search-open state). iOS-14-safe: `TextField` (iOS 13+); no
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
                if !query.isEmpty {
                    Button(action: { query = "" }) {
                        ZStack {
                            Circle().fill(Self.strokeStrong)
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(theme.text)
                        }
                        .frame(width: 18, height: 18)
                    }
                    .buttonStyle(PlainButtonStyle())
                    // E2E: clear the search query (sheet-search-clear).
                    .accessibilityIdentifier(LBAccessibilityID.sheetSearchClear)
                }
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
            VStack(spacing: 0) {
                ForEach(Array(displayedProducts.enumerated()), id: \.element.id) { index, product in
                    productRow(product, index: index)
                }
            }
        }
    }

    // MARK: - Product row (LBPProductRow layout:'row')
    //
    // Mirrors `LBPProductRow` `layout:'row'`:
    //   • 64×64 rounded-12 thumbnail with a centered play affordance overlay.
    //   • name (14pt semibold) + price block. Sold-out → 「已售完」line; in-stock →
    //     strike original (`originalPriceShow`) + accent sale price (`priceShow`).
    //   • trailing action group: detail circle + share circle (outline accent) +
    //     cart circle (filled accent; bell glyph when sold out → 補貨通知, cart glyph
    //     otherwise → 加購).
    // The whole name/price column AND the detail icon funnel the row tap to
    // `onOpenProduct(product)`. The THUMBNAIL tap forwards to `onSeekToIntro(product)`
    // (→ host → core `seek(seconds: beginTime)`, issue 5) and the SHARE icon forwards to
    // `onShareProduct(product)` (→ host → system share with `?t=beginTime`, issue 6) —
    // both host-wired (nil → no-op for demo / snapshot, byte-identical baselines).

    private func productRow(_ product: LBProduct, index: Int) -> some View {
        // 狀態標籤改吃後端結論欄 `label`（rb-ios-goods-label-unified ③，單一優先序）；label 空
        // （舊後端 / demo）經 raw fallback 仍正確 → baseline 不變。
        let statusBadge = ProductStatusBadge.resolve(product)
        let soldOut = statusBadge == .soldOut
        // out_soon / hot 小徽章只認**明確** label（label 空不臆測 → demo / 舊後端中性）。
        let explicitBadge = ProductStatusBadge.fromLabel(product.label)
        // Thumbnail overlay by playback MODE (rb-ios-product-row-status-overlay), via a pure
        // function. `mode` falls back to deriving from the real-frame `live` flag for existing
        // call sites / snapshots (`live ? .live : .vod`) so baselines stay byte-identical.
        //   VOD          → play icon (seek-to-intro)
        //   active live  → 介紹中 on the narrating product (introducingProductId), else nothing
        //   replay       → 介紹中 when playbackPosition ∈ [beginTime, endTime], else play icon
        let effectiveMode = mode ?? (live ? .live : .vod)
        let isNarratingThis = introducingProductId != nil && product.id == introducingProductId
        let overlay = ProductRowOverlay.decide(
            mode: effectiveMode,
            isNarrating: isNarratingThis,
            beginTime: product.beginTime,
            endTime: product.endTime,
            position: playbackPosition
        )
        // 優先序 sold_out > narrating：售罄時壓過「介紹中」橫幅（rb-ios-goods-label-unified ③）。
        let isIntroducing = overlay.showIntroducing && !soldOut
        let showPlay = overlay.showPlay
        return HStack(spacing: 12) {
            // Thumbnail + play affordance. `live` + a real photo → the product image loads over
            // the placeholder; the play affordance stays on top (rb-ios-product-real-images).
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Self.bgSunken)
                if live, let url = Self.photoURL(product) {
                    RemoteStillImageView(url: url, contentMode: .scaleAspectFill)
                }
                if showPlay {
                    ZStack {
                        Circle().fill(Color.black.opacity(0.5))
                        Image(systemName: "play.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .frame(width: 26, height: 26)
                }
                // 「介紹中」橫幅 — 貼齊縮圖底部、左右填滿（accent 底滿版 + 白色等化器 + 白字）。
                if isIntroducing {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        HStack(spacing: 3) {
                            EqualizerGlyph(size: 9, color: .white)
                            Text(Self.introducingLabel)
                                .font(.system(size: 10 * theme.fontScale, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .fixedSize()
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 4)
                        .background(theme.accent)
                    }
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            // 縮圖點擊 → 影片跳轉到該商品介紹時間（`beginTime`），對齊設計 `LBPProductRow` 的縮圖
            // `onSeek`（issue 5）。整個 64×64 可點（`contentShape`）。snapshot 無互動 → 像素不變。
            .contentShape(Rectangle())
            .onTapGesture { onSeekToIntro?(product) }
            // E2E: per-item product thumbnail (seek-to-intro affordance).
            .accessibilityIdentifier(LBAccessibilityID.productRowThumb(index))

            // Name + price column (tap → open detail via host/core).
            Button(action: { onOpenProduct?(product) }) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(product.name)
                        .font(.system(size: 14 * theme.fontScale, weight: .semibold))
                        .foregroundColor(theme.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if soldOut {
                        Text(Self.soldOutLabel)
                            .font(.system(size: 12 * theme.fontScale))
                            .foregroundColor(Self.soldOutColor)
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            if !product.originalPriceShow.isEmpty,
                               product.originalPriceShow != product.priceShow {
                                Text(product.originalPriceShow)
                                    .font(.system(size: 12 * theme.fontScale))
                                    .foregroundColor(Self.textDim)
                                    .strikethrough(true, color: Self.textDim)
                            }
                            Text(product.priceShow)
                                .font(.system(size: 14 * theme.fontScale, weight: .heavy))
                                .foregroundColor(Self.saleColor)
                            // out_soon / hot 小徽章（rb-ios-goods-label-unified ③）——僅明確 label
                            // 觸發（label 空不臆測）。最終配色 DECISION-PENDING 待設計稿。
                            switch explicitBadge {
                            case .outSoon: statusPill(Self.outSoonLabel, Self.outSoonColor)
                            case .hot:     statusPill(Self.hotLabel, theme.accent)
                            default:       EmptyView()
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(PlainButtonStyle())
            // E2E: per-item name/price column → open detail (product-row-detail).
            .accessibilityIdentifier(LBAccessibilityID.productRowDetail(index))

            // Trailing action group (detail · share · cart/bell).
            HStack(spacing: 8) {
                rowOutlineIcon("doc.text", action: { onOpenProduct?(product) })
                // 分享鈕 → 系統分享，連結帶該商品介紹時間 `?t=beginTime`（issue 6，對齊設計
                // `LBPProductRow` 的 `onShare`）。轉發到 host-wired `onShareProduct`。glyph 為自繪
                // `ShareGlyph`（設計 `Icons.share` size 16，rb-ios-share-icon-design-align）。
                rowOutlineGlyph(action: { onShareProduct?(product) }) {
                    ShareGlyph(size: 16, color: theme.accent)
                }
                // E2E: per-item share circle (product-row-share).
                .accessibilityIdentifier(LBAccessibilityID.productRowShare(index))
                rowCartButton(soldOut: soldOut, product: product)
                    // E2E: per-item cart/bell circle (product-row-cart).
                    .accessibilityIdentifier(LBAccessibilityID.productRowCart(index))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(
            // Bottom hairline (LBPProductRow `borderBottom: 1px solid stroke`).
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Rectangle()
                    .fill(Self.stroke)
                    .frame(height: 1)
            }
        )
    }

    /// An outline-accent 30pt circular icon button (detail / share affordances).
    private func rowOutlineIcon(_ systemName: String, action: (() -> Void)?) -> some View {
        Button(action: { action?() }) {
            ZStack {
                Circle()
                    .stroke(theme.accent, lineWidth: 1)
                Image(systemName: systemName)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(theme.accent)
            }
            .frame(width: 30, height: 30)
            // Whole 30pt circle taps — the stroke-only ring would leave the interior dead.
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    /// Glyph overload of `rowOutlineIcon` — same 30pt accent outline ring, but draws a custom
    /// glyph view (e.g. the hand-drawn `ShareGlyph`) instead of an SF Symbol
    /// (rb-ios-share-icon-design-align).
    private func rowOutlineGlyph<Glyph: View>(action: (() -> Void)?, @ViewBuilder glyph: () -> Glyph) -> some View {
        Button(action: { action?() }) {
            ZStack {
                Circle()
                    .stroke(theme.accent, lineWidth: 1)
                glyph()
            }
            .frame(width: 30, height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    /// The filled-accent cart button — bell glyph (補貨通知) when sold out → `onNotifyRestock`
    /// (專屬補貨入口，開 NotifyRestock sheet；名稱 / 明細仍走 `onOpenProduct` 開詳情，
    /// rb-ios-soldout-row-detail-vs-restock)，falling back to `onOpenProduct` when nil; cart glyph
    /// (加購) otherwise → `onQuickAdd` (the compact AddToCart sheet), falling back to
    /// `onOpenProduct` when `onQuickAdd` is nil (rb-ios-product-action-sheet).
    private func rowCartButton(soldOut: Bool, product: LBProduct) -> some View {
        Button(action: {
            if soldOut {
                (onNotifyRestock ?? onOpenProduct)?(product)
            } else {
                (onQuickAdd ?? onOpenProduct)?(product)
            }
        }) {
            ZStack {
                Circle().fill(theme.accent)
                Image(systemName: soldOut ? "bell" : "cart")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
            }
            .frame(width: 30, height: 30)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Bottom cart CTA (LBPCartCTA — bag glyph + label + count)

    private var cartCTA: some View {
        Button(action: { onOpenCart?() }) {
            HStack(spacing: 10) {
                ShopBagGlyph(size: 20, color: .white)
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
    /// `theme.surface.bgSunken` (thumbnail placeholder fill — light mode).
    static let bgSunken = Color(hex: "#F4F4F6") ?? Color.gray.opacity(0.08)
    /// `theme.sale` (sale price red — `design/brands/livebuy/tokens.jsx`).
    static let saleColor = Color(hex: "#E0334B") ?? Color.red
    /// `theme.soldOut` (sold-out grey label — `design/brands/livebuy/tokens.jsx`).
    static let soldOutColor = Color(hex: "#9A96A3") ?? Color.gray
    /// out_soon「即將售完」徽章色（暖橘；最終配色 DECISION-PENDING 待設計稿）。
    static let outSoonColor = Color(hex: "#F5A623") ?? Color.orange

    // MARK: - Fixed localized copy (static presentation strings)

    static let title = "銷售商品"
    static let cartLabel = "查看購物車"
    static let soldOutLabel = "已售完"
    static let emptyLabel = "目前沒有商品"
    static let introducingLabel = "介紹中"
    static let outSoonLabel = "即將售完"
    static let hotLabel = "熱賣中"
    // 搜尋（rb-ios-product-list-search，對齊設計 ProductListSheet）
    static let searchPlaceholder = "搜尋商品名稱"
    static let searchCancel = "取消"
    static let noResultsFormat = "找不到符合「%@」的商品"

    /// First product photo as a non-empty URL, or nil (empty / whitespace → placeholder).
    static func photoURL(_ product: LBProduct) -> URL? {
        guard let s = product.photos.first?.trimmingCharacters(in: .whitespacesAndNewlines),
              !s.isEmpty else { return nil }
        return URL(string: s)
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
    /// out_soon / hot 小徽章（rb-ios-goods-label-unified ③）。最小中性 pill；最終樣式
    /// DECISION-PENDING 待設計稿。
    private func statusPill(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 10 * theme.fontScale, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color))
    }

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
