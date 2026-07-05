import SwiftUI
import LiveBuySDK
import LiveBuyUI

// MARK: - ChatFeedView — family-2 surface 1 (merged chat-feed stream)
//
// Spec: `reference-ui-rendering/spec.md` (family-2 feed-win, surface 1)
// Design: rb-ios-feed-win design.md D-2 (`moments.jsx` `LBLiveChatStream` /
// `LBChatLine` / `LBEventJoinLine` / `LBActivityLine`; `live-chrome.jsx`
// `LBLiveChatOverlay`).
//
// The merged, bottom-anchored translucent chat-feed stream layered over the live
// video area. Mirrors `moments.jsx` `LBLiveChatStream`: a left-aligned vertical
// stack with the NEWEST row at the BOTTOM and a top gradient mask that fades the
// oldest rows out, exactly like `live-chrome.jsx` `LBLiveChatOverlay`.
//
// It dispatches each `LBFeedItem` BY `kind` into one row type:
//
//   • `.chat`              → LBChatLine   — name-colored avatar + translucent
//                                            bubble carrying the prebuilt `text`.
//   • `.eventJoin`         → LBEventJoinLine — ticket chip + 2-line keyword copy +
//                                            「加入活動」CTA / 「已參加」joined state.
//                                            The ONLY interactive row.
//   • `.activity(tier:)`   → LBActivityLine  — tier-styled pill (`.join` lowest-key
//                                            translucent / `.purchase` dark + accent
//                                            border / `.win` accent-gradient highlight).
//
// CONTRACT (FeedWinOverlayView.swift "SUB-VIEW INPUT PATTERN"):
//   • FIRST positional arg is `theme:`. The feed is passed BY VALUE (`[LBFeedItem]`).
//   • The action closure is LAST and defaults to nil. The container forwards the
//     event-join intent through `FeedWinModel.joinEvent` → template upstream exit
//     (host wired); THIS LAYER NEVER JOINS ITSELF — it only surfaces the tap.
//   • Reads ONLY its passed-in `items`; never reaches back into `FeedWinModel` /
//     `DefaultPlayerTemplate` (one-way data flow, D-1).
//   • `text` is the backend-prebuilt, i18n-complete full string — rows MUST NOT
//     split it into userName / goodsName fields (D-2 / CLAUDE feed invariant).
//     The data layer already merged / ordered / tail-retained (N=7); this layer
//     MUST NOT slice / merge / re-sort.
//
// iOS-14-safe: `ZStack` / `VStack` / `HStack` / `LinearGradient` / `.mask` are all
// iOS-13+. No >14 API is used here, so no `@available` guard is needed.

/// The family-2 merged chat-feed stream surface. Paints the bottom-anchored,
/// newest-at-bottom translucent feed over the video area, dispatching each
/// `LBFeedItem` to its row renderer and themed by the resolved `ReferenceUITheme`.
public struct ChatFeedView: View {

    /// The resolved reference-ui theme (first positional argument, always).
    public let theme: ReferenceUITheme

    /// The merged, ordered, tail-retained feed snapshot (`DefaultActivityFeed
    /// .items`), passed BY VALUE from `FeedWinModel.feedItems`. Already merged /
    /// ordered by the data layer — this view renders it verbatim, oldest → newest
    /// top → bottom.
    public let items: [LBFeedItem]

    /// The「加入活動」intent for the (only) interactive `.eventJoin` row. The
    /// container forwards this to `FeedWinModel.joinEvent(eid:keyword:)` → template
    /// upstream exit (host wired). nil → the join CTA renders but is inert (demo /
    /// snapshot). This layer NEVER joins itself.
    ///
    /// NOTE on the label: the do-not-touch container (`FeedWinOverlayView.swift`)
    /// documents and calls this argument as `onJoinEvent: (eid, keyword) -> Void`,
    /// so the label MUST be `onJoinEvent` to keep the container call site compiling.
    /// (The task brief named it `onTapEventJoin((eid:Int)->Void)?`; the container's
    /// pattern is the binding contract and additionally needs `keyword` to drive the
    /// template upstream exit `joinEvent(eid:keyword:)`, so the container shape wins.)
    public let onJoinEvent: ((_ eid: Int, _ keyword: String) -> Void)?

    /// 商品開賣卡「立即搶購」intent (問題5 / product-sale-card-buy-tap). The container forwards this
    /// to `FeedWinModel.openSaleProduct(name:)` → template `openProductSaleByName(name)` (which
    /// resolves the 商品名 → `channel.goods` → opens that product's detail sheet). nil (demo /
    /// snapshot) → the 立即搶購 CTA renders but is inert. This layer NEVER opens detail itself.
    public let onTapSaleBuy: ((_ name: String) -> Void)?

    /// Scrollable history gate (default `false`, sharing the widget `hostScrollable`
    /// convention + the reference-ui "no `ScrollView` on the snapshot path" invariant).
    /// `false` (demo / snapshot / `ImageRenderer`) → the existing pure-`VStack` bottom-
    /// anchored path (no `ScrollView`, baseline byte-identical). `true` (runtime) → a
    /// `ScrollView` variant so the user can scroll UP to view history (the container
    /// then passes the deeper `DefaultActivityFeed.history` as `items`).
    public let hostScrollable: Bool

    /// 置頂留言（chat-pinned-message-render ⑤c）。非 nil → feed 上緣渲染置頂橫幅；nil（預設 /
    /// demo / snapshot）→ 不出任何置頂像素（baseline byte-identical）。
    public let pinned: LBPinnedMessage?

    /// 主播名稱（`FeedWinModel.hostName` ← `DefaultPlayerTemplate.header.hostName`），純顯示 —
    /// 餵給 `.eventJoin` 列的主播名 + 「主播」badge header（`rb-ios-loading-announce-restyle`）。
    /// 預設 `""` 維持既有呼叫端（未接 `FeedWinModel` 的 demo / snapshot）原始碼相容；空字串 →
    /// `LBEventJoinLineRow` 不畫名字列，其餘 row kind 不受影響。
    public let hostName: String

    /// Auto-stick to the newest row. Starts true; a manual scroll-up (drag) stops it
    /// so the user can read history without being yanked back. Scrollable variant only.
    /// NOTE: this flag now ONLY governs whether a NEW message auto-scrolls to the
    /// newest row — it NO LONGER decides the "↓ latest" pill's visibility (that is
    /// driven by real scroll position via `atBottom`, see `scrollableBody`), so a
    /// switch-swipe that transiently flips this to false can no longer leave the pill
    /// stuck on the next video (`rb-ios-chat-feed-pill-scroll-position`).
    @State private var autoStick: Bool = true

    /// Whether the bottom anchor is currently pinned to the scroll viewport's bottom
    /// (= the user is at the newest row, OR the content is shorter than the viewport so
    /// there is no history to return to). Maintained from a `PreferenceKey` reporting the
    /// bottom anchor's `maxY` in the scroll coordinate space. The "↓ 最新訊息" pill shows
    /// ONLY while `!atBottom`, so an empty / short feed (every post-switch feed for the
    /// first poll window) keeps the pill hidden BY CONSTRUCTION — independent of switch
    /// timing or the gesture race that flips `autoStick`. Scrollable variant only.
    @State private var atBottom: Bool = true

    public init(theme: ReferenceUITheme,
                items: [LBFeedItem],
                hostScrollable: Bool = false,
                pinned: LBPinnedMessage? = nil,
                hostName: String = "",
                onJoinEvent: ((_ eid: Int, _ keyword: String) -> Void)? = nil,
                onTapSaleBuy: ((_ name: String) -> Void)? = nil) {
        self.theme = theme
        self.items = items
        self.hostScrollable = hostScrollable
        self.pinned = pinned
        self.hostName = hostName
        self.onJoinEvent = onJoinEvent
        self.onTapSaleBuy = onTapSaleBuy
    }

    public var body: some View {
        // `hostScrollable == false` keeps the original pure-VStack path (no ScrollView)
        // so the snapshot / `ImageRenderer` baseline stays byte-identical; `true` swaps
        // in the scroll-up-for-history variant (runtime only). `topOverlayStack` is mounted
        // INSIDE `staticBody` / `scrollableBody` (rb-ios-activity-toast-position-fix), not as
        // an `.overlay` here — see the rationale on `topOverlayStack` below.
        feedBody
    }

    /// Activity-notification toast (rb-ios-activity-toast) stacked above the pinned banner
    /// (`chat-pinned-message-render` ⑤c), mirroring `LBLiveChatStream`'s `gap:6` column
    /// ([ActivityToast, PinnedMessage, feed]).
    ///
    /// rb-ios-activity-toast-position-fix: mounted as a LAYOUT-PARTICIPATING sibling directly
    /// above the row content INSIDE `staticBody` / `scrollableBody`'s bottom-anchored stack —
    /// NOT as an `.overlay(_:alignment: .topLeading)` on the full-height `feedBody` (the prior
    /// approach). `feedBody`'s outer frame is stretched to `maxHeight: .infinity` (needed so
    /// the full-bleed swipe / tap-to-mute gesture area still covers the whole player — see
    /// `staticBody` / `scrollableBody`), so a `.topLeading` overlay anchored to THAT frame
    /// lands near the top of the entire player, not above the actual bottom-packed visible
    /// rows — that was the bug (toast rendering with a large empty gap above the chat, near
    /// the screen top). Moving it INSIDE the same bottom-anchored `VStack` as the rows means
    /// it moves DOWN together with them, landing directly above the visible content —
    /// matching Android/RN/Flutter's wrap-content-bottom-anchored pattern and the design
    /// source (`moments.jsx` `LBLiveChatStream`: `[ActivityToast, PinnedMessage, feed]` inside
    /// ONE `flexDirection:'column'` block whose bottom edge is fixed and top edge grows with
    /// content — the SwiftUI equivalent of a leading `Spacer` + intrinsically-sized content).
    ///
    /// Gated on `hasActivityItem` (a plain `if`, no `else`) so that when `items` has NO
    /// `.activity` item at all — `ActivityToastView` can then structurally never show
    /// anything — this branch contributes ZERO children/spacing to the parent stack
    /// (SwiftUI's well-known spacing-collapse for an `if`-without-`else` that evaluates
    /// false). That keeps the 3 existing baselines with no `.activity` item
    /// (`chat-feed-nickname-demo` / `chat-feed-chat-roles` /
    /// `chat-feed-event-announcement-no-cta`) byte-identical — this view is never even
    /// instantiated for them, so there is no ambiguity about whether an idle
    /// `ActivityToastView`'s own (possibly non-`EmptyView`) empty rendering would still
    /// consume stack spacing. `pinnedBanner`'s own `if let` collapses the same way when
    /// `pinned == nil`. The `.padding(.bottom, 6)` supplies the gap before the next sibling
    /// (first row / scroll region) ONLY when this block actually renders something, so the
    /// "nothing to show" case leaves `staticBody` / `scrollableBody`'s OWN pre-existing
    /// `Spacer` → next-sibling adjacency (and its spacing value) completely unchanged.
    @ViewBuilder
    private var topOverlayStack: some View {
        if hasActivityItem || pinned != nil {
            VStack(alignment: .leading, spacing: 6) {
                if hasActivityItem {
                    ActivityToastView(theme: theme, items: items)
                }
                pinnedBanner
            }
            .padding(.bottom, 6)
        }
    }

    /// Whether `items` contains ANY `.activity` item — i.e. whether `ActivityToastView` could
    /// EVER show something for this feed (reuses `ActivityToastTrigger.latestActivity`). Pure
    /// — no side effects. See `topOverlayStack` for why this gates mounting the toast at all.
    private var hasActivityItem: Bool {
        ActivityToastTrigger.latestActivity(in: items) != nil
    }

    @ViewBuilder
    private var feedBody: some View {
        if hostScrollable {
            scrollableBody
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(LBAccessibilityID.chatFeed)
        } else {
            staticBody
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(LBAccessibilityID.chatFeed)
        }
    }

    /// 置頂橫幅；無置頂 → 空（不出像素）。
    @ViewBuilder
    private var pinnedBanner: some View {
        if let pinned = pinned {
            PinnedMessageBanner(theme: theme, pinned: pinned)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(LBAccessibilityID.pinnedBanner)
        }
    }

    /// `items` with `.activity(tier:)` items excluded (rb-ios-activity-toast, design D-4):
    /// group② 炒氣氛提示 no longer renders as inline rows — it is surfaced by the sibling
    /// `ActivityToastView` (see `topOverlayStack`). This is the SINGLE policy point deciding
    /// which kinds render as rows; `row(for:)` stays a pure per-kind dispatcher. Pure — no
    /// side effects, order-preserving (oldest → newest, unchanged from `items`).
    private var visibleItems: [LBFeedItem] {
        items.filter { !$0.isActivity }
    }

    /// The original bottom-anchored, newest-at-bottom column with a top fade mask
    /// (`LBLiveChatStream`). NO `ScrollView` — used by demo / snapshot (baseline path).
    private var staticBody: some View {
        VStack(alignment: .leading, spacing: Self.rowGap) {
            // `Spacer` pins the content to the bottom so the NEWEST (last) row sits
            // lowest — matching the design's bottom-anchored newest-at-bottom flow.
            Spacer(minLength: 0)
            // rb-ios-activity-toast-position-fix: mounted HERE (inside the same
            // bottom-anchored stack as the rows) so it moves down together with them and
            // sits directly above the topmost visible row — see `topOverlayStack`.
            topOverlayStack
            ForEach(Array(visibleItems.enumerated()), id: \.offset) { index, item in
                row(for: item)
                    // `.contain` keeps the row a single addressable container while
                    // leaving its inline controls (eventJoinCta / saleBuy) as
                    // separately-queryable children — without it the row id shadows
                    // the inner button (rb-ios-e2e-feed-row-contain).
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier(Self.rowAccessibilityID(for: item, index: index))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .mask(Self.topFadeMask)
    }

    /// Scroll-up-for-history variant (runtime, `hostScrollable == true`). Bottom-pins
    /// short content (so few rows still sit at the bottom like the ambient overlay) and
    /// scrolls when content exceeds the viewport; sticks to the newest row unless the
    /// user scrolled up, with a "↓ 最新訊息" pill to return to live. Same top fade mask
    /// + row dispatch as `staticBody`. iOS-14-safe (`ScrollViewReader` / `onChange` /
    /// `scrollTo(_:anchor:)` are iOS-13/14+; `.overlay(_:alignment:)` is iOS-13+).
    private var scrollableBody: some View {
        GeometryReader { geo in
            // The scroll area is BOUNDED to the lower portion (anchored bottom). The
            // empty `Spacer` above it has NO hit-testing, so the player's full-bleed
            // gestures (swipe up/down to change video, tap to mute) keep passing through
            // the upper area — a full-bleed `ScrollView` would otherwise eat them. The
            // smaller viewport also lets scrolling engage with far fewer rows.
            let viewport = geo.size.height * Self.scrollableHeightFraction
            // `alignment: .leading` (was default `.center`) so `topOverlayStack` sits flush
            // left like the rows below it, matching the design's `left:8` column — the
            // ScrollView is unaffected (it always claims the full proposed width regardless
            // of the stack's alignment, being a flexible, not intrinsically-sized, child).
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)
                // rb-ios-activity-toast-position-fix: sits directly above the scroll
                // viewport (mirroring `staticBody`), instead of at the top of the whole
                // player. See `topOverlayStack`.
                topOverlayStack
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: Self.rowGap) {
                            Spacer(minLength: 0)   // bottom-pin short content
                            ForEach(Array(visibleItems.enumerated()), id: \.offset) { index, item in
                                row(for: item)
                                    // `.contain` — see staticBody (rb-ios-e2e-feed-row-contain).
                                    .accessibilityElement(children: .contain)
                                    .accessibilityIdentifier(Self.rowAccessibilityID(for: item, index: index))
                            }
                            // Zero-height bottom anchor for scrollTo(anchor: .bottom) AND the
                            // scroll-position probe: its `maxY` in the scroll coordinate space
                            // tells us whether the newest row is pinned to the viewport bottom.
                            Color.clear.frame(height: 0.5).id(Self.bottomAnchorID)
                                .background(GeometryReader { anchor in
                                    Color.clear.preference(
                                        key: BottomAnchorMaxYKey.self,
                                        value: anchor.frame(in: .named(Self.scrollSpace)).maxY)
                                })
                        }
                        .frame(minHeight: viewport, alignment: .bottom)
                    }
                    .frame(height: viewport)
                    .coordinateSpace(name: Self.scrollSpace)
                    .mask(Self.topFadeMask)
                    // Detect a manual scroll WITHOUT stealing the scroll gesture → stop
                    // auto-sticking so a NEW message does not yank the user back while they
                    // read history. This NO LONGER governs the pill (scroll position does).
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 6).onChanged { _ in autoStick = false })
                    // New rows arrive: stick to newest only if the user hasn't scrolled up.
                    // Keyed on `visibleItems.count` (not `items.count`) so an `.activity`
                    // arrival — which produces NO row (rb-ios-activity-toast) — does not
                    // trigger a no-op scroll-to-bottom.
                    .onChange(of: visibleItems.count) { _ in
                        guard autoStick else { return }
                        withAnimation(.easeOut(duration: 0.18)) {
                            proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
                        }
                    }
                    // REAL scroll position: the bottom anchor's maxY vs the viewport bottom.
                    // `atBottom` drives the pill; reaching the bottom (incl. a freshly cleared /
                    // short post-switch feed, which is bottom-pinned) auto-resumes auto-stick.
                    // This supersedes the prior fragile `onChange(of: items.isEmpty)` reset
                    // (`rb-ios-chat-feed-pill-scroll-position`).
                    .onPreferenceChange(BottomAnchorMaxYKey.self) { maxY in
                        let nowAtBottom = maxY <= viewport + Self.atBottomEpsilon
                        atBottom = nowAtBottom
                        if nowAtBottom { autoStick = true }
                    }
                    .onAppear { proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom) }
                    // "↓ 最新訊息" return-to-live pill, shown only while scrolled away from
                    // the bottom (real scroll position, not the auto-stick flag).
                    .overlay(returnToLatestPill(proxy: proxy), alignment: .bottom)
                }
            }
        }
    }

    /// Accent "↓ 最新訊息" pill — visible only when the user is scrolled AWAY from the
    /// bottom (`atBottom == false`, real scroll position); tapping returns to the newest
    /// row and re-sticks. Driving this off scroll position (not `autoStick`) keeps it
    /// hidden for an empty / short feed, so a switch-swipe race can no longer leave it
    /// stuck on the next video.
    @ViewBuilder
    private func returnToLatestPill(proxy: ScrollViewProxy) -> some View {
        if !atBottom {
            Button(action: {
                autoStick = true
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 10, weight: .bold))
                    Text(Self.returnToLatestLabel)
                        .font(.system(size: 11.5 * theme.fontScale, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(theme.accent))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 6)
            .accessibilityIdentifier(LBAccessibilityID.chatScrollToBottom)
        }
    }

    // MARK: - Row dispatch by LBFeedItem.kind (D-2)

    /// Per-item E2E accessibility id, routed by `kind`: a `.chat` row → `chatLine`,
    /// every activity / notification / event-join / product-sale row → `activityLine`
    /// (the index is the feed loop offset). Pure — no side effects.
    static func rowAccessibilityID(for item: LBFeedItem, index: Int) -> String {
        switch item.kind {
        case .chat:
            return LBAccessibilityID.chatLine(index)
        case .eventJoin, .activity, .productSale:
            return LBAccessibilityID.activityLine(index)
        }
    }

    /// Dispatch a feed item to its row renderer by `kind`.
    @ViewBuilder
    private func row(for item: LBFeedItem) -> some View {
        switch item.kind {
        case .chat:
            LBChatLineRow(theme: theme, text: item.text, userName: item.userName,
                          isHost: item.isHost, isAI: item.isAI, replyText: item.replyText)
        case .eventJoin:
            LBEventJoinLineRow(
                theme: theme,
                text: item.text,
                // 主播名（純顯示，rb-ios-loading-announce-restyle）：`ChatFeedView.hostName` ←
                // `FeedWinModel.hostName`；空字串（未接 model 的呼叫端）→ 不畫名字列。
                userName: hostName,
                // 後端「ek isset 才顯示 CTA」：keyword 非空 → 加入活動 CTA；空（活動結束 / goods 未含
                // 該 event，template 帶入 "")→ 純活動公告無 CTA（問題 1）。
                hasCTA: !(item.keyword ?? "").isEmpty,
                joined: item.joined,
                onJoin: {
                    // Surface the tap; forward via the container's closure. nil →
                    // inert. This layer NEVER joins itself.
                    if let eid = item.eid {
                        onJoinEvent?(eid, item.keyword ?? "")
                    }
                })
        case .activity:
            // rb-ios-activity-toast: `.activity(tier:)` no longer renders as an inline row
            // (moments.jsx 2026-07-03 `LBLiveChatStream` `feed = items.filter(m => m.kind !==
            // 'activity')`) — it is surfaced via the sibling `ActivityToastView` instead
            // (mounted above this list in `ChatFeedView.topOverlayStack`). Callers MUST filter
            // `.activity` items out of the rendered rows before reaching this dispatcher
            // (`visibleItems`), so this branch is UNREACHABLE by construction; it exists only
            // to satisfy Swift's exhaustive switch over `LBFeedItem.Kind` (defined in
            // `LiveBuyUI`, not modifiable here). `EmptyView()` keeps a misuse silent rather
            // than crashing.
            EmptyView()
        case .productSale:
            // chat5 群組①「商品開賣」→ 醒目商品開賣卡（設計 `LBProductSaleCard`）：商品名 = `text`、
            // 現價 = `price`（已格式化）。demo seed 無 `.productSale` → 既有 golden byte-identical。
            // 「立即搶購」(問題5)：綁定時帶商品名上拋（容器 → openSaleProduct）；未綁定 → onTapBuy nil → inert。
            LBProductSaleCardRow(
                theme: theme, name: item.text, price: item.price ?? "",
                onTapBuy: onTapSaleBuy.map { cb in { cb(item.text) } })
        }
    }

    // MARK: - Layout tokens (design)

    /// Inter-row gap (`LBLiveChatStream` `gap: 5`).
    static let rowGap: CGFloat = 5

    /// Identity of the zero-height bottom anchor used by `scrollTo(anchor: .bottom)`
    /// in the scrollable variant.
    static let bottomAnchorID = "lb-chat-feed-bottom"

    /// Named coordinate space of the scrollable variant's `ScrollView`, so the bottom
    /// anchor's `frame(in:).maxY` is measured relative to the (fixed) viewport.
    static let scrollSpace = "lb-chat-feed-scroll"

    /// Slack (pt) when deciding "bottom anchor is at the viewport bottom" — absorbs the
    /// 0.5pt anchor height, the pill overlay, and layout fuzz so a genuine bottom does
    /// not flicker the pill on. Scrollable variant only.
    static let atBottomEpsilon: CGFloat = 24

    /// "↓ 最新訊息" return-to-live pill label (scrollable variant).
    static let returnToLatestLabel = "最新訊息"

    /// Fraction of the available height the SCROLLABLE chat occupies (anchored bottom).
    /// The remaining upper area stays empty so the player's full-bleed gestures (swipe to
    /// change video, tap to mute) pass through; a smaller viewport also lets scrolling
    /// engage with fewer rows. Scrollable variant only — the static path is unaffected.
    /// Lowered 0.46 → 0.38 (rb-ios-chat-feed-lower-height) so the upper pass-through
    /// region grows ~54%→~62%, making swipe-to-switch-video easier to trigger.
    static let scrollableHeightFraction: CGFloat = 0.38

    /// Top fade gradient mask (`maskImage: linear-gradient(to top, #000 58%,
    /// transparent)`): rows are fully opaque for the lower 58% and fade to clear
    /// toward the top so the oldest rows dissolve.
    static var topFadeMask: some View {
        LinearGradient(
            gradient: Gradient(stops: [
                .init(color: .clear, location: 0.0),
                .init(color: .black, location: 0.42),
                .init(color: .black, location: 1.0),
            ]),
            startPoint: .top,
            endPoint: .bottom)
    }

    // MARK: - Deterministic demo factory (D-1)

    /// A deterministic `ChatFeedView` for previews / snapshot tests: a fixed feed
    /// covering all four row kinds (chat / eventJoin / activity .join / .purchase /
    /// .win) painted with the supplied theme, with NO action wired (so it renders
    /// inert and stable). Mirrors `moments.jsx` `useActivityStream` seed copy.
    public static func demo(theme: ReferenceUITheme = ReferenceUIThemePalette.minimal) -> ChatFeedView {
        ChatFeedView(theme: theme, items: demoFeed)
    }

    /// Deterministic demo feed (oldest → newest), mirroring the design seed in
    /// `moments.jsx` `useActivityStream` plus one `.eventJoin` row so all four row
    /// kinds and all FOUR activity tiers (join / purchase / intro / win) are
    /// exercised in the snapshot baseline.
    public static let demoFeed: [LBFeedItem] = [
        LBFeedItem(kind: .chat, text: "Boa 博士心動 💛"),
        LBFeedItem(kind: .activity(tier: .join), text: "王小明 剛剛加入"),
        LBFeedItem(kind: .eventJoin,
                   text: "🎉 抽獎開始！留言「抽獎」即可參加",
                   eid: 8821, keyword: "抽獎", joined: false),
        LBFeedItem(kind: .activity(tier: .intro), text: "開始介紹「玫瑰精華水 150ml」"),
        LBFeedItem(kind: .chat, text: "CoCo 這個顏色好美 😍"),
        LBFeedItem(kind: .activity(tier: .purchase), text: "Mia 購買了「絲絨唇釉 #04 焦糖」"),
        LBFeedItem(kind: .activity(tier: .win),
                   text: "boacat77 中獎了！",
                   winner: LBWinner(
                       id: "p_77",
                       eventId: 8821,
                       title: "週年慶抽獎",
                       award: LBAward(type: "product", code: "SKU_77", name: "限量好禮"))),
    ]
}

// MARK: - BottomAnchorMaxYKey — scroll-position probe for the scrollable feed
//
// Reports the bottom anchor's `maxY` within the scrollable feed's named coordinate
// space. When the newest row is pinned to the viewport bottom (at-bottom, or content
// shorter than the viewport) the value ≈ the viewport height; once the user scrolls
// up it grows past the viewport. `ChatFeedView.scrollableBody` compares it against
// `viewport + atBottomEpsilon` to drive `atBottom` (and thus the "↓ 最新訊息" pill).
private struct BottomAnchorMaxYKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - LBChatLineRow — single chat row (LBChatLine)
//
// Mirrors `moments.jsx` `LBChatLine`: a 22pt round name-colored avatar + a
// translucent dark bubble (radius 12). The REAL `.chat` feed item carries only a
// single backend-prebuilt `text` string (no separate user / avatar fields exist
// on `LBFeedItem` — those live only in the design's web demo). We therefore put
// the whole `text` in the bubble (NOT split) and derive a DETERMINISTIC avatar
// fill + glyph from the text so the row keeps the design's name-colored avatar
// language without parsing fields.

struct LBChatLineRow: View {
    let theme: ReferenceUITheme
    let text: String
    /// The chat author's nickname (chat-nickname-render). nil / empty → text-only
    /// row, BYTE-IDENTICAL to the pre-nickname layout (avatar keyed by `text`, bubble
    /// straight in the HStack). Non-empty → a name label above the bubble + the avatar
    /// keyed by the nickname (so one author = one stable avatar).
    var userName: String? = nil

    // MARK: - 群組① 真正的聊天角色 metadata (chat-message-taxonomy ⑤)
    /// 主播留言 / 主播回覆。`true` → accent 軌 + `crown.fill` + accent 氣泡 +「主播」實心標。
    var isHost: Bool = false
    /// AI 自動回覆。`true` → `sparkles` 軌 glyph +「AI」外框標（疊在主播回覆版型上）。
    var isAI: Bool = false
    /// 主播回覆 / AI 回覆 的被回覆引用內容。非 nil → 氣泡內加引用框（只顯引用文字）。
    var replyText: String? = nil

    /// 是否帶角色版型（主播 / 回覆 / AI）。皆 false → 走既有觀眾留言路徑（byte-identical）。
    private var hasRole: Bool { isHost || isAI || (replyText?.isEmpty == false) }

    /// Avatar derivation key: the nickname when present, else `text` (legacy).
    private var avatarKey: String { (userName?.isEmpty == false) ? userName! : text }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            slot
            // 無角色 → 既有暱稱內聯前綴氣泡（byte-identical）；有角色 → 角色版型氣泡。
            if hasRole { roleBubble } else { bubble }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 24px 圖示軌（主播 / AI = accent + glyph；觀眾 = 名字色頭像）

    @ViewBuilder
    private var slot: some View {
        if isAI {
            Circle().fill(theme.accent).frame(width: 24, height: 24)
                .overlay(Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .bold)).foregroundColor(.white))
        } else if isHost {
            Circle().fill(theme.accent).frame(width: 24, height: 24)
                .overlay(Image(systemName: "crown.fill")
                    .font(.system(size: 11, weight: .bold)).foregroundColor(.white))
        } else {
            // Name-colored avatar (24×24 round — shared rail with activity slots) —
            // deterministic from the nickname (or `text` when none). Dark glyph
            // (`#3a2e25`) reads on the pastel demo avatars (`LBChatLine` ACT_SLOT).
            Circle()
                .fill(Self.avatarColor(for: avatarKey))
                .frame(width: 24, height: 24)
                .overlay(
                    Text(Self.avatarGlyph(for: avatarKey))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color(hex: "#3a2e25") ?? .black))
        }
    }

    // MARK: - 角色版型氣泡（主播標 / 引用框 / AI 標），對齊 `LBChatLine`

    private var roleBubble: some View {
        VStack(alignment: .leading, spacing: 3) {
            // header：名字 +「主播」/「AI」標（以版型而非顏色區分）。
            HStack(spacing: 5) {
                if let name = userName, !name.isEmpty {
                    Text(name)
                        .font(.system(size: 11.5 * theme.fontScale,
                                      weight: isHost ? .bold : .semibold))
                        .foregroundColor(.white.opacity(isHost ? 0.95 : 0.66))
                        .lineLimit(1)
                }
                if isAI {
                    roleTag("AI", solid: false)
                } else if isHost {
                    roleTag("主播", solid: true)
                }
            }
            // 引用框（主播回覆 / AI 回覆）：左側直條 + 暗底，只顯引用文字（後端無引用者名）。
            if let reply = replyText, !reply.isEmpty {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.white.opacity(0.7))
                        .frame(width: 2)
                    Text(reply)
                        .font(.system(size: 10.5 * theme.fontScale, weight: .regular))
                        .foregroundColor(.white.opacity(0.82))
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(0.26)))
                .fixedSize(horizontal: false, vertical: true)
            }
            // 訊息文字。主播 / AI / 引用回覆屬權威訊息 → 不限行數完整顯示
            // （chat-host-message-full-lines-refui）。一般觀眾留言的 `bubble` 仍維持
            // `.lineLimit(2)`（避免洗頻 / 版面爆量），此處只放開角色氣泡 `roleBubble`。
            Text(text)
                .font(.system(size: 11.5 * theme.fontScale, weight: .regular))
                .foregroundColor(.white)
                .lineLimit(nil)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isHost ? theme.accent : Color.black.opacity(0.42)))
    }

    /// 名字後的角色標。`solid`=true → 白 0.22 實心（主播）；false → 透明 + 白 0.55 邊框（AI）。
    @ViewBuilder
    private func roleTag(_ label: String, solid: Bool) -> some View {
        Text(label)
            .font(.system(size: 9 * theme.fontScale, weight: .heavy))
            .foregroundColor(.white)
            .padding(.horizontal, 5)
            .frame(height: 14)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(solid ? Color.white.opacity(0.22) : Color.clear)
                    .overlay(solid ? nil : RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.white.opacity(0.55), lineWidth: 1)))
    }

    /// Translucent dark bubble. ACT_BUBBLE: radius 12, black 0.42, padding h11/v5.
    private var bubble: some View {
        bubbleText
            .lineLimit(2)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.42)))
    }

    /// The bubble content: an inline dimmed nickname prefix + the message (design
    /// `LBChatLine`), or just the message when there is no nickname. The message text is
    /// the backend-prebuilt body (NOT name-embedded — design `m.text` is the message only).
    private var bubbleText: Text {
        let body = Text(text)
            .font(.system(size: 11.5 * theme.fontScale, weight: .regular))
            .foregroundColor(.white)
        guard let userName = userName, !userName.isEmpty else { return body }
        return Text(userName)
            .font(.system(size: 11.5 * theme.fontScale, weight: .semibold))
            .foregroundColor(.white.opacity(0.72))
            + Text("  ")   // design `marginRight: 6` between name and message
            + body
    }

    /// Deterministic avatar fill from the text (one of the design's pastel demo
    /// avatar colors, `moments.jsx`), chosen by a stable hash so the same string
    /// always maps to the same color (no field parsing).
    static func avatarColor(for text: String) -> Color {
        let palette = ["#FFD7A8", "#C8E6C9", "#A8C7FA", "#FFB4A8", "#E1BEE7"]
        // Mask off the sign bit (never `abs` — `abs(Int.min)` traps) so the index
        // is always non-negative for any host string.
        let idx = (stableHash(text) & Int.max) % palette.count
        return Color(hex: palette[idx]) ?? Color.gray
    }

    /// The first character of the text as the avatar glyph (presentation-only).
    static func avatarGlyph(for text: String) -> String {
        guard let first = text.first else { return "·" }
        return String(first).uppercased()
    }

    /// A small, stable, platform-independent hash (FNV-1a over the UTF-8 bytes) so
    /// the avatar color is deterministic across runs / architectures (Swift's
    /// `String.hashValue` is seeded per-process and would break the snapshot).
    static func stableHash(_ s: String) -> Int {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 {
            h ^= UInt64(b)
            h = h &* 0x100000001b3
        }
        return Int(truncatingIfNeeded: h)
    }
}

// MARK: - LBEventJoinLineRow — event-join row (LBEventJoinLine)
//
// Mirrors the UPDATED `moments.jsx` `LBEventJoinLine` (design re-sync `c3c98733`,
// `rb-ios-loading-announce-restyle`): the row is now styled like the主播留言 host bubble
// (`LBChatLineRow.roleBubble`) rather than a standalone invite card — a 24×24 round accent
// SLOT OUTSIDE the bubble using the SAME `crown.fill` glyph as `LBChatLineRow.roleBubble`'s
// isHost avatar (the design's slot SVG path is byte-identical to the host crown path —
// confirmed against the RN/Android siblings — NOT a checkmark), on the shared 24px icon
// rail (same language as `LBActivityLineRow`), then a FLAT `theme.accent` bubble (radius 12, same fill formula as
// the host chat bubble — no gradient wash / border anymore) stacking a name+「主播」badge
// header (when `userName` is non-empty) above the 2-line keyword copy, with the「加入活動」/
// 「已參加」CTA moved BELOW the text as its own row (was inline beside the text). The ONLY
// interactive row in the stream — its tap is FORWARDED via `onJoin` (host wired); this layer
// never joins itself. (rb-ios-event-message-design-align, rb-ios-loading-announce-restyle.)

struct LBEventJoinLineRow: View {
    let theme: ReferenceUITheme
    let text: String
    /// 主播名稱（`ChatFeedView.hostName` ← `FeedWinModel.hostName` ← `DefaultPlayerTemplate
    /// .header.hostName`），純顯示 — 對齊 `LBChatLineRow.roleBubble` 的主播名 + 「主播」badge
    /// 版型。空字串（未綁定 `FeedWinModel` 的呼叫端，如各 snapshot test 直接建構 `ChatFeedView`
    /// 未帶 `hostName`）→ 不畫名字列，不影響其餘版型 / CTA gating。
    let userName: String
    /// keyword 非空 → 畫「加入活動」CTA（後端「`ek` isset 才顯示 CTA」契約，問題 1）；空 → 純活動公告
    /// （活動已結束 / goods `event[]` 未含該 event → template 帶入 keyword ""），不畫 CTA / 已參加 chip。
    let hasCTA: Bool
    let joined: Bool
    let onJoin: () -> Void

    var body: some View {
        // Shared message-row language (ACT_ROW gap 8): round crown-glyph slot OUTSIDE the
        // bubble, `.top`-aligned like `LBChatLineRow`'s avatar + bubble pairing.
        HStack(alignment: .top, spacing: 8) {
            eventSlot
            bubble
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// 24×24 round accent slot (`ACT_SLOT`) with the SAME `crown.fill` glyph as
    /// `LBChatLineRow.roleBubble`'s isHost avatar (design re-sync `c3c98733`: was `sparkles`;
    /// the design's own slot path is the host crown shape, not a checkmark), drawn OUTSIDE the
    /// bubble on the shared 24px icon rail (same shape/size as `LBActivityLineRow`'s icon slot).
    private var eventSlot: some View {
        Circle()
            .fill(theme.accent)
            .frame(width: 24, height: 24)
            .overlay(
                Image(systemName: "crown.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white))
    }

    /// Host-bubble-styled card (design re-sync `c3c98733`): flat `theme.accent` fill (SAME
    /// formula as `LBChatLineRow.roleBubble`'s `isHost` bubble — no gradient wash / border),
    /// stacking an optional name+badge header, the keyword copy, and the CTA (moved below
    /// the text, was inline beside it).
    private var bubble: some View {
        VStack(alignment: .leading, spacing: 3) {
            if !userName.isEmpty {
                hostNameHeader
            }
            // Full prebuilt text (NOT split). No fixed `maxWidth` anymore — the CTA no
            // longer shares this row, so the text can use the bubble's natural width.
            Text(text.isEmpty ? Self.defaultEventCopy : text)
                .font(.system(size: 11.5 * theme.fontScale, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if hasCTA {
                ctaRow
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 12).fill(theme.accent))
    }

    /// 主播名 + 「主播」badge header row, same formula as `LBChatLineRow.roleBubble`'s name +
    /// `roleTag("主播", solid: true)`.
    private var hostNameHeader: some View {
        HStack(spacing: 5) {
            Text(userName)
                .font(.system(size: 11.5 * theme.fontScale, weight: .bold))
                .foregroundColor(.white.opacity(0.95))
                .lineLimit(1)
            hostBadge
        }
    }

    /// 「主播」badge — white 0.22 solid capsule, same formula as `LBChatLineRow.roleTag(_:
    /// solid: true)`.
    private var hostBadge: some View {
        Text("主播")
            .font(.system(size: 9 * theme.fontScale, weight: .heavy))
            .foregroundColor(.white)
            .padding(.horizontal, 5)
            .frame(height: 14)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.22)))
    }

    /// Trailing CTA row — 加入活動 / 已參加, moved BELOW the text (design re-sync `c3c98733`:
    /// was inline beside the text).
    @ViewBuilder
    private var ctaRow: some View {
        if joined {
            joinedChip.padding(.top, 4)
        } else {
            joinButton.padding(.top, 4)
        }
    }

    /// 加入活動 CTA button — white capsule, accent text (design re-sync `c3c98733`: was accent
    /// capsule + white text), weight `.heavy` (was `.bold`).
    private var joinButton: some View {
        Button(action: onJoin) {
            Text(Self.joinLabel)
                .font(.system(size: 12 * theme.fontScale, weight: .heavy))
                .foregroundColor(theme.accent)
                .padding(.horizontal, 13)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.white))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(LBAccessibilityID.eventJoinCta)
    }

    /// 已參加 chip (`padding 11/5`, white 0.2 capsule, white 0.82 text — design re-sync
    /// `c3c98733`: was white 0.16 / white 0.72) + checkmark.
    private var joinedChip: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .heavy))
            Text(Self.joinedLabel)
                .font(.system(size: 11.5 * theme.fontScale, weight: .bold))
        }
        .foregroundColor(Color.white.opacity(0.82))
        .padding(.horizontal, 11)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.white.opacity(0.2)))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(LBAccessibilityID.eventJoinJoined)
    }

    /// 加入活動 CTA label.
    static let joinLabel = "加入活動"
    /// 已參加 joined-state label.
    static let joinedLabel = "已參加"
    /// Fallback copy when `text` is empty (`LBEventJoinLine` default copy).
    static let defaultEventCopy = "🎉 抽獎開始！留言「抽獎」即可參加"
}

// MARK: - LBActivityLineRow — tier-styled activity row (LBActivityLine)
//
// Mirrors the UPDATED `moments.jsx` `LBActivityLine`: every row shares one unified
// language — a 24×24 round icon SLOT + a rounded-12 bubble — and tiers differ ONLY
// by accent-wash intensity + icon (emphasis ASCENDING):
//   • `.join`     — 進場: lowest-key. slot 白 0.16 / grey icon; bubble 黑 0.32, NO
//                   accent, text 白 0.9, medium.
//   • `.purchase` — 購買: slot accent / white bag icon; bubble 黑 0.46 + accent 0.13
//                   wash, medium.
//   • `.intro`    — 介紹: slot accent / white megaphone icon; bubble 黑 0.46 + accent
//                   0.18 wash, medium (商品開始介紹 — 強調介於購買與中獎之間).
//   • `.win`      — 中獎: slot accent / white trophy icon; bubble 黑 0.46 + accent
//                   0.23 wash + 細框 accent 0.4 + 極淡光暈 accent 0.2, bold. NO 🎉.
//
// The design's accent wash `linear-gradient(accentXX,accentXX)` over `rgba(0,0,0,0.46)`
// = a flat accent overlay (alpha XX) on a 0.46 black base — modelled as a black-base
// RoundedRectangle with an accent-tinted overlay.

struct LBActivityLineRow: View {
    let theme: ReferenceUITheme
    let text: String
    let tier: LBActivityTier

    var body: some View {
        HStack(spacing: 8) {
            iconSlot
            Text(text)
                .font(.system(size: 11.5 * theme.fontScale, weight: textWeight))
                .foregroundColor(textColor)
                .lineLimit(2)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(bubble)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 24px icon slot (shared rail with chat avatar)

    @ViewBuilder
    private var iconSlot: some View {
        Circle()
            .fill(slotFill)
            .frame(width: 24, height: 24)
            .overlay(
                Image(systemName: glyphName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(glyphColor))
    }

    // `.browse`（觀眾選購，chat-message-taxonomy ⑤）與 `.join` 同為最低調（白 0.16 軌、黑 0.32
    // 氣泡、白 0.9 文字、medium），僅圖示不同：browse 出放大鏡（逛 / 選購語意）、join 出進場人像。
    private var slotFill: Color {
        switch tier {
        case .join, .browse: return Color.white.opacity(0.16)
        case .purchase, .intro, .win: return theme.accent
        }
    }

    private var glyphName: String {
        switch tier {
        case .join: return "person.fill.badge.plus"
        case .browse: return "magnifyingglass"
        case .purchase: return "bag"
        case .intro: return "megaphone.fill"
        case .win: return "trophy.fill"
        }
    }

    private var glyphColor: Color {
        switch tier {
        case .join, .browse: return Color.white.opacity(0.85)
        case .purchase, .intro, .win: return .white
        }
    }

    // MARK: - Rounded-12 bubble, accent-wash by tier

    @ViewBuilder
    private var bubble: some View {
        switch tier {
        case .join, .browse:
            // 進場 / 觀眾選購 — black 0.32, no accent wash（最低調，無 accent 暈染）。
            RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.32))
        case .purchase:
            washBubble(0.13)   // accent22
        case .intro:
            washBubble(0.18)   // accent2e
        case .win:
            // 中獎 — accent 0.23 wash + hairline accent border + faint glow. NO 🎉.
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.46))
                .overlay(RoundedRectangle(cornerRadius: 12).fill(theme.accent.opacity(0.23)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.accent.opacity(0.4), lineWidth: 1))
                .shadow(color: theme.accent.opacity(0.2), radius: 5, x: 0, y: 2)
        }
    }

    /// Black 0.46 base + an accent-tinted overlay (the design's `accentXX` wash).
    private func washBubble(_ wash: Double) -> some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.black.opacity(0.46))
            .overlay(RoundedRectangle(cornerRadius: 12).fill(theme.accent.opacity(wash)))
    }

    private var textColor: Color {
        (tier == .join || tier == .browse) ? Color.white.opacity(0.9) : .white
    }

    private var textWeight: Font.Weight {
        // join / purchase / intro = medium (500); win = bold (700).
        tier == .win ? .bold : .medium
    }
}

// MARK: - 商品開賣卡（chat-message-taxonomy ⑤ 群組① onsale → LBProductSaleCard）

/// 商品開賣 feed item 的醒目卡片（設計 `moments.jsx` `LBProductSaleCard`）：24px tag 軌 + 暗玻璃卡
/// （accent 邊框 + 圓角 12）＝[46×46 縮圖 placeholder] +「開賣中」徽章 + 商品名 + 現價，底部滿版
/// 「立即搶購」鈕。`name` = `push.text`（商品名）、`price` = `push.price`（已格式化開賣價，直接顯示）。
/// **PARK（後端缺）**：listPrice 刪線原價、真實縮圖 URL、搶購 deeplink → 縮圖走確定性 placeholder、
/// 搶購鈕暫 inert（無跳轉目標，待 deeplink 落地再 wire）。
struct LBProductSaleCardRow: View {
    let theme: ReferenceUITheme
    let name: String
    let price: String
    /// 「立即搶購」tap (問題5 / product-sale-card-buy-tap). nil（demo / snapshot）→ 按鈕 inert 且
    /// 渲染與綁定前 byte-identical；非 nil → 「立即搶購」變成可點按鈕（內容不變）。
    var onTapBuy: (() -> Void)? = nil

    // 暫時隱藏商品圖片與價格（後端真實縮圖 URL / 價格資料定案前，先收斂卡片為
    // 「徽章 + 商品名 + 立即搶購」）。**還原**：把對應 flag 設回 `true`（或移除 gate）即可恢復
    // 縮圖與現價——`thumbnail` 計算屬性與 `price` 參數刻意保留（資料仍流入，僅不渲染），無需改資料層。
    private static let showsThumbnail = false
    private static let showsPrice = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // 24px accent 軌 — tag 圖示（共用聊天 / 活動軌 ACT_SLOT）。
            Circle().fill(theme.accent).frame(width: 24, height: 24)
                .overlay(Image(systemName: "tag")
                    .font(.system(size: 11, weight: .bold)).foregroundColor(.white))
            card
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var card: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                // 商品圖片暫時隱藏（showsThumbnail = false）；恢復時走確定性 placeholder。
                if Self.showsThumbnail { thumbnail }
                VStack(alignment: .leading, spacing: 2) {
                    saleBadge
                    Text(name)
                        .font(.system(size: 11 * theme.fontScale, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    // 現價暫時隱藏（showsPrice = false）；恢復時直接顯示已格式化的 `price`（不補幣別前綴）。
                    if Self.showsPrice {
                        Text(price)
                            .font(.system(size: 13 * theme.fontScale, weight: .heavy))
                            .foregroundColor(.white)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            buyButton
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.62)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.accent, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // 46×46 確定性縮圖 placeholder（gradient + 商品名首字 monogram；無網路 / AsyncImage → snapshot 穩定，
    // 對齊 MiniCartView 的 ProductMock placeholder）。真實縮圖 URL 待後端。
    private var thumbnail: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(hex: "#FFD7A8") ?? .orange,
                    Color(hex: "#E27D5A") ?? .orange,
                ]),
                startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(Self.monogram(for: name))
                .font(.system(size: 15 * theme.fontScale, weight: .heavy))
                .foregroundColor(.white.opacity(0.92))
        }
        .frame(width: 46, height: 46)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // 「開賣中」徽章 — accent 圓點（外圈淡暈）+ accent 文字。
    private var saleBadge: some View {
        HStack(spacing: 4) {
            ZStack {
                Circle().fill(theme.accent.opacity(0.2)).frame(width: 11, height: 11)
                Circle().fill(theme.accent).frame(width: 5, height: 5)
            }
            Text("開賣中")
                .font(.system(size: 9.5 * theme.fontScale, weight: .heavy))
                .foregroundColor(theme.accent)
        }
    }

    // 立即搶購 — 滿版 accent 鈕 + bag 圖示。`onTapBuy` 綁定時 → 可點開該商品 detail（問題5）；
    // 未綁定（demo / snapshot）→ inert，且像素與綁定前 byte-identical。
    @ViewBuilder
    private var buyButton: some View {
        if let onTapBuy = onTapBuy {
            // `.buttonStyle(.plain)` 不加任何 chrome → 與靜態 label 像素一致，只是變可點。
            Button(action: onTapBuy) { buyButtonLabel }
                .buttonStyle(.plain)
                .accessibilityIdentifier(LBAccessibilityID.saleBuy)
        } else {
            buyButtonLabel
                .accessibilityIdentifier(LBAccessibilityID.saleBuy)
        }
    }

    /// 「立即搶購」按鈕的視覺內容（按鈕化前後共用，確保像素不變）。
    private var buyButtonLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: "bag")
                .font(.system(size: 11, weight: .bold)).foregroundColor(.white)
            Text("立即搶購")
                .font(.system(size: 12 * theme.fontScale, weight: .heavy))
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(theme.accent)
    }

    /// 商品名首個非空字元（大寫）作 monogram；空 → "?"。確定性 → snapshot 穩定。
    static func monogram(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first else { return "?" }
        return String(first).uppercased()
    }
}

// MARK: - Pinned message banner (chat-pinned-message-render ⑤c)

/// 置頂留言橫幅：pin glyph + 留言者名（`kind == .comment` / name 非空時）+ 內容。最小中性
/// 渲染（最終視覺 DECISION-PENDING 待設計稿）；只在 `ChatFeedView.pinned != nil` 時被建出，
/// 故無置頂時不出像素（snapshot baseline byte-identical）。
private struct PinnedMessageBanner: View {
    let theme: ReferenceUITheme
    let pinned: LBPinnedMessage

    /// 主播置頂（`kind == .host` / name 空）不顯示名前綴；comment 顯示「{name}：」。
    private var namePrefix: String {
        (pinned.kind == .comment && !pinned.name.isEmpty) ? "\(pinned.name)：" : ""
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "pin.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(theme.accent)
            (Text(namePrefix).fontWeight(.bold) + Text(pinned.text))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.55))
        )
        .padding(.horizontal, 8)
        .padding(.top, 6)
    }
}
