import SwiftUI
import LiveBuySDK
import LiveBuyUI

// MARK: - LiveBottomBarView — family-1 player-shell LIVE bottom bar
//
// Spec: `reference-ui-rendering/spec.md`
//   § "LiveBuyReferenceUI 渲染 LIVE 底部 bar（LiveBottomBarView），綁 bagCount / shareUrl / isReplay"
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
//   • a nickname (person-edit) button,
//   • a share button,
//   • an accent like (heartFill) button.
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
    /// CC toggle → host-wired subtitle toggle. RETAINED for source compatibility (defaulted
    /// nil); the LIVE bottom bar no longer draws a CC button (the prior replay variant is
    /// removed — prerecorded-live-bottom-bar-comment). nil → inert.
    public let onToggleCC: (() -> Void)?

    public init(
        theme: ReferenceUITheme,
        bagCount: Int,
        isReplay: Bool,
        isUpcoming: Bool = false,
        bagOnly: Bool = false,
        chatClosed: Bool = false,
        onBag: (() -> Void)? = nil,
        onComment: (() -> Void)? = nil,
        onNickname: (() -> Void)? = nil,
        onShare: (() -> Void)? = nil,
        onLike: (() -> Void)? = nil,
        onToggleCC: (() -> Void)? = nil
    ) {
        self.theme = theme
        self.bagCount = bagCount
        self.isReplay = isReplay
        self.isUpcoming = isUpcoming
        self.bagOnly = bagOnly
        self.chatClosed = chatClosed
        self.onBag = onBag
        self.onComment = onComment
        self.onNickname = onNickname
        self.onShare = onShare
        self.onLike = onLike
        self.onToggleCC = onToggleCC
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

                // Nickname (person-edit) button shows ONLY in the normal LIVE variant
                // (`!isUpcoming && !chatClosed`): dropped in the upcoming slim variant (design
                // gates it on `!upcoming`) AND in the 回放 chat-closed variant (改名 only serves
                // commenting; with the chat room closed it is useless). The LIVE bottom bar no
                // longer swaps it for a CC toggle on the behind-edge `isReplay`
                // (prerecorded-live-bottom-bar-comment).
                if !isUpcoming && !chatClosed {
                    // 設定暱稱 draws the hand-drawn person-EDIT composite (head + pencil
                    // badge, design `live-chrome.jsx` ≈224), not SF `person.fill`
                    // (rb-align-nickname-icon-person-edit).
                    iconButton(action: onNickname) { PersonEditGlyph(size: Self.iconGlyphSize, color: .white) }
                        .accessibilityIdentifier(LBAccessibilityID.livePersonEdit)
                }

                // Share draws the hand-drawn `ShareGlyph` (design `Icons.share`),
                // not SF `square.and.arrow.up` (rb-ios-share-icon-design-align).
                iconButton(action: onShare) { ShareGlyph(size: Self.iconGlyphSize, color: .white) }
                    .accessibilityIdentifier(LBAccessibilityID.liveShare)
                iconButton(symbol: Self.likeSymbol, tint: theme.accent, action: onLike)
                    .accessibilityIdentifier(LBAccessibilityID.liveHeart)
            }
        }
        .padding(.horizontal, Self.barHPadding)
        .padding(.vertical, Self.barVPadding)
        .frame(maxWidth: .infinity)
        .background(
            // `linear-gradient(to top, rgba(0,0,0,0.55), transparent)`.
            LinearGradient(
                gradient: Gradient(colors: [Color.black.opacity(0.55), Color.clear]),
                startPoint: .bottom, endPoint: .top)
        )
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
                    Image(systemName: Self.bagSymbol)
                        .font(.system(size: Self.iconGlyphSize, weight: .semibold))
                        .foregroundColor(theme.accent)
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
    /// Pure (unit-testable). Dropped in upcoming slim / bag-only / 回放 chat-closed.
    static func showsNickname(bagOnly: Bool, isUpcoming: Bool, chatClosed: Bool) -> Bool {
        !bagOnly && !isUpcoming && !chatClosed
    }

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

    // MARK: - Badge text

    /// Clamp very large counts so the badge stays compact (`99+` past 99).
    static func badgeText(_ count: Int) -> String {
        count > 99 ? "99+" : "\(count)"
    }
}

// MARK: - Design tokens (lifted from `live-chrome.jsx` `LBLiveBottomBar`)

private extension LiveBottomBarView {
    // bar container
    static let barGap: CGFloat = 8            // flex gap
    static let barHPadding: CGFloat = 10      // padding 8px 10px
    static let barVPadding: CGFloat = 8

    // iconBtn (36×36 round, rgba(20,20,24,0.6))
    static let iconSize: CGFloat = 36
    static let iconGlyphSize: CGFloat = 18    // Icons size 18
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
    static let bagSymbol = "bag"                    // Icons.bag
    // 設定暱稱 改用自繪 PersonEditGlyph（人頭 + 鉛筆 badge），不再用 SF `person.fill`
    // （rb-align-nickname-icon-person-edit）。
    // share 改用自繪 ShareGlyph（Icons.share 三節點），不再用 SF symbol（rb-ios-share-icon-design-align）。
    static let likeSymbol = "heart.fill"            // Icons.heartFill
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
        }
        .padding(.vertical, 40)
        .background(Color.black)
        .previewLayout(.sizeThatFits)
    }
}
#endif
