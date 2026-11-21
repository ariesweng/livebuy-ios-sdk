import SwiftUI
import LivebuyUI

// MARK: - Flash-sale bid presentation helpers (rb-ios-flash-sale-bid)
//
// Spec: `reference-ui-rendering/spec.md` §「LivebuyReferenceUI 搶購場商品明細狀態（iOS）」/
//       §「LivebuyReferenceUI 搶購下標結果提示（iOS）」.
// Design: `design/templates/minimal/screens.jsx` `LBPBidWaitingBanner` / `LBPQtyHint`;
//         `design/contract/claude-design-sync.md` D10.
//
// Pure presentation over the view-model fields `LBProductDetailState.bidWaiting` / `limitNum` /
// `buyButtonHidden` and `DefaultPlayerTemplate.bidOutcome` (live-bid-ios-template). Nothing here
// owns business state; every decision is a pure static function so it is unit-testable without
// rendering (unit-test-discipline).

// MARK: - Qty-row hint (LBPQtyHint)

/// What the qty row shows to the left of the stepper.
///
/// Design `LBPQtyHint` order: sold out > 每人限購 > 庫存. On iOS the sold-out case keeps the
/// existing rule of drawing NO caption in the qty row (the price row already reads「已售完」;
/// rb-ios-show-stock-caption-toggle) — only its precedence over the limit is taken from the design.
enum QtyHint: Equatable {
    case none
    /// 「每人限購 {num} 組」— drawn regardless of `showStock` (the design checks the limit first).
    case limit(Int)
    /// 「只剩庫存 {count} 組」.
    case stock

    static func resolve(isSoldOut: Bool, showStock: Bool, limitNum: Int) -> QtyHint {
        if isSoldOut { return .none }
        if limitNum > 0 { return .limit(limitNum) }
        // The stock caption stays decided by THE single existing predicate.
        return ProductDetailSheetView.showsStockCaption(showStock: showStock, isSoldOut: isSoldOut)
            ? .stock : .none
    }
}

// MARK: - Detail / add-to-cart footer slots

/// Which footer slots the product sheet draws. `buyButtonHidden` (直播管家搶購場、商品沒設搶購
/// 關鍵字) removes the CTA outright — no placeholder, no substitute copy (design D10). When neither
/// slot remains the footer (incl. its top separator) is not drawn at all (design
/// `!(live && buyButtonHidden)`).
struct ProductSheetFooterSlots: Equatable {
    let share: Bool
    let cta: Bool
    var isEmpty: Bool { !share && !cta }

    static func resolve(isDetailPresentation: Bool, isLive: Bool,
                        buyButtonHidden: Bool) -> ProductSheetFooterSlots {
        ProductSheetFooterSlots(share: isDetailPresentation && !isLive, cta: !buyButtonHidden)
    }
}

// MARK: - Bid outcome → toast copy

/// The toast shown for a flash-sale bid outcome (`DefaultPlayerTemplate.bidOutcome`).
struct BidToastContent: Equatable {
    let key: String
    let args: [String: String]
    let isError: Bool

    var text: String { ReferenceUIStrings.text(key, args) }

    /// `.placed` → success「已加入搶購」; `.failed(code)` → error copy chosen by backend
    /// `error_code` (rb-flash-sale-bid-strings design.md §2):
    ///   `purchase_limit_exceeded` → `bid_limit` (num = `limitNum`; `limitNum <= 0` → `bid_failed`),
    ///   `out_of_stock` → `bid_failed_out_of_stock`, `keyword_missing` → `bid_failed_unavailable`,
    ///   anything else / nil → `bid_failed`.
    static func resolve(_ outcome: LBBidOutcome, limitNum: Int) -> BidToastContent {
        switch outcome {
        case .placed:
            return BidToastContent(key: "bid_placed_toast", args: [:], isError: false)
        case .failed(let code):
            return BidToastContent(key: failureKey(code: code, limitNum: limitNum),
                                   args: code == "purchase_limit_exceeded" && limitNum > 0
                                       ? ["num": String(limitNum)] : [:],
                                   isError: true)
        }
    }

    static func failureKey(code: String?, limitNum: Int) -> String {
        switch code {
        case "purchase_limit_exceeded": return limitNum > 0 ? "bid_limit" : "bid_failed"
        case "out_of_stock": return "bid_failed_out_of_stock"
        case "keyword_missing": return "bid_failed_unavailable"
        default: return "bid_failed"
        }
    }
}

// MARK: - BidWaitingBannerView (LBPBidWaitingBanner)

/// Full-width `#F03246` banner: hourglass +「正在等待結果...」on the left,「搶購中」on the right
/// (white, 12pt bold). Drawn at the top of the sheet body while `detail.bidWaiting`.
struct BidWaitingBannerView: View {
    @ObservedObject var l10n = ReferenceUILanguage.shared
    let theme: ReferenceUITheme

    static let red = Color(hex: "#F03246") ?? .red

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                HourglassGlyph(size: 14, color: .white, lineWidth: 2)
                Text(ReferenceUIStrings.text("bid_waiting"))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(ReferenceUIStrings.text("product_rush"))
                .lineLimit(1)
                .fixedSize()
        }
        .font(.system(size: 12 * theme.fontScale, weight: .bold))
        .foregroundColor(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Self.red)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(LBAccessibilityID.bidWaitingBanner)
    }
}
