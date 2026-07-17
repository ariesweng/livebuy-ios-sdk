import LivebuySDK

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

/// Visual-tier marker for an activity feed item. Chat items carry no tier.
/// 語意層級（強調遞增）：**觀眾選購 ≈ 進場（最低調社會認同）< 購買 < 介紹 < 中獎**。
/// `browse`（觀眾選購，chat-message-taxonomy ⑤，來源 `kind == .narrate` / `#66F796`）為與
/// `join` 同級的最低調熱度信號（非主播訊息、非購買、非介紹中）。`intro`（商品開始介紹）來源
/// 為商品推播 push，強調介於購買與中獎之間。
/// 註：`rawValue` 僅作 `dedupeSignature` 的穩定判別子與跨端 parity 對齊（不持久化、不序列化），
/// **不等於強調順序**——`browse = 4` 為 append（不重排既有值），語意上仍是最低調。
public enum LBActivityTier: Int, Equatable {
    case join = 0
    case purchase = 1
    case intro = 2
    case win = 3
    /// 觀眾選購（最低調社會認同，與 `join` 同級）。
    case browse = 4
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
        /// A 商品開賣 (onsale) product-sale row (chat5 群組①「商品開賣」). Host draws the
        /// `moments.jsx` `LBProductSaleCard` (縮圖 + 商品名 `text` + 現價 `price` + 搶購鈕).
        /// Surfaced ONLY for `kind == .onsale` with a non-empty product name; the
        /// ProductController-empty source falls back to a plain `.chat` notice.
        case productSale
    }

    public let kind: Kind
    public let text: String
    /// Present only for `.chat` rows — the message author's nickname (backend
    /// `LBPushMsg.name` / `LBComment.name`). `nil` for every other kind and for
    /// chat with no usable name (blank → normalized to nil by `appendChat`). The
    /// reference-ui renders it as the chat-row nickname; nil → text-only fallback
    /// (chat-nickname-display).
    public let userName: String?

    // MARK: - Chat role metadata (chat-message-taxonomy ⑤, 群組① 真正的聊天)
    /// `.chat` only — 主播留言 / 主播回覆。`false` for viewer (`.comment`) messages.
    /// Lets the reference-ui draw the「主播」tag + accent bubble — distinguishing by
    /// LAYOUT, not colour. Default `false` keeps existing viewer rows byte-identical.
    public let isHost: Bool
    /// `.chat` only — AI 自動回覆（`kind == .aiReply`）。`true` adds the「AI」badge on
    /// top of the host-reply layout. Default `false`.
    public let isAI: Bool
    /// `.chat` only — 主播回覆 / AI 回覆 的**被回覆引用內容**（backend `LBPushMsg.reply`），
    /// 為一段獨立字串（NOT split from `text`）。`nil` → 無引用框。後端無「引用者名稱」欄，故
    /// 只帶引用文字。Default `nil`.
    public let replyText: String?
    /// Present only for `.activity(tier: .win)`; nil otherwise. Lets the host
    /// drill into the won award without re-parsing `text`.
    public let winner: LBWinner?

    /// `.productSale` only — 商品開賣現價（已格式化字串，backend `LBPushMsg.p` / `price`，chat5
    /// 群組①「商品開賣」）。`nil` for every other kind (default → existing feed byte-identical). The
    /// reference-ui renders it as the card's price line; `text` is the 商品名. 原價（劃線 listPrice）/
    /// 真實縮圖 URL / 搶購 deeplink 仍待後端補欄 (PARK).
    public let price: String?

    // MARK: - Event-join fields (livebuy-ui-event-join-and-error-state-template)
    /// Present only for `.eventJoin`; nil otherwise. Core event id (`> 0`).
    public let eid: Int?
    /// Present only for `.eventJoin`; nil otherwise. Core event keyword (`ek`).
    public let keyword: String?
    /// `.eventJoin` only — template-OPTIMISTIC join flag. false on surface; the
    /// template flips it to true once the host triggers the join intent (core
    /// has NO "join succeeded" callback). Ignored for non-eventJoin rows.
    public internal(set) var joined: Bool

    public init(kind: Kind, text: String, userName: String? = nil, winner: LBWinner? = nil,
                eid: Int? = nil, keyword: String? = nil, joined: Bool = false,
                isHost: Bool = false, isAI: Bool = false, replyText: String? = nil,
                price: String? = nil) {
        self.kind = kind
        self.text = text
        self.userName = userName
        self.winner = winner
        self.eid = eid
        self.keyword = keyword
        self.joined = joined
        self.isHost = isHost
        self.isAI = isAI
        self.replyText = replyText
        self.price = price
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
        lhs.kind == rhs.kind && lhs.text == rhs.text && lhs.userName == rhs.userName
            && lhs.winner?.id == rhs.winner?.id
            && lhs.eid == rhs.eid && lhs.keyword == rhs.keyword && lhs.joined == rhs.joined
            && lhs.isHost == rhs.isHost && lhs.isAI == rhs.isAI && lhs.replyText == rhs.replyText
            && lhs.price == rhs.price
    }
}

/// Merged activity + chat feed view-model. Newest item is at the tail; only the
/// last `tailRetain` items are kept (shared Default-template constant N = 7).
public final class DefaultActivityFeed {

    private let tailRetain: Int
    /// Per-type retain cap for CHAT rows (`kind == .chat`). Chat is trimmed INDEPENDENTLY of
    /// activity so it is never evicted by activity rows (chat-activity-separate-retention-ios-template).
    private let chatRetain: Int
    /// Per-type retain cap for ACTIVITY-bucket rows (everything that is NOT `.chat`).
    private let activityRetain: Int

    /// Full scrollable history buffer, newest at the tail. The reference-ui SCROLLABLE chat feed
    /// binds this so the user can scroll up to view recent history. Same merge / order / de-dup /
    /// no-chat-double-write rules as `items`. Trim is by SEPARATE per-type caps (chat-activity-
    /// separate-retention-ios-template): chat rows capped at `chatRetain`, activity-bucket rows
    /// (`.activity` / `.eventJoin` / `.productSale`) capped at `activityRetain`, the two never
    /// affecting each other — so real chat (`.chat`) is NEVER pushed out by activity rows.
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
                chatRetain: Int = DefaultTemplateConstants.activityFeedChatRetain,
                activityRetain: Int = DefaultTemplateConstants.activityFeedActivityRetain) {
        self.tailRetain = max(1, tailRetain)
        self.dedupeWindow = max(1, dedupeWindow)
        // Chat retain is at least as deep as the ambient slice: `items` (newest tailRetain of
        // history) derives from a history that may be all chat, so chatRetain must cover it.
        self.chatRetain = max(max(1, tailRetain), chatRetain)
        self.activityRetain = max(1, activityRetain)
    }

    // MARK: - Activity ingestion (from core showJoin / showPurchase / showWin)

    public func appendJoin(text: String) {
        append(LBFeedItem(kind: .activity(tier: .join), text: text))
    }

    public func appendPurchase(text: String) {
        append(LBFeedItem(kind: .activity(tier: .purchase), text: text))
    }

    /// 觀眾選購（chat-message-taxonomy ⑤ `kind == .narrate`，`#66F796`，上游 `ty=ds`）→ feed
    /// 社會認同 activity row（「{觀眾名} 正在選購商品～」）。**性質同 join**——是觀眾行為、
    /// **非主播訊息、非購買、非「商品介紹中」**（介紹中改由 goods `is_narrating` 在商品列呈現）。
    /// 依設計稿 chat5 定案，以**自己的低調 `.browse` tier**（與 `join` 同級）呈現，解除先前
    /// 「最終視覺 tier DECISION-PENDING」。push 無 stable id → 走 activity 去重（簽名涵蓋
    /// `.browse` tier + text）。
    public func appendNarrate(text: String) {
        append(LBFeedItem(kind: .activity(tier: .browse), text: text))
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

    /// chat row（push / comment）。`isHost` / `replyText` / `isAI` 為**群組① 真正的聊天**的
    /// 角色 metadata（chat-message-taxonomy ⑤），供 reference-ui 依版型區分主播留言 / 主播回覆 /
    /// AI 回覆；皆帶預設值，使既有觀眾留言（`.comment`）呼叫點 byte-identical。`replyText` 為
    /// 後端 `LBPushMsg.reply` 帶來的獨立引用字串（NOT split from `text`）。
    public func appendChat(text: String, name: String? = nil,
                           isHost: Bool = false, replyText: String? = nil, isAI: Bool = false) {
        // Normalize the author nickname: a missing / blank name → nil so the
        // reference-ui falls back to its text-only chat row (chat-nickname-display).
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let userName = (trimmed?.isEmpty == false) ? trimmed : nil
        // Normalize the quoted reply: blank → nil（無引用框）。
        let trimmedReply = replyText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let reply = (trimmedReply?.isEmpty == false) ? trimmedReply : nil
        append(LBFeedItem(kind: .chat, text: text, userName: userName,
                          isHost: isHost, isAI: isAI, replyText: reply))
    }

    /// A SYSTEM / 商品推播 notice (e.g. 「商品開賣」) surfaced as a chat row but DE-DUPED. The
    /// poll `push[]` bucket carries no stable id, so the backend re-sending the same system
    /// notice on an adjacent poll would otherwise appear twice. Unlike free user chat (which
    /// legitimately repeats and is NEVER de-duped), an identical system notice (signature
    /// `cs|<text>`) within the bounded recent-seen window is dropped SILENTLY (no append, no
    /// `onMutation`). Routed here by `DefaultPlayerTemplate.handlePush` for product/event/promo
    /// pushes (`color == productPushColor` / `eid > 0` / `ct` / `p`).
    public func appendSystemNotice(text: String) {
        // **不再傳 dedupeKey**（chat-history-dedupe-template）：`cs|<text>` 內容指紋會誤殺後台刻意
        // 重送的相同內容真實系統通知。相鄰輪重送防重複改由 cursor-based backlog 分流承擔。
        append(LBFeedItem(kind: .chat, text: text))
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

    /// True while a `batchIngest(_:)` batch is in progress (live-chat-backlog-batch-ingest-template).
    /// While set, `append(_:)` still writes into `history` immediately (preserving the existing
    /// dedupe-signature check's semantics), but SKIPS the per-call per-type trim and
    /// `onMutation` fan-out — those are deferred to `batchIngest`'s single end-of-batch step.
    /// Non-reentrant by construction: `ingestBacklog` is the only caller and never nests batches.
    private var isBatching = false

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
        // Append to the deep `history` buffer; the ambient `items` slice (newest N=7) is
        // derived from it.
        history.append(item)
        // Inside a `batchIngest` batch, the trim + notify are deferred to the batch's single
        // end-of-batch step (live-chat-backlog-batch-ingest-template) — see that method's doc.
        guard !isBatching else { return }
        // Separate per-type retention (chat-activity-separate-retention-ios-template): chat rows
        // are trimmed independently of activity rows, so a busy stream's activity churn never
        // evicts real chat.
        history = Self.trimmedByType(history, chatCap: chatRetain, activityCap: activityRetain)
        // One append == one coalesced mutation (no redraw storm; each event
        // notifies exactly once).
        onMutation?()
    }

    /// Pure: keeps the last `cap` elements of `items` (a single, one-shot trim), or returns
    /// `items` unchanged when already within `cap`. A GENERIC single-cap primitive retained as a
    /// building block (and exercised directly by unit tests with an explicit `cap:`); the live
    /// merged-feed trim is now `trimmedByType(_:chatCap:activityCap:)` (chat-activity-separate-
    /// retention-ios-template), which no longer uses one shared cap. NOTE (design.md D1): for a
    /// FIXED append order, trimming after every append vs. trimming once at the end produce the
    /// IDENTICAL final result — this function alone does not fix an ordering bug.
    static func trimmed(_ items: [LBFeedItem], cap: Int) -> [LBFeedItem] {
        items.count > cap ? Array(items.suffix(cap)) : items
    }

    /// Pure: enforce SEPARATE retention caps per row type on a chronologically-ordered buffer
    /// (newest at the tail), preserving the survivors' original chronological interleaving
    /// (chat-activity-separate-retention-ios-template). CHAT rows (`kind == .chat`) are kept up to
    /// `chatCap`; every OTHER row (the "activity bucket": `.activity` / `.eventJoin` /
    /// `.productSale`) is kept up to `activityCap`. The two caps are independent — trimming one
    /// type never removes rows of the other — so real chat is NEVER evicted by activity rows.
    /// When a type exceeds its cap, its OLDEST rows are dropped (walk from the head, skipping the
    /// oldest surplus of each type). O(n), no sort. `items` (newest `tailRetain` of the result)
    /// therefore still reflects the newest rows overall, keeping its contract unchanged.
    static func trimmedByType(_ items: [LBFeedItem], chatCap: Int, activityCap: Int) -> [LBFeedItem] {
        let chatCount = items.reduce(0) { $0 + ($1.kind == .chat ? 1 : 0) }
        let activityCount = items.count - chatCount
        // Fast path: nothing exceeds its cap → identical result to no trim.
        if chatCount <= chatCap && activityCount <= activityCap { return items }
        var chatToDrop = max(0, chatCount - chatCap)
        var activityToDrop = max(0, activityCount - activityCap)
        var result: [LBFeedItem] = []
        result.reserveCapacity(items.count - chatToDrop - activityToDrop)
        for item in items {
            if item.kind == .chat {
                if chatToDrop > 0 { chatToDrop -= 1; continue }
            } else if activityToDrop > 0 {
                activityToDrop -= 1
                continue
            }
            result.append(item)
        }
        return result
    }

    /// Run `body` as ONE atomic ingest batch (live-chat-backlog-batch-ingest-template): every
    /// `appendXXX` call made inside `body` (via the existing per-kind entry points — this does
    /// NOT introduce a new item-construction path) accumulates into `history` without the
    /// per-call per-type trim or `onMutation` firing; both are applied EXACTLY ONCE after
    /// `body` returns. This matters for the messages `is_init` backlog round, which can deliver
    /// up to 500 items in one poll response — feeding that through the live per-item path would
    /// otherwise trim 500 times and fan out up to 500 redundant host-facing notifications for one
    /// screen paint. `onMutation` fires only if `history` actually changed (a batch that appends
    /// nothing — e.g. an empty backlog — stays silent, matching the live path's behaviour where a
    /// no-op call never notifies).
    func batchIngest(_ body: () -> Void) {
        let before = history
        isBatching = true
        body()
        isBatching = false
        history = Self.trimmedByType(history, chatCap: chatRetain, activityCap: activityRetain)
        if history != before {
            onMutation?()
        }
    }

    /// De-dup signature for a feed row. **所有 kind 現在皆回 `nil`（不做內容指紋去重）**：`.chat`
    /// 一向 nil（兩人同字合法）；`.activity` / `.productSale` 於 chat-history-dedupe-template 移除；
    /// `.eventJoin` 於 chat-event-message-no-dedupe-template 移除（活動公告會被刻意重播，每筆都顯示）。
    /// 後端 push 無單則 id，內容指紋去重會誤殺後台刻意重送的真實通知；機制性 backlog 重放的防重複改由
    /// cursor 分流承擔（chat-history-dedupe，含跨重入保存）。本函式保留為去重 seam（`append` 仍支援顯式
    /// `dedupeKey`），目前無 caller 產生非 nil 簽名。
    static func dedupeSignature(for item: LBFeedItem) -> String? {
        switch item.kind {
        case .chat:
            return nil
        case .activity:
            // 進場 / 購買 / 選購 / 中獎跑馬燈：**移除內容指紋去重**（chat-history-dedupe-template）——
            // `a<tier>|<text>` 會誤殺後台「推廣活動」刻意重送的相同內容真實通知。相鄰輪重送的防重複
            // 改由 TemplateAttachment 的 cursor-based backlog 分流承擔（後續輪照顯示、首輪 backlog 抑制）。
            return nil
        case .eventJoin:
            // 活動公告（`kind=event`）：**移除內容指紋去重**（chat-event-message-no-dedupe-template）——
            // 直播主把活動公告當「循環提醒」刻意重播多次（live 實測：messages 首輪 backlog 內同 `eid`
            // 連續多筆），`e<eid>|<text>` 內容指紋去重會把這些真實重播誤塌成一筆。比照其他真實訊息每筆都
            // 顯示；機制性 backlog 重放的防重複改由 cursor 分流承擔（chat-history-dedupe / 跨重入保存）。
            // CTA 顯示與否仍由 reference-ui 依 keyword（push.ek）isset 決定（event-join-cta-isset-ek）。
            return nil
        case .productSale:
            // 商品開賣：**移除內容指紋去重**（同 activity 理由）。相鄰輪重送由 backlog 分流承擔。
            return nil
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

    /// Wholesale-replaces `history` with a previously-saved snapshot — used to restore a
    /// per-videoId cached feed when an in-place video switch returns to a video already visited
    /// earlier in this same session (`chat-history-video-switch-cache-template`), instead of
    /// leaving the feed empty after a `clear()`. Applies the same separate per-type caps as
    /// ordinary ingestion (defensive; a saved snapshot is already within cap) and resets the
    /// de-dup window (mirrors `clear()` — the restored history is a distinct data set from
    /// whatever produced the currently-tracked signatures). Fires `onMutation` exactly once,
    /// symmetric with `clear()`, regardless of whether `items` is empty.
    public func restore(_ items: [LBFeedItem]) {
        history = Self.trimmedByType(items, chatCap: chatRetain, activityCap: activityRetain)
        recentActivitySignatures.removeAll()
        onMutation?()
    }
}
