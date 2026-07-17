import Foundation

/// Playback mode that decides a product-list row's thumbnail overlay
/// (rb-ios-product-row-status-overlay). Distinct from the real-frame `live`
/// flag (photo loading) — this is VOD vs active-live vs replay.
public enum ProductRowMode: Equatable {
    case vod      // 純點播：可 seek 到商品介紹片段 → 播放 icon
    case live     // 直播中：無未來可跳 → 正在介紹的商品標「介紹中」、其餘無 icon
    case replay   // 直播回放：依 begin_time/end_time vs 當下播放秒數逐商品判「介紹中」
}

/// Pure decision for a product-list row's thumbnail overlay AND the row's share
/// icon visibility. Unit-testable in isolation (rb-ios-product-row-status-overlay
/// / rb-ios-live-hide-product-share). The play affordance and the「介紹中」label
/// are mutually exclusive on any single row.
///
/// - VOD: play affordance (seek-to-intro), never 介紹中. Share icon shown (a VOD
///   product has a real `beginTime` a share link can point at).
/// - active live: 介紹中 ⟺ `isNarrating` (the `narrate_status == 2` product);
///   never the play affordance (live has no future to scrub to). Share icon
///   HIDDEN (rb-ios-live-hide-product-share, design R12) — a genuinely-live
///   product has no settled "start time" a share link could carry.
/// - replay: 介紹中 ⟺ the current playback `position` is inside the product's
///   `[beginTime, endTime]` window (inclusive); otherwise the play affordance
///   (seek to its segment). `isNarrating` is ignored for replay
///   (`introducingProductId` is non-nil only during active live). Share icon
///   shown — replay products have real `beginTime`/`endTime`, same semantics
///   as VOD.
public enum ProductRowOverlay {
    public static func decide(
        mode: ProductRowMode,
        isNarrating: Bool,
        beginTime: Int?,
        endTime: Int?,
        position: Int
    ) -> (showPlay: Bool, showIntroducing: Bool, showShare: Bool) {
        let showShare = mode != .live
        switch mode {
        case .vod:
            return (showPlay: true, showIntroducing: false, showShare: showShare)
        case .live:
            return (showPlay: false, showIntroducing: isNarrating, showShare: showShare)
        case .replay:
            let inWindow = beginTime != nil && endTime != nil
                && beginTime! <= position && position <= endTime!
            return (showPlay: !inWindow, showIntroducing: inWindow, showShare: showShare)
        }
    }
}
