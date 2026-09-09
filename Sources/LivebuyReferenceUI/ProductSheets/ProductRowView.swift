import SwiftUI
import LivebuySDK
import LivebuyUI

// MARK: - ProductRowView — reusable product-card component (row / grid two states)
//
// Spec: `reference-ui-rendering/spec.md` §"LivebuyReferenceUI 商品卡元件（row / grid 兩態）供
//        商品列表與商品明細更多商品推薦格共用"
// Design: rb-ios-product-detail-recommendations tasks.md §1 +
//          `design/templates/minimal/sdk-components.jsx` `LBPProductRow` (design R21,
//          `design/contract/claude-design-sync.md` §R21).
//
// Extracted from `ProductListView`'s former private `productRow(_:index:)` function
// (rb-ios-product-detail-recommendations §1). `ProductListView` now constructs this
// view for its EXISTING `.row` call site — behavior / pixels UNCHANGED (see the
// `.row` DELIBERATE DEVIATION note below). The new `.grid` layout is used ONLY by
// the「更多商品」推薦格 (`ProductDetailSheetView`'s recommendations section).
//
// iOS-14-safe SwiftUI only, mirrors `ProductListView`'s existing constraints.

/// Which card geometry this row renders (design R21).
public enum ProductRowLayout: Equatable {
    /// The existing horizontal list row (thumbnail · name/price · action-icon group) —
    /// `ProductListView`'s product list drawer.
    case row
    /// The new vertical card (thumbnail on top, info below) — used ONLY by the
    /// 「更多商品」推薦格 (2×2, always `hideSub: true`).
    case grid
}

/// A single product card, in either the existing `.row` layout or the new `.grid`
/// layout (rb-ios-product-detail-recommendations §1). All action closures are
/// NO-ARG — the caller captures the specific `product` it is rendering when
/// constructing this view per iteration (mirrors how `ProductSheetsOverlayView`
/// already captures per-item closures when wiring `ProductListView`).
public struct ProductRowView: View {

    /// The resolved reference-ui theme (FIRST positional argument, always).
    public let theme: ReferenceUITheme

    /// The product this card renders. For `.grid` (推薦格) call sites this MAY be a
    /// presentation-only conversion of `LBProductRecommendation`
    /// (`LBProductRecommendation.asDisplayProduct`) — see that extension's doc for why
    /// it is safe to use for RENDERING while the tap closures resolve the real
    /// `LBProduct` independently.
    public let product: LBProduct

    /// Row index — used only for the `row` layout's per-item accessibility identifiers
    /// (unused by `.grid`, which has its own identifier scheme).
    public let index: Int

    /// `false` (snapshot / demo) → thumbnail draws the deterministic placeholder only.
    /// `true` (host runtime) → loads `product.photos.first` / `product.pic` over the
    /// placeholder via `RemoteStillImageView` (rb-ios-product-real-images).
    public let live: Bool

    /// `.row` (default) or `.grid` (design R21).
    public let layout: ProductRowLayout

    /// `.row`: hides the secondary text line under the product name (struck-through
    /// original price + current price + status pill, OR 已售完 sub-line). Default
    /// `false` (existing `.row` behavior unchanged).
    ///
    /// `.grid` (add-recommendation-original-price-reference-ui-ios): does **NOT** gate
    /// the original-price strikethrough — mirrors design source
    /// `design/templates/minimal/sdk-components.jsx`'s `LBPProductRow` grid branch,
    /// where `hideSub` only gates an unrelated `p.sub` caption field (`{!hideSub &&
    /// p.sub}`) and the strikethrough (`p.was`) is unconditional. `ProductRowView` has
    /// no `.grid`-specific counterpart to that `p.sub` caption yet, so `hideSub`
    /// currently has NO effect on `.grid` at all — this is an honest reflection of
    /// current scope, not a removed feature. The「更多商品」推薦格 call site still
    /// passes `true` (reserved for if/when a `.grid` sub-caption data source is added).
    public let hideSub: Bool

    /// `.row`-only: playback-mode overlay decision inputs (rb-ios-product-row-status-overlay).
    /// Ignored entirely by `.grid` (cross-video recommendation cards have no live-narrating
    /// concept). Defaults reproduce `ProductListView`'s existing VOD fallback.
    public let mode: ProductRowMode
    public let isNarrating: Bool
    public let playbackPosition: Int

    /// 搶購場旗標（`rb-ios-flash-sale-live-signal-wiring`）— `ProductSheetsModel.isFlashSale`
    /// ← `header.isFlashSale`, threaded through `ProductListView`. `.row`-only, consulted by
    /// `nameTag` (`mode == .live` branch: `.rush` "搶購中" vs `.livePrice` "直播價") ONLY.
    /// The narrating-banner text (`introducingLabel`) previously ALSO read this flag
    /// (`rb-ios-flash-sale-live-signal-wiring`) but that two-way split was reverted per
    /// user decision (`rb-ios-narrating-banner-revert-flash-sale-text`) — the banner is
    /// now a constant「介紹中」regardless of `isFlashSale`. `.grid` never reads this
    /// (mirrors `mode`/`isNarrating` above). Default `false` keeps every EXISTING call
    /// site (which predates this flag) byte-identical.
    public let isFlashSale: Bool

    /// Thumbnail top-leading number / HOT badge (rb-ios-product-row-number-badge, design R35
    /// `sdk-components.jsx:LBPProductRow` `numberBadge`). `nil` (default — every EXISTING call
    /// site, incl. the `.grid` 「更多商品」推薦格, which has no notion of "this video's backend
    /// order") → no badge drawn. The `.row` `ProductListView` call site resolves this via the pure
    /// `ProductRowNumberBadge.resolveIndex(product:backendOrder:mode:)` (VOD always `nil`).
    /// Deliberately named `badgeIndex`, NOT `index` — `index` above already exists for a DIFFERENT
    /// purpose (per-item accessibility identifiers, present on every row regardless of layout /
    /// playback mode); reusing that name here would collide both in Swift and in meaning (a plain
    /// 0-based array position vs. a 1-based "position in the ORIGINAL backend order", shown only in
    /// live / replay). When `isIntroducing` (below) is true, the badge shows a flame icon + "HOT"
    /// INSTEAD OF this number — see `numberBadge(index:)`.
    public let badgeIndex: Int?

    /// Host-wired 卡片本體 / 名稱 tap → open detail (`ProductListView.onOpenProduct` /
    /// the recommendation grid's card-body tap). nil → no-op (demo / snapshot).
    private let onOpenProduct: (() -> Void)?

    /// Host-wired 加購鈕 tap (`.row`: in-stock cart glyph / `.grid`: the independent accent
    /// cart circle). nil → no-op.
    private let onQuickAdd: (() -> Void)?

    /// `.row`-only: 售完列補貨鈴鐺鈕 tap. nil → no-op. `.grid` never shows this affordance
    /// (sold-out recommendation cards simply hide the cart circle, design R21).
    private let onNotifyRestock: (() -> Void)?

    /// `.row`-only: 縮圖點擊 → seek to intro (issue 5). Also the FALLBACK for `onPlayClick`
    /// when the latter is nil (design R21 "未傳退回 onSeek").
    private let onSeekToIntro: (() -> Void)?

    /// `.row`-only: 列分享鈕 tap (issue 6). `.grid` never shows a share icon.
    private let onShareProduct: (() -> Void)?

    /// Independent 播放/看講解 tap handler (rb-ios-product-detail-recommendations §1.3).
    /// `.row`: nil falls back to `onSeekToIntro` (design R21 "未傳退回 onSeek") — so
    /// `ProductListView`'s existing call site (never passes this) is behavior-unchanged.
    /// `.grid`: this ALSO gates whether the play button is shown at all — the caller
    /// (the recommendations renderer) MUST only pass a non-nil closure when the
    /// underlying `LBProductRecommendation.videoId` is non-nil (task 4.1: a nil
    /// `videoId` MUST hide/disable the play affordance, not present a dead button).
    private let onPlayClick: (() -> Void)?

    /// Continuous-animation throttling gate for the `.grid` play button's breathing
    /// pulse (ios-power-profile-animation-throttle-reference-ui).
    /// `ImageRenderer` never fires `.onAppear`, so the resting frame is captured
    /// regardless — snapshot goldens stay deterministic.
    @Environment(\.continuousAnimationGate) private var motionGate

    /// Local breathing-pulse animation state for the `.grid` play button. Never driven
    /// by a core call — purely presentational.
    @State private var breathing = false

    public init(
        theme: ReferenceUITheme,
        product: LBProduct,
        index: Int = 0,
        live: Bool = false,
        layout: ProductRowLayout = .row,
        hideSub: Bool = false,
        mode: ProductRowMode = .vod,
        isNarrating: Bool = false,
        playbackPosition: Int = 0,
        isFlashSale: Bool = false,
        badgeIndex: Int? = nil,
        onOpenProduct: (() -> Void)? = nil,
        onQuickAdd: (() -> Void)? = nil,
        onNotifyRestock: (() -> Void)? = nil,
        onSeekToIntro: (() -> Void)? = nil,
        onShareProduct: (() -> Void)? = nil,
        onPlayClick: (() -> Void)? = nil
    ) {
        self.theme = theme
        self.product = product
        self.index = index
        self.live = live
        self.layout = layout
        self.hideSub = hideSub
        self.mode = mode
        self.isNarrating = isNarrating
        self.playbackPosition = playbackPosition
        self.isFlashSale = isFlashSale
        self.badgeIndex = badgeIndex
        self.onOpenProduct = onOpenProduct
        self.onQuickAdd = onQuickAdd
        self.onNotifyRestock = onNotifyRestock
        self.onSeekToIntro = onSeekToIntro
        self.onShareProduct = onShareProduct
        self.onPlayClick = onPlayClick
    }

    // MARK: - Shared derived state

    /// 狀態標籤吃後端結論欄 `label`（rb-ios-goods-label-unified ③，單一優先序）；`label` 空
    /// （舊後端 / demo / `.grid`'s `LBProductRecommendation` conversion, which never sets a
    /// label）falls back to the raw fields in the SAME priority order — so this reduces to
    /// plain `product.soldOut == 1` for `.grid` while reproducing `.row`'s exact prior
    /// behavior (label-priority) verbatim.
    private var soldOut: Bool { ProductStatusBadge.resolve(product) == .soldOut }

    /// `.row`-only overlay decision (rb-ios-product-row-status-overlay /
    /// rb-ios-live-hide-product-share). Unused by `.grid`.
    private var overlay: (showPlay: Bool, showIntroducing: Bool, showShare: Bool) {
        ProductRowOverlay.decide(
            mode: mode,
            isNarrating: isNarrating,
            beginTime: product.beginTime,
            endTime: product.endTime,
            position: playbackPosition)
    }

    /// 「已售完」與「介紹中」互不影響、可同時成立（rb-ios-product-row-soldout-introducing-visible,
    /// 2026-09-07 使用者拍板訂正 `design/contract/claude-design-sync.md` D6 — 設計稿 `sdk-components
    /// .jsx` 的 `introBadge`/`numberBadge` 渲染條件從未有 `!p.sold` 排除；先前的
    /// `sold_out > narrating` 排除（`&& !soldOut`）是 reference-ui 實作層自行加上的規則，非設計決定，
    /// 已移除）。
    private var isIntroducing: Bool { overlay.showIntroducing }

    // MARK: - Name-tag pill (rb-ios-product-row-name-tag-system, design R39)
    //
    // `.row`-only inline pill rendered immediately BEFORE `product.name` — mutually
    // exclusive by `mode`: `.live` → outline "直播價" pill; `.vod` / `.replay` → the
    // pre-existing solid `out_soon` / `hot` capsule, MOVED here from its former
    // after-price placement (recolored, same trigger data). `.grid` never reads `mode`
    // so it never reads this either. See `ProductRowNameTag.resolve` for the pure
    // decision (unit-tested in isolation, no SwiftUI host needed).
    private var nameTag: ProductRowNameTag {
        // `soldOut` (above) is the SAME single source of truth (`ProductStatusBadge
        // .resolve(product) == .soldOut`, full raw-field fallback included) the
        // 「已售完」price-row swap already uses — passed through rather than
        // re-derived from `label` alone, so a sold-out row never shows a name-tag
        // pill in ANY mode (see `ProductRowNameTag.resolve`'s doc for the bug this
        // fixes: `.live` previously skipped this check entirely).
        ProductRowNameTag.resolve(mode: mode, label: product.label, soldOut: soldOut, isFlashSale: isFlashSale)
    }

    @ViewBuilder
    private var nameTagView: some View {
        switch nameTag {
        case .livePrice: livePricePill
        case .rush:      rushPill
        case .outSoon:   nameTagPill(Self.outSoonLabel, textColor: theme.text, fillColor: Self.outSoonColor)
        case .hot:       nameTagPill(Self.hotLabel, textColor: .white, fillColor: Self.hotNameTagColor)
        case .none:      EmptyView()
        }
    }

    /// Shared small-corner-radius pill for ALL FOUR name-tag variants (`rb-ios-product-
    /// row-name-tag-style` — checkpoint correction: the `.outSoon`/`.hot` cases originally
    /// reused the pre-existing `statusPill(_:_:)` helper, a full `Capsule()` — mismatched
    /// against design source `sdk-components.jsx`'s shared `nameTagEl` style
    /// (`padding: 1px 4px`, `borderRadius: 3`, `fontSize: 11`, `fontWeight: 500`), which
    /// EVERY variant (`直播價`/`搶購中`/`熱賣中`/`即將售完`) draws from. `livePricePill`
    /// delegates here too, so all three currently-reachable variants share one code path
    /// — not three independently hand-matched shapes that could drift apart later.
    /// `borderColor` is `nil` for a solid fill (`.outSoon`/`.hot`) or set for an outline
    /// (`.livePrice`, transparent fill). `statusPill(_:_:)` itself is left untouched
    /// (unused by this view now, kept in case of a future full-capsule use case).
    private func nameTagPill(_ text: String, textColor: Color, fillColor: Color, borderColor: Color? = nil) -> some View {
        Text(text)
            .font(.system(size: 11 * theme.fontScale, weight: .medium))
            .foregroundColor(textColor)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 3).fill(fillColor))
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(borderColor ?? .clear, lineWidth: borderColor == nil ? 0 : 1)
            )
    }

    /// "直播價" outline pill (`mode == .live`, `isFlashSale == false`) — 1pt `theme.accent`
    /// border, transparent fill, `theme.accent` text (design R39, shared `nameTagPill`
    /// shape). Text is `livePriceLabel` — see that constant's doc for why this is a
    /// hardcoded literal rather than a call through the core SDK's i18n system.
    private var livePricePill: some View {
        nameTagPill(Self.livePriceLabel, textColor: theme.accent, fillColor: .clear, borderColor: theme.accent)
    }

    /// "搶購中" solid pill (`mode == .live`, `isFlashSale == true`) — `rb-ios-flash-sale-
    /// live-signal-wiring`, the rush-mode variant `ProductRowNameTag`'s doc previously
    /// called "pipe-first, no water yet". Design source
    /// `design/templates/minimal/sdk-components.jsx:LBPProductRow`'s `liveMode === 'rush'`
    /// branch: `{ bg: accent, fg: '#fff', border: accent }` — solid `theme.accent` fill,
    /// white text, same shared `nameTagPill` shape as every other name-tag variant.
    private var rushPill: some View {
        nameTagPill(Self.rushLabel, textColor: .white, fillColor: theme.accent, borderColor: theme.accent)
    }

    // MARK: - Number / HOT badge (rb-ios-product-row-number-badge, design R35)
    //
    // Top-leading thumbnail overlay, independent of the play-hint / 介紹中 banner overlays
    // above (all four can coexist — this one sits at a different corner). `nil` `badgeIndex`
    // draws nothing (both layouts' current callers besides `ProductListView`'s `.row` never
    // pass one). `isIntroducing` reuses the SAME flag the bottom 介紹中 banner uses — no second
    // "is this row currently being introduced" computation.

    @ViewBuilder
    private var numberBadgeOverlay: some View {
        if let badgeIndex = badgeIndex {
            numberBadge(index: badgeIndex)
        } else {
            EmptyView()
        }
    }

    /// Design `numberBadge`: black 70%-opacity, white text, top-left + bottom-right rounded
    /// (`border-radius: 0.25rem 0 0.25rem 0`) 4pt corners via `NumberBadgeShape`. Sizing / font
    /// differ by `layout` per the design (`.grid` 20pt box / 12pt font, `.row` 18pt / 11pt) even
    /// though only `.row` is wired to a non-nil `badgeIndex` today (see `badgeIndex`'s doc).
    /// `isIntroducing` swaps the whole content for a flame icon + "HOT" — the flame's fixed 10pt
    /// size matches the design's literal `Icons.hot size={10}` (not layout- or `theme.fontScale`-
    /// scaled, matching this file's existing hand-drawn-glyph convention, e.g. `EqualizerGlyph`).
    private func numberBadge(index: Int) -> some View {
        let isGrid = layout == .grid
        return HStack(spacing: 3) {
            if isIntroducing {
                HotFlameGlyph(size: 10, color: .white)
                Text(Self.hotBadgeLabel)
            } else {
                Text("\(index)")
            }
        }
        .font(.system(size: (isGrid ? 12 : 11) * theme.fontScale, weight: .bold))
        .foregroundColor(.white)
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, isIntroducing ? 6 : 5)
        .frame(minWidth: isGrid ? 20 : 18, minHeight: isGrid ? 20 : 18)
        .background(Self.numberBadgeBackground)
        .clipShape(NumberBadgeShape(radius: 4))
    }

    public var body: some View {
        switch layout {
        case .row:
            rowBody
        case .grid:
            gridBody
        }
    }

    // MARK: - `.row` layout — matches design R21's `row` play-hint pill
    //
    // `rb-ios-product-row-play-hint-pill`: the play-hint visual for `showPlay` now matches
    // design R21 (`sdk-components.jsx` ~1146-1156) — a bottom-centered white translucent
    // text pill「看講解」— replacing the prior black-circle icon. This is an EXPLICITLY
    // user-authorized regeneration of the 5 existing snapshot baselines that used to lock
    // the black-circle pixels (`product-list-drawer-populated` /
    // `product-sheets-overlay-list-presented` / `product-list-search-open` /
    // `product-list-search-no-results` / `product-list-outsoon-hot-labels`). The ACTION
    // wiring (`onPlayClick ?? onSeekToIntro` fallback) is unchanged by this visual swap.
    //
    // `.row` THUMBNAIL CORNER + BORDER (design R34, `rb-ios-product-detail-image-gallery`,
    // 2026-09-04): corner radius 12→4 + a new `1px solid #D2D2D2` border — the SAME 5
    // baselines above are affected AGAIN by this change (thumbnail geometry, not just the
    // play-hint pill inside it).

    private var rowBody: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Self.bgSunken)
                if live, let url = Self.photoURL(product) {
                    RemoteStillImageView(url: url, contentMode: .scaleAspectFill)
                }
                // VOD (rb-ios-product-row-vod-intro-mask, design R36): a DIFFERENT, unified
                // three-phase visual — centered play button / full-bleed equalizer mask / no
                // overlay — replacing the「看講解」pill and「介紹中」banner below for `.vod`
                // ONLY. `.live` / `.replay` keep those existing visuals byte-identical.
                if mode == .vod {
                    if overlay.showPlay {
                        vodPlayOverlay
                    } else if isIntroducing {
                        vodIntroducingMask
                    }
                } else {
                    if overlay.showPlay {
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            HStack(spacing: 3) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(Self.playHintText)
                                Text(Self.playHintLabel)
                                    .font(.system(size: 9.5, weight: .semibold))
                                    .foregroundColor(Self.playHintText)
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.white.opacity(0.75)))
                            .padding(.bottom, 4)
                        }
                    }
                    if isIntroducing {
                        // R31 (`rb-ios-vod-live-product-card-restyle`): fixed
                        // `rgba(240,50,70,.7)` coral (was `theme.accent`) — unified with
                        // `LiveOverlayChromeView.pinnedCard(_:)`'s narrate badge, same color
                        // token. Font size 10pt → 12pt (design `sdk-components.jsx:LBPProductRow`).
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            HStack(spacing: 3) {
                                EqualizerGlyph(size: 9, color: .white)
                                Text(Self.introducingLabel)
                                    .font(.system(size: 12 * theme.fontScale, weight: .bold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 3)
                            .padding(.horizontal, 4)
                            .background(Self.introducingBadgeColor)
                        }
                    }
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            // Number / HOT badge (rb-ios-product-row-number-badge, design R35) — top-leading
            // overlay. `.overlay(_:alignment:)` (the plain-View-argument overload, NOT the
            // `@ViewBuilder` closure overload added in iOS 15) keeps this file iOS-14-safe.
            .overlay(numberBadgeOverlay, alignment: .topLeading)
            // `.row` thumbnail border (design R34, `rb-ios-product-detail-image-gallery`,
            // 2026-09-04): `1px solid #D2D2D2` — the corner radius shrink (12→4) above and this
            // border are the SAME visual direction as the R33 carousel-card white-card /
            // R34 product-photo-gallery convergence; `.grid` layout is UNAFFECTED (its own
            // 14pt radius + deliberate no-border stays, see the `.grid` MARK below).
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Self.rowThumbBorder, lineWidth: 1)
            )
            .contentShape(Rectangle())
            // design R21 task 1.3: `onPlayClick` non-nil overrides the existing seek — nil
            // (ProductListView's existing call site) falls back to `onSeekToIntro` exactly
            // as before.
            .onTapGesture { (onPlayClick ?? onSeekToIntro)?() }
            .accessibilityIdentifier(LBAccessibilityID.productRowThumb(index))

            Button(action: { onOpenProduct?() }) {
                VStack(alignment: .leading, spacing: 4) {
                    if nameTag == .none {
                        // Byte-identical to the pre-`rb-ios-product-row-name-tag-system` tree —
                        // no HStack wrapper, no extra spacing — for every row that draws no
                        // name-tag pill (the overwhelming majority of existing call sites).
                        Text(product.name)
                            .font(.system(size: 14 * theme.fontScale, weight: .semibold))
                            .foregroundColor(theme.text)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            nameTagView
                            Text(product.name)
                                .font(.system(size: 14 * theme.fontScale, weight: .semibold))
                                .foregroundColor(theme.text)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                    }

                    if !hideSub {
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
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityIdentifier(LBAccessibilityID.productRowDetail(index))

            HStack(spacing: 8) {
                rowOutlineGlyph(action: onOpenProduct) {
                    DetailGlyph(size: 16, color: theme.accent)
                }
                if overlay.showShare {
                    rowOutlineGlyph(action: onShareProduct) {
                        ShareGlyph(size: 16, color: theme.accent)
                    }
                    .accessibilityIdentifier(LBAccessibilityID.productRowShare(index))
                }
                rowCartButton
                    .accessibilityIdentifier(LBAccessibilityID.productRowCart(index))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Rectangle()
                    .fill(Self.stroke)
                    .frame(height: 1)
            }
        )
    }

    // MARK: - VOD-only thumbnail overlays (rb-ios-product-row-vod-intro-mask, design R36)
    //
    // `.row`-only (see `rowBody`'s `mode == .vod` branch above); `.grid` never reads `overlay`
    // so these are never reached from `gridBody`.

    /// VOD `upcoming` phase: a centered black circle play button — replaces the bottom
    /// 「看講解」pill for VOD ONLY (`.live` / `.replay` keep the pill, see `rowBody`). Design
    /// `sdk-components.jsx:LBPProductRow`'s `playOverlay`: 32pt circle, `rgba(0,0,0,0.5)` fill,
    /// centered white 15pt play triangle.
    private var vodPlayOverlay: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.5))
                .frame(width: 32, height: 32)
            Image(systemName: "play.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
        }
    }

    /// VOD `now` phase: a full-bleed `rgba(0,0,0,0.5)` mask + centered white equalizer, with
    /// NO text — visually distinct from the `.live` / `.replay` bottom「介紹中」coral banner
    /// (same semantic — this product is currently being introduced — different presentation).
    /// Reuses the existing `EqualizerGlyph` (same bars as the `.live`/`.replay` banner's, just
    /// larger: 18pt here vs 9pt there), matching design `introBadge`'s VOD branch.
    private var vodIntroducingMask: some View {
        ZStack {
            Color.black.opacity(0.5)
            EqualizerGlyph(size: 18, color: .white)
        }
    }

    private func rowOutlineGlyph<Glyph: View>(action: (() -> Void)?, @ViewBuilder glyph: () -> Glyph) -> some View {
        Button(action: { action?() }) {
            ZStack {
                Circle().stroke(theme.accent, lineWidth: 1)
                glyph()
            }
            .frame(width: 30, height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    /// `.row`'s existing cart/bell circle (rb-ios-product-detail-recommendations §1: this
    /// element and its behavior are UNTOUCHED by this change — regression-locked by
    /// `ProductRowViewRowRegressionTests`).
    private var rowCartButton: some View {
        Button(action: {
            if soldOut {
                onNotifyRestock?()
            } else {
                onQuickAdd?()
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

    private func statusPill(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 10 * theme.fontScale, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color))
    }

    // MARK: - `.grid` layout — NEW (design R21, no existing baseline — free to design)
    //
    // Vertical card: square thumbnail (top-trailing breathing accent play circle, shown
    // only when `onPlayClick` is provided — task 4.1's videoId-nil gate lives at the
    // CALLER, which simply omits `onPlayClick` in that case) + name + price row with an
    // independent accent cart circle (hidden when sold out, design R21 "p.sold 時不顯示").
    // `hideSub` is expected `true` at the recommendations call site (reserved for a
    // future `.grid`-specific sub-caption; NOT the original-price strikethrough — see
    // `hideSub`'s doc comment above, add-recommendation-original-price-reference-ui-ios).
    //
    // Price cell + cart button layout (rb-ios-product-row-price-cart-layout-fix): the
    // current price and (optional) struck-through original price live in ONE
    // leading-aligned VStack (original price is the SECOND child, i.e. BELOW the current
    // price) — mirrors design source `sdk-components.jsx:1116-1129`'s flex column, where
    // `p.was` is the column's second child under `p.price`. That price VStack and the
    // cart button are siblings inside a `.bottom`-aligned HStack (mirrors the design's
    // outer `alignItems:'flex-end'`), so the cart button always stays pinned to the row's
    // bottom edge whether the price cell is 1 line (price only) or 2 lines (price +
    // original-price strikethrough) tall — it must never be pushed down or stay centered
    // when the second line appears.

    private var gridBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Self.bgSunken)
                if live, let url = Self.photoURL(product) {
                    RemoteStillImageView(url: url, contentMode: .scaleAspectFill)
                }
                if onPlayClick != nil {
                    gridPlayButton
                        .padding(6)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            // Number / HOT badge (rb-ios-product-row-number-badge, design R35) — same overlay as
            // `.row` above. In practice `badgeIndex` is always `nil` here today (the「更多商品」
            // recommendation grid call site never passes one — a cross-video recommendation card
            // has no "this video's backend order" to number), so this renders nothing for every
            // EXISTING `.grid` call site; kept implemented for design-component fidelity (the
            // design's `LBPProductRow` draws `numberBadge` in both its `row` and `grid` branches).
            .overlay(numberBadgeOverlay, alignment: .topLeading)

            Text(product.name)
                .font(.system(size: 13 * theme.fontScale, weight: .semibold))
                .foregroundColor(theme.text)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .bottom, spacing: 6) {
                VStack(alignment: .leading, spacing: 0) {
                    if soldOut {
                        Text(Self.soldOutLabel)
                            .font(.system(size: 13 * theme.fontScale, weight: .bold))
                            .foregroundColor(Self.soldOutColor)
                    } else {
                        Text(product.priceShow)
                            .font(.system(size: 14 * theme.fontScale, weight: .heavy))
                            .foregroundColor(Self.saleColor)

                        // NOT gated by `hideSub` (add-recommendation-original-price-reference-ui-ios)
                        // — matches design source `LBPProductRow` grid branch, where the
                        // strikethrough (`p.was`) is unconditional and `hideSub` only gates the
                        // unrelated `p.sub` caption. See `hideSub`'s doc comment above. Placed
                        // BELOW the current price, same VStack (rb-ios-product-row-price-cart-
                        // layout-fix) — see this method's header comment.
                        if !product.originalPriceShow.isEmpty
                            && product.originalPriceShow != product.priceShow {
                            Text(product.originalPriceShow)
                                .font(.system(size: 11 * theme.fontScale))
                                .foregroundColor(Self.textDim)
                                .strikethrough(true, color: Self.textDim)
                        }
                    }
                }
                Spacer(minLength: 0)
                // Independent accent cart circle — design R21 "p.sold 時不顯示" (simply
                // hidden, not converted to a bell like `.row`'s rowCartButton). Sibling of
                // the price VStack above in a `.bottom`-aligned HStack, so it stays pinned
                // to the row's bottom edge regardless of the price cell's height
                // (rb-ios-product-row-price-cart-layout-fix).
                if !soldOut {
                    gridCartButton
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(theme.background)
        )
        .contentShape(Rectangle())
        .onTapGesture { onOpenProduct?() }
        .accessibilityIdentifier(LBAccessibilityID.productRecommendationCard(index))
    }

    /// Top-right accent play circle with a breathing pulse (design R21 "呼吸閃爍").
    /// Gated by `onPlayClick != nil` at the call site (task 4.1). Mirrors
    /// `WinEntryView`'s `pulsing` driver + `continuousAnimationGate` throttle.
    private var gridPlayButton: some View {
        Button(action: { onPlayClick?() }) {
            ZStack {
                Circle().fill(theme.accent)
                Image(systemName: "play.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
            }
            .frame(width: 24, height: 24)
            .opacity(breathing ? Self.breathOpacityMin : Self.breathOpacityMax)
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear { startBreathing() }
        .onChange(of: motionGate) { _ in startBreathing() }
        .onDisappear { breathing = false }
        .accessibilityIdentifier(LBAccessibilityID.productRecommendationPlay(index))
    }

    /// Independent accent cart circle (design R21 grid `onCart`).
    private var gridCartButton: some View {
        Button(action: { onQuickAdd?() }) {
            ZStack {
                Circle().fill(theme.accent)
                Image(systemName: "cart")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
            }
            .frame(width: 26, height: 26)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier(LBAccessibilityID.productRecommendationCart(index))
    }

    /// (Re)start the breathing pulse. Skips the
    /// `repeatForever` driver under thermal pressure / Reduce Motion (leaves the button at
    /// its resting opacity); `ImageRenderer` never fires `.onAppear`, so snapshot goldens
    /// always capture the resting frame regardless.
    private func startBreathing() {
        breathing = false
        guard motionGate.allowsAnimation(visible: true) else { return }
        withAnimation(.easeInOut(duration: Self.breathDuration).repeatForever(autoreverses: true)) {
            breathing = true
        }
    }

    // MARK: - Decorative design tokens (literal minimal hex — duplicated verbatim from
    // `ProductListView` / `ProductDetailSheetView`'s own token sets, the established
    // pattern in this module rather than a shared cross-file constant).

    static let textDim = Color(hex: "#6B6775") ?? Color.gray
    static let stroke = Color(hex: "#ECEAF0") ?? Color.gray.opacity(0.2)
    static let bgSunken = Color(hex: "#F4F4F6") ?? Color.gray.opacity(0.08)
    /// `.row` thumbnail border (design R34, `rb-ios-product-detail-image-gallery`) — distinct
    /// from `stroke` above (the `.row` list's own hairline divider color).
    static let rowThumbBorder = Color(hex: "#D2D2D2") ?? Color.gray.opacity(0.4)
    static let saleColor = Color(hex: "#E0334B") ?? Color.red
    static let soldOutColor = Color(hex: "#9A96A3") ?? Color.gray
    /// 「即將售完」名稱前標籤底色（rb-ios-product-row-name-tag-system，色碼訂正）：
    /// `#F5A623`（琥珀）→ `#FACC15`（黃）。
    static let outSoonColor = Color(hex: "#FACC15") ?? Color.yellow
    /// 「介紹中」橫幅底色（R31，`rb-ios-vod-live-product-card-restyle`）：固定
    /// `rgba(240,50,70,.7)` 珊瑚紅，不再跟隨商家 `theme.accent`。與
    /// `LiveOverlayChromeView.pinnedCard(_:)` 的新標籤共用同一色票（
    /// `design/templates/minimal/sdk-components.jsx:LBPProductRow`）。
    static let introducingBadgeColor = (Color(hex: "#F03246") ?? Color.red).opacity(0.7)
    /// 「熱賣中」名稱前標籤底色（rb-ios-product-row-name-tag-system，色碼訂正）：固定
    /// `rgba(240,50,70,.7)`——與 `introducingBadgeColor` 數值相同的既有色票——取代先前隨商家
    /// `theme.accent` 主題色變動的寫法（不做成可設定項，直接硬編）。
    static let hotNameTagColor = (Color(hex: "#F03246") ?? Color.red).opacity(0.7)

    static let soldOutLabel = "已售完"
    /// 「介紹中」底部橫幅文案——恆定字面值，不受 `isFlashSale` 影響
    /// （`rb-ios-narrating-banner-revert-flash-sale-text`）。`rb-ios-flash-sale-live-signal-
    /// wiring` 曾依後端文件原話「App 需要用它決定 goods[].label 為 narrating 時顯示『開標中』
    /// （搶購）或『介紹中』（一般）」把這個字面值改成依 `isFlashSale` 二選一函式；使用者事後
    /// 拍板撤回該二選一，改回本檔案長期以來的恆定字面值。寫死字面值，不走 i18n（見
    /// `livePriceLabel` 的文件對此模組既定慣例的說明）。
    static let introducingLabel = "介紹中"
    /// 「即將售完」名稱前標籤文案——含 🔥 emoji 前綴，對齊設計來源 `sdk-components.jsx`
    /// 的字面值 `'🔥 即將售完'`（`rb-ios-product-row-name-tag-style` checkpoint 訂正）。
    static let outSoonLabel = "🔥 即將售完"
    static let hotLabel = "熱賣中"
    /// 「直播價」名稱前標籤文案（rb-ios-product-row-name-tag-system，design R39）——沿用既有
    /// core i18n key `live_price` 的 zh-TW 譯文字面值（`ios/Sources/LivebuySDK/Resources/
    /// zh-Hant-TW.lproj/Localizable.strings`）。reference-ui 層文案一律寫死、不走 i18n
    /// ——`LBLocalizedString` / `LBLocalization` 是 `LivebuySDK` 模組內部 `internal` 型別
    /// （非 `public`），`LivebuyReferenceUI` 是獨立模組，即使 `import LivebuySDK` 也無法呼叫；
    /// 這與本檔案既有的 `soldOutLabel` / `introducingLabel` / `outSoonLabel` / `hotLabel`
    /// 寫死慣例一致，並非遺漏 i18n 串接。
    static let livePriceLabel = "直播價"
    /// 「搶購中」名稱前標籤文案（`rb-ios-flash-sale-live-signal-wiring`，design R39
    /// `liveMode === 'rush'` 分支）——同上，寫死字面值、不走 i18n。
    static let rushLabel = "搶購中"

    /// Number / HOT badge background (design `rgba(0,0,0,0.7)`, rb-ios-product-row-number-badge).
    /// Distinct from `introducingBadgeColor` above (bottom banner) — a different badge, different
    /// corner, different color token.
    static let numberBadgeBackground = Color.black.opacity(0.7)
    /// Number badge's introducing-state label (design "HOT") — distinct from `introducingLabel`
    /// ("介紹中", the bottom banner's text); the two badges show DIFFERENT text for the same state.
    static let hotBadgeLabel = "HOT"

    /// `.row` play-hint pill text/icon color (design R21, `rb-ios-product-row-play-hint-pill`).
    static let playHintText = Color(hex: "#111111") ?? Color.black
    static let playHintLabel = "看講解"

    static let breathDuration: Double = 0.9
    static let breathOpacityMin: Double = 0.55
    static let breathOpacityMax: Double = 1.0

    /// First product photo (falling back to `pic`) as a non-empty URL, or nil.
    static func photoURL(_ product: LBProduct) -> URL? {
        let raw = product.photos.first ?? product.pic
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        return URL(string: s)
    }
}

// MARK: - NumberBadgeShape — iOS-14-safe two-corner-rounded rectangle
//         (rb-ios-product-row-number-badge, design R35)
//
// Design `border-radius: 0.25rem 0 0.25rem 0` (CSS 4-value shorthand = top-left /
// top-right / bottom-right / bottom-left) — top-left AND bottom-right rounded,
// top-right AND bottom-left square. `UnevenRoundedRectangle` (the direct SwiftUI
// equivalent) is iOS 16+; this module stays iOS-14-safe throughout (see
// `SheetKit/TopRoundedRectangle.swift`'s identical rationale for its own
// two-of-four-corners shape), so this is a small hand-rolled `Shape` using the
// same `addQuadCurve` technique.
private struct NumberBadgeShape: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(radius, min(rect.width, rect.height) / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))                 // top edge → top-right (square)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))             // right edge
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - r, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY))                    // bottom-right (rounded)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))                // bottom edge → bottom-left (square)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))            // left edge
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + r, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY))                   // top-left (rounded)
        path.closeSubpath()
        return path
    }
}

// MARK: - LBProductRecommendation → LBProduct (PRESENTATION-ONLY conversion)
//
// `LBProductDetailState.recommendations` (`[LBProductRecommendation]`, from
// `expose-other-goods-recommendations-template`) is a DELIBERATELY minimal shape
// (`productId` / `name` / `priceShow` / `pic` / `videoId?` / `soldOut`) — it carries
// no `specifications` / `specOptions` / `originalPriceShow` / `stock` (design.md D2 of
// that template change). `ProductRowView` renders `LBProduct`, so this extension
// (added HERE in the reference-ui layer, mirroring the established pattern —
// `LBProductDetailState: Identifiable` is added the same way in
// `ProductSheetsOverlayView.swift`) builds a PRESENTATION-ONLY `LBProduct` carrying
// just enough to paint the `.grid` card correctly.
//
// ⚠️ This conversion MUST NOT be used as the payload for `onProductTap` / the nested
// detail's data — that would silently degrade the nested detail (no real
// specifications/stock). The container resolves the REAL `LBProduct` for a tapped
// recommendation from core `LivebuyPlayerViewController.channel?.otherGoods` (matched
// by `productId`) instead — see the "商品明細新增『商品介紹』文字區與『更多商品』推薦格"
// spec Requirement. This conversion exists ONLY to feed `ProductRowView`'s pixels.
//
// `originalPriceShow` is a direct pass-through of the receiver's own field
// (add-recommendation-original-price-reference-ui-ios) — `LBProductRecommendation`
// gained this field in `add-recommendation-original-price-template-ios`; the source
// product's own `""` (no original price) flows through unchanged, same as
// `priceShow: priceShow` immediately below.
extension LBProductRecommendation {
    var asDisplayProduct: LBProduct {
        LBProduct(
            id: productId, goodsNo: "", goodsGpn: "", name: name,
            price: 0, priceShow: priceShow, originalPrice: nil,
            originalPriceShow: originalPriceShow,
            stock: soldOut == 1 ? 0 : 1, pic: pic, photos: pic.isEmpty ? [] : [pic],
            brief: "", soldOut: soldOut, isHot: 0, isOutSoon: 0, narrateStatus: 0,
            isAwait: 0, isAwaitNotice: 0, beginTime: nil, endTime: nil, diversionUrl: "",
            specifications: [], specOptions: [], videoId: videoId)
    }
}
