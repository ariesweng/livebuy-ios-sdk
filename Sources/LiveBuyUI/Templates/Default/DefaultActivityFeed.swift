import LiveBuySDK

// MARK: - DefaultActivityFeed — §1 merged activity + chat feed (behaviour layer)
//
// Spec: `ui-template-foundation/spec.md`
//   § "Default Template Activity 與 Chat 合流 Feed 行為"
// Design: design.md D1 — 資料層合流, host 繪製 `LBLiveChatStream` 列.
//
// This is a DATA-LAYER view-model, NOT a renderer. It merges the core's
// activity events (`showJoin` / `showPurchase` / `showWin`) with chat messages
// (push + comments) into ONE ordered feed (newest at the tail) and exposes it
// for the host to draw. It MUST NOT double-write activity items into the
// ChatView chat data source — the activity items live only in this feed model.
//
// Tail-retain N is a SHARED Default-template constant across all 4 platforms
// (see `DefaultTemplateConstants.activityFeedTailRetain`), taken from the
// delivered design `moments.jsx` `LBLiveChatStream` `items.slice(-7)`.

/// Visual-tier marker for an activity feed item. Ordered ascending so a host
/// can decide emphasis: 入場 < 購買 < 介紹 < 中獎. Chat items carry no tier.
/// `intro`（商品開始介紹）來源為商品推播 push（`#66F796`），強調介於購買與中獎之間。
public enum LBActivityTier: Int, Equatable {
    case join = 0
    case purchase = 1
    case intro = 2
    case win = 3
}

/// One row in the merged feed. `text` is the backend-prebuilt, i18n-complete
/// string and MUST stay a single string (NOT split into userName + goodsName).
public struct LBFeedItem: Equatable {
    public enum Kind: Equatable {
        /// An activity row (join / purchase / win). `tier` drives host emphasis.
        case activity(tier: LBActivityTier)
        /// A chat row (push / comment).
        case chat
        /// An event-join row (core event-begin push). Host draws the
        /// `moments.jsx` `LBEventJoinLine` (CTA「加入活動」) bound to `eid` /
        /// `keyword` / `joined`. Surfaced ONLY for event-begin; event-end stays
        /// a plain `.chat` row.
        case eventJoin
    }

    public let kind: Kind
    public let text: String
    /// Present only for `.activity(tier: .win)`; nil otherwise. Lets the host
    /// drill into the won award without re-parsing `text`.
    public let winner: LBWinner?

    // MARK: - Event-join fields (livebuy-ui-event-join-and-error-state-template)
    /// Present only for `.eventJoin`; nil otherwise. Core event id (`> 0`).
    public let eid: Int?
    /// Present only for `.eventJoin`; nil otherwise. Core event keyword (`ek`).
    public let keyword: String?
    /// `.eventJoin` only — template-OPTIMISTIC join flag. false on surface; the
    /// template flips it to true once the host triggers the join intent (core
    /// has NO "join succeeded" callback). Ignored for non-eventJoin rows.
    public internal(set) var joined: Bool

    public init(kind: Kind, text: String, winner: LBWinner? = nil,
                eid: Int? = nil, keyword: String? = nil, joined: Bool = false) {
        self.kind = kind
        self.text = text
        self.winner = winner
        self.eid = eid
        self.keyword = keyword
        self.joined = joined
    }

    /// Convenience: the tier if this is an activity row, else nil.
    public var tier: LBActivityTier? {
        if case .activity(let t) = kind { return t }
        return nil
    }

    public var isActivity: Bool { tier != nil }

    /// Convenience: true when this row is an event-join row.
    public var isEventJoin: Bool { kind == .eventJoin }

    // `LBWinner` (core model) is not Equatable, so compare by `winner.id`.
    public static func == (lhs: LBFeedItem, rhs: LBFeedItem) -> Bool {
        lhs.kind == rhs.kind && lhs.text == rhs.text && lhs.winner?.id == rhs.winner?.id
            && lhs.eid == rhs.eid && lhs.keyword == rhs.keyword && lhs.joined == rhs.joined
    }
}

/// Merged activity + chat feed view-model. Newest item is at the tail; only the
/// last `tailRetain` items are kept (shared Default-template constant N = 7).
public final class DefaultActivityFeed {

    private let tailRetain: Int
    private let historyRetain: Int

    /// Full scrollable history buffer (cap `historyRetain`, deeper than the N=7
    /// ambient slice), newest at the tail. The reference-ui SCROLLABLE chat feed binds
    /// this so the user can scroll up to view recent history. Same merge / order /
    /// de-dup / no-chat-double-write rules as `items`.
    private(set) public var history: [LBFeedItem] = []

    /// The ambient overlay slice — the newest `tailRetain` (N=7) rows of `history`.
    /// UNCHANGED contract (tail-retain N=7, newest at tail) for the non-scrollable feed,
    /// other-platform parity and snapshot demo; DERIVED from `history` so there is a
    /// single source of truth (`items` never accumulates independently).
    public var items: [LBFeedItem] {
        history.count <= tailRetain ? history : Array(history.suffix(tailRetain))
    }

    /// Bounded recent-seen signatures for ACTIVITY / EVENT-JOIN rows so a backend
    /// re-send on an adjacent poll (the `user[]` / `push[]` / `rush[]` buckets carry
    /// NO stable id) is not appended twice. Chat rows are NEVER recorded / de-duped
    /// (identical chat text from two users is legitimate). Reset by `clear()` (incl.
    /// `VIDEO_SWITCH`) so a new session can re-show same-text activity.
    private var recentActivitySignatures: [String] = []
    private let dedupeWindow: Int

    /// Internal coalesced "feed mutated" hook. The owning `DefaultPlayerTemplate`
    /// wires this to fan a single host-facing `onChange` (main-thread) per
    /// mutation. NOT public — the host observes via the template's `onChange`,
    /// it does NOT subscribe to the feed model directly.
    var onMutation: (() -> Void)?

    public init(tailRetain: Int = DefaultTemplateConstants.activityFeedTailRetain,
                dedupeWindow: Int = DefaultTemplateConstants.activityFeedDedupeWindow,
                historyRetain: Int = DefaultTemplateConstants.activityFeedHistoryRetain) {
        self.tailRetain = max(1, tailRetain)
        self.dedupeWindow = max(1, dedupeWindow)
        // History is at least as deep as the ambient slice (items derives from it).
        self.historyRetain = max(max(1, tailRetain), historyRetain)
    }

    // MARK: - Activity ingestion (from core showJoin / showPurchase / showWin)

    public func appendJoin(text: String) {
        append(LBFeedItem(kind: .activity(tier: .join), text: text))
    }

    public func appendPurchase(text: String) {
        append(LBFeedItem(kind: .activity(tier: .purchase), text: text))
    }

    /// 商品推播（`push[]` 帶商品推播色 `#66F796`，例如「商品開賣 / 開始介紹」）→ feed
    /// activity row, tier = intro（喇叭 + accent 暈染，強調介於購買與中獎之間）。商品推播
    /// push 無 stable id，故與 join / purchase 同樣走 activity 去重（簽名涵蓋 tier）。
    public func appendIntro(text: String) {
        append(LBFeedItem(kind: .activity(tier: .intro), text: text))
    }

    public func appendWin(text: String, winner: LBWinner?) {
        append(LBFeedItem(kind: .activity(tier: .win), text: text, winner: winner))
    }

    // MARK: - Chat ingestion (push + comments)

    public func appendChat(text: String) {
        append(LBFeedItem(kind: .chat, text: text))
    }

    /// A SYSTEM / 商品推播 notice (e.g. 「商品開賣」) surfaced as a chat row but DE-DUPED. The
    /// poll `push[]` bucket carries no stable id, so the backend re-sending the same system
    /// notice on an adjacent poll would otherwise appear twice. Unlike free user chat (which
    /// legitimately repeats and is NEVER de-duped), an identical system notice (signature
    /// `cs|<text>`) within the bounded recent-seen window is dropped SILENTLY (no append, no
    /// `onMutation`). Routed here by `DefaultPlayerTemplate.handlePush` for product/event/promo
    /// pushes (`color == productPushColor` / `eid > 0` / `ct` / `p`).
    public func appendSystemNotice(text: String) {
        append(LBFeedItem(kind: .chat, text: text), dedupeKey: "cs|\(text)")
    }

    // MARK: - Event-join ingestion (from core event-begin push)

    /// Surface a core event-begin push as an INDEPENDENT event-join feed item
    /// (host draws `LBEventJoinLine`). `joined` starts false. event-END pushes
    /// MUST NOT reach here — they stay plain `.chat` rows (see `handlePush`).
    public func appendEventJoin(eid: Int, keyword: String, text: String = "") {
        append(LBFeedItem(kind: .eventJoin, text: text, eid: eid, keyword: keyword, joined: false))
    }

    /// Template-optimistic join mark: flip every still-unjoined event-join item
    /// for `eid` to `joined = true`. Public so a host that takes over
    /// `eventJoinIntent` itself can set the joined flag via this hook
    /// (design D2). One mutation fires exactly one `onMutation`.
    public func markJoined(eid: Int) {
        var changed = false
        for i in history.indices where history[i].kind == .eventJoin && history[i].eid == eid && !history[i].joined {
            history[i].joined = true
            changed = true
        }
        if changed { onMutation?() }
    }

    // MARK: - Internal

    private func append(_ item: LBFeedItem, dedupeKey: String? = nil) {
        // Defensive de-dup for ACTIVITY / EVENT-JOIN rows (and SYSTEM-notice chat rows that
        // pass an explicit `dedupeKey`): the poll buckets carry no stable id, so a backend
        // re-send on an adjacent poll would otherwise show the same join / system notice
        // twice. A duplicate (signature already in the bounded recent-seen window) is dropped
        // SILENTLY — no append, no `onMutation` (so no redraw for a row that never appears).
        // An ORDINARY chat row has no signature (`dedupeKey == nil`, `.chat` → nil) → never
        // deduped (two users' identical chat is legitimate).
        if let signature = dedupeKey ?? Self.dedupeSignature(for: item) {
            if recentActivitySignatures.contains(signature) { return }
            recentActivitySignatures.append(signature)
            if recentActivitySignatures.count > dedupeWindow {
                recentActivitySignatures.removeFirst(recentActivitySignatures.count - dedupeWindow)
            }
        }
        // Append to the deep `history` buffer (cap `historyRetain`); the ambient
        // `items` slice (newest N=7) is derived from it.
        history.append(item)
        if history.count > historyRetain {
            history.removeFirst(history.count - historyRetain)
        }
        // One append == one coalesced mutation (no redraw storm; each event
        // notifies exactly once).
        onMutation?()
    }

    /// De-dup signature for an ACTIVITY / EVENT-JOIN row, or nil for chat (chat
    /// repeats are legitimate and MUST NOT be de-duped). With no stable message id
    /// the backend-prebuilt `text` is the only usable fingerprint, qualified by the
    /// row kind (+ `tier` / `eid` / `winner.id`) so different row types never collide.
    static func dedupeSignature(for item: LBFeedItem) -> String? {
        switch item.kind {
        case .chat:
            return nil
        case .activity(let tier):
            return "a\(tier.rawValue)|\(item.winner?.id ?? "")|\(item.text)"
        case .eventJoin:
            return "e\(item.eid ?? 0)|\(item.text)"
        }
    }

    /// Drops the whole feed history (e.g. on `load(newVideoId)` / `VIDEO_SWITCH` /
    /// release); `items` (derived) becomes empty too. Also resets the de-dup window so
    /// a new session can re-show same-text activity.
    public func clear() {
        history.removeAll()
        recentActivitySignatures.removeAll()
        onMutation?()
    }
}
