import SwiftUI
import LivebuySDK
import LivebuyUI

// MARK: - LiveOverlayChromeView — family-1 surface 4 (LIVE overlay chrome)
//
// Spec: `reference-ui-rendering/spec.md` (family-1 player-shell, surface 4)
// Design: rb-ios-player-shell design.md D-2 #4 (`live-chrome.jsx`).
//
// The full-bleed LIVE overlay chrome, layered ABOVE the video and BELOW the
// pinned chrome (top bar / side rail / info sheet — those are surfaces 1/2/3,
// owned by their own sub-views). This surface renders ONLY the overlay
// affordances the design's `live-chrome.jsx` paints over the stream:
//
//   • LBLiveAnnounce    — announcement banner (bottom-left, yellow), 2-line clamp.
//   • LBLivePinnedCard  — pinned narrating-product card (bottom-right, white).
//   • LBLiveHostCaption — centered host caption overlay (~46% height), with a
//                         live-price row read from the pinned product.
//   • LBPGestureHint    — centered static gesture-hint pills (tap / hold / swipe).
//
// SCOPE FENCE (do NOT cross): this surface renders overlay affordances only. It
// MUST NOT render the product LIST / sheet (that is rb-ios-product-sheets) nor
// the chat feed / win toasts (that is rb-ios-feed-win). The `LBLiveChatOverlay`
// from `live-chrome.jsx` is therefore intentionally NOT rendered here.
//
// ─────────────────────────────────────────────────────────────────────────────
// SUB-VIEW INPUT PATTERN (matches PlayerShellView.swift's documented contract)
// ─────────────────────────────────────────────────────────────────────────────
//
//   LiveOverlayChromeView(
//       theme: ReferenceUITheme,                 // 1. resolved theme (first)
//       announceText: String,                    // 2. bound snapshot value(s)
//       pinnedProduct: LBProduct?,               //    (by value, from PlayerShellModel)
//       hostCaption: String = "",                //    host-supplied static copy (GAP NOTE)
//       showGestureHints: Bool = true)           //    static presentation toggle
//
// Action closures on this surface are host-wired taps only (the layer NEVER acts itself):
// the pinned card's tap is a host-wired core exit (`onTapPinnedProduct`, D-4), and the
// announce banner's tap is a host-wired navigation that opens the VideoInfoPanel notice tab
// (`onTapAnnounce`, live-announce-tap-open-info-panel). The caption / gesture hints carry no
// tap intent. Both tap closures default to nil → the affordance renders inert (demo / snapshot),
// pixel-neutral either way.
//
// One-way data flow: this view reads ONLY its passed-in values and NEVER reaches
// back into PlayerShellModel or DefaultPlayerTemplate (D-1 / D-4).
//
// iOS-14-safe: all SwiftUI used here is iOS-13+ (ZStack / VStack / HStack / Text /
// Image(systemName:) / RoundedRectangle / LinearGradient). The announce copy is a
// static 2-line clamped Text, so every frame is deterministic for snapshots (D-7).
// ─────────────────────────────────────────────────────────────────────────────

/// The family-1 LIVE overlay chrome surface. Paints the announcement marquee,
/// pinned narrating-product card, host caption, and static gesture hints over
/// the video area, themed by the resolved `ReferenceUITheme`.
public struct LiveOverlayChromeView: View {

    /// The resolved reference-ui theme (first positional argument, always).
    public let theme: ReferenceUITheme

    /// Announcement marquee copy (`LBLiveAnnounce`). Source: `PlayerShellModel
    /// .announceText` (← `noticeTab.notice`). Empty → the banner is omitted.
    public let announceText: String

    /// The LIVE pinned narrating product(s) (`LBLivePinnedCard`). Source:
    /// `PlayerShellModel.livePinnedProducts` (← template `liveActiveProducts`, ALL `narrate_status==2`;
    /// ELSE the single `pinnedProduct` = `activeProduct` ?? first `isHot==1`, as a 1-element list).
    /// Empty → no card; exactly 1 → single card (現狀); >1 → current card + 分頁點 carousel
    /// (問題 7, rb-ios-live-now-introducing-carousel).
    public let pinnedProducts: [LBProduct]

    /// Extra bottom inset added to the shared announce/pinned-card row's `.padding(.bottom,
    /// LiveBottomBarView.barHeight + bottomBarClearanceGap)` (rb-ios-restore-vod-playback-progress-bar;
    /// base value updated by rb-ios-caption-overlay-bottom-bar-clearance-fix). Default `0` keeps
    /// every existing call site /
    /// snapshot baseline pixel-identical. `PlayerShellView` passes a positive value (~36pt)
    /// while the VOD/replay `PlaybackProgressBarView` is expanded but no longer actively being
    /// dragged, so the announce banner + pinned card reappear lifted clear of the still-expanded
    /// transport bar.
    public let bottomInset: CGFloat

    /// Current page in the multi-product pinned-card carousel (only meaningful when
    /// `pinnedProducts.count > 1`). Pure UI `@State`, NOT a view-model.
    @State private var pinnedIndex: Int = 0

    /// `true` (runtime, real live video surface) → the pinned card loads the real
    /// product image over its placeholder; `false` (snapshot / demo) keeps the
    /// deterministic gray placeholder (live-pinned-card-image-radius). Reuses the
    /// same runtime-image gate (`!paintsBackgroundPlaceholder`) the shop logo / VOD
    /// now-introducing card use.
    public let live: Bool

    /// Host caption copy (`LBLiveHostCaption`). There is no public host-caption
    /// view-model on the template (see PlayerShellModel GAP NOTE) — this is a
    /// host-supplied STATIC string. Empty → the caption overlay is omitted.
    public let hostCaption: String

    /// The REAL VTT/CC caption text (`rb-ios-replay-caption-overlay-fix`) — resolved by
    /// `PlayerShellView.effectiveCaption` / gated by `PlayerShellView.showsCaptionOverlay`
    /// (non-empty only during a finished-live REPLAY with CC on; a genuine live broadcast in
    /// progress always feeds `""`). This is a COMPLETELY DIFFERENT mechanism from `hostCaption`
    /// above (`LBLiveHostCaption`, host-supplied static copy with no public data source) — the
    /// two SHALL be able to coexist: this renders as a `CaptionOverlayView` pill directly ABOVE
    /// the announce/pinned-card row (leading-aligned, 8pt gap), while `hostCaption` renders
    /// centered mid-screen (~46% height) — no shared screen real-estate. Empty (default) → the
    /// overlay is omitted; every existing call site is pixel-neutral.
    public let subtitleCaption: String

    /// Whether to draw the static gesture-hint pills (`LBPGestureHint`). Pure
    /// presentation copy — no view-model binding.
    public let showGestureHints: Bool

    /// RETIRED gate (rb-ios-gesture-clean-mode-rewrite, supersedes rb-ios-live-hold-pause-
    /// suppress): used to hide the「長按畫面 = 暫停 / 繼續」hold-to-pause hint pill while
    /// `model.isLive`. Long-press no longer drives pause/resume — it now toggles `cleanMode`
    /// (unconditionally, not gated on live/VOD) — so the hold-hint pill (now reading「長按畫面
    /// = 切換乾淨模式」, see `hintHold`) is ALWAYS shown regardless of this flag. The stored
    /// property is kept (source compatibility for any existing explicit-`false` call site) but
    /// no longer read anywhere in `body`.
    @available(*, deprecated, message: "no longer gates anything; the hold-hint pill is always shown (long-press now toggles cleanMode, not pause)")
    public let showsHoldPauseHint: Bool

    /// LIVE vs VOD flag (`PlayerShellModel.isLive`). Gates the LONG-PRESS hint pill's
    /// visibility (`rb-ios-gesture-clean-mode-v2`, design R29, supersedes R23's use of this
    /// flag to branch the TAP-hint copy — every short tap now toggles `cleanMode`
    /// unconditionally, so the tap-hint copy no longer depends on `isLive` at all, see
    /// `hintTap`): `true` (actual live in progress, this sub-view's only reachable `isLive
    /// == true` case per its `PlayerShellView` call site — replay feeds `false`) → the
    /// hold-hint pill (`hintHold`, "長按畫面 = 2倍速快轉") does NOT render at all, since
    /// long-press has no effect while actually live; `false` (已結束直播回放, the only other
    /// case reaching this sub-view) → the hold-hint pill DOES render. Default `true` keeps
    /// any call site that doesn't pass it byte-identical to the prior LIVE-shaped baseline.
    public let isLive: Bool

    /// When true, the gesture-hint pills fade out shortly after appearing
    /// (onboarding affordance over a real live video). Defaults to `false` →
    /// static presentation so snapshot baselines stay deterministic.
    public let autoFadeGestureHints: Bool

    /// 「乾淨模式」(rb-ios-gesture-clean-mode-rewrite, design R23, ADDED Requirement
    /// "LivebuyReferenceUI PlayerShellView 長按切換「乾淨模式」隱藏懸浮 chrome") — `true` hides
    /// this sub-view's announce banner / host caption / gesture hints, but MUST NOT affect the
    /// pinned-card carousel (`pinnedCardCarousel`), which stays visible so the viewer can still
    /// see (and act on) the currently-narrating product while chrome is hidden. Default `false`
    /// keeps every existing call site byte-identical (this Requirement is fully additive).
    public let cleanMode: Bool

    /// Tap on the pinned-product card → host-wired turnkey product-detail flow
    /// (PlayerShellView forwards to `model.performProductTap`). nil → the card is
    /// drawn but inert (demo / snapshot). No pixel change either way.
    private let onTapPinnedProduct: ((LBProduct) -> Void)?

    /// Tap on the pinned-card close chip (top-right X) → host-wired per-product-id
    /// local dismiss (PlayerShellView adds the id to a local `dismissedLivePinnedIds`
    /// Set and re-filters the fed product list). The close chip is an INNER Button, so
    /// its tap is consumed and does NOT bubble to the card's outer open-detail Button
    /// (mirrors `MiniCartView.closeButton`'s `e.stopPropagation()`). nil → the chip is
    /// drawn but inert (demo / snapshot). No pixel change either way
    /// (rb-ios-live-pinned-card-dismiss; parity to Android `0f6b56a5`).
    private let onDismissPinnedProduct: ((String) -> Void)?

    /// Tap on the announcement banner (`LBLiveAnnounce`) → host-wired navigation that
    /// opens the `VideoInfoPanelView` notice tab (PlayerShellView wires
    /// `selectInfoTab(.notice)` + `infoPanelPresented = true`). nil → the banner is drawn
    /// but inert (demo / snapshot). Pixel-neutral either way (`PlainButtonStyle` wrapper) —
    /// live-announce-tap-open-info-panel.
    private let onTapAnnounce: (() -> Void)?

    public init(theme: ReferenceUITheme,
                announceText: String,
                pinnedProducts: [LBProduct],
                bottomInset: CGFloat = 0,
                live: Bool = false,
                hostCaption: String = "",
                subtitleCaption: String = "",
                showGestureHints: Bool = true,
                showsHoldPauseHint: Bool = true,
                isLive: Bool = true,
                autoFadeGestureHints: Bool = false,
                cleanMode: Bool = false,
                onTapPinnedProduct: ((LBProduct) -> Void)? = nil,
                onDismissPinnedProduct: ((String) -> Void)? = nil,
                onTapAnnounce: (() -> Void)? = nil) {
        self.theme = theme
        self.announceText = announceText
        self.pinnedProducts = pinnedProducts
        self.bottomInset = bottomInset
        self.live = live
        self.hostCaption = hostCaption
        self.subtitleCaption = subtitleCaption
        self.showGestureHints = showGestureHints
        self.showsHoldPauseHint = showsHoldPauseHint
        self.isLive = isLive
        self.autoFadeGestureHints = autoFadeGestureHints
        self.cleanMode = cleanMode
        self.onTapPinnedProduct = onTapPinnedProduct
        self.onDismissPinnedProduct = onDismissPinnedProduct
        self.onTapAnnounce = onTapAnnounce
    }

    /// Gesture-hint opacity — starts visible, then fades out shortly after the
    /// overlay appears so the onboarding pills don't linger over the live video.
    /// Static snapshot renders capture it at the initial full opacity (no
    /// `onAppear` / animation runs there → baselines unchanged).
    @State private var gestureHintsOpacity: Double = 1

    /// Trailing inset for the `subtitleCaption` window (rb-ios-caption-overlay-align-hide-chat) —
    /// matches the design's `LBPCaptionOverlay` override for the LIVE/回放 caller
    /// (`screens.jsx` line ~576: `<LBPCaptionOverlay right={120} .../>`, vs. the VOD caller's
    /// default `right=68` — `PlayerShellView.floatingBagClearance`). The two callers intentionally
    /// use different values (this row's own bottom bar / pinned-card column is wider than the VOD
    /// floating bag), so this is a separate, independently-named constant rather than a shared one.
    static let captionTrailingClearance: CGFloat = 120

    /// Explicit, named safety gap ABOVE `LiveBottomBarView`'s real height that the announce/
    /// pinned-card row's bottom padding clears (`rb-ios-caption-overlay-bottom-bar-clearance-fix`).
    /// Before this change the row used a standalone hardcoded `64` constant with ZERO coupling to
    /// `LiveBottomBarView`'s actual rendered height (`barTopPadding(8) + iconSize(36) +
    /// barBottomPadding(16) = 60pt`) — that left only a razor-thin margin (`64 − 60 = 4pt` for the
    /// row itself; `64 + 8 − 60 = 12pt` for the `subtitleCaption` overlay stacked above it, in the
    /// worst case where the row is otherwise empty) that could silently erode to zero if either
    /// file's own constants ever drifted independently (user-reported real-device overlap). `12`
    /// gives a deliberately more generous buffer (row: 12pt, caption worst-case: 20pt) — a
    /// judgment call (see design.md D3), not a value read off the design mockup (the mockup itself
    /// only uses the same rough `bottom: 64` literal this replaces).
    static let bottomBarClearanceGap: CGFloat = 12

    public var body: some View {
        // Full-bleed overlay. Affordances are positioned with explicit padding
        // so the layout matches `live-chrome.jsx`'s absolute placement without an
        // iOS-15+ `safeAreaInset`. Taps pass through where the design declares
        // `pointerEvents: none` (caption / gesture hints).
        ZStack {
            // Centered host caption (~46% from the top — `LBLiveHostCaption`). Hidden in
            // `cleanMode` (rb-ios-gesture-clean-mode-rewrite ADDED Requirement) — the pinned
            // card itself stays (see `pinnedCardCarousel`, unaffected by `cleanMode`).
            if !hostCaption.isEmpty && !cleanMode {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                        .frame(maxHeight: .infinity)
                    hostCaptionOverlay
                    Spacer(minLength: 0)
                        .frame(maxHeight: .infinity)
                }
                .padding(.horizontal, 12)
                .allowsHitTesting(false)   // design: pointerEvents: none
            }

            // Centered gesture hints (`LBPGestureHint`). Onboarding affordance:
            // when autoFadeGestureHints is set (real live overlay) they show
            // briefly then fade out; otherwise static (snapshot-deterministic). Hidden in
            // `cleanMode` (rb-ios-gesture-clean-mode-rewrite ADDED Requirement).
            if showGestureHints && !cleanMode {
                Group {
                    if autoFadeGestureHints {
                        gestureHints
                            .opacity(gestureHintsOpacity)
                            .onAppear {
                                withAnimation(.easeOut(duration: 0.6).delay(3.5)) {
                                    gestureHintsOpacity = 0
                                }
                            }
                    } else {
                        gestureHints
                    }
                }
                .allowsHitTesting(false)   // design: pointerEvents: none
            }

            // Bottom row: announce marquee (left) + pinned card (right).
            // `live-chrome.jsx`: announce `left:8 right:120 bottom:70` (R31 — was `right:152`;
            // resolved by `rb-ios-live-announce-chat-clearance-restore`, which followed up on
            // the Open Question left by `rb-ios-vod-live-product-card-restyle` design.md and
            // updated the announce banner's fixed width calc below to 265pt),
            // pinned card `right:8 bottom:64 width:100` (R31, was `width:132`).
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                // Real VTT/CC caption (rb-ios-replay-caption-overlay-fix) — stacked directly
                // ABOVE the announce/pinned-card row below (SwiftUI lays out this VStack's
                // children top-to-bottom, so it self-adjusts to the row's height — no manual
                // pixel offset needed to avoid overlapping the (taller) pinned card). This
                // vertical stacking mechanism is UNCHANGED by rb-ios-caption-overlay-align-hide-
                // chat below — only the horizontal alignment changes.
                // Hidden in `cleanMode` — same internal gate as `announceText` / `hostCaption`
                // below (the CALLER already resolves this to `""` in that case too, see
                // `PlayerShellView.showsCaptionOverlay`; this is defense-in-depth for any other
                // direct caller / test, mirroring `testLiveOverlayChromeView_cleanModeHides...`).
                //
                // rb-ios-caption-overlay-align-hide-chat: centered within a narrow window (left
                // 8pt / right `captionTrailingClearance` == 120pt), matching the design's
                // `LBPCaptionOverlay` override for this caller (`right:120;
                // justifyContent:'center'`) — REPLACES the previous leading-aligned
                // `HStack { CaptionOverlayView(); Spacer() }` (which also used a different,
                // now-retired 10pt trailing inset).
                if !subtitleCaption.isEmpty && !cleanMode {
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        CaptionOverlayView(theme: theme, text: subtitleCaption)
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, 8)
                    .padding(.trailing, Self.captionTrailingClearance)
                    .padding(.bottom, 8)
                }
                HStack(alignment: .bottom, spacing: 8) {
                    if !announceText.isEmpty && !cleanMode {
                        // Tappable → host-wired navigation that opens the VideoInfoPanel notice
                        // tab (PlayerShellView: selectInfoTab(.notice) + infoPanelPresented).
                        // PlainButtonStyle keeps the pixels (snapshot baselines unchanged);
                        // inert when onTapAnnounce == nil (live-announce-tap-open-info-panel).
                        // Hidden in `cleanMode` (rb-ios-gesture-clean-mode-rewrite ADDED
                        // Requirement) — the pinned card on the trailing side of this SAME
                        // HStack is UNAFFECTED (see `pinnedCardCarousel`).
                        Button(action: { onTapAnnounce?() }) {
                            announceBanner
                        }
                        .buttonStyle(PlainButtonStyle())
                        .accessibilityIdentifier(LBAccessibilityID.announceBanner)
                    }
                    Spacer(minLength: 0)
                    pinnedCardCarousel
                }
                // Leading (announce side) stays 8 — the design's `left:8`, unrelated to the
                // announce banner's own fixed 265pt width calc below. Trailing (pinned-card
                // side) is 10 (was 8) so the pinned card's right edge aligns with the LIVE
                // bottom bar's heart button right margin (rb-ios-live-chat-card-edge-align).
                .padding(.leading, 8)
                .padding(.trailing, 10)
                // `bottomInset` (default 0, additive) lifts the row clear of the VOD/replay
                // `PlaybackProgressBarView` transport bar while it is expanded but no longer
                // being actively dragged (rb-ios-restore-vod-playback-progress-bar).
                //
                // rb-ios-caption-overlay-bottom-bar-clearance-fix: REPLACES the previous standalone
                // hardcoded `64` with `LiveBottomBarView.barHeight + Self.bottomBarClearanceGap` —
                // a single source of truth derived from the REAL bottom bar height instead of an
                // independently-guessed literal (see `bottomBarClearanceGap`'s own doc comment).
                .padding(.bottom, LiveBottomBarView.barHeight + Self.bottomBarClearanceGap + bottomInset)
            }
        }
    }

    // MARK: - LBLivePinnedCard carousel — single card OR multi-product carousel + 分頁點

    /// The current pinned product (clamped index), or nil when none. Shared by the bottom-right
    /// pinned-card carousel and the host-caption live-price row.
    private var currentPinnedProduct: LBProduct? {
        guard !pinnedProducts.isEmpty else { return nil }
        return pinnedProducts[min(max(pinnedIndex, 0), pinnedProducts.count - 1)]
    }

    /// Bottom-right pinned product card. `pinnedProducts.count > 1` → current card + 分頁點（卡上方）
    /// + horizontal swipe to change page; `== 1` → single card（現狀）; empty → nothing
    /// (問題 7, rb-ios-live-now-introducing-carousel).
    @ViewBuilder
    private var pinnedCardCarousel: some View {
        if !pinnedProducts.isEmpty {
            let i = min(max(pinnedIndex, 0), pinnedProducts.count - 1)
            let product = pinnedProducts[i]
            VStack(alignment: .trailing, spacing: 6) {
                if pinnedProducts.count > 1 {
                    pinnedPageDots(count: pinnedProducts.count, current: i)
                }
                // Tappable → host-wired turnkey product detail. PlainButtonStyle preserves the pixels
                // (single-card snapshot baselines unchanged); inert when onTapPinnedProduct == nil.
                Button(action: { onTapPinnedProduct?(product) }) {
                    pinnedCard(product)
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityIdentifier(LBAccessibilityID.pinnedCard)
            }
            // 水平 swipe 切頁（方向 gate：僅在水平位移 > 垂直位移時切頁；垂直交給外層上下換片）。
            // `highPriorityGesture` minDistance 10 讓水平拖曳勝過卡片 Button / 外層手勢。單卡時 no-op。
            .highPriorityGesture(
                DragGesture(minimumDistance: 10)
                    .onEnded { value in
                        guard pinnedProducts.count > 1,
                              abs(value.translation.width) > abs(value.translation.height) else { return }
                        if value.translation.width <= -Self.pinnedSwipeThreshold {
                            pinnedIndex = min(i + 1, pinnedProducts.count - 1)
                        } else if value.translation.width >= Self.pinnedSwipeThreshold {
                            pinnedIndex = max(i - 1, 0)
                        }
                    }
            )
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(LBAccessibilityID.pinnedCarousel)
        }
    }

    /// Page dots — one per pinned product, current accent-filled, rest dim. Each dot TAPPABLE
    /// (tap → that page). 6×6 dot keeps exact pixels; `contentShape(...inset -7)` enlarges the tap
    /// target without changing layout. Mirrors `NowIntroducingCarouselView.pageDots`.
    private func pinnedPageDots(count: Int, current: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { idx in
                Circle()
                    .fill(idx == current ? theme.accent : Color.white.opacity(0.4))
                    .frame(width: 6, height: 6)
                    .contentShape(Rectangle().inset(by: -7))
                    .onTapGesture { pinnedIndex = idx }
                    .accessibilityIdentifier(LBAccessibilityID.livePinnedDot(idx))
            }
        }
    }

    static let pinnedSwipeThreshold: CGFloat = 40

    // MARK: - LBLiveAnnounce — announcement marquee banner

    /// Bottom-left dark-glass announcement banner with a red icon badge and
    /// white text. Mirrors `LBLiveAnnounce` from `live-chrome.jsx`
    /// (`rgba(0,0,0,0.42)` background — drawn as a flat translucent fill, no
    /// real backdrop blur, per repo convention — `#F03246` icon badge,
    /// `rb-ios-live-announce-banner-recolor`, design-contract R30).
    private var announceBanner: some View {
        HStack(spacing: 8) {
            // Red icon badge (`#F03246`, 22×22, radius 5). Icon is a hand-drawn
            // custom vector path (`MegaphoneGlyph`, FontAwesome bullhorn silhouette,
            // `design/shared/icons.jsx` `Icons.megaphone`), NOT a system SF Symbol —
            // rb-ios-live-announce-bullhorn-icon, replacing the earlier placeholder
            // `Image(systemName: "megaphone.fill")` which never matched the design's
            // actual bullhorn shape. 13pt (was 11pt) aligns the visual size with the
            // Android/RN/Flutter sibling changes and the design itself.
            RoundedRectangle(cornerRadius: 5)
                .fill(Self.announceBadgeColor)
                .frame(width: 22, height: 22)
                .overlay(
                    MegaphoneGlyph(size: 13, color: .white)
                )

            // Announce copy — 2-line clamped text (`LBLiveAnnounce`
            // `WebkitLineClamp:2`). White text on dark glass; tail-truncates past 2 lines.
            Text(announceText)
                .font(.system(size: 10.5 * theme.fontScale, weight: .semibold))
                .foregroundColor(Self.announceTextColor)
                .lineLimit(2)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Self.announceBgColor)
        )
        // Design `LBLiveAnnounce` is `left:8 right:120` (`live-chrome.jsx`, R31 — was
        // right:152, tightened as a ripple of the pinned card's 132×92→100×88 shrink),
        // i.e. its right edge sits 120pt from the screen edge so the (now-narrower)
        // pinned card clears it. On the 393pt reference frame that resolves to
        // 393−8−120 = 265pt (the HStack's 8pt horizontal padding supplies `left:8`).
        // Matches the Android parity width (rb-ios-live-announce-chat-clearance-restore).
        .frame(maxWidth: 265, alignment: .leading)
    }

    // MARK: - LBLivePinnedCard — pinned narrating-product card

    /// Bottom-right white product card for the single narrating product. Mirrors
    /// `LBLivePinnedCard`: image area, accent narrate tag, 1-line name, accent
    /// live price. Tap is a host-wired core exit (not owned here) so the card is
    /// presentation-only.
    private func pinnedCard(_ product: LBProduct) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Image area (design height 88 — R31: was 92; R34, 2026-09-04, `rb-ios-product-
            // detail-image-gallery`: 88→100 — the card's height 88 / width 100 non-equal
            // rectangle from R31 is corrected to a 100×100 SQUARE, matching the card's own
            // 100pt width below. This is a second, independent tweak on TOP of R31's 132×92→
            // 100×88 shrink — it does NOT revert R31's shrink decision, only the aspect ratio).
            // Themed placeholder so the snapshot baseline is deterministic without a network
            // image (no AsyncImage).
            ZStack(alignment: .topTrailing) {
                // Image area (design height 100, R34 — see above): a gray placeholder with the
                // REAL product image layered over it at runtime (`live` + a non-empty URL); the
                // snapshot path keeps the deterministic placeholder
                // (live-pinned-card-image-radius).
                ZStack {
                    Rectangle()
                        .fill(Color(hex: "#EFEFF2") ?? Color(.systemGray5))
                        .overlay(
                            Image(systemName: "photo")
                                .font(.system(size: 22, weight: .regular))
                                .foregroundColor(Color(hex: "#C7C7CC") ?? .gray)
                        )
                    if live, let url = Self.imageURL(product) {
                        RemoteStillImageView(url: url, contentMode: .scaleAspectFill)
                    }

                    // Narrate badge (R31, `rb-ios-vod-live-product-card-restyle`): moved OFF
                    // the below-image text row (see the name/price VStack below) onto a
                    // full-bleed banner overlaid on the image's bottom edge — design
                    // `LBLivePinnedCard` `position:absolute,left:0,right:0,bottom:0`, fixed
                    // `rgba(240,50,70,0.7)` coral (unified with `ProductRowView`'s「介紹中」
                    // badge — no longer `theme.accent`).
                    if Self.isNarrating(product, isLive: isLive) {
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            HStack(spacing: 3) {
                                EqualizerGlyph(size: 9, color: .white)
                                Text(Self.narrateTagText)
                                    .font(.system(size: 12 * theme.fontScale, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 3)
                            .padding(.horizontal, 4)
                            .background(Self.narrateBadgeColor)
                        }
                    }
                }
                .frame(height: 100)
                .clipped()

                // Close affordance chip → per-product-id local dismiss. An INNER Button
                // intercepts the tap so the card's OUTER open-detail Button does NOT also
                // fire (nested SwiftUI Buttons: the inner one wins within its bounds —
                // mirrors `MiniCartView.closeButton`'s `e.stopPropagation()`). PlainButtonStyle
                // keeps the pixels (baselines unchanged); inert when onDismissPinnedProduct == nil.
                Button(action: { onDismissPinnedProduct?(product.id) }) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.black.opacity(0.6))
                        .frame(width: 18, height: 18)
                        .overlay(
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityIdentifier(LBAccessibilityID.pinnedCardClose)
                .padding(4)
            }

            VStack(alignment: .leading, spacing: 3) {
                // Product name (R31: 2-line clamp / 10pt — was 1-line-clamp / 11pt; the
                // narrate tag that used to sit here moved onto the image banner above).
                Text(product.name)
                    .font(.system(size: 10 * theme.fontScale, weight: .semibold))
                    .foregroundColor(theme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .truncationMode(.tail)

                // Live price — sold-out shows「已售完」(dim) instead of the price, matching
                // the same sold_out > (nothing) precedence `MiniCartView`/`ProductRowView`
                // already use (`ProductStatusBadge.resolve`, single-source-of-truth per
                // goods-status-label-render). `priceShow` is the pre-formatted string.
                Text(Self.isSoldOut(product) ? Self.soldOutLabel : Self.livePriceText(product))
                    .font(.system(size: 13 * theme.fontScale,
                                  weight: Self.isSoldOut(product) ? .semibold : .heavy))
                    .foregroundColor(Self.isSoldOut(product) ? Self.soldOutColor : theme.accent)
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 8)
        }
        .frame(width: 100, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white)
        )
        // 4a: clip the whole card to the rounded shape so the top image area's corners
        // follow the card radius (previously the image `Rectangle` showed square top corners).
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .compositingGroup()
        .shadow(color: Color.black.opacity(0.25), radius: 9, x: 0, y: 6)
    }

    // MARK: - LBLiveHostCaption — centered host caption overlay

    /// Centered black-on-white host caption (`LBLiveHostCaption`). Translucent
    /// dark card with a "主持人" label + the host caption copy + a live-price row.
    /// The price row mirrors the design's third line — `價格:<pink>NT$ X</pink>
    /// 開始銷售` — and reads the price from `pinnedProduct` (NOT the caption
    /// string); it is omitted when there is no pinned product.
    private var hostCaptionOverlay: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Self.hostCaptionLabel)
                .font(.system(size: 11 * theme.fontScale, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.78))
            Text(hostCaption)
                .font(.system(size: 12 * theme.fontScale, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            // Live-price row (`LBLiveHostCaption` 3rd line) — reads the CURRENT pinned product
            // (follows the carousel page when multiple products are being introduced).
            if let product = currentPinnedProduct {
                HStack(spacing: 0) {
                    Text(Self.priceCaptionLabel)
                        .font(.system(size: 11 * theme.fontScale, weight: .regular))
                        .foregroundColor(Color.white.opacity(0.85))
                    Text(Self.livePriceText(product))
                        .font(.system(size: 11 * theme.fontScale, weight: .bold))
                        .foregroundColor(Self.captionPriceColor)
                    Text(Self.priceCaptionSuffix)
                        .font(.system(size: 11 * theme.fontScale, weight: .regular))
                        .foregroundColor(Color.white.opacity(0.85))
                        .padding(.leading, 10)
                }
                .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.45))
        )
    }

    // MARK: - LBPGestureHint — centered static gesture hints

    /// Up to three centered dark hint pills (`LBPGestureHint`): tap (不分直播/VOD 恆為切換
    /// 乾淨模式), 長按 = 2 倍速快轉（僅 seekable，即 `!isLive`，此 sub-view 情境下代表已結束
    /// 直播回放——真直播進行中長按無對應動作，該行整條不渲染）, swipe-to-switch. Pure static
    /// localized copy (`rb-ios-gesture-clean-mode-v2`, design R29, supersedes R23's
    /// `isLive`-branched tap copy + unconditionally-shown hold copy). The former
    /// `showsHoldPauseHint`-gated omission (rb-ios-gesture-clean-mode-rewrite, supersedes
    /// rb-ios-live-hold-pause-suppress) remains RETIRED and irrelevant here — the hold pill's
    /// visibility is now driven entirely by `!isLive` (seekable), not by that deprecated flag.
    private var gestureHints: some View {
        VStack(spacing: 8) {
            gestureHintPill(symbol: "hand.point.up.left.fill", text: Self.hintTap)
            if !isLive {
                gestureHintPill(symbol: "hand.raised.fill", text: Self.hintHold)
            }
            gestureHintPill(symbol: "arrow.up.arrow.down", text: Self.hintSwipe)
        }
    }

    private func gestureHintPill(symbol: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.white)
            Text(text)
                .font(.system(size: 11 * theme.fontScale, weight: .medium))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(Color.black.opacity(0.55))
        )
    }

    // MARK: - Design tokens / derived copy (pure)

    /// Announce banner background (`rgba(0,0,0,0.42)` — design-contract R30,
    /// `rb-ios-live-announce-banner-recolor`; replaces the never-synced
    /// `#FFE08A` yellow this layer shipped with since 2026-05-29). The design
    /// pairs this with `backdropFilter: blur(6px)`, which this layer does NOT
    /// implement — every `rgba(…)` "glass" fill in this package is drawn as a
    /// plain translucent color instead (see `FloatingWidgetView.closeGlass`
    /// and its doc comment for the documented rationale); this is that same
    /// deliberate convention, not an oversight.
    static let announceBgColor = Color.black.opacity(0.42)
    /// Announce icon badge (`#F03246` — the brand red used decoratively here).
    /// UNCHANGED by `rb-ios-live-announce-banner-recolor` — the design only
    /// recolored the banner background/text, not this square.
    static let announceBadgeColor = Color(hex: "#F03246") ?? Color.red
    /// Announce text color (`#fff` white on the dark-glass background —
    /// design-contract R30, `rb-ios-live-announce-banner-recolor`; replaces
    /// the never-synced `#15131A` dark text this layer shipped with since
    /// 2026-05-29).
    static let announceTextColor = Color.white

    /// Host caption label ("主持人").
    static let hostCaptionLabel = "主持人"
    /// Host-caption price-row prefix ("價格:") and suffix ("開始銷售").
    static let priceCaptionLabel = "價格:"
    static let priceCaptionSuffix = "開始銷售"
    /// Host-caption live-price color (`#FFD0D7` — design pink for the price span).
    static let captionPriceColor = Color(hex: "#FFD0D7") ?? Color.pink
    /// Narrate-tag copy shown on the pinned card — 恆定「介紹中」，不受 isFlashSale 影響
    /// (`rb-ios-narrating-banner-revert-flash-sale-text`). `rb-ios-flash-sale-live-signal-
    /// wiring` previously split this into「開標中」(flash-sale) vs「介紹中」(default) per
    /// the backend documentation's wording; the user later decided to revert that split for
    /// both this pinned-card copy AND `ProductRowView.introducingLabel` (a SEPARATE view/
    /// file's product-row narrating banner) — both are constants again. Written as a
    /// literal — reference-ui 層文案一律寫死、不走 i18n（同本檔案既有慣例）。
    static let narrateTagText = "介紹中"
    /// Narrate badge background (R31, `rb-ios-vod-live-product-card-restyle`): fixed
    /// `rgba(240,50,70,0.7)` coral — no longer `theme.accent`. Shared verbatim with
    /// `ProductRowView.introducingBadgeColor` (same design decision, same color).
    static let narrateBadgeColor = (Color(hex: "#F03246") ?? Color.red).opacity(0.7)

    /// Gesture-hint copy (static localized presentation strings, matching
    /// `LBPGestureHint` in `sdk-components.jsx`).
    ///
    /// Tap-hint copy (`rb-ios-gesture-clean-mode-v2`, design R29, supersedes R23's
    /// `isLive`-branched `hintTap(isLive:)` / `hintTapMute` / `hintTapPlayPause` trio): every
    /// short tap now toggles `cleanMode` — there is no longer a second outcome to branch on,
    /// so the copy is a single unconditional constant regardless of `isLive`.
    static let hintTap = "點擊畫面 = 切換乾淨模式"
    /// 長按提示文案（`rb-ios-gesture-clean-mode-v2`，design R29，取代 R23「長按畫面 = 切換
    /// 乾淨模式」版本）：長按改驅動 2 倍速快轉，僅在 seekable（此 sub-view 情境下即
    /// `!isLive`，代表已結束直播回放）時才有意義——`gestureHints` 只在該情境渲染這一行；
    /// 真直播進行中長按無對應動作，該行整條不渲染（見 `gestureHints`）。
    static let hintHold = "長按畫面 = 2倍速快轉"
    static let hintSwipe = "上下滑動 = 切換影片"

    /// The pinned product is "narrating" when `narrateStatus == 2`
    /// (core convention — see `LivebuyPlayerViewController.narrating`) — but ONLY when the
    /// pinned card comes from a genuinely-live source (`isLive == true`, `pinnedProducts` fed
    /// from `livePinnedProducts`). `narrate_status` is a per-product manual state machine the
    /// host operator drives while a broadcast is live; once the broadcast ends it freezes at
    /// whatever value it last had (may never have been cleared) and is no longer a meaningful
    /// signal. For a finished-live replay (`isLive == false`), `pinnedCard(_:)` only ever
    /// receives products already selected from `vodActiveProducts` — i.e. products whose
    /// `[beginTime,endTime)` window already contains the current playhead — so membership in
    /// that list IS the "narrating" signal; re-checking the stale `narrateStatus` on top of it
    /// makes the ribbon depend on backend leftover state instead of the actual introduction
    /// window (rb-ios-live-pinned-card-replay-narrate-fix).
    static func isNarrating(_ product: LBProduct, isLive: Bool) -> Bool {
        isLive ? product.narrateStatus == 2 : true
    }

    /// The pinned products that remain visible after applying the per-product-id local
    /// dismiss set (rb-ios-live-pinned-card-dismiss). The DECISION of "filter the pinned
    /// products by the dismissed set" — extracted as a pure function so the call-site wiring
    /// is unit-testable without rendering a real View (library test target has no host app;
    /// mirrors `WidgetVisibility.visibleVideos`). Empty `dismissedIds` → returns `products`
    /// AS-IS so the default path is provably zero-change (snapshot-safe). Semantically mirrors
    /// the VOD now-introducing card's `Set<String>` local hide + Android `0f6b56a5`.
    static func visiblePinnedProducts(_ products: [LBProduct], dismissedIds: Set<String>) -> [LBProduct] {
        dismissedIds.isEmpty ? products : products.filter { !dismissedIds.contains($0.id) }
    }

    /// A non-empty product image URL (`photos.first ?? pic`, whitespace-trimmed) for the
    /// real pinned-card image, or nil (empty / blank → keep the gray placeholder). Pure —
    /// mirrors `MiniCartView.imageURL` / `ProductListView.photoURL`.
    static func imageURL(_ product: LBProduct) -> URL? {
        let s = (product.photos.first ?? product.pic).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        return URL(string: s)
    }

    /// The live-price label. Prefers the pre-formatted `priceShow`; falls back to
    /// `NT$ <price>` when the show string is empty. Pure.
    static func livePriceText(_ product: LBProduct) -> String {
        let show = product.priceShow.trimmingCharacters(in: .whitespaces)
        if !show.isEmpty { return show }
        return "NT$ \(Int(product.price))"
    }

    /// Sold-out check for the pinned introducing-product card
    /// (rb-ios-live-pinned-card-soldout-label) — single source of truth via
    /// `ProductStatusBadge.resolve`, same helper `MiniCartView`/`ProductRowView` use.
    static func isSoldOut(_ product: LBProduct) -> Bool {
        ProductStatusBadge.resolve(product) == .soldOut
    }

    /// Sold-out price-line label (design「已售完」— same copy as `MiniCartView.soldOutLabel`).
    static let soldOutLabel = "已售完"

    /// Sold-out price-line color — CORRECTED from an earlier `textDim` (`#6B6775`) mistake
    /// (rb-ios-live-pinned-card-soldout-label-color-fix): `#6B6775` is this module's general
    /// dim-text token (struck-through original price etc — see `MiniCartView.textDim` /
    /// `ProductRowView.textDim`), NOT the sold-out-specific color. The correct convention for
    /// a「已售完」label specifically is `ProductRowView.soldOutColor` / `MiniCartView`'s own
    /// sold-out color, both `#9A96A3`.
    static let soldOutColor = Color(hex: "#9A96A3") ?? Color.gray
}
