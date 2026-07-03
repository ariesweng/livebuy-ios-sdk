import SwiftUI
import LiveBuySDK
import LiveBuyUI

// MARK: - PlayerHeaderBarView — family-1 surface 1 (top-bar chrome)
//
// Spec: `reference-ui-rendering/spec.md` (family-1 player-shell, surface 1)
// Design: rb-ios-player-shell design.md D-2 #1.
//   Mirrors design `LBPTopBar` / `LBPHostBadge`
//   (sdk-components.jsx): a pinned top bar with a glassy host pill (avatar + title
//   + host name + LIVE pill + viewer count + subscribe affordance) on the leading
//   edge, and a cluster of round glass icon buttons (info / share / mute / close)
//   on the trailing edge, over a top-down dark scrim gradient.
//
// This is family-1 SURFACE 1. It follows the documented SUB-VIEW INPUT PATTERN
// from `PlayerShellView.swift` EXACTLY:
//   1. `theme: ReferenceUITheme` — FIRST positional argument, always.
//   2. The bound SNAPSHOT VALUES it renders (title / hostName / shopLogo /
//      viewerCount / isSubscribed / muted / shareUrl), passed BY VALUE.
//   3. Optional action closures, trailing, each defaulting to `nil`. The shell
//      does NOT own actions — the host wires taps to core `simulate*` (D-4).
//
// It reads ONLY its passed-in values (one-way data flow, D-1/D-4): it never
// reaches back into `PlayerShellModel` or `DefaultPlayerTemplate`, and it renders
// correctly with EVERY action closure nil (so demo / snapshot tests construct it
// action-free).
//
// iOS-14-safe: uses only `ZStack` / `VStack` / `HStack` / `Text` / `Image(systemName:)`
// / `LinearGradient` / `Capsule` / `Circle` — all iOS-13+. The only API that needs
// an `@available` guard (`.foregroundStyle`) is intentionally NOT used; we use the
// iOS-13-safe `.foregroundColor` throughout (D-7).

/// The family-1 top-bar chrome. Pinned to the top of the player shell; paints the
/// glassy host pill + round glass control cluster over a dark scrim gradient.
public struct PlayerHeaderBarView: View {

    // MARK: - Inputs (documented sub-view input pattern)

    /// The resolved reference-ui theme (FIRST positional argument, always).
    public let theme: ReferenceUITheme

    // -- Bound snapshot values (passed BY VALUE from PlayerShellModel) ----------

    /// Host-pill title (`DefaultPlayerHeaderState.title`).
    public let title: String
    /// Host / shop name (`DefaultPlayerHeaderState.hostName`).
    public let hostName: String
    /// Host-pill / top-bar logo URL (`DefaultPlayerHeaderState.shopLogo`). The
    /// avatar is `live`-gated (same convention as `CarouselCardView`): `live ==
    /// false` (demo / snapshot) ALWAYS paints the deterministic monogram
    /// placeholder so the baseline is stable without a network image; `live ==
    /// true` (runtime) draws the REAL shop logo from this URL via the iOS-14-safe
    /// `RemoteStillImageView` when the URL is non-empty / parseable, and falls back
    /// to the monogram when it is empty / invalid (no logo → default).
    public let shopLogo: String
    /// Live viewer count (`DefaultPlayerHeaderState.viewerCount`). Shown only when
    /// `isLive && viewerCountVisible && showViewerCount` (see `showsViewerBadge`).
    public let viewerCount: Int
    /// Subscribe affordance state (`DefaultPlayerHeaderState.isSubscribed`).
    public let isSubscribed: Bool
    /// LIVE vs VOD flag (`DefaultPlayerHeaderState.isLive`, channel `liveStatus == 1`).
    /// Drives the viewer-count (shown ⟺ `isLive && viewerCountVisible && showViewerCount`,
    /// see `showsViewerBadge`) and — together with `isReplay` — the LIVE pill (shown ⟺
    /// `isLive && !isReplay`). VOD (`isLive == false`) shows neither.
    public let isLive: Bool

    /// Replay (回放) flag — a LIVE stream scrubbed behind the live edge
    /// (`DefaultPlaybackProgressState.isReplay`; `liveStatus == 1` so `isLive` STAYS true,
    /// `isReplay == true`). A by-value presentation flag fed from `PlayerShellModel` via
    /// `PlayerShellView` (NOT a header view-model field). Per design `LBPHostBadge`
    /// (`hideLivePill = isReplay`): replay HIDES the LIVE pill but KEEPS the viewer count.
    public let isReplay: Bool

    /// Live-runtime image gate (same convention as `CarouselCardView.live`). A
    /// by-value presentation flag (default `false`, NOT a header view-model field):
    /// `PlayerShellView` feeds `!paintsBackgroundPlaceholder` so the avatar loads the
    /// real `shopLogo` ONLY when the shell sits over a real video surface (runtime).
    /// `false` (demo / snapshot / `ImageRenderer` path) → avatar stays the monogram
    /// placeholder so the baseline never touches the network.
    public let live: Bool

    /// Host-controllable viewer-count visibility gate (rb-ios-hide-viewer-count-config).
    /// A by-value presentation flag fed from `PlayerShellModel` (sourced from
    /// `LiveBuyPlayerConfig.showViewerCount`; default `true`, NOT a header view-model field).
    /// The viewer count shows ⟺ `isLive && viewerCountVisible && showViewerCount`; `false`
    /// HIDES the viewer count even while `isLive` (incl. replay), WITHOUT affecting the LIVE
    /// pill or the core / view-model `viewerCount` data pipeline.
    public let showViewerCount: Bool

    /// Backend-driven viewer-count visibility mirror (rb-ios-viewer-count-show-pv-num).
    /// A by-value presentation flag fed from `PlayerShellModel.viewerCountVisible`, which
    /// mirrors the view-model `DefaultPlayerHeaderState.viewerCountVisible` (= core
    /// `LBPlayerMomentState.viewerCountVisible` = backend `channel.show_pv_num == 1`).
    /// Default `true` keeps existing preview / snapshot construction byte-identical. The
    /// viewer count shows ⟺ `isLive && viewerCountVisible && showViewerCount`: `false`
    /// (backend `show_pv_num != 1`) HIDES the viewer count even while `isLive` (incl. replay,
    /// which wears LIVE chrome — so replay honours the original live-time setting), WITHOUT
    /// affecting the LIVE pill or the core / view-model `viewerCount` data pipeline. Distinct
    /// from `showViewerCount` (host config): BOTH must be true to draw the badge.
    public let viewerCountVisible: Bool

    // -- Optional action closures (LAST, each defaulting to nil) ----------------
    //
    // The header's top-right is a SINGLE minimize affordance (design `LBPTopBar`
    // pip): tap → `onMinimize` (host collapses into the bottom-right floating widget).
    // Subscribe stays on the avatar badge. info / share live in the side rail; mute is
    // the tap-to-unmute gesture on the video area — neither is a header control.

    /// Tap on the top-right minimize button → host collapses the player into the
    /// bottom-right floating preview (`FloatingWidgetView`). nil → drawn but inert.
    public var onMinimize: (() -> Void)?
    /// Tap on the subscribe affordance (the small badge on the avatar).
    public var onSubscribe: (() -> Void)?
    /// Tap on the host badge (the whole host pill) → the shell opens the
    /// VideoInfoPanel (design `LBPHostBadge onTap → video_info`; presentation-only,
    /// replaces the removed VOD rail `more` pill). The subscribe badge is a nested
    /// Button that takes its own taps first, so tapping subscribe does NOT also fire
    /// this. nil → the badge is inert (demo / snapshot).
    public var onTapHostBadge: (() -> Void)?

    public init(
        theme: ReferenceUITheme,
        title: String,
        hostName: String,
        shopLogo: String,
        viewerCount: Int,
        isSubscribed: Bool,
        isLive: Bool,
        isReplay: Bool = false,
        live: Bool = false,
        showViewerCount: Bool = true,
        viewerCountVisible: Bool = true,
        onMinimize: (() -> Void)? = nil,
        onSubscribe: (() -> Void)? = nil,
        onTapHostBadge: (() -> Void)? = nil
    ) {
        self.theme = theme
        self.title = title
        self.hostName = hostName
        self.shopLogo = shopLogo
        self.viewerCount = viewerCount
        self.isSubscribed = isSubscribed
        self.isLive = isLive
        self.isReplay = isReplay
        self.live = live
        self.showViewerCount = showViewerCount
        self.viewerCountVisible = viewerCountVisible
        self.onMinimize = onMinimize
        self.onSubscribe = onSubscribe
        self.onTapHostBadge = onTapHostBadge
    }

    // MARK: - Design tokens (literal decorative hex from live-chrome.jsx)
    //
    // These are FIXED decorative colors from the design (glass pill / scrim /
    // on-glass white text). They are deliberately literal — they are NOT the
    // theme's accent / text / background, which the design uses for the LIVE pill
    // / subscribe badge and which we pull from `theme` below.

    /// Glass fill `rgba(20,20,24,0.55)` (host pill, live-chrome.jsx).
    private var pillGlass: Color { Color(hex: "#141418")?.opacity(0.55) ?? Color.black.opacity(0.55) }
    /// Glass fill `rgba(20,20,24,0.45)` (round icon buttons, live-chrome.jsx).
    private var iconGlass: Color { Color(hex: "#141418")?.opacity(0.45) ?? Color.black.opacity(0.45) }
    /// On-glass primary text — white.
    private var onGlass: Color { Color.white }
    /// On-glass secondary text `rgba(255,255,255,0.85)`.
    private var onGlassDim: Color { Color.white.opacity(0.85) }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                // The whole host pill is tappable → info panel (design `LBPHostBadge
                // onTap → video_info`). The nested subscribe Button inside takes its
                // own taps first (SwiftUI inner-button priority), so tapping subscribe
                // does NOT fire onTapHostBadge. PlainButtonStyle keeps the pixels
                // identical (pixel-neutral wrapper).
                Button(action: { onTapHostBadge?() }) { hostPill }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityIdentifier(LBAccessibilityID.playerHeaderHostPill)
                Spacer(minLength: 8)
                iconCluster
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 14)

            Spacer(minLength: 0)
        }
        // Top-down dark scrim gradient (linear-gradient rgba(0,0,0,0.45) → transparent).
        // The header body carries an internal `Spacer(minLength: 0)` so it expands to roughly
        // half the shell height in the shell's top VStack slot; its gradient `.background`
        // therefore covers the whole upper half. A SwiftUI `.background` participates in
        // hit-testing by DEFAULT, so without the guard below this purely-decorative scrim
        // SWALLOWS every tap / long-press / swipe in the upper half — they never reach the
        // full-bleed gesture layer (`Color.clear`) below it in `PlayerShellView`'s ZStack.
        // `.allowsHitTesting(false)` makes the scrim non-interactive (pixel-identical — it is
        // still drawn) so the upper-half gestures fall through to that gesture layer. The real
        // interactive controls (host pill / minimize) are foreground VStack content, NOT the
        // background, so they keep taking their own taps.
        .background(
            LinearGradient(
                gradient: Gradient(colors: [Color.black.opacity(0.45), Color.clear]),
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(LBAccessibilityID.playerHeader)
    }

    // MARK: - Host pill (LBPTopBar / LBPHostBadge)

    private var hostPill: some View {
        HStack(spacing: 8) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12 * theme.fontScale, weight: .bold))
                    .foregroundColor(onGlass)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(hostName)
                        .font(.system(size: 10.5 * theme.fontScale, weight: .regular))
                        .foregroundColor(onGlassDim)
                        .lineLimit(1)
                    // Per design `LBPHostBadge` (`isLive && !upcoming` outer gate; inner
                    // `hideLivePill = isReplay` / `hideViewerCount = upcoming`): the LIVE
                    // pill shows ⟺ `isLive && !isReplay` (replay HIDES the pill). VOD shows
                    // neither. The viewer count is gated by `showsViewerBadge` (the pure
                    // truth-table helper): it shows ⟺ `isLive && viewerCountVisible &&
                    // showViewerCount` — backend `show_pv_num == 1` (viewerCountVisible,
                    // rb-ios-viewer-count-show-pv-num) AND host `showViewerCount` (default
                    // true, rb-ios-hide-viewer-count-config). Either being false hides the
                    // count even while `isLive` (incl. replay, which wears LIVE chrome →
                    // replay honours the original live-time `show_pv_num`), without touching
                    // the LIVE pill.
                    if isLive {
                        if !isReplay {
                            livePill
                        }
                        if Self.showsViewerBadge(isLive: isLive,
                                                 viewerCountVisible: viewerCountVisible,
                                                 hostShowViewerCount: showViewerCount) {
                            viewerBadge
                        }
                    }
                }
            }
        }
        .padding(.leading, 4)
        .padding(.trailing, 12)
        .padding(.vertical, 4)
        .background(Capsule().fill(pillGlass))
    }

    /// Avatar — a white-backed 28×28 circle. The design fills it with the shop
    /// mark. `live`-gated (same convention as `CarouselCardView`): at runtime
    /// (`live == true`) with a non-empty / parseable `shopLogo` we draw the REAL
    /// shop logo via the iOS-14-safe `RemoteStillImageView` (no `AsyncImage`),
    /// clipped to the circle. Otherwise — `live == false` (demo / snapshot) OR an
    /// empty / invalid URL — we paint the deterministic monogram (first letter of
    /// host name, accent-tinted) so the baseline is stable without a network image.
    private var avatar: some View {
        ZStack {
            Circle().fill(Color.white)
            if live, let url = logoURL {
                // REAL shop logo over the white backing, filling and clipped to the
                // circle (square-ish marks fill cleanly; non-square get center-cropped).
                RemoteStillImageView(url: url, contentMode: .scaleAspectFill)
                    .clipShape(Circle())
            } else {
                // No logo (empty / invalid URL) or snapshot path → monogram default.
                Text(monogram)
                    .font(.system(size: 13 * theme.fontScale, weight: .bold))
                    .foregroundColor(theme.accent)
            }
        }
        .frame(width: 28, height: 28)
        // Subscribe badge sits at the bottom-trailing of the avatar (both backings).
        .overlay(subscribeBadge, alignment: .bottomTrailing)
    }

    /// Parsed `shopLogo` URL, or nil when empty / unparseable (→ monogram fallback).
    private var logoURL: URL? {
        shopLogo.isEmpty ? nil : URL(string: shopLogo)
    }

    /// First grapheme of the host name (or title) for the placeholder monogram.
    private var monogram: String {
        let source = hostName.isEmpty ? title : hostName
        return source.isEmpty ? "·" : String(source.prefix(1)).uppercased()
    }

    /// The small +/✓ subscribe badge overlaid on the avatar (LBPHostBadge).
    /// Subscribed → theme text fill + check; not subscribed → accent fill + plus.
    private var subscribeBadge: some View {
        Button(action: { onSubscribe?() }) {
            Text(isSubscribed ? "✓" : "+")
                .font(.system(size: 9 * theme.fontScale, weight: .bold))
                .foregroundColor(Color.white)
                .frame(width: 16, height: 16)
                .background(
                    Circle()
                        .fill(isSubscribed ? theme.text : theme.accent)
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                )
        }
        .buttonStyle(PlainButtonStyle())
        .offset(x: 3, y: 3)
        .accessibilityIdentifier(LBAccessibilityID.subscribeBadge)
    }

    /// The red LIVE pill (accent-filled) with a pulsing dot — drawn static for the
    /// snapshot baseline. Background uses `theme.accent` (the brand action red the
    /// design uses for the LIVE badge).
    ///
    /// The pill mirrors the design's `inline-flex` LIVE badge (`LBPTopBar` /
    /// `LBPHostBadge`): it MUST keep its intrinsic width and never wrap "LIVE" to a
    /// second line. `.lineLimit(1)` + `.fixedSize` on the label, and `.fixedSize`
    /// on the whole pill, make it rigid so the flexible title / host name (single
    /// line + ellipsis) absorb any horizontal squeeze first.
    private var livePill: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(Color.white)
                .frame(width: 4, height: 4)
            Text("LIVE")
                .font(.system(size: 9.5 * theme.fontScale, weight: .heavy))
                .foregroundColor(Color.white)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
        .background(RoundedRectangle(cornerRadius: 4).fill(theme.accent))
        .fixedSize(horizontal: true, vertical: false)
    }

    /// Viewer count with a small people glyph. Mirrors the design's nowrap
    /// viewer-count span: `.fixedSize` keeps "12.3K" fully visible (never clipped
    /// to "12...."); only the title / host name ellipsize under squeeze.
    private var viewerBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "person.2")
                .font(.system(size: 9 * theme.fontScale))
                .foregroundColor(onGlassDim)
            Text(Self.formatViewerCount(viewerCount))
                .font(.system(size: 10.5 * theme.fontScale, weight: .regular))
                .foregroundColor(onGlassDim)
                .lineLimit(1)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: - Trailing control — SINGLE minimize button (LBPTopBar pip affordance)
    //
    // The top-right contains ONLY a minimize control (design `LBPTopBar` pip; user
    // requirement「右上角只有縮小的元件」). Tapping it collapses the player into the
    // bottom-right floating preview (host-owned, reusing `FloatingWidgetView`). info /
    // share live in the side rail; mute is the tap-to-unmute gesture on the video area.

    private var iconCluster: some View {
        glassIconButton(systemName: "pip.enter", action: onMinimize)
            .accessibilityIdentifier(LBAccessibilityID.playerMinimize)
    }

    /// A 36×36 round glass icon button (live-chrome.jsx iconBtn). Inert when its
    /// action is nil — still rendered so the chrome is visually complete.
    private func glassIconButton(systemName: String, action: (() -> Void)?) -> some View {
        Button(action: { action?() }) {
            Image(systemName: systemName)
                .font(.system(size: 16 * theme.fontScale, weight: .semibold))
                .foregroundColor(onGlass)
                .frame(width: 36, height: 36)
                .background(Circle().fill(iconGlass))
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Pure helpers

    /// Viewer-count badge visibility gate (rb-ios-viewer-count-show-pv-num). Pure /
    /// deterministic truth table — extracted so the gate is unit-testable without
    /// rendering. The viewer count draws ⟺ ALL THREE hold:
    ///   - `isLive` — live-chrome family (true live OR finished-live replay; VOD shows none).
    ///   - `viewerCountVisible` — backend `channel.show_pv_num == 1` (mirrored from the
    ///     view-model `DefaultPlayerHeaderState.viewerCountVisible`). Replay reuses the LIVE
    ///     chrome so it honours the original live-time setting.
    ///   - `hostShowViewerCount` — host config `LiveBuyPlayerConfig.showViewerCount` (default
    ///     true); a host may force-hide regardless of the backend flag.
    /// Any one being `false` hides the badge; the LIVE pill is unaffected (separate gate).
    static func showsViewerBadge(isLive: Bool,
                                 viewerCountVisible: Bool,
                                 hostShowViewerCount: Bool) -> Bool {
        isLive && viewerCountVisible && hostShowViewerCount
    }

    /// Compact viewer-count formatting (e.g. `12345` → `12.3K`). Pure / deterministic.
    static func formatViewerCount(_ count: Int) -> String {
        if count < 1000 { return String(count) }
        let thousands = Double(count) / 1000.0
        // One decimal, trim trailing `.0` (e.g. 2000 → "2K", 12345 → "12.3K").
        let rounded = (thousands * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return "\(Int(rounded))K"
        }
        return String(format: "%.1fK", rounded)
    }
}

// MARK: - Deterministic demo (previews / snapshot tests)

extension PlayerHeaderBarView {
    /// A deterministic, action-free demo instance for previews / snapshot tests.
    /// `live` toggles the LIVE chrome (LIVE pill + viewer count) vs the VOD chrome;
    /// `replay` (only meaningful when `live`) drops the LIVE pill while keeping the
    /// viewer count (回放 = scrubbed behind the live edge). Seeds stable copy so the
    /// baseline does not depend on a live player.
    static func demo(theme: ReferenceUITheme = ReferenceUIThemePalette.minimal,
                     live: Bool = true,
                     replay: Bool = false) -> PlayerHeaderBarView {
        PlayerHeaderBarView(
            theme: theme,
            title: "夏日彩妝特賣",
            hostName: "BeautyTown 官方",
            shopLogo: "",
            viewerCount: 12345,
            isSubscribed: false,
            isLive: live,
            isReplay: replay
        )
    }
}

#if DEBUG
struct PlayerHeaderBarView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color(hex: "#2A2730") ?? .gray
            VStack {
                PlayerHeaderBarView.demo()
                Spacer()
            }
        }
        .previewLayout(.fixed(width: 393, height: 180))
    }
}
#endif
