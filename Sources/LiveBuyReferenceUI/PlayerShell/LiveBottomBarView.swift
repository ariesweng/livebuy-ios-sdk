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
//   • a nickname (person-edit) button — OR, in the replay variant, a CC toggle,
//   • a share button,
//   • an accent like (heartFill) button.
//
// Replay variant (D-3): when `isReplay`, the "留言..." pill becomes a disabled
// "聊天室已關閉" state and the nickname button is swapped for the CC toggle
// (`live-chrome.jsx` `replay` branch, lines 198-221).
//
// Upcoming SLIM variant (rb-ios-upcoming-live-chrome): when `isUpcoming`, the comment
// area collapses to a flex spacer and the nickname / CC button is dropped — only
// bag + share + like remain (the stream hasn't started, so there is no chat). Mirrors
// `LBLiveBottomBar({ upcoming: true })` (`live-chrome.jsx` lines 195-197). Takes
// precedence over `isReplay`. Used for the awaitingLive countdown.
//
// bag-only variant (rb-ios-intro-chrome-minimal): when `bagOnly`, the bar collapses
// further to JUST the shopping-bag button + a trailing flex spacer — comment / nickname
// / CC / share / like are ALL dropped. This is the minimal chrome for 直播預告的開場影片
// (`introPlaying`, the upcoming intro MP4 playing). `bagOnly` takes PRECEDENCE over
// `isUpcoming` / `isReplay`. (awaitingLive keeps the slim three-button bar above.)
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
// The user-facing strings ("留言...", "聊天室已關閉") are design-literal (the minimal
// design mockup is the source of truth); localization is a cross-layer follow-up.

/// The family-1 LIVE bottom bar surface. Renders the horizontal bag / comment /
/// nickname-or-CC / share / like row from `LBLiveBottomBar`, with the replay
/// "聊天室已關閉" variant keyed on `isReplay`.
public struct LiveBottomBarView: View {

    // MARK: - Inputs (sub-view input pattern: theme, snapshot values, actions)

    /// The resolved reference-ui theme (FIRST positional argument, always).
    public let theme: ReferenceUITheme

    /// Shopping-bag badge count. `> 0` → draw the badge on the bag button.
    public let bagCount: Int

    /// Replay (重播) variant flag. `true` → the comment pill becomes the disabled
    /// "聊天室已關閉" state and the nickname button is swapped for the CC toggle.
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
    /// CC toggle (replay variant) → host-wired subtitle toggle. nil → inert.
    public let onToggleCC: (() -> Void)?

    public init(
        theme: ReferenceUITheme,
        bagCount: Int,
        isReplay: Bool,
        isUpcoming: Bool = false,
        bagOnly: Bool = false,
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
                // Flex comment area. Upcoming (slim) → an ACTIVE flex (no chat before the
                // stream starts); replay → disabled "聊天室已關閉"; LIVE → tap-target "留言...".
                // The upcoming flex uses `Color.clear` + `maxWidth: .infinity` (mirrors the
                // design `<div flex:1/>` and the LIVE commentPill), NOT a bare `Spacer` — a
                // bare Spacer collapses to ideal-width when the bar is hosted without an
                // explicit width proposal, pushing the end buttons (bag / like) off-screen.
                if isUpcoming {
                    Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                } else if isReplay {
                    chatClosedPill
                } else {
                    commentPill
                }

                // Nickname / CC button is dropped entirely in the upcoming variant (design
                // gates both on `!upcoming`). Replay swaps the nickname for a CC toggle.
                if !isUpcoming {
                    if isReplay {
                        iconButton(symbol: Self.ccSymbol, tint: .white, action: onToggleCC)
                    } else {
                        // 設定暱稱 draws the hand-drawn person-EDIT composite (head + pencil
                        // badge, design `live-chrome.jsx` ≈224), not SF `person.fill`
                        // (rb-align-nickname-icon-person-edit).
                        iconButton(action: onNickname) { PersonEditGlyph(size: Self.iconGlyphSize, color: .white) }
                    }
                }

                // Share draws the hand-drawn `ShareGlyph` (design `Icons.share`),
                // not SF `square.and.arrow.up` (rb-ios-share-icon-design-align).
                iconButton(action: onShare) { ShareGlyph(size: Self.iconGlyphSize, color: .white) }
                iconButton(symbol: Self.likeSymbol, tint: theme.accent, action: onLike)
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
    }

    /// Replay variant: disabled, centered "聊天室已關閉" pill (no tap).
    private var chatClosedPill: some View {
        Text(Self.chatClosedLabel)
            .font(.system(size: Self.chatClosedFontSize))
            .foregroundColor(Color.white.opacity(0.5))
            .frame(height: Self.iconSize)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(Self.chatClosedBackground))
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

    // replay closed pill (rgba(20,20,24,0.45), text rgba(255,255,255,0.5) 12px center)
    static let chatClosedFontSize: CGFloat = 12
    static let chatClosedBackground = Color(.sRGB, red: 20 / 255, green: 20 / 255, blue: 24 / 255, opacity: 0.45)
    static let chatClosedLabel = "聊天室已關閉"

    // glyphs (match OperationRailView.symbolName mapping)
    static let bagSymbol = "bag.fill"               // Icons.bag
    // 設定暱稱 改用自繪 PersonEditGlyph（人頭 + 鉛筆 badge），不再用 SF `person.fill`
    // （rb-align-nickname-icon-person-edit）。
    // share 改用自繪 ShareGlyph（Icons.share 三節點），不再用 SF symbol（rb-ios-share-icon-design-align）。
    static let likeSymbol = "heart.fill"            // Icons.heartFill
    static let ccSymbol = "captions.bubble"         // Icons.cc
}

// MARK: - Preview (deterministic demo)

#if DEBUG
struct LiveBottomBarView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 24) {
            LiveBottomBarView(theme: ReferenceUIThemePalette.minimal, bagCount: 8, isReplay: false)
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
