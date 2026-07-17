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

    /// **DEPRECATED on iOS** (chat-activity-separate-retention-ios-template): the single
    /// shared-FIFO total cap for the merged `history` buffer. iOS no longer trims the merged
    /// feed by ONE shared cap — it now retains chat rows and activity rows under SEPARATE
    /// per-type caps (`activityFeedChatRetain` / `activityFeedActivityRetain`) so real chat
    /// (`.chat`) is NEVER evicted by activity rows. This constant's value (500) is kept only
    /// for source-compatibility (a downstream reader must not fail to compile); it is NOT the
    /// trim cap on iOS anymore. Android / RN / Flutter still use their own single-shared-500
    /// cap (`HISTORY_RETAIN` / `DEFAULT_FEED_HISTORY_RETAIN` / `historyRetainDefault`);
    /// their separate-retention parity is a follow-up.
    @available(*, deprecated, message: "iOS 改用分離保留：改用 activityFeedChatRetain / activityFeedActivityRetain。此常數僅為源碼相容保留，不再是 iOS 合流 feed 的 trim 依據。")
    public static let activityFeedHistoryRetain: Int = 500

    /// Per-type retain cap for CHAT rows (`kind == .chat`: 觀眾留言 / 主播留言 / 主播回覆 / AI 回覆)
    /// in the merged `history` buffer (chat-activity-separate-retention-ios-template). When the
    /// chat-row count exceeds this, ONLY the oldest chat rows are trimmed — NEVER touched by the
    /// activity-row count. Kept generous (500, the prior overall cap) so a session's chat is at
    /// least as protected as before AND is no longer diluted by activity rows. This is a
    /// per-platform constant (each of the 4 platforms keeps its own copy); iOS-only pilot —
    /// Android / RN / Flutter still share a single 500 FIFO, their separate-retention parity is
    /// a follow-up.
    public static let activityFeedChatRetain: Int = 500

    /// Per-type retain cap for ACTIVITY-bucket rows (everything that is NOT `.chat`:
    /// `.activity(join/purchase/browse/intro/win)` / `.eventJoin` / `.productSale`) in the merged
    /// `history` buffer (chat-activity-separate-retention-ios-template). Bounds the activity rows
    /// so a busy stream cannot grow the buffer without limit, while its trim is INDEPENDENT of the
    /// chat cap (so activity churn never evicts chat). 200 is ample scroll-back for ambient
    /// social-proof rows (the ambient overlay only ever shows the newest `activityFeedTailRetain`
    /// = 7) and comfortably exceeds `activityFeedTailRetain` and `activityFeedDedupeWindow`.
    /// Memory upper bound of the merged feed is `activityFeedChatRetain + activityFeedActivityRetain`
    /// (= 700) lightweight `LBFeedItem`. Per-platform constant; iOS-only pilot (see above).
    public static let activityFeedActivityRetain: Int = 200

    /// Backend "product push" message color (spec §PollManager fan-out). A poll `push[]`
    /// row carrying this `color` is a 商品推播 / 開賣 notification that only surfaces in the
    /// chat feed (it does NOT trigger a goods refresh). Used to route such system notices
    /// through the DE-DUPED chat path so an adjacent-poll re-send isn't shown twice
    /// (free user chat — without this color / event / promo signal — stays un-deduped).
    /// Shared across all 4 platforms (NOT per-platform).
    public static let productPushColor: String = "#66F796"
}
