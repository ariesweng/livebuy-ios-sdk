// MARK: - DefaultTemplateConstants — shared Default-template tuning values
//
// These are FOUR-PLATFORM-SHARED Default template constants (not per-platform).
// Keeping the value here (and matching it on Android / RN / Flutter) avoids the
// cross-platform state drift called out in design.md OQ1.

public enum DefaultTemplateConstants {
    /// Merged activity + chat feed tail-retain count. Taken from the delivered
    /// design `design/templates/minimal/moments.jsx` `LBLiveChatStream`
    /// `items.slice(-7)`. Shared across all 4 platforms (NOT per-platform).
    /// Stay / fade / animation timings are host-drawn and NOT fixed here.
    public static let activityFeedTailRetain: Int = 7

    /// Recent-seen signature window for de-duplicating merged-feed ACTIVITY /
    /// EVENT-JOIN rows (chat is never de-duped). poll buckets (`user[]` / `push[]`
    /// / `rush[]`) carry NO stable id, so a backend re-send on an adjacent poll
    /// would otherwise append the same join / system notice twice. The window is
    /// bounded (oldest signatures evicted) so it spans several poll cycles without
    /// suppressing a legitimately-recurring activity much later. Shared across all
    /// 4 platforms (NOT per-platform).
    public static let activityFeedDedupeWindow: Int = 64

    /// Scrollable history depth for the merged feed — deeper than the ambient
    /// `activityFeedTailRetain` (N=7) slice so the reference-ui chat feed can scroll
    /// up to view recent history. The ambient `items` slice keeps N=7; this only
    /// governs how many rows the `history` buffer retains for scroll-back. Shared
    /// across all 4 platforms (NOT per-platform).
    public static let activityFeedHistoryRetain: Int = 50

    /// Backend "product push" message color (spec §PollManager fan-out). A poll `push[]`
    /// row carrying this `color` is a 商品推播 / 開賣 notification that only surfaces in the
    /// chat feed (it does NOT trigger a goods refresh). Used to route such system notices
    /// through the DE-DUPED chat path so an adjacent-poll re-send isn't shown twice
    /// (free user chat — without this color / event / promo signal — stays un-deduped).
    /// Shared across all 4 platforms (NOT per-platform).
    public static let productPushColor: String = "#66F796"
}
