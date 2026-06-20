import Foundation

/// Playback mode that decides a product-list row's thumbnail overlay
/// (rb-ios-product-row-status-overlay). Distinct from the real-frame `live`
/// flag (photo loading) — this is VOD vs active-live vs replay.
public enum ProductRowMode: Equatable {
    case vod      // 純點播：可 seek 到商品介紹片段 → 播放 icon
    case live     // 直播中：無未來可跳 → 正在介紹的商品標「介紹中」、其餘無 icon
    case replay   // 直播回放：依 begin_time/end_time vs 當下播放秒數逐商品判「介紹中」
}

/// Pure decision for a product-list row's thumbnail overlay. Unit-testable in
/// isolation (rb-ios-product-row-status-overlay). The play affordance and the
/// 「介紹中」label are mutually exclusive on any single row.
///
/// - VOD: play affordance (seek-to-intro), never 介紹中.
/// - active live: 介紹中 ⟺ `isNarrating` (the `narrate_status == 2` product);
///   never the play affordance (live has no future to scrub to).
/// - replay: 介紹中 ⟺ the current playback `position` is inside the product's
///   `[beginTime, endTime]` window (inclusive); otherwise the play affordance
///   (seek to its segment). `isNarrating` is ignored for replay
///   (`introducingProductId` is non-nil only during active live).
public enum ProductRowOverlay {
    public static func decide(
        mode: ProductRowMode,
        isNarrating: Bool,
        beginTime: Int?,
        endTime: Int?,
        position: Int
    ) -> (showPlay: Bool, showIntroducing: Bool) {
        switch mode {
        case .vod:
            return (showPlay: true, showIntroducing: false)
        case .live:
            return (showPlay: false, showIntroducing: isNarrating)
        case .replay:
            let inWindow = beginTime != nil && endTime != nil
                && beginTime! <= position && position <= endTime!
            return (showPlay: !inWindow, showIntroducing: inWindow)
        }
    }
}
