import SwiftUI
import LivebuySDK
import LivebuyUI

// MARK: - LiveBottomBarView — family-1 player-shell LIVE bottom bar
//
// Spec: `reference-ui-rendering/spec.md`
//   § "LivebuyReferenceUI 渲染 LIVE 底部 bar（LiveBottomBarView），綁 bagCount / shareUrl / isReplay"
// Change: rb-align-ios-live-bottom-bar (D-1 + D-3).
//   Design source: `design/templates/minimal/live-chrome.jsx` → `LBLiveBottomBar` (lines 161-237).
//
// The LIVE-mode bottom bar. `screens.jsx` mode-branches the player chrome on
// `isLive`: the LIVE screen renders this horizontal bottom bar (`LBLiveBottomBar`)
// while the side rail (`LBPSideRail` / `OperationRailView`) is VOD-only (`!isLive`).
// The bar paints, left → right:
//
//   • a white shopping-bag button + cart badge (when `bagCount > 0`),
//   • a flex "留言..." TAP-TARGET pill (NOT an inline TextField — design `onComment`
//     opens a sheet; the real composer is the host's),
//   • a leading slot — NICKNAME (person-edit) in every variant except `chatClosed`, where
//     it is replaced by「更多」(⋯) opening `LiveMoreSheetView` (design R32,
//     `rb-ios-live-replay-more-menu-and-video-info-live-copy` — see `leadingSlotKind`),
//   • a trailing slot — SHARE in every variant except `chatClosed`, where it is replaced
//     by a CC (字幕) toggle forwarding `onToggleCC` (design R32 moves the CC button INTO
//     share's old position — see `trailingActionKind`),
//   • a like (heartFill) button — white by default, accent while `liked == true` (design R37,
//     `rb-ios-live-like-burst-restyle`; the caller drives the timing).
//
// `chatClosed` variant button count (design `LBLiveBottomBar`'s `replay` branch,
// `design/contract/components.md` line 67): FOUR icon buttons — bag / 更多 (leading slot,
// `更多`'s old CC position) / CC (trailing slot, share's old position) / heart. A 2026-09-03
// correction round restored the CC button (a prior pass replaced Share with More but dropped
// CC entirely, leaving only 3 buttons — see `onToggleCC`'s doc comment for the button's own
// functional history).
//
// Comment entry ALWAYS available (prerecorded-live-bottom-bar-comment, 問題 1): this bar
// renders ONLY for a live broadcast (`isLive == true`, i.e. `channel.liveStatus == 1`) /
// upcoming / introPlaying — true 回放/VOD (`liveStatus == 3`) uses the side rail, not this
// bar. A live broadcast's chat room is open REGARDLESS of the viewer's playback position,
// so the "留言..." pill and the nickname button are NEVER collapsed on `isReplay`. The
// prior "replay variant" (disabled "聊天室已關閉" + CC swap) is removed: `isReplay` was a
// playback-position heuristic that mis-flags a 預錄直播 (a finite-length HLS routed to the
// IVS engine, `position < duration - 5` immediately true) and wrongly closed its chat.
//
// Upcoming SLIM variant (rb-ios-upcoming-live-chrome): when `isUpcoming`, the comment
// area collapses to a flex spacer and the nickname button is dropped — only bag + share +
// like remain (the stream hasn't started, so there is no chat). Mirrors
// `LBLiveBottomBar({ upcoming: true })` (`live-chrome.jsx` lines 195-197). Used for the
// awaitingLive countdown.
//
// bag-only variant (rb-ios-intro-chrome-minimal): when `bagOnly`, the bar collapses
// further to JUST the shopping-bag button + a trailing flex spacer — comment / nickname
// / share / like are ALL dropped. This is the minimal chrome for 直播預告的開場影片
// (`introPlaying`, the upcoming intro MP4 playing). `bagOnly` takes PRECEDENCE over
// `isUpcoming`. (awaitingLive keeps the slim three-button bar above.)
//
// One-way data flow (mirrors OperationRailView): this view reads ONLY its passed-in
// SNAPSHOT VALUES (`bagCount` / `isReplay`); it never reaches back into
// PlayerShellModel / DefaultPlayerTemplate, and it does NOT call any core
// `simulate*`. Every button surfaces a single intent closure that the shell / host
// wires to the matching template/core exit. A nil closure renders an inert button
// (demo / snapshot).
//
// iOS-14-safe SwiftUI only: `HStack` / `ZStack` / `Capsule` / `Circle` /
// `LinearGradient` / `Image(systemName:)` + `PlainButtonStyle` are all iOS-13+.
// No `ScrollView` / `Lazy*` (the `ImageRenderer` snapshot path renders those blank).
//
// The user-facing string ("留言...") is design-literal (the minimal design mockup is the
// source of truth); localization is a cross-layer follow-up.

/// The family-1 LIVE bottom bar surface. Renders the horizontal bag / comment /
/// nickname / share / like row from `LBLiveBottomBar`. The comment entry is always
/// available for a live broadcast (prerecorded-live-bottom-bar-comment).
public struct LiveBottomBarView: View {

    // MARK: - Inputs (sub-view input pattern: theme, snapshot values, actions)

    /// The resolved reference-ui theme (FIRST positional argument, always).
    public let theme: ReferenceUITheme

    /// Shopping-bag badge count. `> 0` → draw the badge on the bag button.
    public let bagCount: Int

    /// Replay (behind-live-edge) flag. RETAINED for source compatibility, but it NO LONGER
    /// alters this bar's comment / nickname rendering: the LIVE bottom bar renders only for a
    /// live broadcast (whose chat room is open regardless of playback position), so the comment
    /// entry is always available (prerecorded-live-bottom-bar-comment, 問題 1). The header's
    /// separate LIVE-pill `isReplay` handling (`PlayerHeaderBarView`) is a different surface.
    public let isReplay: Bool

    /// Upcoming (直播預告) SLIM variant flag. `true` → the comment area collapses to a
    /// flex spacer and the nickname / CC button is dropped — only bag + share + like
    /// remain (the stream hasn't started, so there is no chat). Mirrors
    /// `LBLiveBottomBar({ upcoming: true })`. Takes precedence over `isReplay`.
    public let isUpcoming: Bool

    /// Bag-only variant flag (直播預告的開場影片 `introPlaying`). `true` → the bar collapses to
    /// JUST the shopping-bag button + a trailing flex spacer (bag left-anchored); the
    /// comment area / nickname / CC / share / like are ALL dropped. This is the minimal
    /// intro-MP4 chrome (`rb-ios-intro-chrome-minimal`). Takes PRECEDENCE over `isUpcoming`
    /// / `isReplay` (when `bagOnly` is true, the other variant flags are ignored).
    public let bagOnly: Bool

    /// 回放（已結束直播）聊天室已關閉旗標。`true`（來源 `PlayerShellModel.isFinishedLiveReplay`，
    /// `type==3 || (type==2 && liveStatus==3)`）→ 留言區改 disabled「聊天室已關閉」（非互動）、暱稱隱藏：
    /// 因後端 `POST /sdk/video/commentsub` 對已結束直播回 404（`notLive`）。**與 behind-edge `isReplay`
    /// 不同**——`isReplay`（仍 `liveStatus==1` 的預錄直播）留言恆開（prerecorded-live-bottom-bar-comment）；
    /// `chatClosed` 才是真正已結束的回放。優先序低於 `bagOnly` / `isUpcoming`（rb-ios-replay-chat-closed-bottom-bar）。
    public let chatClosed: Bool

    /// Bag tap → host opens the product list. nil → inert.
    public let onBag: (() -> Void)?
    /// "留言..." tap → host opens its comment composer / nickname flow. nil → inert.
    public let onComment: (() -> Void)?
    /// Nickname (person-edit) tap → host opens the guest-name-edit flow. nil → inert.
    public let onNickname: (() -> Void)?
    /// Share tap → host-wired share exit. nil → inert.
    public let onShare: (() -> Void)?
    /// Like (❤️) tap → host-wired like exit. nil → inert.
    public let onLike: (() -> Void)?
    /// CC (字幕) toggle → host-wired subtitle toggle. RESTORED 2026-09-03 (correction round,
    /// `rb-ios-live-replay-more-menu-and-video-info-live-copy`) after a brief period as
    /// source-compat-only dead weight: `prerecorded-live-bottom-bar-comment` (2026-06-18)
    /// removed this button's RENDERING (it used to swap in for the nickname slot on the old,
    /// now-defunct `isReplay`-driven replay variant) while keeping the closure param for ABI
    /// compat; design R32 (2026-09-03) re-introduces a CC button for the `chatClosed` variant,
    /// in the TRAILING slot (share's old position — see `trailingActionKind`), not the
    /// leading/nickname slot it originally occupied.
    ///
    /// ⚠️ Functional history (verified against git history + `PlayerShellView`'s caption
    /// rendering gate before restoring this): pre-removal, `PlayerShellView` wired this to the
    /// SAME real forwarder restored below (`model.toggleSubtitle()`) — never a no-op — so this
    /// is NOT "reviving inert UI debris." But `CaptionOverlayView` has been gated on `!isLive`
    /// since its very first commit, and `isReplay` (the old trigger) implies `isLive == true`
    /// exactly like `chatClosed`/`isFinishedLiveReplay` does today — so toggling this NEVER
    /// produced a visible caption while this button was live-chrome-side, either historically
    /// or now. Restoring the button + its historical wiring is faithful parity (matches
    /// `OperationRailView`'s still-active VOD `.subtitle` rail item, which forwards to the
    /// identical `model.toggleSubtitle()`); extending `CaptionOverlayView`'s rendering gate to
    /// the live-chrome branch so a caption actually appears is a SEPARATE, larger scope
    /// EXPLICITLY NOT undertaken in this round — see design.md.
    ///
    /// nil → inert (demo / snapshot). Only forwarded when `CcIconState` is `.on`/`.off`
    /// (`subtitleAvailable == true`) — `rb-ios-cc-icon-availability-redesign` — an `.unavailable`
    /// tap (`subtitleAvailable == false`) swallows the tap and shows `SubtitleUnavailableTooltip`
    /// instead, never calling this closure.
    public let onToggleCC: (() -> Void)?
    /// LIVE 讚鈕亮色狀態（design R37 `LBLiveBottomBar` — `liked` prop，`rb-ios-live-like-burst-restyle`）。
    /// **預設 `false` → 白色**（與其餘 icon 一致）；`PlayerShellView` 在使用者點擊愛心後把它設為
    /// `true`，並在本地計時（隨飄心次數而定，見 `PlayerShellView.likeGlowDurationMs(count:)`）過後
    /// 恢復 `false`。**與舊行為的差異**：愛心圖示先前恆為 `theme.accent`（不論是否剛按過）；本
    /// 旗標把它改為「沒按時白色、按了之後短暫亮 accent」，其餘四顆 icon（購物袋 / 暱稱或更多 /
    /// 分享或 CC）不受影響、維持既有色彩。This sub-view remains READ-ONLY presentation: it does
    /// NOT drive the timer itself, only paints the tint the caller passes in.
    public let liked: Bool
    /// 「更多」(⋯) tap → host opens `LiveMoreSheetView` (分享 + 客服). Only rendered in the
    /// `chatClosed` (finished-live-replay) variant, in the LEADING slot (nickname's position —
    /// design `LBLiveBottomBar` R32: the old CC-toggle slot now shows「更多」; CC itself moves
    /// to the TRAILING slot, share's old position — see `leadingSlotKind` / `trailingActionKind`
    /// below). nil → inert.
    /// A fresh seam rather than repurposing `onToggleCC`: the two are now DISTINCT buttons in
    /// DISTINCT slots that both render simultaneously in the `chatClosed` variant, so they could
    /// not share one closure even if naming allowed it (rb-ios-live-replay-more-menu-and-video-info-live-copy).
    public let onMore: (() -> Void)?

    /// 是否目前已啟用字幕（CC）——僅影響 `chatClosed` 變體 TRAILING slot 的 CC 切換鈕，資料來源與
    /// `OperationRailView` 呼叫端已在用的既有 `PlayerShellModel.subtitleEnabled` 完全同一個欄位
    /// （NOT 一個新 view-model 欄位）。與 `subtitleAvailable`（見其自身 doc comment）一起經
    /// `CcIconState.resolve` 解出三態（`rb-ios-cc-icon-availability-redesign`，MODIFIED——先前僅本
    /// 欄位單獨驅動二態）：`subtitleAvailable && true` → `.on`（按鈕背景轉 `Color.white`、`CcGlyph`
    /// 顏色轉 `theme.accent`）；`subtitleAvailable && false`（**預設**）→ `.off`（維持既有的半透明
    /// 深色底 + 白色 glyph，與修正前行為一致）；`!subtitleAvailable` → `.unavailable`（不論本欄位值）。
    /// 預設值 `false`（而非比照 `OperationRailView` 走必填參數）讓既有的多個測試 / Preview / demo
    /// 呼叫點零修改仍可編譯——只有生產呼叫點（`PlayerShellView`）需要接上真實值。對 `.share` /
    /// `.nickname` / `.more` / 購物袋 / 愛心任一按鈕的背景色或圖示顏色 MUST NOT 影響。
    public let subtitleEnabled: Bool

    /// 是否有字幕來源可用（`subtitleAvailable`，`rb-ios-cc-icon-availability-redesign`）——與
    /// `OperationRailView`（`items[.subtitle].enabled`）讀的是同一個既有 view-model 布林值，這裡
    /// 是**新** init 參數，因為 LIVE 底部 bar 先前完全沒有可用性訊號。連同 `subtitleEnabled` 一起
    /// 解出 `CcIconState`（`.on` / `.off` / `.unavailable`）。**預設 `true`**（源碼相容——既有的多個
    /// 測試 / Preview / demo 呼叫點零修改仍可編譯，等同「原本就恆可用」的既有觀感）；正式生產呼叫點
    /// （`PlayerShellView`）由既有 `model.railItems` 推導帶入真實值，不新增任何 `PlayerShellModel`
    /// API。`false`（無字幕來源）時 TRAILING slot 的 `.cc` 分支改畫 `CcUnavailableGlyph`（固定灰、
    /// 非正方形），點擊 MUST NOT 轉發 `onToggleCC`——改顯示本地提示泡泡（見 `handleCcTap(state:)`）。
    public let subtitleAvailable: Bool

    /// Local, presentation-only UI state: whether the CC toggle's `.unavailable`-state transient
    /// tooltip (`SubtitleUnavailableTooltip`) is currently shown (`rb-ios-cc-icon-availability-
    /// redesign`). NOT part of the public init shape — mirrors `PlayerShellView.liveLiked`'s
    /// identically-shaped local timed UI state.
    @State private var subtitleTooltipVisible = false

    // MARK: - Viewport-clamp geometry state (`rb-ios-cc-tooltip-viewport-clamp`)
    //
    // Three measured inputs to `SubtitleUnavailableTooltip.clampedTopOffsetX` — see that
    // function's own doc comment for why they are measured via a NAMED `GeometryReader`
    // coordinate space anchored to THIS view's own root (`ccTooltipViewportSpace`) rather than
    // `UIScreen.main.bounds`/`.global`. All three default to `0` ("not yet measured"), which the
    // clamp function's own guard treats as "apply no additional shift" — matching this package's
    // existing `LoopingVideoView.onScreen` precedent (seeded to a safe default, corrected once
    // real geometry lands).

    /// The bar's own measured width — a self-contained proxy for "the viewport" (in production
    /// this bar spans the full device width via `.frame(maxWidth: .infinity)` inside a
    /// full-screen player). The isolated `ccToggleButtonForTesting(tooltipVisible:)` test
    /// accessor (used by the EXISTING `live-bottom-bar-chat-closed-cc-tooltip-visible` baseline)
    /// renders ONLY `ccToggleButton`'s own subtree, never `body`'s probe — so this stays `0`
    /// there, the clamp is a guaranteed no-op, and that baseline is unaffected by this change.
    @State private var ccTooltipViewportWidth: CGFloat = 0

    /// The CC toggle button's own horizontal center, in the SAME named coordinate space as
    /// `ccTooltipViewportWidth` — the second input to the clamp calculation.
    @State private var ccButtonCenterXInBar: CGFloat = 0

    /// The CC tooltip bubble's own measured width — the third input. `0` until the tooltip is
    /// first shown and its own `GeometryReader` reports real geometry (the tooltip renders
    /// nothing while `show == false`, so this is genuinely unmeasured, not just stale, at rest).
    @State private var ccTooltipBubbleWidth: CGFloat = 0

    public init(
        theme: ReferenceUITheme,
        bagCount: Int,
        isReplay: Bool,
        isUpcoming: Bool = false,
        bagOnly: Bool = false,
        chatClosed: Bool = false,
        liked: Bool = false,
        subtitleEnabled: Bool = false,
        subtitleAvailable: Bool = true,
        onBag: (() -> Void)? = nil,
        onComment: (() -> Void)? = nil,
        onNickname: (() -> Void)? = nil,
        onShare: (() -> Void)? = nil,
        onLike: (() -> Void)? = nil,
        onToggleCC: (() -> Void)? = nil,
        onMore: (() -> Void)? = nil
    ) {
        self.theme = theme
        self.bagCount = bagCount
        self.isReplay = isReplay
        self.isUpcoming = isUpcoming
        self.bagOnly = bagOnly
        self.chatClosed = chatClosed
        self.liked = liked
        self.subtitleEnabled = subtitleEnabled
        self.subtitleAvailable = subtitleAvailable
        self.onBag = onBag
        self.onComment = onComment
        self.onNickname = onNickname
        self.onShare = onShare
        self.onLike = onLike
        self.onToggleCC = onToggleCC
        self.onMore = onMore
    }

    // MARK: - Body

    public var body: some View {
        HStack(spacing: Self.barGap) {
            bagButton

            // bag-only variant (introPlaying intro MP4) — JUST the bag + a trailing flex
            // spacer (bag left-anchored). Takes precedence over every other variant: the
            // comment area / nickname / CC / share / like are all dropped. The flex uses
            // `Color.clear` + `maxWidth: .infinity` (NOT a bare Spacer) so the bag stays
            // left even when the bar is hosted without an explicit width proposal.
            if bagOnly {
                Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
            } else {
                // Flex comment area — variant resolved by the pure `commentAreaKind`:
                //   • upcoming(slim) → an ACTIVE flex spacer (no chat before the stream starts).
                //   • chatClosed(回放) → disabled「聊天室已關閉」(non-interactive): the FINISHED live's
                //     chat room is closed (backend commentsub → 404 notLive). Distinct from a
                //     behind-edge `isReplay` (a live broadcast where the viewer scrubbed back —
                //     still liveStatus==1, chat OPEN → keep the tap-target "留言...").
                //   • comment → the tap-target "留言..." (LIVE, incl. 預錄直播 mis-flagged isReplay).
                // The flex spacer uses `Color.clear` + `maxWidth: .infinity` (mirrors design
                // `<div flex:1/>` and the LIVE commentPill), NOT a bare `Spacer` — a bare Spacer
                // collapses to ideal-width without an explicit width proposal, pushing the end
                // buttons (bag / like) off-screen.
                switch Self.commentAreaKind(bagOnly: bagOnly, isUpcoming: isUpcoming, chatClosed: chatClosed) {
                case .upcomingSpacer:
                    Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                case .chatClosed:
                    chatClosedPill
                case .comment:
                    commentPill
                case .bagOnlySpacer:
                    // Unreachable here (bagOnly handled above), but keeps the switch total.
                    Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                }

                // Leading slot — NICKNAME in the normal LIVE variant, 更多 (More) in chatClosed
                // (design `LBLiveBottomBar` R32: More occupies the nickname/CC slot's position),
                // NOTHING in upcoming slim (design gates both on `!upcoming`) — see
                // `leadingSlotKind`. 2026-09-03 correction round: a prior pass simply omitted
                // this slot's content in chatClosed instead of rendering More here (More had been
                // misplaced into the TRAILING slot, displacing CC entirely — see git history /
                // design.md for the correction).
                switch Self.leadingSlotKind(bagOnly: bagOnly, isUpcoming: isUpcoming, chatClosed: chatClosed) {
                case .nickname:
                    // 設定暱稱 draws the hand-drawn person-EDIT composite (head + pencil
                    // badge, design `live-chrome.jsx` ≈224), not SF `person.fill`
                    // (rb-align-nickname-icon-person-edit).
                    iconButton(action: onNickname) { PersonEditGlyph(size: Self.iconGlyphSize, color: .white) }
                        .accessibilityIdentifier(LBAccessibilityID.livePersonEdit)
                case .more:
                    iconButton(action: onMore) { MoreGlyph(size: Self.iconGlyphSize, color: .white) }
                        .accessibilityIdentifier(LBAccessibilityID.liveMore)
                case .none:
                    EmptyView()
                }

                // Trailing slot — SHARE in every variant EXCEPT chatClosed, where design R32
                // moves the CC (字幕) toggle into this position (share itself moves INTO the new
                // `LiveMoreSheetView`「更多」sheet instead) — see `trailingActionKind`. Share
                // draws the hand-drawn `ShareGlyph` (design `Icons.share`), not SF
                // `square.and.arrow.up` (rb-ios-share-icon-design-align). CC draws the hand-drawn
                // `CcGlyph` (design `Icons.cc`), not SF Symbol `captions.bubble`
                // (rb-ios-live-bottom-bar-cc-icon-align) — the same glyph `OperationRailView`'s
                // VOD `.subtitle` rail item already draws (rb-ios-cc-icon-design-align), so the
                // two CC call sites in this package are now visually consistent.
                trailingAction
                // 亮色狀態 SHALL 依 `liked`（design R37）：沒按時白色（與其餘 icon 一致）、按了
                // 之後短暫亮 accent（`rb-ios-live-like-burst-restyle`；舊行為恆為 accent）。
                iconButton(symbol: Self.likeSymbol, tint: liked ? theme.accent : .white, action: onLike)
                    .accessibilityIdentifier(LBAccessibilityID.liveHeart)
            }
        }
        .padding(.horizontal, Self.barHPadding)
        .padding(.top, Self.barTopPadding)
        .padding(.bottom, Self.barBottomPadding)
        .frame(maxWidth: .infinity)
        // rb-ios-live-chrome-gradient-removal: no background scrim (design dropped
        // `LBLiveBottomBar`'s `linear-gradient(to top, rgba(0,0,0,0.55), transparent)` 2026-08-31).
        // rb-ios-cc-tooltip-viewport-clamp: names this view's own root as the coordinate space
        // the CC toggle's viewport-clamp geometry (`ccButtonCenterXInBar` / `ccTooltipViewportWidth`)
        // is measured in, and probes this view's OWN width via an invisible `Color.clear`
        // `GeometryReader` background (mirrors `LoopingVideoView`'s established off-screen-probe
        // idiom) — zero visual/layout footprint, so every EXISTING baseline is byte-unaffected.
        .coordinateSpace(name: Self.ccTooltipViewportSpace)
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: CcTooltipViewportWidthPreferenceKey.self, value: geo.size.width)
            }
        )
        .onPreferenceChange(CcTooltipViewportWidthPreferenceKey.self) { ccTooltipViewportWidth = $0 }
    }

    // MARK: - Bag button (`LBLiveBottomBar` bag)

    /// White circle + accent bag glyph + soft shadow, with the cart badge when
    /// `bagCount > 0` (accent fill, white text, white border, top-trailing).
    private var bagButton: some View {
        Button(action: { onBag?() }) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .shadow(color: Color.black.opacity(0.2), radius: 5, x: 0, y: 4)
                    BagGlyph(size: Self.bagGlyphSize, color: theme.accent)
                }
                .frame(width: Self.iconSize, height: Self.iconSize)

                if bagCount > 0 {
                    cartBadge.offset(x: 2, y: -2)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier(LBAccessibilityID.liveBagButton)
    }

    private var cartBadge: some View {
        Text(Self.badgeText(bagCount))
            .font(.system(size: Self.badgeFontSize, weight: .heavy))
            .foregroundColor(.white)
            .padding(.horizontal, 4)
            .frame(minWidth: Self.badgeMinSize, minHeight: Self.badgeMinSize)
            .background(Capsule().fill(theme.accent))
            .overlay(Capsule().stroke(Color.white, lineWidth: Self.badgeBorderWidth))
    }

    // MARK: - Comment area

    /// Flex tap-target "留言..." pill — a button (NOT an inline TextField); tap
    /// forwards `onComment` to the host (design `onComment` opens a sheet).
    private var commentPill: some View {
        Button(action: { onComment?() }) {
            HStack(spacing: 0) {
                Text(Self.commentPlaceholder)
                    .font(.system(size: Self.commentFontSize))
                    .foregroundColor(Color.white.opacity(0.78))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Self.commentHPadding)
            .frame(height: Self.iconSize)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(Self.commentBackground))
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier(LBAccessibilityID.liveCommentPill)
    }

    /// Disabled「聊天室已關閉」flex pill for the 回放 (finished-live) variant — a NON-interactive
    /// `HStack` (NOT a `Button`), so a tap does nothing (no `onComment` → no composer, no
    /// 「請先登入」mis-fire, no commentsub 404). Dimmer than the active pill (text 0.5 vs 0.78,
    /// fainter capsule) to read as disabled. String is design-literal (mirrors `commentPlaceholder`).
    private var chatClosedPill: some View {
        HStack(spacing: 0) {
            Text(Self.chatClosedPlaceholder)
                .font(.system(size: Self.commentFontSize))
                .foregroundColor(Color.white.opacity(0.5))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Self.commentHPadding)
        .frame(height: Self.iconSize)
        .frame(maxWidth: .infinity)
        .background(Capsule().fill(Self.commentBackground.opacity(0.6)))
        .accessibilityIdentifier(LBAccessibilityID.liveCommentPill)
    }

    // MARK: - Comment-area variant (pure, unit-testable — no rendering)

    /// Which thing the flex comment area draws. Pure decision of the three variant flags
    /// (`commentAreaKind`), extracted so the precedence is unit-testable without rendering
    /// (mirrors `PlayerShellView.resolveGestureEnd` discipline).
    enum CommentAreaKind: Equatable { case bagOnlySpacer, upcomingSpacer, chatClosed, comment }

    /// Resolve the comment-area variant. Precedence: `bagOnly` > `isUpcoming` > `chatClosed`
    /// > 正常留言. Pure (no I/O, no UIKit).
    static func commentAreaKind(bagOnly: Bool, isUpcoming: Bool, chatClosed: Bool) -> CommentAreaKind {
        if bagOnly { return .bagOnlySpacer }
        if isUpcoming { return .upcomingSpacer }
        if chatClosed { return .chatClosed }
        return .comment
    }

    /// Whether the nickname (person-edit) button shows — only in the normal LIVE variant.
    /// Pure (unit-testable). Dropped in upcoming slim / bag-only / 回放 chat-closed. RETAINED
    /// as its own boolean (existing tests read it directly); `leadingSlotKind` below is the
    /// render-time source of truth and is defined in terms consistent with this predicate
    /// (`leadingSlotKind(...) == .nickname` iff `showsNickname(...) == true`).
    static func showsNickname(bagOnly: Bool, isUpcoming: Bool, chatClosed: Bool) -> Bool {
        !bagOnly && !isUpcoming && !chatClosed
    }

    /// Which affordance the LEADING slot (between the comment area and the trailing slot)
    /// draws (`rb-ios-live-replay-more-menu-and-video-info-live-copy`, design R32). Pure
    /// (unit-testable, no rendering) — mirrors `commentAreaKind`'s discipline. This is the
    /// slot the OLD (pre-`prerecorded-live-bottom-bar-comment`) CC toggle used to occupy;
    /// design R32 now puts「更多」there for `chatClosed` instead of CC (CC itself moves to
    /// the TRAILING slot — see `trailingActionKind`).
    enum LeadingSlotKind: Equatable { case nickname, more, none }

    /// Resolve the leading slot's variant: `bagOnly` or `isUpcoming` → `.none` (neither
    /// affordance applies — bag-only drops this whole section, upcoming slim has no chat to
    /// moderate); `chatClosed` → `.more`; otherwise → `.nickname` (normal LIVE). Pure (no I/O,
    /// no UIKit). `bagOnly` is defensive-complete (this whole section is skipped by the
    /// `if bagOnly` branch in `body` before this is ever consulted), matching
    /// `trailingActionKind`'s own signature shape.
    static func leadingSlotKind(bagOnly: Bool, isUpcoming: Bool, chatClosed: Bool) -> LeadingSlotKind {
        if bagOnly || isUpcoming { return .none }
        return chatClosed ? .more : .nickname
    }

    /// Which affordance the TRAILING slot (between the leading slot and like) draws
    /// (`rb-ios-live-replay-more-menu-and-video-info-live-copy`, design R32). Pure
    /// (unit-testable, no rendering) — mirrors `commentAreaKind` / `leadingSlotKind`'s
    /// discipline. This is the slot the OLD (pre-`prerecorded-live-bottom-bar-comment`) Share
    /// button unconditionally occupied; design R32 now puts CC (字幕) there for `chatClosed`
    /// instead (Share itself moves INTO the new「更多」sheet — see `LeadingSlotKind.more`).
    enum TrailingActionKind: Equatable { case share, cc }

    /// Resolve the trailing action slot's variant: `chatClosed` (finished-live-replay, and
    /// not `bagOnly`/`isUpcoming` — those two variants keep their own unrelated trailing
    /// affordance, `share`, unaffected by this swap) → `.cc` (design moves CC INTO share's old
    /// position for this ONE variant); every other combination → `.share` (unchanged). Pure
    /// (no I/O, no UIKit).
    static func trailingActionKind(bagOnly: Bool, isUpcoming: Bool, chatClosed: Bool) -> TrailingActionKind {
        (!bagOnly && !isUpcoming && chatClosed) ? .cc : .share
    }

    /// The TRAILING slot's actual content — extracted out of `body`'s inline `switch`
    /// (rb-ios-live-bottom-bar-cc-icon-align) purely so `trailingActionForTesting` below can
    /// hand a test a bounded subtree to `Mirror`-walk (mirrors `OperationRailView
    /// .pillButtonForTesting`'s reasoning: `body` mixes this slot's content with the leading
    /// slot / bag button / like button, so asserting on `body` directly cannot isolate what
    /// THIS slot alone draws). Behavior is byte-identical to the inline `switch` it replaces.
    @ViewBuilder
    private var trailingAction: some View {
        switch Self.trailingActionKind(bagOnly: bagOnly, isUpcoming: isUpcoming, chatClosed: chatClosed) {
        case .share:
            iconButton(action: onShare) { ShareGlyph(size: Self.iconGlyphSize, color: .white) }
                .accessibilityIdentifier(LBAccessibilityID.liveShare)
        case .cc:
            // 3-state icon (`rb-ios-cc-icon-availability-redesign`, MODIFIED — supersedes the
            // prior 2-state `subtitleEnabled`-only active-fill logic): `CcIconState.resolve`
            // combines `subtitleAvailable` (NEW — see its own doc comment) with `subtitleEnabled`
            // to pick `.on` / `.off` / `.unavailable`, extracted into `ccToggleButton` (its own
            // function, mirrors `OperationRailView.subtitlePillButton`) so it can attach a
            // tooltip overlay alongside the button — a plain `iconButton(...)` call chain cannot
            // add a sibling node.
            ccToggleButton(tooltipVisible: subtitleTooltipVisible)
        }
    }

    /// The TRAILING slot's `.cc` content: 3-state icon (`CcIconState`) + tap-routing (`.on`/
    /// `.off` forward `onToggleCC`; `.unavailable` shows `SubtitleUnavailableTooltip` instead,
    /// `rb-ios-cc-icon-availability-redesign`). Extracted out of `trailingAction`'s `switch` (same
    /// reasoning as `trailingAction` itself, and mirrors `OperationRailView.subtitlePillButton`)
    /// so the button + tooltip compose cleanly.
    ///
    /// Takes `tooltipVisible` as a parameter (rather than reading `subtitleTooltipVisible`
    /// directly) so `ccToggleButtonForTesting(tooltipVisible:)` below can force the tooltip
    /// visible without simulating a real tap + timer (`rb-ios-cc-tooltip-position-fix`). The
    /// tooltip is attached via `.overlay(_:alignment:)` (NOT a raw `ZStack`) so it does NOT
    /// influence the button's own reported size to the bottom bar's `HStack` — see
    /// `SubtitleUnavailableTooltip.positionedOutsideButton()`'s doc comment.
    ///
    /// `rb-ios-cc-tooltip-viewport-clamp`: on top of `positionedOutsideButton()`'s centered
    /// placement, an additional `.offset(x: clampOffsetX)` nudges the bubble back inside the
    /// viewport when this button sits close to its trailing edge (`chatClosed`'s CC button is
    /// the LAST-but-one element in the row). `clampOffsetX` is computed by the pure
    /// `SubtitleUnavailableTooltip.clampedTopOffsetX` from three geometry inputs measured here via
    /// `GeometryReader` + `PreferenceKey` (see the `@State` declarations' own doc comments for why
    /// this button's own anchor + the bar's own width, not `UIScreen.main.bounds`, are the inputs).
    ///
    /// `rb-ios-cc-tooltip-arrow-anchor-fix`: `clampOffsetX` shifts the WHOLE tooltip (bubble +
    /// arrow), which used to leave the arrow no longer pointing at this button once the clamp
    /// engaged. `arrowOffsetX` (`SubtitleUnavailableTooltip.arrowCompensationOffsetX`) is the
    /// equal-and-opposite compensation passed through to keep the arrow pinned to
    /// `ccButtonCenterXInBar` regardless of `clampOffsetX`.
    private func ccToggleButton(tooltipVisible: Bool) -> some View {
        let state = CcIconState.resolve(subtitleAvailable: subtitleAvailable, subtitleEnabled: subtitleEnabled)
        let active = state.isActiveFill
        let placement = SubtitleUnavailableTooltip.Placement.top
        let clampOffsetX = SubtitleUnavailableTooltip.clampedTopOffsetX(
            anchorCenterX: ccButtonCenterXInBar,
            bubbleWidth: ccTooltipBubbleWidth,
            viewportWidth: ccTooltipViewportWidth
        )
        // rb-ios-cc-tooltip-arrow-anchor-fix: the arrow-alone compensation, equal-and-opposite
        // to `clampOffsetX` — see `arrowCompensationOffsetX(bubbleShift:)`'s doc comment. Keeps
        // the arrow pinned to `ccButtonCenterXInBar` even while `clampOffsetX` nudges the bubble
        // body to stay inside the viewport.
        let arrowOffsetX = SubtitleUnavailableTooltip.arrowCompensationOffsetX(bubbleShift: clampOffsetX)
        return Button(action: { handleCcTap(state: state) }) {
            ZStack {
                Circle().fill(active ? Color.white : Self.iconButtonBackground)
                ccGlyph(for: state)
            }
            .frame(width: Self.iconSize, height: Self.iconSize)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier(LBAccessibilityID.liveCC)
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: CcButtonAnchorXPreferenceKey.self,
                    value: geo.frame(in: .named(Self.ccTooltipViewportSpace)).midX
                )
            }
        )
        .onPreferenceChange(CcButtonAnchorXPreferenceKey.self) { ccButtonCenterXInBar = $0 }
        .overlay(
            SubtitleUnavailableTooltip(show: tooltipVisible, placement: placement, arrowOffsetX: arrowOffsetX)
                .positionedOutsideButton()
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: CcTooltipBubbleWidthPreferenceKey.self, value: geo.size.width)
                    }
                )
                .onPreferenceChange(CcTooltipBubbleWidthPreferenceKey.self) { ccTooltipBubbleWidth = $0 }
                .offset(x: clampOffsetX),
            alignment: placement.overlayAlignment
        )
    }

    /// TEST-ONLY: renders the `.cc` trailing-slot button with the tooltip forced to a given
    /// visibility (`rb-ios-cc-tooltip-position-fix`) — mirrors `trailingActionForTesting`'s
    /// established precedent, and `OperationRailView.subtitlePillButtonForTesting`'s identical
    /// reasoning for the sibling call site.
    func ccToggleButtonForTesting(tooltipVisible: Bool) -> some View {
        ccToggleButton(tooltipVisible: tooltipVisible)
    }

    /// The `.cc` toggle's glyph for a given `CcIconState` — `@ViewBuilder` so the 3-way switch
    /// composes directly (no `AnyView`), matching `ccToggleButton`'s reasoning.
    @ViewBuilder
    private func ccGlyph(for state: CcIconState) -> some View {
        switch state {
        case .on:
            CcGlyph(size: Self.iconGlyphSize, color: theme.accent, state: .on)
        case .off:
            CcGlyph(size: Self.iconGlyphSize, color: .white, state: .off)
        case .unavailable:
            CcUnavailableGlyph(size: Self.iconGlyphSize)
        }
    }

    /// Routes a `.cc` toggle tap: `.on`/`.off` forward the existing `onToggleCC` intent
    /// unchanged; `.unavailable` shows the transient tooltip instead
    /// (`rb-ios-cc-icon-availability-redesign`).
    private func handleCcTap(state: CcIconState) {
        if state.forwardsToggleTapIntent {
            onToggleCC?()
        } else {
            showSubtitleTooltipTransiently()
        }
    }

    /// Shows `subtitleTooltipVisible` and schedules its own reset — mirrors
    /// `PlayerShellView`'s established `liveLiked` + `DispatchQueue.main.asyncAfter` self-reset
    /// pattern for identically-shaped local timed UI state (same technique
    /// `OperationRailView.showSubtitleTooltipTransiently()` uses for its own copy of this
    /// tooltip).
    private func showSubtitleTooltipTransiently() {
        subtitleTooltipVisible = true
        DispatchQueue.main.asyncAfter(deadline: .now() + CcUnavailableTooltipTiming.autoDismissSeconds) {
            subtitleTooltipVisible = false
        }
    }

    /// Test-only access to `trailingAction`'s rendered subtree (mirrors `OperationRailView
    /// .pillButtonForTesting`). Not gated behind `#if DEBUG` — the sibling accessor isn't either
    /// (source parity), and this is a pure, side-effect-free computed property.
    var trailingActionForTesting: some View { trailingAction }

    // MARK: - Icon button (`LBLiveBottomBar` iconBtn)

    /// A round translucent-dark icon button (36×36). `tint` colors the glyph
    /// (white for nickname / share / CC; accent for like). nil action → inert.
    private func iconButton(symbol: String, tint: Color, action: (() -> Void)?) -> some View {
        Button(action: { action?() }) {
            ZStack {
                Circle().fill(Self.iconButtonBackground)
                Image(systemName: symbol)
                    .font(.system(size: Self.iconGlyphSize, weight: .semibold))
                    .foregroundColor(tint)
            }
            .frame(width: Self.iconSize, height: Self.iconSize)
        }
        .buttonStyle(PlainButtonStyle())
    }

    /// Glyph overload — same 36×36 round translucent-dark button, but drawing a custom glyph
    /// view (e.g. the hand-drawn `ShareGlyph`) instead of an SF Symbol
    /// (rb-ios-share-icon-design-align).
    private func iconButton<Glyph: View>(action: (() -> Void)?, @ViewBuilder glyph: () -> Glyph) -> some View {
        Button(action: { action?() }) {
            ZStack {
                Circle().fill(Self.iconButtonBackground)
                glyph()
            }
            .frame(width: Self.iconSize, height: Self.iconSize)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // The former `iconButton(active:action:glyph:)` overload (glyph + explicit "active" fill
    // state) has no remaining call site as of `rb-ios-cc-icon-availability-redesign` — the ONE
    // caller it existed for (`.cc` trailing-slot button) now needs a sibling tooltip node
    // alongside the `Button`, which this two-argument-closure shape cannot express, so that
    // button was inlined into `ccToggleButton` instead. Removed rather than left dead.

    // MARK: - Badge text

    /// Clamp very large counts so the badge stays compact (`99+` past 99).
    static func badgeText(_ count: Int) -> String {
        count > 99 ? "99+" : "\(count)"
    }

    // MARK: - Shared height token (rb-ios-caption-overlay-bottom-bar-clearance-fix)

    /// This bar's own real total rendered height (`barTopPadding + iconSize + barBottomPadding`,
    /// currently 60pt) — the SINGLE SOURCE OF TRUTH other family-1 surfaces positioned above this
    /// bar (currently `LiveOverlayChromeView`'s announce/pinned-card row + the `subtitleCaption`
    /// overlay stacked above it) MUST reference instead of re-guessing an independent literal.
    /// Before this change, `LiveOverlayChromeView` hardcoded a standalone `64` constant with ZERO
    /// compile-time/runtime coupling to this bar's actual height — any future edit to
    /// `barTopPadding` / `iconSize` / `barBottomPadding` below would silently NOT be reflected
    /// there, leaving an already-thin safety gap free to erode further unnoticed. Internal (not
    /// `public`) — both files live in the same `LivebuyReferenceUI` module, so this does not need
    /// to be host-visible API (mirrors `LiveOverlayChromeView.captionTrailingClearance`, also
    /// internal).
    static var barHeight: CGFloat { barTopPadding + iconSize + barBottomPadding }
}

// MARK: - Viewport-clamp geometry `PreferenceKey`s (`rb-ios-cc-tooltip-viewport-clamp`)
//
// Three `Color.clear`-background `GeometryReader` probes (`body`'s own width + `ccToggleButton`'s
// anchor + `SubtitleUnavailableTooltip`'s own bubble width) feed these into `@State` via
// `.onPreferenceChange` — see the `@State` declarations above and `ccToggleButton`'s doc comment.
// File-private: this plumbing is specific to THIS view's CC toggle, not a shared package type.

private struct CcTooltipViewportWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct CcButtonAnchorXPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct CcTooltipBubbleWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - Design tokens (lifted from `live-chrome.jsx` `LBLiveBottomBar`)

private extension LiveBottomBarView {
    // bar container
    static let barGap: CGFloat = 8            // flex gap
    static let barHPadding: CGFloat = 10      // padding: 8px 10px 16px (CSS 3-value shorthand)
    static let barTopPadding: CGFloat = 8
    // rb-ios-live-bottom-bar-16pt-align: bottom inset unified to 16pt so content sits the same
    // distance from the screen edge as the VOD floating bag button (`FloatingBagButtonView`'s
    // `bottom: 16pt`). Paired with the outer wrapper in PlayerShellView losing its static "8" —
    // net effect on content position is zero (see design.md algebra), only the background now
    // extends flush to the true bottom edge.
    static let barBottomPadding: CGFloat = 16

    // iconBtn (36×36 round, rgba(20,20,24,0.6))
    static let iconSize: CGFloat = 36
    static let iconGlyphSize: CGFloat = 18    // Icons size 18 (nickname / share / like)
    // 商品袋圖示專屬尺寸（rb-ios-live-bottom-bar-bag-icon-enlarge）：`LBLiveBottomBar` 設計稿
    // 只有 Icons.bag 用了比其他圖示更大的尺寸（25pt，約佔 36pt 容器 70%），只套用在 bagButton，
    // 不影響共用 iconGlyphSize（暱稱 / 分享 / 愛心維持 18pt）。
    static let bagGlyphSize: CGFloat = 25     // Icons.bag size 25 (~70% of 36pt button)
    static let iconButtonBackground = Color(.sRGB, red: 20 / 255, green: 20 / 255, blue: 24 / 255, opacity: 0.6)

    // cart badge (minWidth 16 / height 16, fontSize 10 weight 800, 1.5px #fff border)
    static let badgeMinSize: CGFloat = 16
    static let badgeFontSize: CGFloat = 10
    static let badgeBorderWidth: CGFloat = 1.5

    // comment pill (flex, h36, rgba(20,20,24,0.55), text rgba(255,255,255,0.78) 13px left)
    static let commentHPadding: CGFloat = 14
    static let commentFontSize: CGFloat = 13
    static let commentBackground = Color(.sRGB, red: 20 / 255, green: 20 / 255, blue: 24 / 255, opacity: 0.55)
    static let commentPlaceholder = "留言..."
    /// 回放 chat-closed 變體文字（design-literal，同 `commentPlaceholder` 模式）。
    static let chatClosedPlaceholder = "聊天室已關閉"

    // glyphs (match OperationRailView.symbolName mapping)
    // bag 改用自繪 BagGlyph（Icons.bag fill+鏤空環），不再用 SF symbol（rb-ios-icon-parity）。
    // 設定暱稱 改用自繪 PersonEditGlyph（人頭 + 鉛筆 badge），不再用 SF `person.fill`
    // （rb-align-nickname-icon-person-edit）。
    // share 改用自繪 ShareGlyph（Icons.share 三節點），不再用 SF symbol（rb-ios-share-icon-design-align）。
    static let likeSymbol = "heart.fill"            // Icons.heartFill
    // CC (字幕) 改用自繪 CcGlyph（Icons.cc 圓角矩形徽章 + 雙 c 弧線），不再用 SF Symbol
    // `captions.bubble`（rb-ios-live-bottom-bar-cc-icon-align）。`ccSymbol` 保留（源碼相容），
    // unused — `trailingAction` 的 `.cc` 分支已改畫 `CcGlyph`，與 `OperationRailView`.subtitle
    // 現行值共用同一顆 glyph。
    static let ccSymbol = "captions.bubble"         // unused — see CcGlyph

    // Viewport-clamp coordinate space (`rb-ios-cc-tooltip-viewport-clamp`) — see the
    // `ccTooltipViewportWidth` / `ccButtonCenterXInBar` `@State` doc comments and `body`'s
    // `.coordinateSpace(name:)` call.
    static let ccTooltipViewportSpace = "liveBottomBarCcTooltipViewport"
}

// MARK: - Preview (deterministic demo)

#if DEBUG
struct LiveBottomBarView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 24) {
            LiveBottomBarView(theme: ReferenceUIThemePalette.minimal, bagCount: 8, isReplay: false)
            // isReplay == true (預錄直播) now renders the SAME live bar (comment 留言 stays available).
            LiveBottomBarView(theme: ReferenceUIThemePalette.minimal, bagCount: 0, isReplay: true)
            LiveBottomBarView(theme: ReferenceUIThemePalette.minimal, bagCount: 3, isReplay: false, isUpcoming: true)
            // bag-only (introPlaying intro MP4) — just the bag button
            LiveBottomBarView(theme: ReferenceUIThemePalette.minimal, bagCount: 5, isReplay: false, bagOnly: true)
            // chatClosed (finished-live-replay) — 留言區 disabled、leading 格為「更多」(⋯)、
            // trailing 格為 CC 字幕（design R32；2026-09-03 補正輪還原）。
            LiveBottomBarView(theme: ReferenceUIThemePalette.minimal, bagCount: 4, isReplay: false, chatClosed: true)
            // liked == true (rb-ios-live-like-burst-restyle) — 愛心亮 accent，其餘不變。
            LiveBottomBarView(theme: ReferenceUIThemePalette.minimal, bagCount: 2, isReplay: false, liked: true)
        }
        .padding(.vertical, 40)
        .background(Color.black)
        .previewLayout(.sizeThatFits)
    }
}
#endif
