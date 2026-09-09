import SwiftUI
import LivebuySDK
import LivebuyUI

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

    /// The designated initializer, PLUS a test-only trailing parameter,
    /// `initialAtBottomForTesting`, that seeds `atBottom`'s INITIAL `@State` value (same
    /// `*ForTesting` seam pattern as `LivebuyPlayerPresenter.isMinimizedForTesting` —
    /// `docs/unit-test-discipline.md` §3). DEFAULT `true` (= current "at bottom, pill
    /// hidden" behavior) keeps every existing call site byte-for-byte unaffected.
    ///
    /// WHY THIS EXISTS (`rb-ios-chat-pill-color-align`): `atBottom` is private `@State`
    /// driven by real scroll position with no read window, and this package's test target
    /// has no ViewInspector / gesture-simulation infra to actually scroll a `ScrollView` in
    /// the deterministic `ImageRenderer` snapshot path. Seeding the INITIAL `@State` value
    /// at construction — before SwiftUI ever mounts the view — lets a snapshot test render
    /// `returnToLatestPill` in its visible state through a REAL SwiftUI render pass, entirely
    /// via this package's public/testable surface, no private-state reflection needed.
    public init(theme: ReferenceUITheme,
                items: [LBFeedItem],
                hostScrollable: Bool = false,
                pinned: LBPinnedMessage? = nil,
                hostName: String = "",
                onJoinEvent: ((_ eid: Int, _ keyword: String) -> Void)? = nil,
                initialAtBottomForTesting: Bool = true) {
        self.theme = theme
        self.items = items
        self.hostScrollable = hostScrollable
        self.pinned = pinned
        self.hostName = hostName
        self.onJoinEvent = onJoinEvent
        self._atBottom = State(initialValue: initialAtBottomForTesting)
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
                    // leaving its inline control (eventJoinCta) as separately-queryable
                    // children — without it the row id shadows the inner button
                    // (rb-ios-e2e-feed-row-contain).
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

    /// White-background / accent-foreground "↓ 最新訊息" pill (`rb-ios-chat-pill-color-align`)
    /// — visible only when the user is scrolled AWAY from the bottom (`atBottom == false`,
    /// real scroll position); tapping returns to the newest row and re-sticks. Driving this
    /// off scroll position (not `autoStick`) keeps it hidden for an empty / short feed, so a
    /// switch-swipe race can no longer leave it stuck on the next video.
    ///
    /// Color scheme (`rb-ios-chat-pill-color-align`): background `Color.white`, text +
    /// `ArrowDownGlyph` both `theme.accent` — a role SWAP of the prior `theme.accent`-background
    /// / white-foreground scheme (same color source, `theme.accent`, just moved to the opposite
    /// role), not a new hardcoded color. Position (`.overlay(alignment: .bottom)`, already
    /// horizontally centered), padding, corner radius, font size, and trigger timing are
    /// unchanged.
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
                    ArrowDownGlyph(size: 10, color: theme.accent)
                    Text(Self.returnToLatestLabel)
                        .font(.system(size: 11.5 * theme.fontScale, weight: .semibold))
                }
                .foregroundColor(theme.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.white))
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

    /// `.eventJoin` 列顯示的主播名 resolve 邏輯（`rb-ios-event-join-streamer-name`）：優先用
    /// 該則訊息自己的 `item.userName`（`LBFeedItem.userName`，由前置 view-model 層 change
    /// `event-join-streamer-name-template` 經 `push.name` 寫入）；`item.userName` 為 `nil` 或
    /// 空字串（**用 `.isEmpty` 判斷，不能只判斷 `== nil`**——`push.name` 生產路徑上是必填、
    /// strict-decoded 欄位，缺值更常見的形態是 `Optional("")` 而非 `nil`；只判斷 `== nil` 會讓
    /// 空字串被誤判為「有名字」而顯示空白 badge）才 fallback 至舊有的整場共用 `hostName`
    /// （← `FeedWinModel.hostName`，`rb-ios-loading-announce-restyle`）；兩者皆空 → 回傳空字串，
    /// 維持既有「不畫名字列」行為不變（見 `LBEventJoinLineRow.bubble` 的 `if !userName.isEmpty`
    /// gate）。純函式、無 `self` 依賴 — 依 `docs/unit-test-discipline.md` 抽出以便直接單元測試。
    static func resolvedEventJoinUserName(item: LBFeedItem, hostName: String) -> String {
        (item.userName?.isEmpty == false) ? item.userName! : hostName
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
                userName: Self.resolvedEventJoinUserName(item: item, hostName: hostName),
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
            // `LivebuyUI`, not modifiable here). `EmptyView()` keeps a misuse silent rather
            // than crashing.
            EmptyView()
        case .productSale:
            // onsale 商品開賣推播已改走 host 主播聊天氣泡（template `DefaultPlayerTemplate` 對
            // `.onsale` 走 `appendChat(...isHost:true)`），已無 production 路徑產生 `.productSale`
            // feed item — 原「商品開賣卡」渲染（`LBProductSaleCardRow`）為死碼、已移除。保留此 no-op
            // case 以維持 Swift 對 `LBFeedItem.Kind`（定義於 `LivebuyUI`，此處不可改）的窮盡 switch；
            // 型別完整移除需跨層 change。比照上方 `.activity` 的 `EmptyView()` no-op。
            EmptyView()
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
    /// 主播留言 / 主播回覆。`true` → accent 軌 + `crown.fill`（軌現依 `rb-ios-feed-avatar-
    /// icon-hide` 不渲染）+ 中性色氣泡 + accent 色底名牌（內容＝`userName`，`rb-ios-chat-
    /// message-line-restyle`，design R30：取代先前的整片 accent 氣泡 +「主播」實心標）。
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
        // `rb-ios-feed-avatar-icon-hide`（design R20）：24px 圖示 / 頭像軌不再組裝進渲染樹——
        // 對齊設計稿 `moments.jsx` `ACT_SLOT` 由 `display:'flex'` 改 `display:'none'`（可逆的暫時
        // 性決定，設計稿註解「改回顯示把 display 換成 'flex'」）。`slot` 不放進 HStack 子項，讓
        // bubble 貼齊列最左側起點，不留原本 slot + `spacing: 8` 的空白區塊。`slot` 本身的繪製邏輯
        // 保留在下方不刪，供未來復原（加回 `slot` 子項即可，spacing 值不變）。
        //
        // `alignment: .center`（原為 `.top`，rb-ios-chat-bubble-text-vertical-center 順手修
        // 正）：對齊設計稿 `moments.jsx` 第 330–335 行 `ACT_ROW` 的 `alignItems: 'center'`——這個
        // HStack 原本是「24px 圖示 / 頭像 slot + bubble」兩個子項並排，`.top` 會讓 bubble 貼齊
        // slot 頂端；`rb-ios-feed-avatar-icon-hide` 把 slot 從渲染樹拿掉後，HStack 目前只剩單一
        // 子項（`bubble` 或 `roleBubble`），單一子項時 alignment 對其自身渲染是 no-op（沒有第二
        // 個子項可供比較上下對齊），故這裡改成 `.center` 不會讓現有 baseline 的像素跳動——純粹是
        // 「若 slot 未來依設計稿註解復原顯示」時預先避免 bubble 貼齊 slot 頂端造成明顯偏移的防禦
        // 性修正。
        HStack(alignment: .center, spacing: 8) {
            // 無角色 → 既有暱稱內聯前綴氣泡（byte-identical）；有角色 → 角色版型氣泡。
            if hasRole { roleBubble } else { bubble }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 24px 圖示軌（主播 / AI = accent + glyph；觀眾 = 名字色頭像）
    //
    // `rb-ios-feed-avatar-icon-hide`（design R20）起不再被 `body` 組裝渲染（見上）——保留此
    // computed view 供未來設計稿改回 `display:'flex'` 時可直接復原（把 `slot` 加回 `body` 的
    // HStack 第一個子項）。

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
            // header：名字 / 名牌 +「AI」標（以版型而非顏色區分）+ 冒號.
            //
            // `rb-ios-chat-message-line-restyle`（design R30，2026-09-03）：主播身分
            // 不再靠獨立的固定字串「主播」實心標——`userName` 本身直接放進一個 accent
            // 色底名牌（`roleTag(name, solid: true, bg: theme.accent)`），取代先前
            // 「暱稱文字（獨立 `Text`）+ 獨立『主播』badge」兩個並排元素。AI 外框標
            // （`isAI` 時）不受影響，與主播名牌並存（AI 訊息本身也帶 `isHost == true`）。
            // 非主播但仍走角色版型（`hasRole == true && isHost == false`，例如僅帶
            // `replyText` 的少見情境）的暱稱顏色從白 `0.66` 改固定 `#FBB0B7`（粉色，
            // 對齊 design 的觀眾識別色）。
            // `rb-ios-chat-header-colon-spacing-fix`：外層 `HStack(spacing: 0)` 讓冒號
            // 與名牌 / AI 標群組零間距貼齊——`spacing: 5` 只保留在內層，只管「名牌 / 暱稱」
            // 與「AI 標」之間的間距（對齊設計稿 `moments.jsx` `gap: 5` 只作用於這兩者之間，
            // 冒號是外層獨立 sibling `<span>`，不共用這份間距）。先前把冒號一併塞進同一個
            // `HStack(spacing: 5)`，導致冒號多吃一份不該有的 `5pt` 間距——即本次要修正的
            // 偏差。
            HStack(spacing: 0) {
                HStack(spacing: 5) {
                    if let name = userName, !name.isEmpty {
                        if isHost {
                            roleTag(name, solid: true, bg: theme.accent)
                        } else {
                            Text(name)
                                .font(.system(size: 11.5 * theme.fontScale, weight: .semibold))
                                .foregroundColor(Self.guestRoleNameColor)
                                .lineLimit(1)
                        }
                    }
                    if isAI {
                        roleTag("AI", solid: false)
                    }
                }
                // 冒號（design R30）：`hasRole == true` 路徑自本輪起也統一補冒號，比照
                // 觀眾留言 `bubbleText` 既有的冒號慣例（`rb-ios-chat-message-colon-
                // separator`）。MUST 帶明確 `.font()`——`rb-ios-chat-colon-font-
                // baseline-fix` 的既知坑：未設 `.font()` 的 `Text` 片段會吃到 ambient
                // ~17pt 預設字體，讓行高與相鄰片段不一致。放在外層零間距 `HStack` 的最後
                // 一個子項（名牌 / AI 標群組之後），與該群組零間距貼齊，對齊 design「名牌
                // 後緊接冒號」的視覺意圖，不牽動下方內文 `Text` 既有的獨立分行 /
                // `lineLimit(nil)` 結構。
                //
                // NOTE（邊界情境，未測試覆蓋）：若 `userName` 為 nil/空字串但
                // `isHost`/`isAI` 為真（目前所有真實呼叫端與既有測試皆不會發生——
                // 主播訊息的 `userName` 恆非空），header 會只剩下這個冒號本身。這是
                // 舊版「即使沒暱稱仍畫固定字串『主播』」行為的一個副作用性改變，design
                // 沒有交代這個邊界情境的 fallback，本次不臆測補一個新文案。
                Text("：")
                    .font(.system(size: 11.5 * theme.fontScale, weight: .regular))
                    .foregroundColor(.white)
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
                // `rb-ios-chat-message-line-restyle`（design R30）：主播氣泡不再整片
                // 染 accent——與觀眾留言氣泡（`bubble`）同一底色，身分改由上方的
                // accent 名牌承載，不再靠氣泡染色區分。
                .fill(Color.black.opacity(0.42)))
    }

    /// 名字 / 角色標。`solid`=true → 實心，底色為 `bg`（`isHost` 名牌用 `theme.accent`；
    /// 未指定回退既有白 0.22，維持 AI 標既有呼叫點原始碼相容）；`solid`=false → 透明 +
    /// 白 0.55 邊框（AI 標，`bg` 對此分支無作用）。`bg` 參數為 `rb-ios-chat-message-line-
    /// restyle`（design R30）新增，對齊設計原始碼 `moments.jsx` 的 `tag(label, solid, bg)`
    /// helper 同步擴充第三參數（主播名牌需要指定 accent 底色，取代固定字串「主播」）。
    @ViewBuilder
    private func roleTag(_ label: String, solid: Bool, bg: Color = Color.white.opacity(0.22)) -> some View {
        Text(label)
            .font(.system(size: 9 * theme.fontScale, weight: .heavy))
            .foregroundColor(.white)
            .padding(.horizontal, 5)
            .frame(height: 14)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(solid ? bg : Color.clear)
                    .overlay(solid ? nil : RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.white.opacity(0.55), lineWidth: 1)))
    }

    /// 非主播但仍走角色版型（`hasRole == true && isHost == false`）的暱稱顏色（design
    /// R30：固定 `#FBB0B7` 粉色，取代先前的白 `0.66`）。internal（非 `private`）以便單元
    /// 測試直接斷言數值。**第二個消費點（`rb-ios-chat-audience-bubble-pink-nickname-full-
    /// lines`）**：一般觀眾留言（`hasRole == false`）的 `bubbleText` 暱稱/冒號自本 change
    /// 起也套用同一顆常數，取代先前的半透明白 `.white.opacity(0.72)`——兩個路徑現在共用
    /// 同一份色值來源，非各自獨立定義、恰好數值相同。
    static let guestRoleNameColor: Color = Color(hex: "#FBB0B7") ?? .pink

    /// Translucent dark bubble. ACT_BUBBLE: radius 12, black 0.42, padding h11/v4.
    /// Vertical padding tightened from 5→3 (rb-ios-chat-bubble-padding-tighten) to
    /// align with `roleBubble`'s existing compact-spacing convention (its inner
    /// `VStack(spacing: 3)` / reply-quote `.padding(.vertical, 3)`), then widened
    /// 3→4 (rb-ios-guest-bubble-padding-widen — an owner-directed product judgment
    /// call to shrink the residual cross-platform visual gap vs Android's guest
    /// bubble, whose own line-height metrics run taller even at the same nominal
    /// padding; NOT a design-token realignment, and Android's `vertical = 3.dp`
    /// is intentionally left unchanged by that change).
    ///
    /// `.lineLimit(nil)` (was `.lineLimit(2)`, `rb-ios-chat-audience-bubble-pink-nickname-
    /// full-lines`): the message text is now fully shown, no longer capped at 2 lines +
    /// ellipsis — matching `roleBubble`'s existing unlimited-lines behavior (host / AI /
    /// reply messages), which previously excluded this general-viewer path on purpose (see
    /// the dedicated "主播 / 角色聊天氣泡訊息完整顯示（不限行數）" spec Requirement this
    /// change revises). For content that already fits within 2 lines this produces
    /// byte-identical pixels (already established by that Requirement's own "snapshot /
    /// demo baseline 不位移" scenario), so most existing demo/snapshot content is
    /// unaffected by this specific edit — only the nickname/colon color change above
    /// moves pixels for those baselines.
    ///
    /// `bubbleText.offset(y:)` (`rb-ios-chat-bubble-text-vertical-center`) compensates for
    /// `Text`'s own line-box being vertically asymmetric around its glyph ink at this size
    /// (measured, not assumed — see design.md): even though `.padding(.vertical, 4)` above
    /// is perfectly symmetric, a rendered isolated guest bubble on a non-black backdrop
    /// (`chat-feed-guest-bubble-light-bg`, the existing baselines all sit on `Color.black`
    /// where the `0.42`-alpha bubble is indistinguishable from the backdrop) showed the ink
    /// sitting measurably closer to the bubble's BOTTOM edge than its top — i.e. `Text`
    /// reserves more headroom above the glyphs than footroom below them at 11.5pt. The
    /// offset shifts the ink UP by that measured gap difference so it lands centered
    /// between the (unchanged) symmetric padding, WITHOUT touching the padding values
    /// themselves — `ChatLineRowBubblePaddingTests.swift` asserts the single
    /// `.padding(.vertical, 4)` node's insets are exactly `(4, 4)`, and `.offset` is a
    /// pure paint-time translation (it does not add/alter any `_PaddingLayout` node or
    /// change the view's reported size), so that structural assertion is unaffected. The
    /// asymmetry being compensated is intrinsic to the glyph ink within its own line box,
    /// independent of the surrounding (symmetric) outer padding value, so the 3→4 widening
    /// is not expected to invalidate the `guestBubbleTextVerticalOffset == 0.0` measurement
    /// below — confirmed visually against the regenerated `chat-feed-guest-bubble-light-bg`
    /// baseline (rb-ios-guest-bubble-padding-widen); re-run the diagnostic in that change's
    /// design.md if a future change alters the line-box asymmetry itself.
    ///
    /// Re-measured after `rb-ios-chat-colon-font-baseline-fix` (see that change's design.md):
    /// the ORIGINAL `-1.8pt` was measured while the colon segment (`bubbleText`) had NO
    /// `.font()` modifier and rendered at the ambient (~17pt) default, which inflated that
    /// segment's line-box height and skewed the whole line's ink asymmetrically low — the
    /// `-1.8pt` was largely compensating for THAT, not an intrinsic asymmetry of `Text` at
    /// 11.5pt. Once the colon was given the correct `11.5 * theme.fontScale` font (matching
    /// the nickname / body on either side of it), re-running the same `.scaleEffect(6)` +
    /// pixel-bounding-box diagnostic on the same content ("小雨：求鏈接~") showed the ink
    /// EXACTLY centered (58px / 58px top and bottom gaps at 12x total scale, 0pt diff) with
    /// NO offset applied at all — so `guestBubbleTextVerticalOffset` is now `0.0`.
    private var bubble: some View {
        bubbleText
            .offset(y: Self.guestBubbleTextVerticalOffset * theme.fontScale)
            .lineLimit(nil)
            .padding(.horizontal, 11)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.42)))
    }

    /// Vertical paint-time compensation (pt, at `fontScale == 1.0`) for the guest bubble's
    /// text-vs-line-box asymmetry described on `bubble` above. Negative = shift the ink UP.
    /// Scales with `theme.fontScale` (same convention as the `11.5 * theme.fontScale` font
    /// sizes) since the underlying asymmetry is a property of the rendered font size, not a
    /// fixed pixel amount.
    ///
    /// `0.0` (was `-1.8` pre-`rb-ios-chat-colon-font-baseline-fix`): re-measured once the
    /// colon segment got its correct font — see the note on `bubble` above. The `.offset(y:)`
    /// call is kept in place (rather than removed) so the established measurement-driven
    /// compensation mechanism stays available if a future content shape or font-render change
    /// reintroduces a measurable asymmetry; today it is a documented no-op.
    private static let guestBubbleTextVerticalOffset: CGFloat = 0.0

    /// The bubble content: an inline dimmed nickname prefix + the message (design
    /// `LBChatLine`), or just the message when there is no nickname. The message text is
    /// the backend-prebuilt body (NOT name-embedded — design `m.text` is the message only).
    ///
    /// The nickname/message separator is a single full-width colon「：」
    /// (`rb-ios-chat-message-colon-separator`, mirroring the design's `!isHost` branch:
    /// the nickname is now followed directly by「：」with `marginRight` zeroed out — no
    /// extra space). This ONLY applies to this general-viewer path (`hasRole == false`);
    /// `roleBubble` (host / AI / reply, `hasRole == true`) keeps its own independent
    /// name-row layout and is unaffected.
    ///
    /// The colon SHALL carry the SAME `.font()` / `.foregroundColor()` as the nickname
    /// (`rb-ios-chat-colon-font-baseline-fix`): `moments.jsx` `LBChatLine` (line ~434)
    /// puts the colon literally INSIDE the same `<span>` as `m.user` — `{m.user}{!isHost
    /// && '：'}` — sharing that span's `opacity` / `fontWeight`, with `fontSize: 11.5`
    /// inherited from the shared `ACT_BUBBLE` for every child (nickname / colon / body
    /// alike). Before this fix `Text("：")` had NO `.font()` modifier at all — SwiftUI
    /// keeps each concatenated `Text` segment's OWN styling (a segment never inherits a
    /// neighboring segment's `.font()`), so an un-styled segment falls back to the
    /// ambient/environment default font (~17pt system body), not the `11.5 *
    /// theme.fontScale` used everywhere else in this bubble. That size mismatch gave the
    /// colon glyph a taller line box than the text on either side of it, reading as "not
    /// vertically centered" — see `guestBubbleTextVerticalOffset` below for the
    /// re-measurement this fix triggered.
    ///
    /// The NICKNAME color is fixed pink `#FBB0B7` (`Self.guestRoleNameColor`,
    /// `rb-ios-chat-audience-bubble-pink-nickname-full-lines`) — **replaces** the prior
    /// translucent white `.white.opacity(0.72)`. This reuses the SAME color constant
    /// already applied to the "non-host but still role-styled" nickname in `roleBubble`
    /// (see its doc comment above `guestRoleNameColor`) — the two call sites now share one
    /// source of value, not two definitions that happen to match.
    ///
    /// The COLON is white (`rb-ios-chat-audience-nickname-colon-color-fix`) — **not** the
    /// nickname's pink. `pink-nickname-full-lines` landed this whole block by giving BOTH
    /// the nickname `Text` AND the colon `Text` the same `.foregroundColor(guestRoleNameColor)`,
    /// mis-reading `moments.jsx`'s `LBChatLine` as one shared style. Re-checking the actual
    /// markup (lines ~429-452) shows the nickname and colon are two INDEPENDENT `<span>`s:
    /// `<span style={{ color: '#FBB0B7' }}>{m.user}</span>` next to a sibling
    /// `<span style={{ color: '#fff' }}>：</span>` — the colon's color never varies with
    /// `isHost`, it is always the shared white span. Only the FONT SIZE (`11.5 *
    /// theme.fontScale`) is legitimately shared across nickname / colon / body (all three
    /// inherit `ACT_BUBBLE`'s `fontSize: 11.5`); the color is not. This mirrors
    /// `roleBubble`'s own colon (`hasRole == true` path, a few lines below), which has
    /// always been an independent `.foregroundColor(.white)` and was never affected by the
    /// `pink-nickname-full-lines` bug — that fix scope was `bubbleText` only. Font WEIGHT is
    /// intentionally left at `.semibold` here (unchanged) rather than aligned to
    /// `roleBubble`'s `.regular` colon: the design markup doesn't spell out a weight
    /// distinction, so this fix's scope is color only, not a weight realignment.
    private var bubbleText: Text {
        let body = Text(text)
            .font(.system(size: 11.5 * theme.fontScale, weight: .regular))
            .foregroundColor(.white)
        guard let userName = userName, !userName.isEmpty else { return body }
        return Text(userName)
            .font(.system(size: 11.5 * theme.fontScale, weight: .semibold))
            .foregroundColor(Self.guestRoleNameColor)
            + Text("：")
                .font(.system(size: 11.5 * theme.fontScale, weight: .semibold))
                .foregroundColor(.white)
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
// the host chat bubble — no gradient wash / border anymore) stacking a name+badge
// header (when `userName` is non-empty) above the 2-line keyword copy, with the CTA /
// 「已參加」chip moved BELOW the text as its own row (was inline beside the text). The ONLY
// interactive row in the stream — its tap is FORWARDED via `onJoin` (host wired); this layer
// never joins itself. (rb-ios-event-message-design-align, rb-ios-loading-announce-restyle.)
//
// `rb-ios-chat-message-line-restyle`（design R30，2026-09-03）further updates the name
// header (name+「主播」badge → a single accent-colored nameplate carrying `userName`
// itself, plus a trailing colon — same treatment as `LBChatLineRow.roleBubble`) and the
// unjoined CTA (white-capsule/accent-text/「加入活動」 → accent-filled/white-text/
// full-width/「立即參加」). The joined-state chip is unaffected. Correction (2026-09-03,
// same change, second pass): the bubble fill itself ALSO moves off `theme.accent` to the
// same neutral `Color.black.opacity(0.42)` `roleBubble` now uses (verified against
// `design/templates/minimal/moments.jsx:634` — `ACT_BUBBLE`'s own fill, no accent
// override) — the "FLAT `theme.accent` bubble" description above (from the earlier
// `c3c98733` re-sync) is now HISTORICAL only; identity is carried by `hostNameplate`
// instead. See the NOTE on `bubble` below for the full account.

struct LBEventJoinLineRow: View {
    let theme: ReferenceUITheme
    let text: String
    /// 主播名稱，純顯示 — 對齊 `LBChatLineRow.roleBubble` 的 accent 名牌版型
    /// （`rb-ios-chat-message-line-restyle`，design R30）。呼叫端（`ChatFeedView.row(for:)`）
    /// 自 `rb-ios-event-join-streamer-name` 起優先餵入該則訊息自己的 `LBFeedItem.userName`，
    /// 缺值時才 fallback 至整場共用的 `ChatFeedView.hostName` ← `FeedWinModel.hostName` ←
    /// `DefaultPlayerTemplate.header.hostName`（此 struct 本身不知道兩者的差異，仍只是單純
    /// 接收一個已 resolve 好的 `String`）。空字串（兩個來源皆缺值，如未綁定 `FeedWinModel` 的
    /// 呼叫端、各 snapshot test 直接建構 `ChatFeedView` 未帶 `hostName` 也未帶 `item.userName`）
    /// → 不畫名字列，不影響其餘版型 / CTA gating。
    let userName: String
    /// keyword 非空 → 畫 CTA（後端「`ek` isset 才顯示 CTA」契約，問題 1）；空 → 純活動公告
    /// （活動已結束 / goods `event[]` 未含該 event → template 帶入 keyword ""），不畫 CTA / 已參加 chip。
    let hasCTA: Bool
    let joined: Bool
    let onJoin: () -> Void

    var body: some View {
        // Shared message-row language (ACT_ROW gap 8): round crown-glyph slot OUTSIDE the
        // bubble, matching `LBChatLineRow`'s avatar + bubble pairing.
        //
        // `rb-ios-feed-avatar-icon-hide`（design R20）：`eventSlot` 不再組裝進渲染樹——對齊
        // 設計稿 `moments.jsx` `ACT_SLOT` 由 `display:'flex'` 改 `display:'none'`（可逆的暫時性
        // 決定）。`bubble` 貼齊列最左側起點，不留原本 slot + `spacing: 8` 的空白。`eventSlot`
        // 繪製邏輯保留在下方不刪，供未來復原。
        //
        // `alignment: .center`（原為 `.top`，rb-ios-chat-bubble-text-vertical-center 順手修
        // 正，理由同 `LBChatLineRow.body`）：對齊設計稿 `moments.jsx` `ACT_ROW` 的
        // `alignItems: 'center'`；HStack 目前只剩單一子項（`bubble`），單一子項時 alignment 對
        // 渲染是 no-op，故不影響現有 baseline，只是為 slot 未來復原顯示預先避免頂端對齊偏移。
        HStack(alignment: .center, spacing: 8) {
            bubble
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// 24×24 round accent slot (`ACT_SLOT`) with the SAME `crown.fill` glyph as
    /// `LBChatLineRow.roleBubble`'s isHost avatar (design re-sync `c3c98733`: was `sparkles`;
    /// the design's own slot path is the host crown shape, not a checkmark), drawn OUTSIDE the
    /// bubble on the shared 24px icon rail (same shape/size as `LBActivityLineRow`'s icon slot).
    ///
    /// `rb-ios-feed-avatar-icon-hide`（design R20）起不再被 `body` 組裝渲染（見上）——保留供
    /// 未來復原（把 `eventSlot` 加回 `body` 的 HStack 第一個子項）。
    private var eventSlot: some View {
        Circle()
            .fill(theme.accent)
            .frame(width: 24, height: 24)
            .overlay(
                Image(systemName: "crown.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white))
    }

    /// Host-bubble-styled card (design re-sync `c3c98733`): flat `theme.accent` fill (no
    /// gradient wash / border), stacking an optional name+badge header, the keyword copy,
    /// and the CTA (moved below the text, was inline beside it).
    ///
    /// NOTE（`rb-ios-chat-message-line-restyle`，design R30；補正 2026-09-03）：權威來源
    /// `design/templates/minimal/moments.jsx` 第 634 行已核對——`LBEventJoinLine` 落地版
    /// 的氣泡是 `<span style={{ ...ACT_BUBBLE, ... }}>`，**沒有** `background: accent` 覆寫，
    /// `ACT_BUBBLE` 本身底色即 `rgba(0,0,0,0.42)`，與 `LBChatLineRow.roleBubble` 本輪改版
    /// 後的中性底同一套公式。上一輪「留給未來若有明確決策再處理」的保留判斷已由此次核對
    /// 收斂——**本 struct 的氣泡底色本輪一併改為中性色**，與 `roleBubble` 一致，身分識別
    /// 改由 `hostNameplate`（accent 底名牌）承載，不再靠氣泡本身染色區分。
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
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.42)))
    }

    /// 主播名牌 + 冒號 header row（`rb-ios-chat-message-line-restyle`，design R30：取代先前的
    /// 「暱稱文字（獨立 `Text`）+ 獨立『主播』badge」兩個並排元素——比照 `LBChatLineRow
    /// .roleBubble` 的同一套改版：accent 色底名牌承載身分識別，名牌後緊接冒號）。
    private var hostNameHeader: some View {
        // `rb-ios-chat-header-colon-spacing-fix`：`hostNameplate` 與冒號零間距貼齊
        // （`HStack(spacing: 0)`）——先前 `spacing: 5` 讓冒號多吃一份不該有的間距，對齊
        // `roleBubble` 同款修正與設計稿 `moments.jsx` 冒號是外層獨立 sibling、零間距的
        // 意圖。
        HStack(spacing: 0) {
            hostNameplate
            // 冒號（design R30）：MUST 帶明確 `.font()`，比照 `LBChatLineRow.roleBubble`
            // 的既知坑（`rb-ios-chat-colon-font-baseline-fix`）——未設 font 的 `Text` 片
            // 段會吃到 ambient ~17pt 預設字體。
            Text("：")
                .font(.system(size: 11.5 * theme.fontScale, weight: .semibold))
                .foregroundColor(.white)
        }
    }

    /// 主播名牌 — accent 色底、內容為主播暱稱本身（`rb-ios-chat-message-line-restyle`，
    /// design R30：取代原本「暱稱文字（`size 11.5`、`weight .bold`、白 `0.95`）+ 獨立
    /// 『主播』badge（白 `0.22` 底）」兩個並排元素）。樣式公式沿用既有「主播」badge 的參數
    /// （白字、`size 9`、`weight .heavy`、圓角 4、`height 14`），僅底色改 `theme.accent`、
    /// 內容改 `userName`——與 `LBChatLineRow.roleTag(_:solid:bg:)` 同構，但此 struct
    /// 獨立實作一份（不共用該 private method；`private` 對同檔案內不同 struct 本來就互相
    /// 不可見，這兩個 struct 對「主播」badge 一向各自一份，本次沿用既有慣例）。
    private var hostNameplate: some View {
        Text(userName)
            .font(.system(size: 9 * theme.fontScale, weight: .heavy))
            .foregroundColor(.white)
            .lineLimit(1)
            .padding(.horizontal, 5)
            .frame(height: 14)
            .background(RoundedRectangle(cornerRadius: 4).fill(theme.accent))
    }

    /// Trailing CTA row — 加入活動 / 已參加, moved BELOW the text (design re-sync `c3c98733`:
    /// was inline beside the text). Top padding `7` matches design source
    /// `moments.jsx` `marginTop: 7` and Android `EventJoinLine`'s `padding(top = 7.dp)`
    /// (rb-ios-event-join-cta-margin-top-align — was `4`, a drift from the design value).
    @ViewBuilder
    private var ctaRow: some View {
        if joined {
            joinedChip.padding(.top, 7)
        } else {
            joinButton.padding(.top, 7)
        }
    }

    /// 「立即參加」CTA button（`rb-ios-chat-message-line-restyle`，design R30：文案由
    /// 「加入活動」改「立即參加」；樣式由「白底 accent 字」（design re-sync `c3c98733`
    /// 當時的樣式）對調回「accent 底白字」；寬度撐滿容器，對齊設計稿 `width: '100%'`）。
    /// `.frame(maxWidth: .infinity)` 讓外層既有的彈性佈局（`bubble` VStack → 外層
    /// `HStack(.frame(maxWidth: .infinity, alignment: .leading))`）自然把整個氣泡撐寬，
    /// 不需要另外量測 / 寫死任何像素寬度常數。
    private var joinButton: some View {
        Button(action: onJoin) {
            Text(Self.joinLabel)
                .font(.system(size: 12 * theme.fontScale, weight: .heavy))
                .foregroundColor(.white)
                .padding(.horizontal, 13)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(Capsule().fill(theme.accent))
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

    /// CTA label（`rb-ios-chat-message-line-restyle`，design R30：was 「加入活動」）.
    static let joinLabel = "立即參加"
    /// 已參加 joined-state label.
    static let joinedLabel = "已參加"
    /// Fallback copy when `text` is empty (`LBEventJoinLine` default copy).
    static let defaultEventCopy = "🎉 抽獎開始！留言「抽獎」即可參加"
}

// MARK: - LBActivityLineRow — tier-styled activity row (LBActivityLine)
//
// Mirrors the UPDATED `moments.jsx` `LBActivityLine`: every row shares one unified
// language — a 24×24 round icon SLOT + a rounded-12 bubble. Icon differs by tier;
// bubble color differs by tier as follows:
//   • `.join`     — 進場: slot 白 0.16 / grey icon; bubble **固定語意色珊瑚紅**
//                   `rgba(232,108,108,0.72)`, text 白 0.9, medium.
//   • `.browse`   — 觀眾選購: slot 白 0.16 / grey icon; bubble 黑 0.32, NO accent,
//                   text 白 0.9, medium（design 這輪未涵蓋，維持不變）.
//   • `.purchase` — 購買: slot accent / white bag icon; bubble **固定語意色青綠**
//                   `rgba(45,212,191,0.72)`, medium.
//   • `.intro`    — 介紹: slot accent / white megaphone icon; bubble 黑 0.46 + accent
//                   0.18 wash, medium（商品開始介紹 — design 這輪未涵蓋，維持不變）.
//   • `.win`      — 中獎: slot accent / white trophy icon; bubble **固定語意色鮮紅**
//                   `rgba(240,50,70,0.72)` + 細框 accent 0.4 + 極淡光暈 accent 0.2,
//                   bold. NO 🎉.
//
// `rb-ios-chat-message-line-restyle`（design R30，2026-09-03）：`.join` / `.purchase` /
// `.win` 的氣泡底色從「隨商家 accent 主題色調的暈染」（`washBubble(_:)`，黑底 + accent
// overlay）改成三種**固定**語意色 —— 三種活動類型的視覺差異從此不再受商家主題色影響。
// `.browse` / `.intro` 這輪 design 未涵蓋，維持原本黑底 / 黑底+accent 暈染邏輯不動。
// `.win` 的 `border` / `boxShadow` 光暈仍用 accent（design 原文 `border: 1px solid
// ${accent}66; boxShadow: 0 2px 10px ${accent}33`），這是刻意保留、不是遺漏。
//
// `.intro` 分支是 iOS（連同 Android/RN/Flutter）既有的共通擴充 tier——design 畫布的
// `LBActivityLine` 本身只有 join/purchase/browse/win 四種分支，沒有 `.intro` 對應項；
// 這是「design 沒有涵蓋到的既有擴充」，R30 這輪同樣沒有觸及，維持既有 accent 暈染樣式。
//
// 舊版（`.purchase`/`.intro` 曾用）的 accent wash 模型 `linear-gradient(accentXX,
// accentXX)` over `rgba(0,0,0,0.46)` = a flat accent overlay (alpha XX) on a 0.46
// black base — 仍套用在未改版的 `.intro` 分支，模型為 a black-base RoundedRectangle
// with an accent-tinted overlay（見 `washBubble(_:)`）。

struct LBActivityLineRow: View {
    let theme: ReferenceUITheme
    let text: String
    let tier: LBActivityTier

    var body: some View {
        // `rb-ios-feed-avatar-icon-hide`（design R20）：`iconSlot` 不再組裝進渲染樹——對齊設計
        // 稿 `moments.jsx` `ACT_SLOT` 由 `display:'flex'` 改 `display:'none'`（可逆的暫時性決
        // 定）。文字氣泡貼齊列（或 toast）最左側起點，不留原本 slot + `spacing: 8` 的空白。tier
        // 差異化視覺（`bubble` 的 accent 暈染 / 邊框 / 光暈、`textColor` / `textWeight`）不受影
        // 響——只隱藏 icon slot。`iconSlot` 繪製邏輯保留在下方不刪，供未來復原。
        HStack(spacing: 8) {
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
    //
    // `rb-ios-feed-avatar-icon-hide`（design R20）起不再被 `body` 組裝渲染（見上）——保留供未來
    // 復原（把 `iconSlot` 加回 `body` 的 HStack 第一個子項）。

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
        case .join:
            // 進場 — 固定語意色珊瑚紅（rb-ios-chat-message-line-restyle，design R30：
            // 取代先前的黑 0.32 中性色，不再隨 accent 主題色調）。
            RoundedRectangle(cornerRadius: 12).fill(Self.joinBubbleColor)
        case .browse:
            // 觀眾選購 — black 0.32, no accent wash（design 這輪未涵蓋，維持不變）。
            RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.32))
        case .purchase:
            // 購買 — 固定語意色青綠（rb-ios-chat-message-line-restyle，design R30：
            // 取代先前的黑 0.46 + accent 0.13 暈染）。
            RoundedRectangle(cornerRadius: 12).fill(Self.purchaseBubbleColor)
        case .intro:
            washBubble(0.18)   // accent2e（design 這輪未涵蓋，維持不變）
        case .win:
            // 中獎 — 固定語意色鮮紅純色底（rb-ios-chat-message-line-restyle，design R30：
            // 取代先前的黑 0.46 + accent 0.23 暈染）+ hairline accent border + faint
            // accent glow（`border`/`boxShadow` 仍用 accent，design 原文明確保留）. NO 🎉.
            RoundedRectangle(cornerRadius: 12)
                .fill(Self.winBubbleColor)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.accent.opacity(0.4), lineWidth: 1))
                .shadow(color: theme.accent.opacity(0.2), radius: 5, x: 0, y: 2)
        }
    }

    /// Black 0.46 base + an accent-tinted overlay (the design's `accentXX` wash).
    /// Only `.intro` still uses this (rb-ios-chat-message-line-restyle, design R30 —
    /// `.join` / `.purchase` / `.win` moved to fixed semantic colors below).
    private func washBubble(_ wash: Double) -> some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.black.opacity(0.46))
            .overlay(RoundedRectangle(cornerRadius: 12).fill(theme.accent.opacity(wash)))
    }

    // MARK: - Fixed semantic colors (rb-ios-chat-message-line-restyle, design R30)
    //
    // `Color(hex:)` (`ReferenceUITheme.swift`) only parses 6-digit RGB and returns an
    // opaque (alpha 1.0) color; `.opacity(_:)` on an already-opaque `Color` sets the
    // alpha directly, so `hex + .opacity(0.72)` is exactly equivalent to the design's
    // `rgba(r,g,b,0.72)` literal. Fallback is `.gray` (not an iOS-15+ semantic color
    // like `.teal`) to keep the file's existing iOS-14-safe convention.

    /// 進場氣泡固定語意色（design R30：珊瑚紅 `rgba(232,108,108,0.72)`）。internal（非
    /// `private`）以便單元測試直接斷言數值（`docs/unit-test-discipline.md` 純資料層斷言）。
    static let joinBubbleColor: Color = (Color(hex: "#E86C6C") ?? .gray).opacity(0.72)
    /// 購買氣泡固定語意色（design R30：青綠 `rgba(45,212,191,0.72)`）。
    static let purchaseBubbleColor: Color = (Color(hex: "#2DD4BF") ?? .gray).opacity(0.72)
    /// 中獎氣泡固定語意色（design R30：鮮紅 `rgba(240,50,70,0.72)`）。
    static let winBubbleColor: Color = (Color(hex: "#F03246") ?? .gray).opacity(0.72)

    private var textColor: Color {
        (tier == .join || tier == .browse) ? Color.white.opacity(0.9) : .white
    }

    private var textWeight: Font.Weight {
        // join / purchase / intro = medium (500); win = bold (700).
        tier == .win ? .bold : .medium
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
            PinFillGlyph(size: 10, color: theme.accent)
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
