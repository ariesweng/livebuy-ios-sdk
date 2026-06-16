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

    /// Scrollable history gate (default `false`, sharing the widget `hostScrollable`
    /// convention + the reference-ui "no `ScrollView` on the snapshot path" invariant).
    /// `false` (demo / snapshot / `ImageRenderer`) → the existing pure-`VStack` bottom-
    /// anchored path (no `ScrollView`, baseline byte-identical). `true` (runtime) → a
    /// `ScrollView` variant so the user can scroll UP to view history (the container
    /// then passes the deeper `DefaultActivityFeed.history` as `items`).
    public let hostScrollable: Bool

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
                onJoinEvent: ((_ eid: Int, _ keyword: String) -> Void)? = nil) {
        self.theme = theme
        self.items = items
        self.hostScrollable = hostScrollable
        self.onJoinEvent = onJoinEvent
    }

    public var body: some View {
        // `hostScrollable == false` keeps the original pure-VStack path (no ScrollView)
        // so the snapshot / `ImageRenderer` baseline stays byte-identical; `true` swaps
        // in the scroll-up-for-history variant (runtime only).
        if hostScrollable {
            scrollableBody
        } else {
            staticBody
        }
    }

    /// The original bottom-anchored, newest-at-bottom column with a top fade mask
    /// (`LBLiveChatStream`). NO `ScrollView` — used by demo / snapshot (baseline path).
    private var staticBody: some View {
        VStack(alignment: .leading, spacing: Self.rowGap) {
            // `Spacer` pins the rows to the bottom so the NEWEST (last) row sits
            // lowest — matching the design's bottom-anchored newest-at-bottom flow.
            Spacer(minLength: 0)
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                row(for: item)
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
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: Self.rowGap) {
                            Spacer(minLength: 0)   // bottom-pin short content
                            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                                row(for: item)
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
                    .onChange(of: items.count) { _ in
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
        }
    }

    // MARK: - Row dispatch by LBFeedItem.kind (D-2)

    /// Dispatch a feed item to its row renderer by `kind`.
    @ViewBuilder
    private func row(for item: LBFeedItem) -> some View {
        switch item.kind {
        case .chat:
            LBChatLineRow(theme: theme, text: item.text)
        case .eventJoin:
            LBEventJoinLineRow(
                theme: theme,
                text: item.text,
                joined: item.joined,
                onJoin: {
                    // Surface the tap; forward via the container's closure. nil →
                    // inert. This layer NEVER joins itself.
                    if let eid = item.eid {
                        onJoinEvent?(eid, item.keyword ?? "")
                    }
                })
        case .activity(let tier):
            LBActivityLineRow(theme: theme, text: item.text, tier: tier)
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
    static let scrollableHeightFraction: CGFloat = 0.46

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

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Name-colored avatar (24×24 round — shared rail with activity slots) —
            // deterministic from `text`. Dark glyph (`#3a2e25`) reads on the pastel
            // demo avatars, matching the updated `LBChatLine` ACT_SLOT.
            Circle()
                .fill(Self.avatarColor(for: text))
                .frame(width: 24, height: 24)
                .overlay(
                    Text(Self.avatarGlyph(for: text))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color(hex: "#3a2e25") ?? .black))

            // Translucent dark bubble carrying the full prebuilt text (NOT split).
            // ACT_BUBBLE: radius 12, black 0.42, padding h11/v5.
            Text(text)
                .font(.system(size: 11.5 * theme.fontScale, weight: .regular))
                .foregroundColor(.white)
                .lineLimit(2)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.42)))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
// Mirrors `moments.jsx` `LBEventJoinLine`: a dark translucent card with an
// accent border + glow, an accent-gradient ticket/sparkle chip, the 2-line
// keyword copy, and a trailing「加入活動」CTA that flips to a「已參加」chip when
// joined. The ONLY interactive row in the stream — its tap is FORWARDED via
// `onJoin` (host wired); this layer never joins itself.

struct LBEventJoinLineRow: View {
    let theme: ReferenceUITheme
    let text: String
    let joined: Bool
    let onJoin: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            // Accent-gradient ticket/sparkle chip (26×26, radius 8).
            RoundedRectangle(cornerRadius: 8)
                .fill(Self.chipGradient(theme.accent))
                .frame(width: 26, height: 26)
                .overlay(
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white))

            // 2-line keyword copy (full prebuilt text, NOT split).
            Text(text.isEmpty ? Self.defaultEventCopy : text)
                .font(.system(size: 12 * theme.fontScale, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: 150, alignment: .leading)

            // Trailing CTA: 加入活動 (accent button) / 已參加 (translucent chip).
            if joined {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .heavy))
                    Text(Self.joinedLabel)
                        .font(.system(size: 12 * theme.fontScale, weight: .bold))
                }
                .foregroundColor(Color.white.opacity(0.72))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.white.opacity(0.16)))
            } else {
                Button(action: onJoin) {
                    Text(Self.joinLabel)
                        .font(.system(size: 12.5 * theme.fontScale, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(theme.accent))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.init(top: 7, leading: 10, bottom: 7, trailing: 7))
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Self.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(theme.accent, lineWidth: 1)))
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Card fill (`rgba(20,20,24,0.72)`).
    static let cardFill = Color(hex: "#141418")?.opacity(0.72) ?? Color.black.opacity(0.72)
    /// 加入活動 CTA label.
    static let joinLabel = "加入活動"
    /// 已參加 joined-state label.
    static let joinedLabel = "已參加"
    /// Fallback copy when `text` is empty (`LBEventJoinLine` default copy).
    static let defaultEventCopy = "🎉 抽獎開始！留言「抽獎」即可參加"

    /// Accent → darker-accent gradient for the chip (`linear-gradient(135deg,
    /// accent, lbShade(accent,-0.28))`). Approximated with the accent over a 28%
    /// black-shaded variant.
    static func chipGradient(_ accent: Color) -> LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [accent, accent.opacity(0.78)]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing)
    }
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

    private var slotFill: Color {
        switch tier {
        case .join: return Color.white.opacity(0.16)
        case .purchase, .intro, .win: return theme.accent
        }
    }

    private var glyphName: String {
        switch tier {
        case .join: return "person.fill.badge.plus"
        case .purchase: return "bag.fill"
        case .intro: return "megaphone.fill"
        case .win: return "trophy.fill"
        }
    }

    private var glyphColor: Color {
        switch tier {
        case .join: return Color.white.opacity(0.85)
        case .purchase, .intro, .win: return .white
        }
    }

    // MARK: - Rounded-12 bubble, accent-wash by tier

    @ViewBuilder
    private var bubble: some View {
        switch tier {
        case .join:
            // 進場 — black 0.32, no accent wash.
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
        tier == .join ? Color.white.opacity(0.9) : .white
    }

    private var textWeight: Font.Weight {
        // join / purchase / intro = medium (500); win = bold (700).
        tier == .win ? .bold : .medium
    }
}
