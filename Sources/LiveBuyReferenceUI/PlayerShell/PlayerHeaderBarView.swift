import SwiftUI
import UIKit
import LivebuySDK
import LivebuyUI

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
    /// `LivebuyPlayerConfig.showViewerCount`; default `true`, NOT a header view-model field).
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
                titleView

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

    // MARK: - Title (LBPMarqueeText) — rb-ios-marquee-title-scroll
    //
    // Parity `design/templates/minimal/sdk-components.jsx`'s `LBPMarqueeText` and the
    // already-shipped Android port. Closes a documented design/implementation gap: the
    // title used to always truncate with an ellipsis; it now marquee-scrolls when it
    // overflows.

    /// The title slot. The layout-participating (and therefore negotiation-affecting)
    /// view is ALWAYS the exact same unconstrained, static `Text` this rendered before
    /// this change — same modifiers, no `.frame`, no wrapper — so it hugs/squeezes in
    /// the surrounding `HStack`/`VStack` negotiation IDENTICALLY to before this change,
    /// for every title, every time. Zero behavior change / byte-identical for the
    /// common (fits) case, guaranteed structurally, not just by a threshold check.
    ///
    /// The marquee, when needed, is attached as an `.overlay` — a PURELY VISUAL
    /// addition that does not feed back into the base `Text`'s own reported size (this
    /// is what makes it safe: an EARLIER attempt that instead swapped the
    /// layout-participating view itself between the static `Text` and a
    /// `.frame`-sized `MarqueeTitleLoopView` was found, by direct empirical testing, to
    /// perturb the surrounding pill's negotiation — the fixed-frame marquee refused to
    /// shrink under squeeze the way the original elastic `Text` did, redirecting that
    /// squeeze pressure onto the host-name row below instead and spuriously
    /// over-truncating it).
    ///
    /// The overlay's content is `GeometryReader` — used here specifically because
    /// `.overlay(_:alignment:)` proposes its content the SAME size the base `Text`
    /// itself resolved to (post-squeeze, if any), and `GeometryReader`'s closure can
    /// read that proposed size and decide what to render SYNCHRONOUSLY, in the exact
    /// same pass — no `@State` / `.onPreferenceChange` round trip needed. An earlier
    /// attempt used this module's established `.background(GeometryReader {
    /// ... }.preference(...))` + `.onPreferenceChange` measuring idiom instead (as used
    /// elsewhere in this module for other views), which requires an `@State` write to
    /// trigger a SECOND render pass before the measurement is available — and whether
    /// `ImageRenderer` (this module's snapshot mechanism) performs that second
    /// settling pass within one synchronous capture was found, by direct empirical
    /// testing, to be UNPREDICTABLE across otherwise-equivalent view shapes. Reading
    /// the proposed size directly inside the overlay's own `GeometryReader` sidesteps
    /// that non-determinism entirely — no second pass is ever required.
    ///
    /// Purely content-driven — there is NO manual toggle; whether the overlay paints is
    /// 100% determined by `marqueeTitleOverflows`.
    private var titleView: some View {
        let font = Font.system(size: 12 * theme.fontScale, weight: .bold)
        let textWidth = Self.marqueeIntrinsicTextWidth(title, fontSize: 12 * theme.fontScale)
        return Text(title)
            .font(font)
            .foregroundColor(onGlass)
            .lineLimit(1)
            .overlay(
                GeometryReader { proxy in
                    let containerWidth = proxy.size.width
                    Group {
                        if Self.marqueeTitleOverflows(textWidth: textWidth, containerWidth: containerWidth) {
                            MarqueeTitleLoopView(
                                title: title,
                                font: font,
                                color: onGlass,
                                textWidth: textWidth,
                                containerWidth: containerWidth,
                                gap: Self.marqueeGap,
                                durationSeconds: Self.marqueeDurationSeconds(textWidth: textWidth)
                            )
                        }
                    }
                },
                alignment: .leading
            )
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
    ///   - `hostShowViewerCount` — host config `LivebuyPlayerConfig.showViewerCount` (default
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

    // MARK: - Marquee pure helpers (rb-ios-marquee-title-scroll)
    //
    // Parity JSX `LBPMarqueeText` (`design/templates/minimal/sdk-components.jsx:282-330`)
    // and the already-shipped Android port
    // (`openspec/changes/archive/2026-07-03-rb-android-marquee-title-scroll/`). All three
    // are pure / deterministic — no SwiftUI, no IO — directly unit-testable
    // (`docs/unit-test-discipline.md`).

    /// Marquee scroll speed in points/sec (parity JSX `speedPxPerSec = 32` and Android's
    /// `MARQUEE_SPEED_DP_PER_SEC`). Points are iOS's device-independent layout unit — the
    /// same conceptual role as Android's dp — so this is a direct port with no unit
    /// adjustment, mirroring Android's own "no adjustment needed" determination.
    static let marqueeSpeedPointsPerSecond: CGFloat = 32
    /// Marquee minimum loop duration floor in seconds (parity JSX `Math.max(8, ...)` /
    /// Android's `MARQUEE_MIN_DURATION_SECONDS`).
    static let marqueeMinDurationSeconds: Double = 8
    /// Gap between the two duplicated title copies in the marquee loop (parity JSX
    /// `gap = 36` / Android's `MARQUEE_GAP_DP`).
    static let marqueeGap: CGFloat = 36

    /// Marquee overflow decision (parity JSX `LBPMarqueeText`'s `scrollWidth <=
    /// clientWidth` / Android's `marqueeTitleOverflows`). Pure / deterministic. `textWidth`
    /// is the title's measured intrinsic single-line width; `containerWidth` is the host
    /// pill's actual available width for the title slot. Overflow (→ marquee) ⟺ the text
    /// is strictly wider than the container — a direct, strict `>` port of Android's
    /// decision (NOT the JSX's own `+ 1` CSS tolerance), kept for 2-platform-consistent
    /// behavior rather than re-deriving from the JSX independently.
    static func marqueeTitleOverflows(textWidth: CGFloat, containerWidth: CGFloat) -> Bool {
        textWidth > containerWidth
    }

    /// Marquee loop duration in seconds (parity JSX `dur = Math.max(8, scrollWidthPx /
    /// speedPxPerSec)` / Android's `marqueeDurationMillis` — direct pt-for-dp port, no
    /// unit adjustment needed). Pure / deterministic.
    static func marqueeDurationSeconds(
        textWidth: CGFloat,
        speedPointsPerSecond: CGFloat = Self.marqueeSpeedPointsPerSecond,
        minDurationSeconds: Double = Self.marqueeMinDurationSeconds
    ) -> Double {
        max(minDurationSeconds, Double(textWidth / speedPointsPerSecond))
    }

    /// The title's intrinsic single-line width at `fontSize` (bold, matching the static
    /// `Text`'s weight) — a pure, synchronous UIKit text-measurement calculation
    /// (`NSString.size(withAttributes:)`), zero rendering / view-hierarchy dependency.
    /// This module already bridges to UIKit/Foundation elsewhere for measurement-adjacent
    /// needs (`ChatComposerBar.swift`'s `NSAttributedString`, `LoadingMarkAnimationView.swift`'s
    /// `UIImage`) — following that precedent keeps this directly unit-testable with no
    /// `View` involved, unlike a hidden SwiftUI probe view would be.
    static func marqueeIntrinsicTextWidth(_ text: String, fontSize: CGFloat) -> CGFloat {
        let font = UIFont.boldSystemFont(ofSize: fontSize)
        return (text as NSString).size(withAttributes: [.font: font]).width
    }
}

// MARK: - MarqueeTitleLoopView (LBPMarqueeText overflow branch) — rb-ios-marquee-title-scroll
//
// The continuously-looping title marquee (overflow branch of
// `PlayerHeaderBarView.titleView`; parity JSX `LBPMarqueeText`'s covered branch —
// duplicate the text with a gap, animate a seamless leftward loop; parity the
// already-shipped Android `MarqueeLoop`). Follows this module's own established
// continuous-loop idiom (`SpinnerRingView.swift`'s `@State` + `.onAppear` +
// `withAnimation(.linear(duration:).repeatForever(autoreverses: false))`, also used by
// `WinEntryView.swift`'s pulse and `StartScreenView.swift`'s spinner) rather than
// introducing a new animation mechanism — a `Timer`-driven frame clock
// (`LoadingMarkAnimationView.swift`'s idiom) is the wrong tool here: that exists for
// *discrete* PNG-sequence frame stepping, whereas this is *continuous* interpolated
// motion, which `withAnimation(...repeatForever...)` handles natively.
//
// Under `ImageRenderer` (this module's snapshot mechanism, `ReferenceUISnapshotHelper`),
// `.onAppear` does not fire (established precedent — see `SpinnerRingView.swift`'s doc
// comment, empirically reconfirmed for this change: `AddToCartSheetViewSnapshotTests
// .testAddToCartSheetView_loadingState_rendersDeterministically`, which renders
// `SpinnerRingView` via the identical idiom, was run twice in direct succession and
// byte-exact-matched its existing golden both times). So a snapshot of this view
// deterministically captures the RESTING frame (`scrolling == false`, offset `0`): two
// duplicated title copies laid out side by side with the fixed gap, no scroll
// displacement yet — still a real, meaningfully different visual from the ellipsized
// static branch, proving the overflow branch renders.
private struct MarqueeTitleLoopView: View {
    let title: String
    let font: Font
    let color: Color
    let textWidth: CGFloat
    let containerWidth: CGFloat
    let gap: CGFloat
    let durationSeconds: Double

    /// `false` at rest (and under `ImageRenderer`, permanently — see the file header
    /// comment above); flips to `true` once in `.onAppear` to start the infinite loop.
    @State private var scrolling = false

    /// Continuous-animation throttling gate (ios-power-profile-animation-throttle-reference-ui).
    /// The infinite marquee `repeatForever` driver only STARTS when this allows it (device not
    /// hot, Reduce Motion off, on-screen). This is layered ON TOP of the existing overflow gate
    /// (this view is only instantiated when the title overflows) — it does NOT change whether
    /// this view is built, only whether it scrolls. Defaults to neutral "animate" when unset.
    @Environment(\.continuousAnimationGate) private var motionGate

    var body: some View {
        HStack(spacing: gap) {
            Text(title).font(font).foregroundColor(color).lineLimit(1).fixedSize()
            Text(title).font(font).foregroundColor(color).lineLimit(1).fixedSize()
        }
        // Translating by exactly `-(textWidth + gap)` moves the second (duplicate) copy
        // into the first copy's original starting position — a seamless loop, mirroring
        // JSX's `-50%` of the doubled content / Android's identical `targetValue`.
        .offset(x: scrolling ? -(textWidth + gap) : 0)
        // This view only ever renders inside `PlayerHeaderBarView.titleView`'s
        // `.overlay(GeometryReader { ... })`, which already proposes it EXACTLY
        // `containerWidth` (the base `Text`'s own true resolved width) — so this
        // `.frame(maxWidth:)` is belt-and-suspenders self-containment (correct even if
        // reused in some other ambient proposal), not the primary defense. Critically,
        // this view's sizing NEVER feeds back into the surrounding `HStack`/`VStack`
        // negotiation at all (overlay content is layout-inert to its ancestors) — that
        // is what actually keeps the host-name row unaffected, verified empirically
        // during this change (an earlier version made this view part of the
        // LAYOUT-PARTICIPATING tree via a `Group` if/else swap with a rigid
        // `.frame(width:)`; that rigid frame refused to shrink under real squeeze,
        // redirecting the excess pressure onto the host-name row and spuriously
        // over-truncating it — switching to `maxWidth` alone did NOT fix it, since the
        // real fix was removing this view from the negotiation entirely via `.overlay`).
        // `.clipped()` clips to whatever width is proposed.
        .frame(maxWidth: containerWidth, alignment: .leading)
        .clipped()
        .onAppear { startScroll() }
        // Re-evaluate when the power-profile / reduce-motion gate flips (heat → freeze at rest,
        // cool → resume). `ContinuousAnimationGate` is `Equatable`.
        .onChange(of: motionGate) { _ in startScroll() }
        // Off-screen: reset to the resting position WITHOUT animation, so no `repeatForever`
        // driver survives off-screen.
        .onDisappear { scrolling = false }
    }

    /// (Re)start the infinite leftward loop — ONLY when the throttling gate allows it. Resets to
    /// the resting offset first; under thermal pressure / Reduce Motion the two title copies stay
    /// at their static side-by-side layout (`scrolling == false`), no `repeatForever` driver
    /// starts. Only ever skips the animation DRIVER — both `Text` copies still instantiate + lay
    /// out, so the overflow-branch snapshot (`player-header-bar-marquee-overflow`) is unchanged.
    private func startScroll() {
        scrolling = false
        guard motionGate.allowsAnimation(visible: true) else { return }
        withAnimation(.linear(duration: durationSeconds).repeatForever(autoreverses: false)) {
            scrolling = true
        }
    }
}

// MARK: - Deterministic demo (previews / snapshot tests)

extension PlayerHeaderBarView {
    /// A deterministic, action-free demo instance for previews / snapshot tests.
    /// `live` toggles the LIVE chrome (LIVE pill + viewer count) vs the VOD chrome;
    /// `replay` (only meaningful when `live`) drops the LIVE pill while keeping the
    /// viewer count (回放 = scrubbed behind the live edge). Seeds stable copy so the
    /// baseline does not depend on a live player. `title` defaults to the existing
    /// short demo title (byte-identical for every existing call site); pass a
    /// deliberately long one (rb-ios-marquee-title-scroll) to exercise the marquee
    /// overflow branch in a snapshot.
    static func demo(theme: ReferenceUITheme = ReferenceUIThemePalette.minimal,
                     live: Bool = true,
                     replay: Bool = false,
                     title: String = "夏日彩妝特賣") -> PlayerHeaderBarView {
        PlayerHeaderBarView(
            theme: theme,
            title: title,
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
