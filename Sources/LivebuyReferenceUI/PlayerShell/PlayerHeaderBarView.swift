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

// MARK: - LBVideoTitleScroll — the single fallback entry point (normalizeTitleScroll)

/// Turns the RAW wire value of `POST /sdk/config` → `data.extensions.video_title_scroll` into the
/// `Bool` that `LivebuyPlayerConfig.titleScroll` takes. The iOS counterpart of the design's
/// `normalizeTitleScroll` (`design/templates/minimal/sdk-components.jsx`, R15).
///
/// `extensions` is an OPAQUE RAW BAG: the `sdk-config` capability forbids the SDK from interpreting
/// any key in it, so core never normalizes this value and never applies the backend's default. The
/// host reads it (`sdkConfig.extensions["video_title_scroll"]?.value` — one `AnyEquatable` unwrap)
/// and hands it here. That makes THIS layer the owner of the malformed-value fallback, which is why
/// the rule lives in reference-ui rather than in core or in each host.
///
/// Deliberately uninhabited (a namespace, not a state): the domain is genuinely binary, so wrapping
/// the answer in a two-case enum would only add a conversion hop between the config field and the
/// view without buying any type safety.
public enum LBVideoTitleScroll {

    /// THE ONLY place a raw `video_title_scroll` value becomes a `Bool`. Mirrors the design's
    /// `normalizeTitleScroll(raw)` (`!(raw === 0 || raw === '0' || raw === false)`) EXACTLY:
    /// ONLY `false`, the number `0`, and the string `"0"` spelled verbatim mean "do not scroll".
    ///
    /// Everything else lands on `true` — the absent key, JSON `null` (`NSNull`), `1`, `"1"`, `""`,
    /// `" 0 "`, `"false"`, and any unexpected type. The comparison is STRICT: no trimming, no case
    /// folding, no alias table, exactly like `LBProductCardMode.normalized(_:)` and
    /// `LBFloatingEntryPosition.normalized(_:)`. Being deliberately as strict as the design keeps
    /// the four platforms' fallback boundary identical precisely when the backend emits something
    /// malformed — which is when a divergence would be hardest to spot. The backend passes
    /// `extensions` through raw and normalizes nothing (the source is a JSON column that can hold
    /// legacy or hand-edited values), so this really does happen.
    ///
    /// The fallback lands on `true` (scrolling) on purpose: that is the side the backend's own
    /// default (`1`, when the merchant never set it) is on, AND the side this module behaved on
    /// before the setting existed — so an unset / malformed value costs an existing host nothing.
    ///
    /// ⚠️ `false` means "do not scroll", NOT "do not show" — see `PlayerHeaderBarView.titleScroll`.
    ///
    /// Type notes (why the cases are in this order):
    ///   - `Bool` first absorbs the `NSNumber` values JSON decoding produces for `0` / `1`, both of
    ///     which bridge to `Bool`; that avoids leaning on `Int` bridging subtleties for the two
    ///     values that actually matter. `NSNumber(2)` does NOT bridge to `Bool` and falls through
    ///     to the `Int` case → `2 != 0` → `true`, matching JS's `2 !== 0`.
    ///   - The `Double` case exists for a Swift-native `0.0` (which `as? Int` would reject); JS
    ///     treats `0.0 === 0` as true, so both land on "do not scroll".
    ///   - A host that forgets the `.value` unwrap and hands over the `AnyEquatable` wrapper hits
    ///     `default` → `true`: the setting silently fails OPEN (title still scrolls) rather than
    ///     doing something destructive.
    public static func normalized(_ raw: Any?) -> Bool {
        switch raw {
        case let flag as Bool:     return flag
        case let number as Int:    return number != 0
        case let number as Double: return number != 0
        case let text as String:   return text != "0"
        default:                   return true
        }
    }
}

// MARK: - Subscribe-badge visibility gate (rb-ios-subscribe-favorite-visibility-toggle)
//
// `LivebuyPlayerConfig.showSubscribe` (default `false`, an intentional opt-in product decision —
// 訂閱功能改為預設關閉隱藏) needs to reach this leaf view WITHOUT this change touching
// `PlayerShellModel.swift` / `PlayerShellView.swift` (both outside this change's file scope —
// see `LivebuyPlayerConfig.showSubscribe`'s doc comment). Delivered via `SwiftUI.Environment`
// instead of an explicit init parameter (a deliberate departure from this file's own documented
// "SUB-VIEW INPUT PATTERN" of bound-value init params, for that one reason only), mirroring the
// EXISTING `continuousAnimationGate` precedent: injected once at the `LivebuyPlayer` overlay root
// (`LivebuyPlayer.swift`), consumed here.

private struct ShowSubscribeKey: EnvironmentKey {
    /// `true` for every construction path OTHER than `LivebuyPlayer` (direct `PlayerHeaderBarView`
    /// construction, `demo(...)`, every existing snapshot / unit test) — so nothing outside the
    /// drop-in container silently loses the badge. Only `LivebuyPlayer` explicitly injects its own
    /// (now `false`-by-default) `config.showSubscribe`.
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Host-configurable subscribe-badge visibility (`LivebuyPlayerConfig.showSubscribe`).
    /// `false` → `avatar` renders WITHOUT `subscribeBadge` at all (not merely hidden — the view is
    /// never constructed). Unset (constructed outside `LivebuyPlayer`) → `true`, byte-identical to
    /// this module's behavior before this change.
    var lbShowSubscribe: Bool {
        get { self[ShowSubscribeKey.self] }
        set { self[ShowSubscribeKey.self] = newValue }
    }
}

/// The family-1 top-bar chrome. Pinned to the top of the player shell; paints the
/// glassy host pill + round glass control cluster over a dark scrim gradient.
public struct PlayerHeaderBarView: View {
    /// Observed so a runtime language switch re-renders this view's localized copy
    /// (`rb-ios-i18n-string-table`; see `ReferenceUILanguage`).
    @ObservedObject var l10n = ReferenceUILanguage.shared

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
    /// false` (demo / snapshot) NEVER loads an image, so the baseline is stable
    /// without a network image; `live == true` (runtime) draws the REAL shop logo
    /// from this URL via the iOS-14-safe `RemoteStillImageView` when the value —
    /// TRIMMED — is non-empty and parseable.
    ///
    /// The deterministic monogram is NOT an either/or fallback: it is drawn
    /// UNCONDITIONALLY beneath the image, so it also covers the loading and failure
    /// windows of a real logo. See `avatar` for why that matters.
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

    /// Backend / merchant-driven marquee CAPABILITY gate (rb-ios-video-title-scroll).
    /// A by-value presentation flag fed from `PlayerShellModel.titleScroll` (sourced from
    /// `LivebuyPlayerConfig.titleScroll`, itself normalized by the host from the wire value
    /// `sdkConfig.extensions["video_title_scroll"]` via `LBVideoTitleScroll.normalized(_:)`).
    /// Default `true` — the backend's own default when the merchant never set it (`1`), and the
    /// behavior this module had before this flag existed, so every existing call site is unchanged.
    ///
    /// It answers「MAY the title scroll」; `marqueeTitleOverflows` answers「is there anything TO
    /// scroll」. They are ANDed in `showsMarqueeTitle` — this flag NEVER changes the measurement.
    ///
    /// ⚠️ `false` means "do not scroll", NOT "do not show". The backend contract
    /// (`openspec/specs/backend/sdk-config.md`, Requirement「`extensions` raw bag schema」) states
    /// it in so many words: `video_title_scroll` expresses HOW the title is presented and MUST NOT
    /// be read as a title-visibility switch. `false` keeps the very same single-line, tail-ellipsized
    /// `Text` (see `titleView`), so the title still occupies its row at exactly the same height.
    public let titleScroll: Bool

    /// Cold-start loading gate (rb-live-entry-viewer-count-loading-gate). Mirrors
    /// `PlayerShellModel.startPhase` (`LBStartScreenPhase`: `.loading` / `.splash` /
    /// `.buffering` / `.done`). While `startPhase == .loading` (the `/sdk/video`
    /// fetch has not yet resolved — SDK has not fired ANY momentState update yet)
    /// the viewer-count badge MUST NOT render, because `viewerCount` in that window
    /// has no real value to show and would otherwise fall back to the type default
    /// `0`, which a user cannot distinguish from "the real count is zero". See
    /// `showsViewerBadge` for the single decision point.
    ///
    /// Default `.done` (the value furthest from `.loading` in the phase's lifecycle)
    /// keeps every existing call site — including `demo(...)` and every existing
    /// snapshot / unit test that does not pass this parameter — byte-identical.
    public let startPhase: LBStartScreenPhase

    /// 「乾淨模式」(rb-ios-gesture-clean-mode-rewrite, design R23, ADDED Requirement
    /// "LivebuyReferenceUI PlayerShellView 長按切換「乾淨模式」隱藏懸浮 chrome"). `true` hides
    /// `hostPill` (which on iOS bundles BOTH the design's separately-toggled `LBPTopBar`
    /// "logo" and `LBPHostBadge` "host badge" into one leading-edge block — see this file's
    /// header comment) while KEEPING `iconCluster` (the trailing-edge minimize button)
    /// unconditionally visible, matching the spec's "MUST 保留頂欄唯一的 minimize(PIP) 按鈕"
    /// requirement. Default `false` keeps every existing call site byte-identical.
    public let cleanMode: Bool

    /// Current mute state (`PlayerShellModel.muted`) — selects the clean-mode-only
    /// mute-toggle button's glyph (`rb-ios-gesture-clean-mode-v2`, design R29). Only meaningful while
    /// `onToggleMute` is non-nil (i.e. `cleanMode == true`); ignored (and the button not
    /// drawn at all) otherwise. Default `false` keeps every existing call site byte-identical.
    public let muted: Bool

    /// Top-right button icon/behavior-label mode (`rb-ios-player-direct-close-button`). A
    /// by-value PRESENTATION flag — this view does NOT know `LivebuySDK.enableDirectCloseButton`
    /// exists; it only draws what it is told, exactly like `isReplay` / `cleanMode` above. Source
    /// is `PlayerShellModel.showCloseIcon`, itself resolved from `LivebuyPlayerConfig
    /// .enableDirectCloseButton ?? Livebuy.shared?.enableDirectCloseButton` by
    /// `LivebuyPlayer.buildModels()` (see `resolvedEnableDirectCloseButton(configValue:
    /// globalValue:)` in `LivebuyPlayerPresenter.swift`).
    ///
    /// - `false` (default) → the button draws `PipGlyph` ("縮小" / minimize), byte-identical to
    ///   every existing call site.
    /// - `true` → the button draws SF Symbol `xmark` ("關閉" / close) instead. The `onMinimize`
    ///   callback's TRIGGER TIMING (tap → call it) is completely unchanged by this flag — only
    ///   the icon + accessibility label change here; WHAT `onMinimize` actually does (collapse to
    ///   floating vs. dismiss outright) is entirely the caller's decision
    ///   (`LivebuyPlayerPresenter.composedConfig`).
    public let showCloseIcon: Bool

    // -- Optional action closures (LAST, each defaulting to nil) ----------------
    //
    // The header's top-right holds the minimize affordance (design `LBPTopBar` pip:
    // tap → `onMinimize`, host collapses into the bottom-right floating widget) and, ONLY
    // during `cleanMode` (`rb-ios-gesture-clean-mode-v2`, design R29), a mute-toggle button
    // immediately to its left — the single-tap-on-video-area mute gesture retired when R29
    // made every short tap toggle `cleanMode` instead, so this button restores the muting
    // affordance while clean mode hides the rest of the chrome. Subscribe stays on the
    // avatar badge. info / share live in the side rail.

    /// Tap on the top-right minimize button → host collapses the player into the
    /// bottom-right floating preview (`FloatingWidgetView`). nil → drawn but inert.
    public var onMinimize: (() -> Void)?
    /// Tap on the subscribe affordance (the small badge on the avatar).
    public var onSubscribe: (() -> Void)?

    /// Tap on the clean-mode mute-toggle button (`rb-ios-gesture-clean-mode-v2`, design
    /// R29). `PlayerShellView` passes a non-nil closure ONLY while `cleanMode == true`
    /// (forwarding to the same host-wired mute path the retired video-area tap gesture
    /// used); `nil` (default, and whenever `cleanMode == false`) → the button is NOT drawn
    /// at all (not merely hidden — see `iconCluster`), so non-clean-mode baselines stay
    /// byte-identical.
    public var onToggleMute: (() -> Void)?

    /// Host-configurable subscribe-badge visibility (rb-ios-subscribe-favorite-visibility-toggle).
    /// See the `ShowSubscribeKey` / `EnvironmentValues.lbShowSubscribe` doc comments above for why
    /// this arrives via Environment rather than an init parameter.
    @Environment(\.lbShowSubscribe) private var showSubscribe
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
        titleScroll: Bool = true,
        startPhase: LBStartScreenPhase = .done,
        cleanMode: Bool = false,
        muted: Bool = false,
        showCloseIcon: Bool = false,
        onMinimize: (() -> Void)? = nil,
        onSubscribe: (() -> Void)? = nil,
        onTapHostBadge: (() -> Void)? = nil,
        onToggleMute: (() -> Void)? = nil
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
        self.titleScroll = titleScroll
        self.startPhase = startPhase
        self.cleanMode = cleanMode
        self.muted = muted
        self.showCloseIcon = showCloseIcon
        self.onMinimize = onMinimize
        self.onSubscribe = onSubscribe
        self.onTapHostBadge = onTapHostBadge
        self.onToggleMute = onToggleMute
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
                headerLeadingSlot
                iconCluster
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 14)

            Spacer(minLength: 0)
        }
        // rb-ios-live-chrome-gradient-removal: design dropped `LBPTopBar`'s visible
        // `linear-gradient(to bottom, rgba(0,0,0,0.55), transparent)` scrim (2026-08-31) — this
        // is NOT swapped for that gradient, but for a solid, VISUALLY-IMPERCEPTIBLE backing
        // (`0.01` alpha, ~2.5/255 — far below the human eye's just-noticeable-difference
        // threshold for overlay alpha, i.e. indistinguishable from "no background" to any
        // viewer). A fully `Color.clear` / genuinely-absent background was tried FIRST and
        // empirically found (bisection, `rb-ios-live-chrome-gradient-removal` design.md) to
        // break `VideoTitleScrollTests.testPlayerShellView_handsTitleScrollToTheHeader`: when
        // this background's alpha rounds to EXACTLY 0/255 in the 8-bit channel (true for
        // `Color.clear` and for any `opacity()` below ~1/255 ≈ 0.0039), `ImageRenderer`'s
        // synchronous capture of the nested `titleView`'s `.overlay(GeometryReader { ... })`
        // marquee-overflow measurement (see that property's doc comment) silently misbehaves
        // when composited inside the FULL `PlayerShellView` tree specifically (the isolated
        // `PlayerHeaderBarView`-only render is unaffected) — both `titleScroll` states end up
        // byte-identical. Any alpha ≥ 1/255 (confirmed by binary search: `0.004` passes,
        // `0.001` fails) avoids it entirely, with zero visible difference from `Color.clear`.
        // This is a workaround for that specific `ImageRenderer` behavior, not a real
        // background — MUST NOT be restyled into anything visible.
        .background(
            Color.black.opacity(0.01)
                .allowsHitTesting(false)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(LBAccessibilityID.playerHeader)
    }

    // MARK: - Leading slot (host pill vs. cleanMode Spacer) — rb-ios-player-header-title-flex-width
    //
    // Extracted from `body`'s inline `if !cleanMode { Button(...) }` + the `Spacer(minLength: 8)`
    // that used to sit unconditionally next to it, mirroring this file's own established
    // extraction precedent (`LiveBottomBarView.trailingAction` / `trailingActionForTesting`,
    // `rb-ios-live-bottom-bar-cc-icon-align`) so `headerLeadingSlotForTesting` can expose the EXACT
    // SAME subtree `body` renders for structural assertions — not a parallel copy.

    /// The leading slot of the top-bar `HStack` (rb-ios-player-header-title-flex-width): the
    /// tappable, WIDTH-CLAIMING host pill in the normal (`!cleanMode`) case, or a plain
    /// `Spacer(minLength: 8)` fallback in `cleanMode` (host pill hidden entirely, per the
    /// `rb-ios-gesture-clean-mode-rewrite` "MUST 保留頂欄唯一的 minimize(PIP) 按鈕" requirement —
    /// `iconCluster` stays unconditionally visible regardless of which branch this resolves to).
    ///
    /// `.frame(maxWidth: .infinity, alignment: .leading)` on the `!cleanMode` branch's `Button`
    /// makes THIS FRAME (not `hostPill`'s own content) claim ALL the leading space the outer
    /// `HStack`'s negotiation has to give — mirroring the design's `LBPHostBadge` container
    /// (`left: 14, right: 64`, its title/host column `flex: '1 1 auto'`). `hostPill`'s actual
    /// drawn content still hugs the LEADING edge (`alignment: .leading`) — this claims WIDTH, it
    /// does not paint new pixels, so a short / non-overflowing title's rendered pixels are
    /// unchanged. What DOES change: (a) the tappable area now spans the full claimed width
    /// instead of just the pill's own content, and (b) `titleView`'s `.overlay(GeometryReader {
    /// ... })` measurement (see that property's doc comment) is proposed the REAL available width
    /// instead of `hostPill`'s previous (too-narrow, content-hugging) width — a wider, more
    /// accurate `containerWidth` is the INTENDED effect of this change, not a side effect to
    /// guard against; `marqueeTitleOverflows` / `showsMarqueeTitle`'s own formulas are unchanged.
    ///
    /// Deliberately NOT paired with a separate `Spacer(minLength: 8)` sibling in the SAME branch:
    /// two siblings that are BOTH maximally width-flexible (a `.frame(maxWidth: .infinity)` view
    /// AND a bare `Spacer`) tie in the `HStack`'s space-negotiation and split the remaining width
    /// evenly between them (see this change's `design.md` for the empirical basis) — which would
    /// leave the host pill claiming only HALF the available leading space, not nearly all of it.
    /// The outer `HStack`'s own `spacing: 8` already guarantees the minimum gap to `iconCluster`,
    /// so no separate `Spacer` is needed in this branch.
    ///
    /// The `cleanMode` branch is the SAME `Spacer(minLength: 8)` this file used unconditionally
    /// before this change — byte-identical `cleanMode` behavior (the `HStack` reduces to exactly
    /// `[Spacer, iconCluster]` either way, so `iconCluster` still gets pushed fully to the
    /// trailing edge).
    private var headerLeadingSlot: some View {
        Group {
            if !cleanMode {
                Button(action: { onTapHostBadge?() }) { hostPill }
                    .buttonStyle(PlainButtonStyle())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier(LBAccessibilityID.playerHeaderHostPill)
            } else {
                Spacer(minLength: 8)
            }
        }
    }

    /// Test-only hook exposing the SAME `headerLeadingSlot` subtree `body` renders, so unit tests
    /// (rb-ios-player-header-title-flex-width) can make STRUCTURAL assertions confirming the
    /// width-claiming `.frame(maxWidth: .infinity)` modifier is actually attached to the
    /// `!cleanMode` branch's `Button`, and that the `cleanMode` branch is still a plain `Spacer`.
    /// Follows the established `hostPillForTesting` / `iconClusterForTesting` precedent.
    ///
    /// MUST NOT be called from production code (it is on no `body` path, so it costs zero pixels),
    /// and MUST keep returning the very same `headerLeadingSlot` — never a parallel copy, which
    /// would decouple the structural assertions from what is actually drawn.
    var headerLeadingSlotForTesting: some View { headerLeadingSlot }

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
                                                 hostShowViewerCount: showViewerCount,
                                                 startPhase: startPhase) {
                            viewerBadge
                        }
                    }
                }
            }
        }
        .padding(.leading, 4)
        .padding(.trailing, 12)
        .padding(.vertical, 4)
        // rb-ios-player-header-viewer-pill: the host pill NO LONGER paints a shared
        // `pillGlass` background — only `viewerBadge` does (see its own `.background`
        // below). Parity `LBPHostBadge` (`sdk-components.jsx:355-458`), which has NO
        // outer background container at all; its text contrast comes from `textShadow`
        // alone. ⚠️ KNOWN GAP (not fixed by this change, flagged intentionally): this
        // module has ZERO `.shadow(...)` on `titleView` / hostName `Text` — unlike the
        // design's `textShadow`, so this SwiftUI tree has NO independent legibility
        // mechanism for those two texts once this background is gone. Left for a
        // follow-up change; MUST NOT be "fixed" here by re-adding a background (that
        // would defeat the point of this change).
    }

    /// Test-only hook exposing the SAME `hostPill` subtree `body` renders, so unit tests
    /// (rb-ios-player-header-viewer-pill) can make STRUCTURAL assertions confirming the
    /// outer `hostPill` container itself no longer carries a `Capsule` background — only
    /// its `viewerBadge` child does (see `viewerBadgeForTesting`). Follows the established
    /// `avatarForTesting` / `titleViewForTesting` precedent.
    ///
    /// MUST NOT be called from production code (it is on no `body` path, so it costs zero
    /// pixels), and MUST keep returning the very same `hostPill` — never a parallel copy.
    var hostPillForTesting: some View { hostPill }

    // MARK: - Title (LBPMarqueeText) — rb-ios-marquee-title-scroll / rb-ios-video-title-scroll
    //
    // Parity `design/templates/minimal/sdk-components.jsx`'s `LBPMarqueeText` and the
    // already-shipped Android port. Closes a documented design/implementation gap: the
    // title used to always truncate with an ellipsis; it now marquee-scrolls when it
    // overflows AND the backend/merchant setting allows scrolling
    // (`titleScroll`, rb-ios-video-title-scroll — design `LBPHostBadge`'s `titleScroll` prop).

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
    /// The OVERFLOW decision stays purely content-driven — no caller preference can stand in for
    /// the measurement. On top of it sits ONE backend/merchant capability gate, `titleScroll`
    /// (rb-ios-video-title-scroll); the two are ANDed in the single pure entry point
    /// `showsMarqueeTitle(titleScroll:textWidth:containerWidth:)`, which is the ONLY thing that
    /// decides whether the overlay paints.
    ///
    /// WHY `titleScroll == false` CANNOT CHANGE THE LINE HEIGHT (structural, not tuned):
    /// disabling the marquee means the `.overlay` is simply not attached. The
    /// layout-participating view — the `Text` below — is byte-identical in BOTH states (same font,
    /// same `lineLimit(1)`, no `.frame`), and overlay content is layout-inert to its ancestors. So
    /// the title row's height, and therefore the host-name / LIVE-pill row beneath it, cannot move.
    /// This mirrors the design's own note on `LBPHostBadge`'s non-scrolling branch (「字級 / 行高 /
    /// maxWidth 與 marquee 分支完全一致，單行高度不變」) — but here it is guaranteed by sharing the
    /// one `Text` rather than by keeping two branches' numbers in agreement.
    ///
    /// MUST NOT be "fixed" by adding a parallel static branch (`if titleScroll { … } else { Text(…) }`):
    /// two copies drift, and that downgrades the equal-height guarantee from a structural fact to a
    /// coincidence. `Text(...).lineLimit(1)` already IS the design's non-scrolling branch (nowrap +
    /// overflow hidden + tail ellipsis).
    ///
    /// ⚠️ VISIBILITY vs. LAYOUT are two different roles (`rb-ios-marquee-title-overlay-fix`). The
    /// `Text` below still owns the LAYOUT role above — same font / `lineLimit(1)` / no `.frame`,
    /// still what the surrounding `HStack`/`VStack` measures and squeezes. But it MUST NOT also be
    /// assumed to be the ONE visible copy: `.overlay()` only ever PAINTS ON TOP, it never hides
    /// what is underneath. The base `Text` here therefore carries `.opacity(0)` — a pure paint-time
    /// no-op that does NOT change its intrinsic size (SwiftUI opacity never affects layout), so
    /// every guarantee above still holds — and the actually-visible content is decided exclusively
    /// inside the `.overlay(GeometryReader { ... })`'s `Group { if/else }`: the marquee when
    /// `showsMarqueeTitle` holds, or a plain visible `Text` sharing the SAME `font` / `title` /
    /// `.lineLimit(1)` locals otherwise. Exactly one of those two branches is ever instantiated by
    /// Swift's own `if/else` semantics (compiled to `_ConditionalContent<Marquee, Text>`, whose
    /// storage is an enum of the two cases — never both at once), so at any instant there is
    /// exactly one PAINTED title: the invisible ghost contributes zero pixels, and whichever
    /// branch the `Group` picked contributes the only visible one. Before this change, the base
    /// `Text` was ALSO the visible layer, so once `MarqueeTitleLoopView.startScroll()` actually
    /// animated the overlay's offset (`.onAppear`, which `ImageRenderer` never fires — see that
    /// view's own doc comment — so no snapshot ever caught this), the static base and the moving
    /// overlay visibly diverged into overlapping/ghosting text. See `VideoTitleScrollTests` for what
    /// automated coverage can and cannot see here (structural
    /// assertions on the ghost's opacity + this file's `Group` shape; NOT the mid-animation frame
    /// itself, which remains a documented `ImageRenderer` blind spot).
    private var titleView: some View {
        let font = Font.system(size: 12 * theme.fontScale, weight: .bold)
        let textWidth = Self.marqueeIntrinsicTextWidth(title, fontSize: 12 * theme.fontScale)
        return Text(title)
            .font(font)
            .lineLimit(1)
            .opacity(0) // layout ghost only — reserves height/squeeze, paints nothing (see above)
            .overlay(
                GeometryReader { proxy in
                    let containerWidth = proxy.size.width
                    Group {
                        if Self.showsMarqueeTitle(titleScroll: titleScroll,
                                                  textWidth: textWidth,
                                                  containerWidth: containerWidth) {
                            MarqueeTitleLoopView(
                                title: title,
                                font: font,
                                color: onGlass,
                                textWidth: textWidth,
                                containerWidth: containerWidth,
                                gap: Self.marqueeGap,
                                durationSeconds: Self.marqueeDurationSeconds(textWidth: textWidth)
                            )
                        } else {
                            // The ONLY visible content when not scrolling — same font/title/
                            // lineLimit locals as the ghost above, so it is pixel-identical to
                            // what the ghost used to paint on its own before this change.
                            Text(title)
                                .font(font)
                                .foregroundColor(onGlass)
                                .lineLimit(1)
                        }
                    }
                },
                alignment: .leading
            )
    }

    /// Test-only hook exposing the SAME `titleView` subtree `body` renders, so unit tests can
    /// measure the title slot's INTRINSIC HEIGHT in both `titleScroll` states and compare two
    /// in-process renders of it (rb-ios-video-title-scroll). Follows the established
    /// `avatarForTesting` precedent.
    ///
    /// MUST NOT be called from production code (it is on no `body` path, so it costs zero pixels),
    /// and MUST keep returning the very same `titleView` — never a parallel copy, which would
    /// decouple the equal-height assertion from what is actually drawn.
    var titleViewForTesting: some View { titleView }

    /// Avatar — a white-backed 28×28 circle. The design fills it with the shop
    /// mark. `live`-gated (same convention as `CarouselCardView`): at runtime
    /// (`live == true`) with a parseable `shopLogo` we draw the REAL shop logo via the
    /// iOS-14-safe `RemoteStillImageView` (no `AsyncImage`), clipped to the circle.
    ///
    /// The gate is a SINGLE predicate — `resolvedShopLogoURL(live:urlString:)`. The
    /// condition below MUST stay expressed as that function's return value (see its
    /// doc comment for why); there is deliberately no second decision point, and the
    /// draw site MUST NOT trim / re-test anything itself.
    ///
    /// STACKED, never `if / else` (header-shop-logo-gate-trim-parity-refui) — the same
    /// shape as the sibling `VideoInfoPanelView.shopRow` and as all three other
    /// platforms. Three layers, bottom to top:
    ///
    ///   1. `Circle().fill(.white)` — backing. Keeps a non-square mark on a clean field
    ///      and gives the accent-tinted monogram the light background it needs. It is
    ///      NOT redundant: drop it and the monogram would sit straight on the video.
    ///   2. the monogram (first letter of host name) — drawn UNCONDITIONALLY, in EVERY
    ///      gate state including while the real logo is on screen.
    ///   3. the real logo — drawn only when the gate resolves, via an `if let` with NO
    ///      `else` (ViewBuilder compiles that to an `Optional`, which occupies nothing
    ///      when nil).
    ///
    /// Why the monogram must be permanent rather than an `else` branch:
    /// `RemoteStillImageView` paints NO pixels while the image is still downloading (its
    /// coordinator sets `imageView.image = nil` the moment a load starts, so a recycled
    /// cell cannot flash the previous image) and NONE at all when the load fails (the
    /// completion handler simply returns). An `else`-only monogram is therefore skipped
    /// for the WHOLE duration of every normal load — the user stared at a blank white
    /// circle with not even the shop's initial on it, on every single open. Stacking
    /// makes the monogram cover the loading state AND the failure state for free, which
    /// is why this needs no spinner, no error UI and no extra placeholder asset.
    ///
    /// Accepted trade-off: a logo with an alpha channel lets the monogram show through
    /// underneath. Hiding it once the bitmap decodes would require `RemoteStillImageView`
    /// to report load state — a primitive-level change affecting every call site (widget
    /// carousel, product thumbs, upcoming background) and all four platforms. Shop marks
    /// are overwhelmingly opaque, and this trades a rare small blemish for a frequent
    /// large one. If it ever becomes a real complaint it is its own four-platform change.
    private var avatar: some View {
        ZStack {
            Circle().fill(Color.white)
            // Permanent monogram backing: snapshot / demo (`live == false`), no logo,
            // unparseable URL, AND the loading / failure window of a real logo.
            Text(monogram)
                .font(.system(size: 13 * theme.fontScale, weight: .bold))
                .foregroundColor(theme.accent)
            if let url = Self.resolvedShopLogoURL(live: live, urlString: shopLogo) {
                // REAL shop logo over the monogram, filling and clipped to the
                // circle (square-ish marks fill cleanly; non-square get center-cropped).
                RemoteStillImageView(url: url, contentMode: .scaleAspectFill)
                    .clipShape(Circle())
            }
        }
        .frame(width: 28, height: 28)
        // Subscribe badge sits at the bottom-trailing of the avatar (all layers). Gated by
        // `showSubscribe` (rb-ios-subscribe-favorite-visibility-toggle): `false` → NOT
        // constructed at all (the `if` branch inside `Group` occupies nothing when absent), not
        // merely visually hidden. `Group { if ... }` (not the iOS-15-only
        // `.overlay(alignment:content:)` trailing-closure form) keeps this iOS-14-safe, matching
        // this file's own D-7 constraint.
        .overlay(
            Group { if showSubscribe { subscribeBadge } },
            alignment: .bottomTrailing
        )
    }

    /// Test-only hook exposing the SAME `avatar` subtree `body` renders, so unit tests can
    /// make STRUCTURAL assertions on it (does a `RemoteStillImageView` node exist, and does
    /// it carry the expected URL). This closes the gap the pure-function tests cannot reach:
    /// `resolvedShopLogoURL` staying perfectly correct while `avatar` was never wired to
    /// `shopLogo` at all — feed it a literal `""` or delete the branch outright and every
    /// pure-function test still passes while the logo silently disappears forever.
    ///
    /// MUST NOT be called from production code (it is on no `body` path, so it costs zero
    /// pixels), and MUST keep returning the very same `avatar` — never a parallel copy, which
    /// would decouple the assertion target from what is actually drawn.
    var avatarForTesting: some View { avatar }

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
    ///
    /// rb-ios-player-header-viewer-pill: carries its OWN `pillGlass` glass-pill
    /// background (`Capsule`, same color token as the now-removed `hostPill` outer
    /// background — no new color value). Small internal padding keeps the icon /
    /// text off the capsule edge; this is purely a local detail of this view and
    /// does not affect `hostPill`'s outer `HStack` negotiation (`viewerBadge` is
    /// already `.fixedSize`).
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
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(pillGlass))
        .fixedSize(horizontal: true, vertical: false)
    }

    /// Test-only hook exposing the SAME `viewerBadge` subtree `body` renders, so unit tests
    /// (rb-ios-player-header-viewer-pill) can make STRUCTURAL assertions confirming it carries
    /// the `Capsule` `pillGlass` background. Follows the established `avatarForTesting` /
    /// `titleViewForTesting` precedent.
    ///
    /// MUST NOT be called from production code (it is on no `body` path, so it costs zero
    /// pixels), and MUST keep returning the very same `viewerBadge` — never a parallel copy.
    var viewerBadgeForTesting: some View { viewerBadge }

    // MARK: - Trailing control — SINGLE minimize/close button (LBPTopBar pip affordance)
    //
    // The top-right contains ONLY a minimize/close control (design `LBPTopBar` pip; user
    // requirement「右上角只有縮小的元件」). By default (`showCloseIcon == false`) tapping it
    // collapses the player into the bottom-right floating preview (host-owned, reusing
    // `FloatingWidgetView`). When `showCloseIcon == true` (`rb-ios-player-direct-close-button`)
    // the icon swaps to `xmark` and the caller (`LivebuyPlayerPresenter`) wires the SAME tap to a
    // direct dismiss instead — this view never decides which; it only draws what it is told. info /
    // share live in the side rail; mute is the tap-to-unmute gesture on the video area.

    /// Minimize (PIP) glyph base size in points, before `theme.fontScale` (design
    /// `Icons.pip size={20}`, `design/templates/minimal/sdk-components.jsx:273`).
    /// Extracted as a `static let` (mirroring this file's `marqueeSpeedPointsPerSecond` /
    /// `marqueeGap` pattern) so it is directly unit-testable without rendering
    /// (`rb-ios-player-chrome-icon-and-overlay-visibility-fixes`). `rb-ios-icon-parity`
    /// aligned this glyph's SHAPE only (hand-drawn `PipGlyph` replacing SF Symbol
    /// `pip.enter`) and left the SIZE at a stale `16pt` — the same class of gap
    /// `rb-ios-bag-icon-enlarge` already fixed once for the bag glyph.
    /// `rb-ios-player-chrome-icon-and-overlay-visibility-fixes` aligned it to `18pt`;
    /// `player-header-minimize-icon-20px-ios` re-aligns it to `20pt` after the design
    /// itself was re-approved from 18 to 20 (commit `ae8b1b2e`).
    static let minimizeGlyphSize: CGFloat = 20

    /// SF Symbol `xmark` glyph size in points for the top-right button's CLOSE mode
    /// (`showCloseIcon == true`, `rb-ios-player-direct-close-button`). No `theme.fontScale`
    /// multiplication — matches this exact 36×36-button cluster's sibling `muteToggleButton`
    /// SF Symbol precedent below (`.font(.system(size: 15, weight: .semibold))`), the closest
    /// existing "SF Symbol inside this file's 36×36 glass icon button" reference point, chosen
    /// over `FloatingWidgetView.closeButton`'s `12pt`/28×28 ratio because that button is a
    /// DIFFERENT (smaller) size class.
    static let closeGlyphSize: CGFloat = 15

    /// Pure derivation of the top-right button's accessibility label from `showCloseIcon`
    /// (`rb-ios-player-direct-close-button`). A `static func` (no instance needed) so the render
    /// site and a unit test share exactly one source — mirrors this file's other pure `static
    /// func` helpers (`showsViewerBadge` / `formatViewerCount` / …).
    static func minimizeButtonAccessibilityLabel(showCloseIcon: Bool) -> String {
        ReferenceUIStrings.text(showCloseIcon ? "player_close_a11y" : "player_minimize_a11y")
    }

    /// A 36×36 round glass icon button (live-chrome.jsx iconBtn) drawing either the
    /// hand-drawn `PipGlyph` (design `Icons.pip` — frame + inset rect + directional
    /// arrow, rb-ios-icon-parity; replaces SF Symbol `pip.enter`) or, when `showCloseIcon`
    /// is `true` (`rb-ios-player-direct-close-button`), SF Symbol `xmark`. Inert when
    /// `onMinimize` is nil — still rendered so the chrome is visually complete. The TAP
    /// still calls the very same `onMinimize` closure in both icon states — only the icon
    /// + accessibility label are gated on `showCloseIcon`; WHAT the tap actually does is
    /// entirely the caller's decision (`LivebuyPlayerPresenter.composedConfig`), not this view's.
    ///
    /// Immediately to its LEADING side, a clean-mode-only mute-toggle button
    /// (`rb-ios-gesture-clean-mode-v2`, design R29) draws ONLY when `onToggleMute` is
    /// non-nil (i.e. `PlayerShellView` is in `cleanMode`) — see `muteToggleButton`. Group,
    /// not HStack: `Group { if ... }` keeps this iOS-14-safe (D-7) and lets the mute button
    /// occupy zero space (not merely zero pixels) when absent, so a non-clean-mode
    /// `iconCluster` renders byte-identical to before this change.
    private var iconCluster: some View {
        HStack(spacing: 8) {
            Group {
                if onToggleMute != nil {
                    muteToggleButton
                }
            }
            Button(action: { onMinimize?() }) {
                Group {
                    if showCloseIcon {
                        Image(systemName: "xmark")
                            .font(.system(size: Self.closeGlyphSize, weight: .semibold))
                            .foregroundColor(onGlass)
                    } else {
                        PipGlyph(size: Self.minimizeGlyphSize * theme.fontScale, color: onGlass)
                    }
                }
                .frame(width: 36, height: 36)
                .background(Circle().fill(iconGlass))
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityIdentifier(LBAccessibilityID.playerMinimize)
            .accessibilityLabel(Self.minimizeButtonAccessibilityLabel(showCloseIcon: showCloseIcon))
        }
    }

    /// Test-only hook exposing the SAME `iconCluster` subtree `body` renders, so unit tests
    /// (rb-ios-player-direct-close-button) can make STRUCTURAL assertions confirming which
    /// glyph is actually drawn for a given `showCloseIcon` value. Follows the established
    /// `hostPillForTesting` / `viewerBadgeForTesting` / `avatarForTesting` precedent.
    ///
    /// MUST NOT be called from production code (it is on no `body` path, so it costs zero
    /// pixels), and MUST keep returning the very same `iconCluster` — never a parallel copy.
    var iconClusterForTesting: some View { iconCluster }

    /// The clean-mode-only mute-toggle button (`rb-ios-gesture-clean-mode-v2`, design R29):
    /// a 36×36 round glass icon button matching `iconCluster`'s minimize button styling,
    /// restoring the mute affordance the retired single-tap-on-video-area gesture used to
    /// carry once R29 made every short tap toggle `cleanMode` instead. Glyph mirrors
    /// `GestureMuteToastView`'s existing SF Symbol convention (`speaker.slash.fill` muted /
    /// `speaker.wave.2.fill` unmuted).
    private var muteToggleButton: some View {
        Button(action: { onToggleMute?() }) {
            Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(onGlass)
                .frame(width: 36, height: 36)
                .background(Circle().fill(iconGlass))
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier(LBAccessibilityID.playerHeaderMuteButton)
    }

    // MARK: - Pure helpers

    /// The avatar's real-shop-logo gate — the SINGLE predicate deciding whether the
    /// remote image is drawn at all, and which URL it gets. Pure / deterministic: no
    /// rendering, no IO, directly unit-testable (`docs/unit-test-discipline.md`).
    ///
    /// Degradation ladder — VERBATIM IDENTICAL to its sibling
    /// `VideoInfoPanelView.resolvedShopLogoURL(live:urlString:)`, down to the CharacterSet:
    ///   1. `live == false`         → nil. Demo / snapshot / preview / non-runtime paths
    ///                                NEVER load an image, so baselines stay deterministic.
    ///                                Short-circuits BEFORE the trim and `URL(string:)`.
    ///   2. trim `.whitespacesAndNewlines`; EMPTY after trimming → nil. No logo (or nothing
    ///      but blanks) → the monogram IS the answer.
    ///   3. otherwise               → `URL(string:)` on the TRIMMED string; unparseable → nil
    ///                                (no crash, no force-unwrap).
    ///
    /// The trim is load-bearing, not tidiness (header-shop-logo-gate-trim-parity-refui).
    /// `URL(string:)` does NOT reject blanks — measured: `URL(string: "   ")` yields a
    /// non-nil `%20%20%20`, and `URL(string: "\t\n ")` yields `%09%0A%20`. Untrimmed, a
    /// whitespace-only `shopLogo` sailed through this gate into the image branch, where that
    /// junk relative URL could only ever fail to load. Conversely `URL(string:)` DOES reject
    /// a padded real URL (`"  https://…  "` → nil), so an untrimmed gate threw away logos
    /// that were perfectly loadable. Both are fixed by trimming once, here.
    ///
    /// This function and `VideoInfoPanelView`'s MUST agree on every input. That equivalence
    /// is pinned by `PlayerHeaderBarShopLogoTests.testResolvedShopLogoURL_matchesVideoInfoPanelForEveryInput`,
    /// so either side drifting again turns that test red. (The two DID diverge until this
    /// change; the earlier test pinning the divergence was rewritten into that equivalence
    /// pin rather than deleted.) Note step 3 still resolves a scheme-less bare string such as
    /// `"BeautyTown"` into a non-nil RELATIVE URL — trimming does not change that, and the
    /// "wired to the wrong non-empty field" counterproof depends on it staying so.
    ///
    /// STRUCTURAL COUPLING (do not undo): `avatar`'s condition MUST be expressed as
    /// `if let url = Self.resolvedShopLogoURL(live: live, urlString: shopLogo)`. It MUST NOT
    /// re-derive an equivalent check inline nor trim again at the draw site, and no second
    /// decision point may exist (the old `logoURL` property was removed for exactly this
    /// reason). Once the verdict and the drawing each own a copy of the logic they eventually
    /// diverge, and unit tests of this function would then prove nothing about what is
    /// actually drawn.
    ///
    /// ⚠️ `live` here is the live-RUNTIME IMAGE gate, not the LIVE broadcast state
    /// (`isLive`) — see the `live` property's doc comment. Note the trap: the `demo(live:)`
    /// helper's `live:` argument means `isLive`, NOT this gate.
    static func resolvedShopLogoURL(live: Bool, urlString: String) -> URL? {
        guard live else { return nil }
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }

    /// Viewer-count badge visibility gate (rb-ios-viewer-count-show-pv-num,
    /// rb-live-entry-viewer-count-loading-gate). Pure / deterministic truth table —
    /// extracted so the gate is unit-testable without rendering. The viewer count
    /// draws ⟺ ALL FOUR hold:
    ///   - `isLive` — live-chrome family (true live OR finished-live replay; VOD shows none).
    ///   - `viewerCountVisible` — backend `channel.show_pv_num == 1` (mirrored from the
    ///     view-model `DefaultPlayerHeaderState.viewerCountVisible`). Replay reuses the LIVE
    ///     chrome so it honours the original live-time setting.
    ///   - `hostShowViewerCount` — host config `LivebuyPlayerConfig.showViewerCount` (default
    ///     true); a host may force-hide regardless of the backend flag.
    ///   - `startPhase != .loading` — NOT in the cold-start window (`/sdk/video` fetch still
    ///     in flight, SDK has not fired any momentState update yet). `viewerCount` has no real
    ///     value there and would otherwise fall back to the type default `0`, which a user
    ///     cannot distinguish from "the real count is zero" (rb-live-entry-viewer-count-loading-gate).
    /// Any one being `false` hides the badge; the LIVE pill is unaffected (separate gate).
    /// `startPhase` defaults to `.done` so every existing 3-argument call site (incl. every
    /// existing test) keeps its byte-identical behavior.
    static func showsViewerBadge(isLive: Bool,
                                 viewerCountVisible: Bool,
                                 hostShowViewerCount: Bool,
                                 startPhase: LBStartScreenPhase = .done) -> Bool {
        isLive && viewerCountVisible && hostShowViewerCount && startPhase != .loading
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
    ///
    /// This answers「is there anything TO scroll」ONLY. It is 100% content-driven and MUST stay
    /// that way: no caller preference may stand in for this measurement. Whether the marquee is
    /// actually attached is `showsMarqueeTitle`, which ANDs this with the `titleScroll` capability
    /// gate. `titleView` MUST call `showsMarqueeTitle`, never this function directly.
    static func marqueeTitleOverflows(textWidth: CGFloat, containerWidth: CGFloat) -> Bool {
        textWidth > containerWidth
    }

    /// THE single decision for whether the marquee overlay is attached (rb-ios-video-title-scroll).
    /// Pure / deterministic. Two orthogonal questions, ANDed — and they MUST NOT be allowed to
    /// substitute for one another:
    ///
    ///   - `titleScroll` — MAY it scroll? A backend / merchant capability gate, sourced from
    ///     `extensions.video_title_scroll` (design `LBPHostBadge`'s `titleScroll` prop). This is
    ///     NOT a caller preference knob, and it MUST NOT influence the measurement below.
    ///   - `marqueeTitleOverflows` — is there anything TO scroll? Content measurement, automatic.
    ///
    /// `titleScroll == false` therefore means「single-line, tail-ellipsized, no scrolling」— NOT
    ///「hidden」: the caller keeps rendering the same `Text`, at the same height (see `titleView`).
    static func showsMarqueeTitle(titleScroll: Bool,
                                  textWidth: CGFloat,
                                  containerWidth: CGFloat) -> Bool {
        titleScroll && marqueeTitleOverflows(textWidth: textWidth, containerWidth: containerWidth)
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
    /// hot, Reduce Motion off, on-screen). This is layered ON TOP of the existing attach gate
    /// (this view is only instantiated when `PlayerHeaderBarView.showsMarqueeTitle` holds — i.e.
    /// the title overflows AND `titleScroll` allows scrolling) — it does NOT change whether this
    /// view is built, only whether it scrolls. Defaults to neutral "animate" when unset.
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
    /// overflow branch in a snapshot. `titleScroll` defaults to `true` (the backend's own
    /// default and this module's pre-existing behavior), so every existing call site renders
    /// byte-identically; pass `false` (rb-ios-video-title-scroll) to exercise the
    /// merchant-disabled branch — the title then stays a single ellipsized line at the SAME
    /// height, it does NOT disappear.
    static func demo(theme: ReferenceUITheme = ReferenceUIThemePalette.minimal,
                     live: Bool = true,
                     replay: Bool = false,
                     title: String = "夏日彩妝特賣",
                     titleScroll: Bool = true,
                     startPhase: LBStartScreenPhase = .done,
                     showCloseIcon: Bool = false) -> PlayerHeaderBarView {
        PlayerHeaderBarView(
            theme: theme,
            title: title,
            hostName: "BeautyTown 官方",
            shopLogo: "",
            viewerCount: 12345,
            isSubscribed: false,
            isLive: live,
            isReplay: replay,
            titleScroll: titleScroll,
            startPhase: startPhase,
            showCloseIcon: showCloseIcon
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
