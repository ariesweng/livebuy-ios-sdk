import SwiftUI
import LivebuySDK
import LivebuyUI

// MARK: - FeedWinOverlayView — family-2 feed + win container (SKELETON)
//
// Spec: `reference-ui-rendering/spec.md` (family-2 feed-win, 3 surfaces)
// Design: rb-ios-feed-win design.md D-1 / D-2 / D-3 / D-4.
//
// The top-level family-2 container (this is the design's `FeedWinView` role; the
// file/type name is `FeedWinOverlayView` to read as an overlay composited over
// the player). It composes the THREE family-2 surface sub-views over the live
// video area:
//
//   1. ChatFeedView       — merged chat-feed stream (D-2 #1, `LBLiveChatStream`)
//   2. WinEntryView       — floating win-claim entry badge (D-3 #2, `LBWinEntry`)
//   3. WinClaimModalView  — EMAIL-LESS claim sheet, presented on demand
//                           (D-4 #3, `LBWinSheet`)
//
// This is the SKELETON: it owns the layout + a `FeedWinModel` + the resolved
// `ReferenceUITheme` + the sheet presentation state, and composes the three
// surface sub-views BY TYPE NAME. The three sub-view TYPES are produced by the
// three parallel surface agents that run after this skeleton — see the "SUB-VIEW
// INPUT PATTERN" contract below, which every surface agent MUST implement
// verbatim so the container's call sites match.
//
// Until all three surface sub-views exist, this file will not compile on its own —
// that is expected (the surface agents land the types). The container's job is to
// FIX the layout + the call-site shape so the parallel agents converge.
//
// iOS-14-safe: `ZStack` / `VStack` / `HStack` / `Spacer` / manual padding are all
// iOS-13+; no `@available` guard needed here. Any surface that reaches for a >14
// API must guard it inside its own sub-view (D §iOS-14-safe).
//
// ─────────────────────────────────────────────────────────────────────────────
// SUB-VIEW INPUT PATTERN — the contract the 3 parallel surface agents MUST follow
// ─────────────────────────────────────────────────────────────────────────────
//
// Every family-2 surface sub-view is a `public struct …: View` whose initializer
// takes, IN THIS ORDER (identical convention to family-1 player-shell):
//
//   1. `theme: ReferenceUITheme`            — the resolved reference-ui theme
//                                             (FIRST positional argument, always).
//   2. its bound SNAPSHOT VALUE(S)          — the read-only state it renders,
//                                             passed BY VALUE from FeedWinModel
//                                             (never the model, never the template).
//   3. optional action closures            — trailing, each defaulting to `nil`
//                                             (`onX: (() -> Void)? = nil`, etc.).
//                                             The container does NOT own actions;
//                                             the host wires submit / join through
//                                             the template / upstream exits.
//
// Concretely, the three surface agents implement EXACTLY these initializers:
//
//   ChatFeedView(
//       theme: ReferenceUITheme,
//       items: [LBFeedItem],
//       onJoinEvent: ((_ eid: Int, _ keyword: String) -> Void)? = nil)
//
//   WinEntryView(
//       theme: ReferenceUITheme,
//       unclaimedCount: Int,
//       onTap: (() -> Void)? = nil)
//
//   WinClaimModalView(
//       theme: ReferenceUITheme,
//       winner: LBWinner,
//       presentation: LBAwardPresentation,
//       resultState: LBAwardClaimResultState?,
//       onClaim: (() -> Void)? = nil,
//       onDismiss: (() -> Void)? = nil)
//
// Rules every surface agent honours:
//   • FIRST positional arg is `theme:`. Snapshot values are passed BY VALUE.
//   • Action closures are LAST, each `… = nil` (the container passes the host /
//     template-wired closure or omits it). A surface sub-view MUST render
//     correctly with all actions nil (so demo / snapshot tests construct it
//     action-free).
//   • A surface sub-view reads ONLY its passed-in values — it MUST NOT reach back
//     into FeedWinModel or DefaultPlayerTemplate (one-way data flow, D-1).
//   • `ChatFeedView` dispatches its rows by `LBFeedItem.kind` internally
//     (`.chat` → ChatLineRow, `.eventJoin` → EventJoinLineRow, `.activity(tier:)`
//     → ActivityLineRow). `text` is the backend-prebuilt full string — sub-views
//     MUST NOT split it into fields (D-2).
//   • `WinClaimModalView` is EMAIL-LESS: NO email / contact field. `onClaim`
//     funnels to `DefaultWinClaim.submit(winner:)` (contact always nil); the
//     sheet only renders + offers「稍後再看」(onDismiss) (D-4).
//   • iOS-14-safe SwiftUI only; any >14 API guarded with `@available` /
//     `if #available` inside the sub-view.
// ─────────────────────────────────────────────────────────────────────────────

/// The family-2 feed-win container. Drives layout for the merged chat-feed
/// stream + the floating win-entry badge over the video area, and presents the
/// EMAIL-LESS win-claim sheet on demand; reads a `FeedWinModel` (republished from
/// a live `DefaultPlayerTemplate` or constructed deterministically) and paints
/// with the resolved `ReferenceUITheme`.
public struct FeedWinOverlayView: View {

    /// The republished, read-only feed-win snapshot.
    @ObservedObject public var model: FeedWinModel

    /// The resolved reference-ui theme.
    public let theme: ReferenceUITheme

    /// Bottom inset applied ONLY to the merged chat-feed stream so its newest
    /// (bottom) rows sit ABOVE the LIVE bottom bar (`LiveBottomBarView`) instead
    /// of being occluded by it. The chat feed and the LIVE bar share the same
    /// player-overlay space (both composed in `PlayerOverlayRootView`'s ZStack),
    /// so the host passes the LIVE-bar clearance here. Default `0` keeps the demo /
    /// snapshot path byte-identical; it does NOT shift the centered claim modal or
    /// the already-anchored win-entry badge — only the chat feed sub-view.
    public let chatBottomInset: CGFloat

    /// Whether the chat feed is the SCROLLABLE variant (runtime) so the user can scroll
    /// up to view history. `true` → `ChatFeedView` is fed the deeper `feedHistory` and
    /// `hostScrollable: true`; `false` (default / demo / snapshot) → the ambient
    /// `feedItems` + non-scrollable path (baseline byte-identical).
    public let chatScrollable: Bool

    /// Whether the family-1 info panel (`VideoInfoPanelView`, a bottom sheet + dim scrim
    /// composed in the lower `PlayerShellView` layer) is currently presented. The chat
    /// feed sits ABOVE that layer and its scrollable variant eats hit-testing, so while
    /// the info panel is up the chat would occlude it / swallow taps meant for the sheet.
    /// `true` → the chat feed sub-view is hidden + non-interactive (so the panel's scrim
    /// cleanly covers the background and the sheet is fully usable); `false` (default /
    /// demo / snapshot) → unchanged (baseline byte-identical). ONLY the chat feed is
    /// affected — the centered claim modal / win-entry badge are not.
    public let infoPanelOpen: Bool

    /// Whether to render the merged chat-feed stream at all. It is a LIVE-only surface, and its
    /// full-bleed scrollable variant eats hit-testing; in VOD (`false`) it would occlude / swallow
    /// taps on the VOD side rail, so the container passes `false` to drop it entirely (the
    /// `ScrollView` is removed, not just hidden — rb-ios-hide-chat-feed-in-vod). `true` (default /
    /// demo / snapshot) → rendered as before (baseline byte-identical). ONLY the chat feed is
    /// gated — the win-entry badge / claim modal are unaffected.
    public let showsChatFeed: Bool

    /// Trailing inset applied ONLY to the merged chat-feed stream so it stays in the design's
    /// LEFT column (`live-chrome.jsx` `LBLiveChatOverlay` `right:152`) and does NOT extend into
    /// / occlude the bottom-right `LBLivePinnedCard` column — nor let the chat `ScrollView` eat
    /// taps meant for that product card. Default `0` keeps the demo / snapshot path
    /// byte-identical; it does NOT shift the centered claim modal or the win-entry badge.
    public let chatTrailingInset: CGFloat

    /// The winner the claim sheet is currently presented for, if any. Local
    /// presentation state only — the sheet CONTENT (award detail / CTA / result)
    /// is driven by the model; this just governs which winner is on screen.
    @State private var claimingWinner: LBWinner?

    public init(model: FeedWinModel, theme: ReferenceUITheme,
                chatBottomInset: CGFloat = 0, chatScrollable: Bool = false,
                infoPanelOpen: Bool = false, chatTrailingInset: CGFloat = 0,
                showsChatFeed: Bool = true) {
        self.model = model
        self.theme = theme
        self.chatBottomInset = chatBottomInset
        self.chatScrollable = chatScrollable
        self.infoPanelOpen = infoPanelOpen
        self.chatTrailingInset = chatTrailingInset
        self.showsChatFeed = showsChatFeed
    }

    public var body: some View {
        ZStack {
            // The merged chat-feed stream — left-aligned, newest at the bottom,
            // top gradient mask (the surface agent paints this). Full-bleed under
            // the win entry. Surface 1. LIVE-only: dropped ENTIRELY in VOD (showsChatFeed ==
            // false) so its full-bleed ScrollView doesn't occlude / eat the VOD side rail's
            // taps (rb-ios-hide-chat-feed-in-vod).
            if showsChatFeed {
            ChatFeedView(
                theme: theme,
                // Scrollable variant binds the deeper history (scroll up for history);
                // the ambient / snapshot path keeps the N=7 feedItems.
                items: chatScrollable ? model.feedHistory : model.feedItems,
                hostScrollable: chatScrollable,
                // 置頂留言（chat-pinned-message-render ⑤c）；nil → 無橫幅（snapshot 中性）。
                pinned: model.pinned,
                // 主播名（純顯示，rb-ios-loading-announce-restyle）→ `.eventJoin` 列的主播名 +
                // 「主播」badge header。
                hostName: model.hostName,
                onJoinEvent: { eid, keyword in
                    // The唯一 interactive row's「加入活動」intent → upstream exit
                    // (host wired) via the model's thin forwarder.
                    model.joinEvent(eid: eid, keyword: keyword)
                })
                // Keep the newest (bottom) rows ABOVE the LIVE bottom bar — applied
                // ONLY to the chat feed (NOT the centered claim modal / win-entry).
                .padding(.bottom, chatBottomInset)
                // Keep the chat in the design's LEFT column (LBLiveChatOverlay right:152) so it
                // does not occlude / eat taps on the bottom-right LBLivePinnedCard column —
                // applied ONLY to the chat feed (rb-ios-live-pinned-card-appears).
                .padding(.trailing, chatTrailingInset)
                // While the info panel (lower-layer bottom sheet + scrim) is up, hide +
                // disable the chat feed so it neither occludes the sheet nor swallows its
                // taps (the panel's scrim then cleanly covers the background). opacity (not
                // removal) preserves the chat's scroll/auto-stick state for when it returns.
                // ONLY the chat feed — the win-entry badge / claim modal below are untouched.
                .opacity(infoPanelOpen ? 0 : 1)
                .allowsHitTesting(!infoPanelOpen)
            }

            // Floating win-claim entry badge — right side, vertically above center
            // (top 42%, design `LBWinEntry` `top:'42%'`). Moved up from the prior
            // bottom-trailing pin so it clears the LIVE bottom bar / pinned card and
            // is easier for the winner to notice. Drawn ONLY when `unclaimedCount > 0`
            // (the sub-view itself no-draws at 0; the container also early-returns the
            // tap when nothing to claim). Surface 2.
            GeometryReader { geo in
                WinEntryView(
                    theme: theme,
                    unclaimedCount: model.unclaimedCount,
                    onTap: { presentNextClaim() })
                    .padding(.trailing, 12)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .offset(y: geo.size.height * 0.42)
            }

            // EMAIL-LESS claim — a CENTERED MODAL (LBWinSheet), presented as a
            // full-bleed overlay layer (NOT a native bottom `.sheet`) so it matches
            // the design's centered-card-over-scrim form factor. The view owns its
            // own dark scrim; tapping it (or 「稍後再看」/ close) clears the winner.
            // Surface 3.
            if let winner = claimingWinner {
                WinClaimModalView(
                    theme: theme,
                    winner: winner,
                    presentation: presentation(for: winner),
                    resultState: model.resultState,
                    onClaim: { model.submitClaim(for: winner) },
                    onDismiss: { claimingWinner = nil })
            }
        }
    }

    /// Open the claim sheet on the EARLIEST unclaimed winner (D-3). No-op when
    /// nothing is claimable (`unclaimedCount == 0`).
    private func presentNextClaim() {
        guard let next = model.nextUnclaimedWinner else { return }
        claimingWinner = next
    }

    /// CTA classification for `winner` (`.product`「查看獎品」/ `.discount`「立即使用」).
    /// Routed through the model so the template's public classifier
    /// (`DefaultWinClaim.awardPresentation(for:)`) is the single source — its
    /// internal `LBAwardPresentation.init(awardType:)` is not reachable here.
    /// Demo instances fall back to the same award-type rule (see `FeedWinModel`).
    private func presentation(for winner: LBWinner) -> LBAwardPresentation {
        model.presentation(for: winner)
    }
}

// MARK: - Identifiable conformance for sheet(item:)
//
// `LBWinner` (core model) is not `Identifiable`; `.sheet(item:)` needs it. We add
// the conformance HERE in the reference-ui layer (it does NOT modify the core
// type's source — it is an extension in the pixel layer only, and `winner.id` is
// the stable ticket id). This keeps the one-way dependency: reference-ui adds the
// presentation affordance, core stays headless.

extension LBWinner: Identifiable {}
