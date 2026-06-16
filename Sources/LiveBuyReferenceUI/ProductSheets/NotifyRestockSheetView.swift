import SwiftUI
import LiveBuySDK
import LiveBuyUI

// MARK: - NotifyRestockSheetView — family-3 product sheet-stack surface 4 (restock-notify)
//
// Spec: `reference-ui-rendering/spec.md` (family-3 product + sheets, surface 4)
// Design: rb-ios-product-sheets design.md D-5 (`NotifyRestockSheet`) +
//          `design/templates/minimal/screens.jsx` `NotifyRestockSheet` (lines 766-803) +
//          `design/templates/minimal/sdk-components.jsx` `LBPBottomSheet` /
//          `LBPSheetHeader` / `LBPButton` (outline) / `LBPQtyStepper` (disabled).
//
// The SOLD-OUT restock-notify sheet for ONE sold-out `LBProductDetailState`
// (`soldOut == 1`). It is the fourth of the four family-3 surface sub-views
// composed by `ProductSheetsOverlayView`, and it implements the agreed SUB-VIEW
// INPUT PATTERN documented in `ProductSheetsOverlayView.swift`:
//
//   1. `theme: ReferenceUITheme`            — FIRST positional argument.
//   2. bound SNAPSHOT VALUES               — `detail: LBProductDetailState`
//      (a sold-out product) + `noticeEnabled: Bool` — passed BY VALUE from
//      `ProductSheetsModel` (never the model, never the template).
//   3. action closures (LAST, each `= nil`) — `onToggleNotice: (() -> Void)?`
//      (funnels to `model.toggleNotice(goodsGpn:)` → `DefaultGoodsTracking
//      .toggleNotice(_:)`, type=2 restock subscription) + `onDismiss: (() -> Void)?`
//      (close affordance).
//
// This sub-view reads ONLY its passed-in values; it never reaches back into
// `ProductSheetsModel` / `DefaultPlayerTemplate` (one-way data flow, D-1 / D-5). It
// also renders correctly with all actions nil (so demo / snapshot tests construct
// it action-free).
//
// FAMILY-3 BOUNDARY (D-5): this is the RESTOCK-NOTIFY subscription ONLY. The
// 「通知我補貨」toggle reflects `noticeEnabled` and forwards `onToggleNotice`
// (→ `goodsTracking.toggleNotice(goodsGpn)`, the notice flag only — the container
// passes `goodsGpn`). It MUST NOT render the goods-tracking AWAIT switch
// (`toggleAwait` / `awaitEnabled`, 到貨追蹤 type=1) — that is family-6.
//
// iOS-14-safe SwiftUI only. `VStack` / `HStack` / `ZStack` / `Text` / `Button` /
// `RoundedRectangle` / `Image` / `Color` are all iOS-13+. The sheet top reuses the
// iOS-14-safe module-internal `TopRoundedRectangle` shape + the grab handle /
// `LBPBottomSheet` / `LBPSheetHeader` styling established by `VideoInfoPanelView`
// (D-5 "reuse the LBPBottomSheet styling") — `TopRoundedRectangle` is NOT
// redefined here (it lives in `VideoInfoPanelView.swift`). No `.task` /
// `AsyncImage` / `NavigationStack` / `.foregroundStyle` / `.tint`.

/// The family-3 SOLD-OUT restock-notify sheet for one sold-out
/// `LBProductDetailState`. Renders the product photo placeholder + name + 已售完,
/// a divider, a disabled quantity row (尚無庫存), and a「通知我補貨」toggle that
/// reflects `noticeEnabled` and forwards `onToggleNotice`. RESTOCK-NOTIFY ONLY —
/// no AWAIT switch (family-6).
public struct NotifyRestockSheetView: View {

    /// The resolved reference-ui theme (FIRST positional argument, always).
    public let theme: ReferenceUITheme

    /// The sold-out product-detail this sheet subscribes restock-notify for
    /// (`detail.soldOut == 1`). Read-only.
    public let detail: LBProductDetailState
    /// Whether restock-notify is currently subscribed for this product
    /// (`DefaultGoodsTracking.noticeEnabled(for:)`). Drives the toggle's active
    /// state. Read-only.
    public let noticeEnabled: Bool
    /// `false` (snapshot / demo) → the photo draws the deterministic placeholder only (baselines
    /// unchanged). `true` (host runtime) → load `detail.photos[0]` over it via
    /// `RemoteStillImageView` (rb-ios-product-real-images).
    public let live: Bool

    /// Host-wired restock-notify toggle. The container forwards
    /// `model.toggleNotice(goodsGpn:)` → `DefaultGoodsTracking.toggleNotice(_:)`
    /// (optimistic flip of the NOTICE flag only — type=2; corrected by
    /// `NOTICE_GOODS_CHANGED`). nil for demo / snapshot instances — the sheet
    /// renders correctly action-free.
    private let onToggleNotice: (() -> Void)?
    /// Host-wired close / dismiss. nil for demo / snapshot instances.
    private let onDismiss: (() -> Void)?
    /// Host-wired zoom badge tap → container opens the full-frame `ProductZoomOverlayView`
    /// (rb-ios-product-image-zoom-lightbox). nil for demo / snapshot instances (the badge
    /// renders byte-identical to the prior decorative badge; tap is a no-op).
    private let onZoomImage: (() -> Void)?

    public init(
        theme: ReferenceUITheme,
        detail: LBProductDetailState,
        noticeEnabled: Bool,
        live: Bool = false,
        onToggleNotice: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil,
        onZoomImage: (() -> Void)? = nil
    ) {
        self.theme = theme
        self.detail = detail
        self.noticeEnabled = noticeEnabled
        self.live = live
        self.onToggleNotice = onToggleNotice
        self.onDismiss = onDismiss
        self.onZoomImage = onZoomImage
    }

    public var body: some View {
        // Content only — the shared `.lbBottomSheet(item:)` presenter (SheetKit) draws the
        // grab handle + `theme.background` + `TopRoundedRectangle(20)` + shadow + dim scrim +
        // drag-to-dismiss (sheetkit-migrate, replacing the system `.sheet(item:)`). The prior
        // full-height `Spacer` (a system-`.sheet` artifact) is dropped so the card is
        // content-sized ("貼底 + 內容自高" per the migration goal).
        // Pinned header (補貨通知 / close) + scrollable body (商品 + 數量) + pinned footer
        // (補貨通知 toggle), within the ½-screen cap (rb-ios-sheet-pinned-header-footer).
        LBSheetScaffold(fillToCap: true) {
            header
        } bodyContent: {
            VStack(spacing: 0) {
                productBlock
                    .padding(.horizontal, 16)
                    .padding(.top, 6)

                // hairline divider (design `margin: '18px 0'`).
                Rectangle()
                    .fill(Self.stroke)
                    .frame(height: 1)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 18)

                qtyRow
                    .padding(.horizontal, 16)
            }
        } footer: {
            noticeFooter
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 18)
                // 頂部分隔線：疊上緣、不佔流式高度，鏡像 `ProductDetailSheetView.footer`
                // （rb-ios-compact-sheet-cap-and-footer）。
                .overlay(Rectangle().fill(Self.stroke).frame(height: 1), alignment: .top)
        }
    }

    // MARK: - Sheet header (NotifyRestockSheet — trailing close only, NO title)
    //
    // 對齊設計 `NotifyRestockSheet` header（`justifyContent: 'flex-end'`）：**無標題**，只右上角
    // 關閉鈕（rb-ios-product-sheet-detail-polish 問題 3——還原先前為「四張 sheet 一致」刻意加上的
    // 置中「補貨通知」標題 deviation）。close 為 no-op 當 `onDismiss == nil`（demo / snapshot）。

    private var header: some View {
        HStack {
            Spacer(minLength: 0)
            // Shared transparent close (rb-ios-sheet-header-close-unify) — was a
            // `Circle(bgSunken) + xmark 11pt`; now aligned to ProductListView / design.
            // Behavior unchanged: tap → `onDismiss` → container `dismissDetail()`.
            SheetHeaderCloseButton(theme: theme, onTap: onDismiss)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    // MARK: - Product block (photo placeholder + name + 已售完 — NotifyRestockSheet body)

    private var productBlock: some View {
        HStack(alignment: .top, spacing: 14) {
            // Square photo placeholder (design 96×96 / radius 12). Decorative — no
            // network image (`AsyncImage` is >14); deterministic for snapshots.
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Self.bgSunken)
                // `live` + a real photo → the product image loads over the placeholder
                // (rb-ios-product-real-images); else the `photo` SF Symbol placeholder shows.
                // The clip lives on the IMAGE (not the ZStack) so the placeholder path is
                // byte-identical to before (no ZStack-level clip → no corner AA diff).
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
            // Zoom affordance (design `screens.jsx:790-793`: right:6 bottom:6, 24×24,
            // black@0.55 disc, white zoom glyph). Decorative media-zoom badge.
            .overlay(zoomBadge, alignment: .bottomTrailing)

            VStack(alignment: .leading, spacing: 6) {
                Text(detail.name)
                    .font(.system(size: 15 * theme.fontScale, weight: .bold))
                    .foregroundColor(theme.text)
                    .fixedSize(horizontal: false, vertical: true)

                // 已售完 — design `color: theme.soldOut`.
                Text(Self.soldOutLabel)
                    .font(.system(size: 13 * theme.fontScale))
                    .foregroundColor(Self.soldOut)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Media-zoom badge pinned to the thumbnail's bottom-trailing corner (design's
    /// `Icons.zoom` disc — black@0.55, white glyph). TAPPABLE → `onZoomImage` opens the
    /// full-frame lightbox; `PlainButtonStyle` keeps pixels byte-identical to the prior
    /// decorative badge.
    private var zoomBadge: some View {
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

    // MARK: - Qty row (數量 + 尚無庫存 + disabled stepper — design qty row)
    //
    // Sold-out → no stock. The stepper is a DISABLED affordance (dimmed, the
    // design's `<LBPQtyStepper value={0} disabled />`) — purely presentational, no
    // qty intent is forwarded from this sheet.

    private var qtyRow: some View {
        HStack(spacing: 14) {
            Text(Self.qtyLabel)
                .font(.system(size: 14 * theme.fontScale, weight: .semibold))
                .foregroundColor(theme.text)

            Spacer(minLength: 0)

            Text(Self.noStockLabel)
                .font(.system(size: 12 * theme.fontScale))
                .foregroundColor(Self.textFaint)

            disabledStepper
        }
    }

    /// Disabled qty stepper affordance (`−  0  +`, all dimmed / non-tappable),
    /// mirroring the design's `disabled` `LBPQtyStepper`.
    private var disabledStepper: some View {
        HStack(spacing: 0) {
            stepperGlyph("minus")
            Text("0")
                .font(.system(size: 14 * theme.fontScale, weight: .semibold))
                .foregroundColor(Self.textFaint)
                .frame(width: 36)
            stepperGlyph("plus")
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Self.stroke, lineWidth: 1))
        .opacity(0.6)
    }

    private func stepperGlyph(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(Self.textFaint)
            .frame(width: 32, height: 32)
    }

    // MARK: - Notice footer (「通知我補貨」toggle — design LBPButton outline + bell)
    //
    // The restock-notify subscription toggle. Reflects `noticeEnabled`:
    //   • not subscribed → outline accent affordance (design `LBPButton kind="outline"`
    //     + bell glyph + 「通知我補貨」), tap subscribes.
    //   • subscribed     → filled accent affordance + bell-fill glyph + 「已開啟補貨通知」,
    //     tap unsubscribes.
    // A no-op when `onToggleNotice == nil` (demo / snapshot). The footer sits above
    // a top hairline (design `borderTop`). RESTOCK-NOTIFY ONLY — no AWAIT switch.

    private var noticeFooter: some View {
        // 頂部分隔線改由 body 的 footer 閉包以 `.overlay`（疊上緣、`alignment: .top`、不佔流式高度）
        // 畫，對齊 `ProductDetailSheetView.footer`，兩個精簡 sheet 的 footer 分隔線一致
        // （rb-ios-compact-sheet-cap-and-footer）。footer 內容只剩補貨 CTA。
        Button(action: { onToggleNotice?() }) {
            HStack(spacing: 8) {
                Image(systemName: noticeEnabled ? "bell.fill" : "bell")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(noticeEnabled ? .white : theme.accent)
                Text(noticeEnabled ? Self.noticeOnLabel : Self.noticeOffLabel)
                    .font(.system(size: 15 * theme.fontScale, weight: .bold))
                    .foregroundColor(noticeEnabled ? .white : theme.accent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(noticeEnabled ? theme.accent : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(theme.accent, lineWidth: 1.5)))
            // Whole pill taps — when off the fill is Color.clear (un-hittable interior).
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Decorative design tokens (literal minimal hex via Color(hex:))
    //
    // accent / text / background come from the resolved theme. These are FIXED
    // decorative colors lifted verbatim from the design's `theme.surface.*` /
    // `theme.soldOut` (light mode, `design/brands/livebuy/tokens.jsx`) —
    // design-literal, NOT theme-resolved. Kept consistent with `WinClaimModalView` /
    // `VideoInfoPanelView` so the family-3 sheet-stack reads as one family.

    /// `theme.surface.textDim` (secondary / caption text).
    static let textDim = Color(hex: "#6B6775") ?? Color.gray
    /// `theme.surface.textFaint` (faint / disabled text — design `#9A9BA5`).
    static let textFaint = Color(hex: "#9A9BA5") ?? Color.gray.opacity(0.5)
    /// `theme.surface.stroke` (hairline border).
    static let stroke = Color(hex: "#ECEAF0") ?? Color.gray.opacity(0.2)
    /// `theme.surface.strokeStrong` (grab handle).
    static let strokeStrong = Color(hex: "#D8D5DE") ?? Color.gray.opacity(0.35)
    /// `theme.surface.bgSunken` (sunken card / placeholder / close-circle fill).
    static let bgSunken = Color(hex: "#F4F4F6") ?? Color.gray.opacity(0.08)
    /// `theme.soldOut` (sold-out caption — design `#9A9BA5`).
    static let soldOut = Color(hex: "#9A9BA5") ?? Color.gray

    // MARK: - Fixed localized copy (static presentation strings)

    static let soldOutLabel = "已售完"
    static let qtyLabel = "數量"
    static let noStockLabel = "尚無庫存"
    static let noticeOffLabel = "補貨通知我"
    static let noticeOnLabel = "已開啟補貨通知"

    /// First product photo as a non-empty URL, or nil (empty / whitespace → placeholder).
    static func photoURL(_ detail: LBProductDetailState) -> URL? {
        guard let s = detail.photos.first?.trimmingCharacters(in: .whitespacesAndNewlines),
              !s.isEmpty else { return nil }
        return URL(string: s)
    }
}

// MARK: - Deterministic demo seed (previews + snapshot tests)
//
// A deterministic sold-out detail (via the skeleton's documented recipe —
// `ProductSheetsModel.demoDetail(soldOut: 1)` → `LBProductDetailState` with
// `soldOut == 1`, stock 0) so previews / the snapshot test render the sheet's
// sold-out path deterministically (no live player). `LBSpecOption` is never
// constructed (its memberwise init is internal) — `demoDetail` passes
// `specifications: []` / `specOptions: []`, which the restock sheet does not need.

public extension NotifyRestockSheetView {

    /// A deterministic SOLD-OUT product-detail for the restock surface
    /// (`soldOut == 1`, stock 0) — built via the skeleton's documented recipe.
    static var demoSoldOutDetail: LBProductDetailState {
        ProductSheetsModel.demoDetail(soldOut: 1)
    }

    /// A deterministic demo restock-notify sheet, NOT yet subscribed
    /// (`noticeEnabled == false` → outline「通知我補貨」). The view renders correctly
    /// with `onToggleNotice` / `onDismiss` nil (no live template / no host wiring).
    static func demo(theme: ReferenceUITheme) -> NotifyRestockSheetView {
        NotifyRestockSheetView(
            theme: theme,
            detail: demoSoldOutDetail,
            noticeEnabled: false)
    }
}

#if DEBUG
struct NotifyRestockSheetView_Previews: PreviewProvider {
    static var previews: some View {
        let theme = ReferenceUIThemePalette.minimal
        Group {
            // Not subscribed → outline「通知我補貨」.
            NotifyRestockSheetView.demo(theme: theme)
                .previewDisplayName("restock · not subscribed")

            // Subscribed → filled「已開啟補貨通知」.
            NotifyRestockSheetView(
                theme: theme,
                detail: NotifyRestockSheetView.demoSoldOutDetail,
                noticeEnabled: true)
                .previewDisplayName("restock · subscribed")
        }
        .frame(width: 393, height: 420)
        .previewLayout(.sizeThatFits)
    }
}
#endif
