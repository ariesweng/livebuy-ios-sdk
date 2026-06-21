import SwiftUI
import LiveBuySDK
import LiveBuyUI

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

    /// Whether to draw the static gesture-hint pills (`LBPGestureHint`). Pure
    /// presentation copy — no view-model binding.
    public let showGestureHints: Bool

    /// When true, the gesture-hint pills fade out shortly after appearing
    /// (onboarding affordance over a real live video). Defaults to `false` →
    /// static presentation so snapshot baselines stay deterministic.
    public let autoFadeGestureHints: Bool

    /// Tap on the pinned-product card → host-wired turnkey product-detail flow
    /// (PlayerShellView forwards to `model.performProductTap`). nil → the card is
    /// drawn but inert (demo / snapshot). No pixel change either way.
    private let onTapPinnedProduct: ((LBProduct) -> Void)?

    /// Tap on the announcement banner (`LBLiveAnnounce`) → host-wired navigation that
    /// opens the `VideoInfoPanelView` notice tab (PlayerShellView wires
    /// `selectInfoTab(.notice)` + `infoPanelPresented = true`). nil → the banner is drawn
    /// but inert (demo / snapshot). Pixel-neutral either way (`PlainButtonStyle` wrapper) —
    /// live-announce-tap-open-info-panel.
    private let onTapAnnounce: (() -> Void)?

    public init(theme: ReferenceUITheme,
                announceText: String,
                pinnedProducts: [LBProduct],
                live: Bool = false,
                hostCaption: String = "",
                showGestureHints: Bool = true,
                autoFadeGestureHints: Bool = false,
                onTapPinnedProduct: ((LBProduct) -> Void)? = nil,
                onTapAnnounce: (() -> Void)? = nil) {
        self.theme = theme
        self.announceText = announceText
        self.pinnedProducts = pinnedProducts
        self.live = live
        self.hostCaption = hostCaption
        self.showGestureHints = showGestureHints
        self.autoFadeGestureHints = autoFadeGestureHints
        self.onTapPinnedProduct = onTapPinnedProduct
        self.onTapAnnounce = onTapAnnounce
    }

    /// Gesture-hint opacity — starts visible, then fades out shortly after the
    /// overlay appears so the onboarding pills don't linger over the live video.
    /// Static snapshot renders capture it at the initial full opacity (no
    /// `onAppear` / animation runs there → baselines unchanged).
    @State private var gestureHintsOpacity: Double = 1

    public var body: some View {
        // Full-bleed overlay. Affordances are positioned with explicit padding
        // so the layout matches `live-chrome.jsx`'s absolute placement without an
        // iOS-15+ `safeAreaInset`. Taps pass through where the design declares
        // `pointerEvents: none` (caption / gesture hints).
        ZStack {
            // Centered host caption (~46% from the top — `LBLiveHostCaption`).
            if !hostCaption.isEmpty {
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
            // briefly then fade out; otherwise static (snapshot-deterministic).
            if showGestureHints {
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
            // `live-chrome.jsx`: announce `left:8 right:152 bottom:70`,
            // pinned card `right:8 bottom:64 width:132`.
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                HStack(alignment: .bottom, spacing: 8) {
                    if !announceText.isEmpty {
                        // Tappable → host-wired navigation that opens the VideoInfoPanel notice
                        // tab (PlayerShellView: selectInfoTab(.notice) + infoPanelPresented).
                        // PlainButtonStyle keeps the pixels (snapshot baselines unchanged);
                        // inert when onTapAnnounce == nil (live-announce-tap-open-info-panel).
                        Button(action: { onTapAnnounce?() }) {
                            announceBanner
                        }
                        .buttonStyle(PlainButtonStyle())
                        .accessibilityIdentifier(LBAccessibilityID.announceBanner)
                    }
                    Spacer(minLength: 0)
                    pinnedCardCarousel
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 64)
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

    /// Bottom-left yellow announcement banner with a red icon badge and a
    /// horizontally-marqueeing text. Mirrors `LBLiveAnnounce` from
    /// `live-chrome.jsx` (`#FFE08A` background, `#F03246` icon badge).
    private var announceBanner: some View {
        HStack(spacing: 8) {
            // Red icon badge (`#F03246`, 22×22, radius 5).
            RoundedRectangle(cornerRadius: 5)
                .fill(Self.announceBadgeColor)
                .frame(width: 22, height: 22)
                .overlay(
                    Image(systemName: "megaphone.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                )

            // Announce copy — 2-line clamped text (`LBLiveAnnounce`
            // `WebkitLineClamp:2`). Dark text on yellow; tail-truncates past 2 lines.
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
        // Design `LBLiveAnnounce` is `left:8 right:152` (`live-chrome.jsx`), i.e. its
        // right edge sits 152pt from the screen edge so the pinned card clears it. On
        // the 393pt reference frame that resolves to 393−8−152 = 233pt (the HStack's
        // 8pt horizontal padding supplies `left:8`). Matches the Android parity width.
        .frame(maxWidth: 233, alignment: .leading)
    }

    // MARK: - LBLivePinnedCard — pinned narrating-product card

    /// Bottom-right white product card for the single narrating product. Mirrors
    /// `LBLivePinnedCard`: image area, accent narrate tag, 1-line name, accent
    /// live price. Tap is a host-wired core exit (not owned here) so the card is
    /// presentation-only.
    private func pinnedCard(_ product: LBProduct) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Image area (design height 92). Themed placeholder so the snapshot
            // baseline is deterministic without a network image (no AsyncImage).
            ZStack(alignment: .topTrailing) {
                // Image area (design height 92): a gray placeholder with the REAL product
                // image layered over it at runtime (`live` + a non-empty URL); the snapshot
                // path keeps the deterministic placeholder (live-pinned-card-image-radius).
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
                }
                .frame(height: 92)
                .clipped()

                // Close affordance chip (presentation-only; tap is host-wired).
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.black.opacity(0.6))
                    .frame(width: 18, height: 18)
                    .overlay(
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                    )
                    .padding(4)
            }

            VStack(alignment: .leading, spacing: 3) {
                // Narrate tag (accent) — shown for the narrating product.
                if Self.isNarrating(product) {
                    HStack(spacing: 3) {
                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text(Self.narrateTagText)
                            .font(.system(size: 11 * theme.fontScale, weight: .bold))
                    }
                    .foregroundColor(theme.accent)
                }

                // Product name (1-line clamp, design dark text).
                Text(product.name)
                    .font(.system(size: 11 * theme.fontScale, weight: .semibold))
                    .foregroundColor(theme.text)
                    .lineLimit(1)
                    .truncationMode(.tail)

                // Live price (accent). `priceShow` is the pre-formatted string.
                Text(Self.livePriceText(product))
                    .font(.system(size: 13 * theme.fontScale, weight: .heavy))
                    .foregroundColor(theme.accent)
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 8)
        }
        .frame(width: 132, alignment: .leading)
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

    /// Three centered dark hint pills (`LBPGestureHint`): tap-to-mute,
    /// long-press-pause, swipe-to-switch. Pure static localized copy.
    private var gestureHints: some View {
        VStack(spacing: 8) {
            gestureHintPill(symbol: "hand.point.up.left.fill", text: Self.hintTap)
            gestureHintPill(symbol: "hand.raised.fill", text: Self.hintHold)
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

    /// Announce banner background (`#FFE08A` — fixed decorative design hex).
    static let announceBgColor = Color(hex: "#FFE08A") ?? Color.yellow
    /// Announce icon badge (`#F03246` — the brand red used decoratively here).
    static let announceBadgeColor = Color(hex: "#F03246") ?? Color.red
    /// Announce text color (`#15131A` — fixed design dark text on yellow).
    static let announceTextColor = Color(hex: "#15131A") ?? Color.black

    /// Host caption label ("主持人").
    static let hostCaptionLabel = "主持人"
    /// Host-caption price-row prefix ("價格:") and suffix ("開始銷售").
    static let priceCaptionLabel = "價格:"
    static let priceCaptionSuffix = "開始銷售"
    /// Host-caption live-price color (`#FFD0D7` — design pink for the price span).
    static let captionPriceColor = Color(hex: "#FFD0D7") ?? Color.pink
    /// Narrate-tag copy shown on the pinned card ("介紹中").
    static let narrateTagText = "介紹中"

    /// Gesture-hint copy (static localized presentation strings, matching
    /// `LBPGestureHint` in `sdk-components.jsx`).
    static let hintTap = "點擊畫面 = 切換靜音"
    static let hintHold = "長按畫面 = 暫停 / 繼續"
    static let hintSwipe = "上下滑動 = 切換影片"

    /// The pinned product is "narrating" when `narrateStatus == 2`
    /// (core convention — see `LiveBuyPlayerViewController.narrating`).
    static func isNarrating(_ product: LBProduct) -> Bool {
        product.narrateStatus == 2
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
}
