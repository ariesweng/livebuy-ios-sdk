import Foundation

// MARK: - VideoFeedSnapshotCache — process-level bounded chat-history switchback cache
// (chat-history-video-switch-cache-template, chat-history-video-switch-cache-cross-instance)
//
// Spec: `chat-history-dedupe-feed/spec.md`
//   § "in-place 換片還原已造訪影片的聊天歷史快照"
//   § "跨實例存活的歷史訊息快取（縮小關閉再進入也保留）"
// Design: openspec/changes/chat-history-video-switch-cache-template/design.md,
//         openspec/changes/chat-history-video-switch-cache-cross-instance-template/design.md
//
// `DefaultPlayerTemplate.handleVideoSwitch()` used to unconditionally `activityFeed.clear()` on
// EVERY in-place switch — including switching BACK to a video the user already watched earlier
// in this same session. Core's `MessagesCursorStore` already keeps that video's high-water
// cursor warm (chat-history-reentry-cursor-core), so `PollManager.start()` correctly skips
// `is_init` — but with no consumer-side cache, the template had nothing to show for the video's
// history, leaving the feed empty until new messages happened to trickle in.
//
// **History**: originally (2026-07-03, `chat-history-video-switch-cache-template`) this cache
// was scoped to ONE `DefaultPlayerTemplate` instance's lifetime, deliberately NOT process-level
// like `MessagesCursorStore` — the stated rationale was "a brand-new instance (VC rebuilt on
// close/reopen) always starts with an empty cache and correctly falls through to the normal
// clear()+backlog-fetch path, since `chat-history-reentry-instance-scoped-cursor-core` already
// forces `is_init` there regardless of any warm cursor." That's still TRUE (network-wise,
// close+reopen self-heals via a real backlog fetch) — but it means every close+reopen of a
// recently-watched video pays a redundant network round-trip AND shows a visible empty/loading
// flash before that fetch resolves, even though the exact same history was sitting in a
// now-deallocated instance's cache moments ago. `chat-history-video-switch-cache-cross-instance`
// promotes this cache to a **process-level singleton** (mirroring `MessagesCursorStore`'s own
// `static let shared` / `NSLock` shape) precisely so a brand-new instance's very FIRST video load
// can ALSO restore instantly from a previous instance's snapshot — closing the "縮小關閉再進入"
// (minimize/close then re-enter) gap without touching core: `PollManager`'s forced-`is_init`
// behavior is UNCHANGED (still fetches a real backlog every time), and the incoming items merge
// harmlessly against the restored cache via the existing `seenPushIds` identity dedup
// (`chat-push-id-dedupe-template`) — this is a pure "skip the visible empty flash + redundant
// bytes are just a self-heal, not a correctness dependency" improvement, not a network-skip.
//
// Bound choice (20, see the cross-instance change's design.md D1): the ORIGINAL per-instance
// scope (10) was sized to "how many distinct videos can one swipe/hot-pick SESSION plausibly
// revisit" (`EndScreenView.maxHotCards == 3`, `Widget/CarouselView.maxCards == 4`, swipe only
// resolves the immediately adjacent channel). Now that this cache is process-level, the relevant
// question is "how many distinct videos might a user browse across MANY player sessions over the
// app's lifetime" — a materially larger number than one session's revisit set, but each entry is
// still meaningfully heavier than `MessagesCursorStore`'s single `Double` (up to the merged feed's
// per-type retention total, `activityFeedChatRetain + activityFeedActivityRetain`, `LBFeedItem`s
// + a `Set<String>` of push ids) — so this stays smaller than that store's bound.
final class VideoFeedSnapshotCache {

    /// Process-wide shared instance used by production `DefaultPlayerTemplate`s so a
    /// brand-new instance's first video load can restore a previous instance's snapshot
    /// (close/reopen). Tests inject a fresh `VideoFeedSnapshotCache()` (or call `reset()`)
    /// to avoid cross-test bleed — mirrors `MessagesCursorStore.shared`'s exact idiom.
    static let shared = VideoFeedSnapshotCache()

    /// One saved snapshot: the feed's `history` at the moment the user switched away, PLUS the
    /// push-id de-dup set (`chat-push-id-dedupe-template`) at that same moment — saved and
    /// restored TOGETHER as one atomic unit so restoring history can never reopen a duplicate-id
    /// hole (see design.md D1).
    struct Snapshot: Equatable {
        let history: [LBFeedItem]
        let seenPushIds: Set<String>
    }

    /// Max distinct videoIds retained. Deliberately smaller than `MessagesCursorStore`'s 50 —
    /// see file doc (heavier per-entry payload).
    private let maxEntries: Int
    private let lock = NSLock()
    private var snapshots: [String: Snapshot] = [:]
    /// Recency order, oldest (least-recently-visited) first — LRU eviction.
    private var order: [String] = []

    init(maxEntries: Int = 20) {
        self.maxEntries = max(1, maxEntries)
    }

    /// The cached snapshot for `videoId`, or `nil` if never visited by any instance this
    /// process (or evicted). A lookup does NOT affect recency — only `save` moves an entry to
    /// most-recently-used (mirrors `MessagesCursorStore`: a cache read costs nothing to "touch").
    func snapshot(for videoId: String) -> Snapshot? {
        lock.lock(); defer { lock.unlock() }
        return snapshots[videoId]
    }

    /// Save (or refresh) `videoId`'s snapshot. A snapshot with EMPTY history is not worth
    /// caching (nothing to restore later, and it would just occupy a slot) — skip silently.
    func save(videoId: String, history: [LBFeedItem], seenPushIds: Set<String>) {
        guard !history.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        (snapshots, order) = Self.inserting(videoId: videoId,
                                             snapshot: Snapshot(history: history, seenPushIds: seenPushIds),
                                             into: snapshots, order: order, maxEntries: maxEntries)
    }

    /// Test-only: drop every saved snapshot (no production caller) — mirrors
    /// `MessagesCursorStore.reset()`, needed now that this cache is a shared singleton so tests
    /// using `.shared` don't bleed videoIds into each other.
    func reset() {
        lock.lock(); defer { lock.unlock() }
        snapshots.removeAll()
        order.removeAll()
    }

    /// Pure: LRU insert-or-update + bound eviction (docs/unit-test-discipline.md — extracted so
    /// eviction is unit-testable without constructing the class). Moves `videoId` to
    /// most-recently-used; evicts the single least-recently-visited entry once `order.count`
    /// would exceed `maxEntries`. Mirrors `MessagesCursorStore.update`'s identical shape.
    static func inserting(videoId: String, snapshot: Snapshot,
                           into snapshots: [String: Snapshot], order: [String], maxEntries: Int)
    -> (snapshots: [String: Snapshot], order: [String]) {
        var snapshots = snapshots
        var order = order
        snapshots[videoId] = snapshot
        if let idx = order.firstIndex(of: videoId) { order.remove(at: idx) }
        order.append(videoId)
        if order.count > maxEntries {
            let oldest = order.removeFirst()
            snapshots.removeValue(forKey: oldest)
        }
        return (snapshots, order)
    }
}
