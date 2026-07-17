import Foundation
import LivebuySDK

/// 商品狀態標籤的**單一優先序**解析（rb-ios-goods-label-unified ③）。
///
/// 後端 batch ③ 由 SDK 算好結論欄 `LBProduct.label`（唯一優先序 `sold_out > narrating >
/// out_soon > hot`，四者皆無 → `""`）。reference-ui 以此為單一來源、停止各自用 raw 欄位臨時自組。
/// 為相容舊後端 / demo（`label == ""`），`resolve` 在 label 空時以 raw 欄位**同序** fallback；
/// `fromLabel` 則只認**明確** label（給「新視覺」用，空 → `.none`，不臆測 raw）。
public enum ProductStatusBadge: Equatable {
    case soldOut     // 售罄
    case narrating   // 介紹中（僅直播 type=2 有意義）
    case outSoon     // 即將售完
    case hot         // 熱賣中
    case none        // 無標籤

    /// 後端結論欄 `label` 字串 → badge（只認明確 label；空 / 未知 → `.none`）。Pure.
    public static func fromLabel(_ label: String) -> ProductStatusBadge {
        switch label {
        case "sold_out":  return .soldOut
        case "narrating": return .narrating
        case "out_soon":  return .outSoon
        case "hot":       return .hot
        default:          return .none
        }
    }

    /// 單一優先序解析：`label` 優先；`label` 空（舊後端 / demo / 未計算）時以 raw 欄位
    /// （`soldOut` / `isNarrating` / `isOutSoon` / `isHot`）**同序** fallback。Pure / testable.
    public static func resolve(_ p: LBProduct) -> ProductStatusBadge {
        let byLabel = fromLabel(p.label)
        if byLabel != .none { return byLabel }
        // fallback（label 空）：維持與後端相同的優先序，確保既有視覺（已售完）相容。
        if p.soldOut == 1 { return .soldOut }
        if p.isNarrating { return .narrating }
        if p.isOutSoon == 1 { return .outSoon }
        if p.isHot == 1 { return .hot }
        return .none
    }
}
