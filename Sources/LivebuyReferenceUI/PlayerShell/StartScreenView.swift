import SwiftUI
import LivebuySDK
import LivebuyUI

// MARK: - StartScreenView — family-1 player-shell START-LIFECYCLE surface
//
// Spec: `reference-ui-rendering/spec.md` (family-1 player-shell, start lifecycle).
// Design: rb-ios-moments design.md §1 (origin) + rb-ios-start-screen-out-of-moments
//         (decoupled from the moments family; bottom splash progress bar removed).
//   Design source: `design/templates/minimal/moments.jsx` start components (design re-sync
//   `LL9WzHAq`, which split the old `LBPStartScreen` into three): `LBPLoadingOverlay`
//   (`.loading`) / `LBPBufferingSpinner` (`.buffering`) / `LBPSkipIntroButton` (`.splash`).
//     This sub-view dispatches the same lifecycle by `phase`:
//      `loading` 全螢幕品牌載入 / `buffering` 內容上方輕量指示 / `splash` 開場影片播放 +
//      右下角略過介紹鈕 / `done` 不畫). Mirrors those components' rendered branches.
//
// OWNERSHIP: this is a family-1 (PLAYER-SHELL) start-lifecycle surface — it is NOT
// part of the moments family. `PlayerShellModel` mirrors `DefaultStartScreenState.phase`
// as `startPhase`; the container composes this sub-view (over the subject chrome) while
// `startPhase != .done`. It is NO LONGER rendered via `MomentsModel` /
// `MomentsOverlayView` (rb-ios-start-screen-out-of-moments).
//
// It follows the documented SUB-VIEW INPUT PATTERN EXACTLY:
//   1. `theme: ReferenceUITheme`            — FIRST positional argument, always.
//   2. the bound SNAPSHOT VALUE it renders  — `phase: LBStartScreenPhase`, the
//      read-only mirror of `DefaultStartScreenState.phase`, passed BY VALUE from
//      `PlayerShellModel.startPhase` (never the model, never the template).
//   3. one optional action closure, trailing, defaulting to `nil` (`onSkip`). The
//      container / host wires it to the core player exit (`skipStart()`); this
//      surface does NOT own the skip intent and renders correctly with it nil (so
//      demo / snapshot instances construct action-free).
//
// One-way data flow (只讀呈現): this view reads ONLY its passed-in `phase` — it never
// reaches back into any model / `DefaultPlayerTemplate`, never holds a second copy of
// the phase, and NEVER drives the skip itself. The splash skip pill shows a STATIC
// 「略過介紹」label (the design's `(N)` countdown is removed per product request — no
// timer / no number). The host wires `onSkip` to `skipStart()`; this layer only FORWARDS
// the CTA tap (design §1).
//
// Phase dispatch (design §1, mirrors the moments.jsx start components
// `LBPLoadingOverlay` / `LBPBufferingSpinner` / `LBPSkipIntroButton`):
//   • `.loading`   → full-bleed brand background + centered brand PNG-sequence
//                    animation ONLY. Design re-sync `c3c98733` REMOVED the wordmark
//                    (accent dot + "Livebuy") and the「載入中…」caption that used to
//                    sit below the spinner — `LBPLoadingOverlay` now renders just the
//                    mark (`rb-ios-loading-announce-restyle`).
//   • `.buffering` → renders NOTHING (`EmptyView`). The former central over-content
//                    spinner was removed (rb-ios-hide-start-buffering-spinner): a stalled
//                    engine keeps the phase at `.buffering`, which left the spinner stuck
//                    on screen. Initial-load feedback is the `.loading` brand loader.
//   • `.splash`    → the opening video plays through the NORMAL path with the family-1
//                    subject chrome (LIVE / VOD) visible; the ONLY added UI is a
//                    bottom-right「略過介紹」skip button (`onSkip`). NO 片頭 tag / muted
//                    indicator / brand backdrop / lower-third card (design
//                    `LBPSkipIntroButton`; 開場不接管畫面 + 開場影片有聲). **ADDED
//                    (rb-ios-clean-mode-upcoming-intro-coverage, functional extension — no
//                    design-canvas coverage, see that change's proposal.md「Why」)**: while
//                    `cleanMode == true` the skip button hides instead, and a FULLY
//                    INTERACTIVE expanded progress track shows in its place — see that MARK
//                    section below. **MODIFIED (rb-ios-intro-progress-bar-interactive)**: the
//                    original delivery was a hand-drawn, read-only, `.allowsHitTesting(false)`
//                    track (intro had no play/pause/seek routing in core at the time).
//                    `intro-player-seek-progress-core` has since wired
//                    `togglePlayPause()`/`seek(seconds:)`/`publishPlaybackProgress()` to the
//                    intro player, so this track is now a REAL `PlaybackProgressBarView`
//                    instance — pausable, playable, drag-to-seek, same as the VOD expanded
//                    transport bar.
//   • `.done`      → renders NOTHING (`EmptyView`).
//
// iOS-14-safe (design §"守住的不變式": iOS-14 樓地板): uses only `ZStack` / `VStack`
// / `HStack` / `Circle` / `Capsule` / `RoundedRectangle` / `LinearGradient` /
// `Image(systemName:)` / `Text` / `.rotationEffect` / `withAnimation` — all
// iOS-13+. The spinner uses the iOS-14-safe `Animation.repeatForever` rotation
// (a `Circle().trim` ring rotated forever — NOT `ProgressView(.circular)` styling
// nor any iOS-17 API). NO ScrollView / LazyVStack / LazyHStack / LazyVGrid (those
// render BLANK under `ImageRenderer` — the family-3 lesson); each branch is a plain
// `ZStack` / `VStack` / `HStack`.

/// The player-shell start-lifecycle surface. Dispatches by `phase`: a full-screen brand
/// loader (`.loading`), nothing for a stall (`.buffering` — the central spinner was removed
/// so a stalled engine can't leave it stuck), a lightweight transparent skip overlay over
/// the playing opening video (`.splash`), or nothing (`.done`). Read-only — it never skips itself;
/// the skip pill only FORWARDS `onSkip` (the host wires it to core `skipStart()`).
public struct StartScreenView: View {

    // MARK: - Inputs (documented sub-view input pattern)

    /// The resolved reference-ui theme (FIRST positional argument, always).
    public let theme: ReferenceUITheme

    /// The start lifecycle phase (`DefaultStartScreenState.phase`), passed BY VALUE
    /// from `PlayerShellModel.startPhase`. Drives which branch renders. Read-only.
    public let phase: LBStartScreenPhase

    /// The video cover URL (`PlayerShellModel.loadingCover` ← `channel.cover`) drawn as
    /// the `.loading` full-bleed background (behind the loader) on the `live == true`
    /// runtime path; empty → the solid `#0C0C10` brand backdrop. Distinct from the
    /// upcoming-scoped cover. Default `""` keeps demo / snapshot on the solid path
    /// (design provenance: `UpcomingCountdownView` cover+mask pattern).
    public let coverUrl: String

    /// Runtime opt-in for the `.loading` cover load. `false` (default — demo / snapshot)
    /// → solid `#0C0C10` backdrop, NO remote cover load (deterministic baselines).
    /// `true` (host runtime, `!paintsBackgroundPlaceholder`) → loads the cover background.
    /// Same mechanism as `UpcomingCountdownView.live`.
    public let live: Bool

    /// Splash「略過介紹」open intent. This surface does NOT own the skip — the
    /// container / host funnels it to core `skipStart()` (design §1). Default `nil`
    /// so demo / snapshot instances construct action-free.
    public let onSkip: (() -> Void)?

    /// Clean-mode gesture state (rb-ios-clean-mode-upcoming-intro-coverage ADDED — functional
    /// extension, no design-canvas coverage). Mirrors `PlayerShellView`'s private `cleanMode`
    /// `@State` (short-tap toggle, `rb-ios-gesture-clean-mode-v2`) — this surface does NOT
    /// detect the gesture itself, it only reads the resolved snapshot value, same one-way-data-
    /// flow contract as `phase`. `true` while `.splash`: hides `skipIntroButton`, shows the
    /// interactive expanded progress track instead. Default `false` keeps every existing call
    /// site and every demo / snapshot baseline byte-identical.
    public let cleanMode: Bool

    /// Opening-video current playhead, seconds (rb-ios-clean-mode-upcoming-intro-coverage
    /// ADDED, rb-ios-intro-progress-bar-interactive MODIFIED to be real data). Feeds the intro
    /// progress bar's fill ratio while `cleanMode == true`. Distinct from
    /// `PlayerShellModel.position` in NAME only — the host (`StartScreenHostView`) now feeds
    /// this parameter FROM `model.position` directly, since `intro-player-seek-progress-core`
    /// made that same published value correctly track the opening MP4's playhead while
    /// `model.introPlaying == true` (a separate `introPlayer` engine, but `PlayerShellModel`'s
    /// `position`/`duration`/`isPlaying` are pure forwarders that now route through it). Default
    /// `0` (demo / snapshot / not-yet-wired call sites).
    public let introPosition: Double

    /// Opening-video total duration, seconds (rb-ios-clean-mode-upcoming-intro-coverage ADDED,
    /// rb-ios-intro-progress-bar-interactive MODIFIED to be real data). Same provenance note as
    /// `introPosition`. Default `0`.
    public let introDuration: Double

    /// Whether the opening video is currently playing (rb-ios-intro-progress-bar-interactive
    /// ADDED). Drives the progress bar's play/pause icon (`PlaybackProgressBarView.isPlaying`).
    /// The host feeds this FROM `model.isPlaying` — same provenance note as `introPosition`.
    /// Default `false`.
    public let isIntroPlaying: Bool

    /// `true` while the finger is actually down on the intro progress bar
    /// (rb-ios-intro-progress-bar-interactive ADDED). Drives the drag-time timestamp readout —
    /// same role as `PlaybackProgressBarView.isScrubbing` at the VOD call site, but this is a
    /// COMPLETELY SEPARATE piece of state (`StartScreenHostView` owns its own `@State`, not
    /// shared with `PlayerShellView`'s `isScrubbing` — two independent render trees). Default
    /// `false`.
    public let isIntroScrubbing: Bool

    /// Intro progress bar play/pause tap → host-wired `model.togglePlayPause()`
    /// (rb-ios-intro-progress-bar-interactive ADDED). `nil` → inert (demo / snapshot).
    public let onIntroTogglePlayPause: (() -> Void)?

    /// Intro progress bar touch-down on the track → host reports scrub start
    /// (rb-ios-intro-progress-bar-interactive ADDED). `nil` → inert.
    public let onIntroScrubStarted: (() -> Void)?

    /// Intro progress bar drag moved → the new ratio `[0, 1]` (rb-ios-intro-progress-bar-
    /// interactive ADDED). Host forwards to `model.seek(to: ratio * model.duration)`. `nil` →
    /// inert (demo / snapshot; the visual still tracks locally, same as
    /// `PlaybackProgressBarView`'s own `dragRatio`).
    public let onIntroScrub: ((Double) -> Void)?

    /// Intro progress bar finger lifted → host reports scrub end
    /// (rb-ios-intro-progress-bar-interactive ADDED). `nil` → inert.
    public let onIntroScrubEnded: (() -> Void)?

    public init(
        theme: ReferenceUITheme,
        phase: LBStartScreenPhase,
        coverUrl: String = "",
        live: Bool = false,
        onSkip: (() -> Void)? = nil,
        cleanMode: Bool = false,
        introPosition: Double = 0,
        introDuration: Double = 0,
        isIntroPlaying: Bool = false,
        isIntroScrubbing: Bool = false,
        onIntroTogglePlayPause: (() -> Void)? = nil,
        onIntroScrubStarted: (() -> Void)? = nil,
        onIntroScrub: ((Double) -> Void)? = nil,
        onIntroScrubEnded: (() -> Void)? = nil
    ) {
        self.theme = theme
        self.phase = phase
        self.coverUrl = coverUrl
        self.live = live
        self.onSkip = onSkip
        self.cleanMode = cleanMode
        self.introPosition = introPosition
        self.introDuration = introDuration
        self.isIntroPlaying = isIntroPlaying
        self.isIntroScrubbing = isIntroScrubbing
        self.onIntroTogglePlayPause = onIntroTogglePlayPause
        self.onIntroScrubStarted = onIntroScrubStarted
        self.onIntroScrub = onIntroScrub
        self.onIntroScrubEnded = onIntroScrubEnded
    }

    // MARK: - Body (phase dispatch — mirrors the moments.jsx start components' branches)

    public var body: some View {
        switch phase {
        case .loading:
            loadingScreen
        case .buffering:
            // `.buffering`: render NOTHING (rb-ios-hide-start-buffering-spinner). The
            // central over-content spinner used to live here, but when the playback engine
            // stalls the phase stays `.buffering`, leaving the spinner stuck on screen.
            // Drawing nothing makes that impossible (initial-load feedback is the `.loading`
            // full-bleed brand loader). Same as `.done`.
            EmptyView()
        case .splash:
            splashScreen
        case .done:
            // `.done`: no overlay. The container short-circuits this branch, but
            // the sub-view stays self-consistent (renders nothing).
            EmptyView()
        }
    }

    // MARK: - .loading — full-bleed brand loader (design §1, `phase === 'loading'`)

    /// First load: a full-bleed background with the centered brand PNG-sequence
    /// animation. The BACKDROP is the video cover (`scaleAspectFill`) + a
    /// `rgba(0,0,0,0.35)` dark mask on the `live == true` runtime path (so first-open
    /// shows the cover instead of black — design provenance: `UpcomingCountdownView`
    /// cover+mask); the demo / snapshot path (`live == false`) and an empty cover fall
    /// back to the solid `#0C0C10` brand backdrop. Design re-sync `c3c98733` REMOVED
    /// the brand wordmark and「載入中…」caption that used to sit below the mark —
    /// `.loading` now renders ONLY `LoadingMarkAnimationView()` over the backdrop
    /// (`rb-ios-loading-announce-restyle`).
    private var loadingScreen: some View {
        ZStack {
            // Backdrop: cover (runtime, fill) + dark mask when a cover URL resolves;
            // else the solid `#0C0C10` brand backdrop (snapshot / demo / empty cover).
            // `live:` gates the remote load so snapshot baselines stay deterministic —
            // the SAME mechanism as `UpcomingCountdownView` (design provenance).
            if let url = Self.loadingCoverURL(live: live, coverUrl: coverUrl) {
                RemoteStillImageView(url: url, contentMode: .scaleAspectFill)
                    .ignoresSafeArea()
                Color.black.opacity(Self.loadingCoverMaskOpacity)
                    .ignoresSafeArea()
            } else {
                Self.loadingBackground
                    .ignoresSafeArea()
            }

            // The brand PNG-sequence mark ONLY (design re-sync `c3c98733`): the
            // wordmark + 「載入中…」caption that used to sit below it are REMOVED.
            // A single `ZStack` child centers itself — no wrapping `VStack` / spacing
            // needed anymore.
            LoadingMarkAnimationView()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(LBAccessibilityID.momentLoading)
    }

    /// Pure gate deciding the `.loading` backdrop: a resolved cover `URL` → draw
    /// cover + mask; `nil` → the solid `#0C0C10` brand backdrop. Returns `nil` when
    /// NOT on the runtime path (`live == false` — demo / snapshot, so no remote load →
    /// deterministic baselines) OR the cover is empty / whitespace (graceful fallback).
    /// Mirrors `UpcomingCountdownView.coverURL` with the `live` gate folded in
    /// (single testable function; unit-test-discipline).
    static func loadingCoverURL(live: Bool, coverUrl: String) -> URL? {
        guard live else { return nil }
        let s = coverUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : URL(string: s)
    }

    // MARK: - .buffering — intentionally not rendered (rb-ios-hide-start-buffering-spinner)
    //
    // The `.buffering` phase used to draw a lightweight over-content spinner pill here. It
    // was REMOVED: when the playback engine stalls, the canonical state stays `buffering`,
    // so the phase stayed `.buffering` and the central spinner remained stuck on screen.
    // `.buffering` now renders `EmptyView` (see `body`); initial-load feedback is the
    // `.loading` full-bleed brand loader.

    // MARK: - .splash — lightweight transparent skip overlay (design §1, `phase === 'splash'`)

    /// Intro skip overlay (design `LBPSkipIntroButton`, design re-sync `LL9WzHAq`): the
    /// opening video plays through the NORMAL playback path with the family-1 subject
    /// chrome (TopBar / host badge / bottom bar) visible — 開場不接管畫面 (start is NOT a
    /// screen takeover). The ONLY added UI is a bottom-right「略過介紹」skip button. NO 片頭
    /// tag / muted indicator / brand backdrop / lower-third title card / progress bar (all
    /// removed per the latest design — the intro now plays unmuted with chrome, not a
    /// muted brand splash).
    private var splashScreen: some View {
        ZStack {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    // 乾淨模式隱藏「略過介紹」(rb-ios-clean-mode-upcoming-intro-coverage ADDED —
                    // 功能擴充，design 稿本無此規範，見該 change proposal.md「Why」).
                    if !cleanMode {
                        skipIntroButton
                    }
                }
            }
            .padding(.trailing, Self.skipTrailing)
            .padding(.bottom, Self.skipBottom)

            // 乾淨模式展開進度條 (rb-ios-clean-mode-upcoming-intro-coverage ADDED, rb-ios-intro-
            // progress-bar-interactive MODIFIED)：直接組合真正的 `PlaybackProgressBarView` 元件
            // 實例——core 層 `intro-player-seek-progress-core` 已補齊開場影片的 play/pause/seek
            // 路由與進度發布，此元件的無條件 play/pause 鈕與無條件 `DragGesture`（上一批 design.md
            // 認定「無法適配」的兩點）現在剛好就是這次要的行為，不再手繪一份唯讀版本。`isExpanded`
            // 恆為 `true`——開場沒有「未展開細線態」這個概念，只在 `cleanMode == true` 才出現。
            // 「退出乾淨模式」小圓鈕已由 `PlayerShellView` 既有、無條件於 `cleanMode == true` 時渲
            // 染的按鈕涵蓋，這裡不重複。
            if cleanMode {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    PlaybackProgressBarView(
                        theme: theme,
                        position: introPosition,
                        duration: introDuration,
                        isPlaying: isIntroPlaying,
                        isScrubbing: isIntroScrubbing,
                        isExpanded: true,
                        onTogglePlayPause: onIntroTogglePlayPause,
                        onScrubStarted: onIntroScrubStarted,
                        onScrub: onIntroScrub,
                        onScrubEnded: onIntroScrubEnded)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(LBAccessibilityID.momentStart)
    }

    // MARK: - .splash cleanMode — interactive intro progress track (rb-ios-clean-mode-upcoming-
    //         intro-coverage ADDED as a hand-drawn read-only track, rb-ios-intro-progress-bar-
    //         interactive MODIFIED to directly compose the real `PlaybackProgressBarView`
    //         instance instead — see `splashScreen` above for the composition. No pure-function
    //         ratio helper or hand-drawn view lives here anymore: `PlaybackProgressBarView` owns
    //         its own `progressRatio`/drag/token logic, reused as-is.)

    /// Bottom-right「略過介紹」skip button (design `LBPSkipIntroButton`). A translucent
    /// blurred capsule with a soft shadow. The label is STATIC「略過介紹」— the design's
    /// `(N)` countdown is removed per product request (the tap forwards `onSkip`; skip is the
    /// host's / core's job).
    private var skipIntroButton: some View {
        Button(action: { onSkip?() }) {
            HStack(spacing: Self.skipGlyphGap) {
                Text(Self.skipLabel)
                    .font(.system(size: Self.skipFontSize, weight: .semibold))
                    .foregroundColor(.white)
                // Fast-forward chevrons (the design's `M5 4l8 8…M14 4l6 8…` SVG).
                // Hand-drawn open double-chevron (design `fill="none" stroke 2.2`); SF
                // `forward.fill` (solid triangles) contradicted the stroke-based icon set.
                ChevronForwardGlyph(size: Self.skipGlyphSize, color: .white)
            }
            .padding(.horizontal, Self.skipHPadding)
            .padding(.vertical, Self.skipVPadding)
            .background(
                Capsule().fill(Self.chromeFill.opacity(Self.skipFillOpacity))
            )
            .shadow(color: Color.black.opacity(Self.skipShadowOpacity),
                    radius: Self.skipShadowRadius, x: 0, y: Self.skipShadowY)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier(LBAccessibilityID.momentStartSkip)
    }

}

// MARK: - Design tokens (lifted from moments.jsx start components — LBPLoadingOverlay /
//         LBPBufferingSpinner / LBPSkipIntroButton)

private extension StartScreenView {
    // --- Fixed decorative design colors (literal design hex via Color(hex:) —
    //     surface-token approach consistent with family-2/3 surfaces; NOT theme
    //     tokens. Resolved once into non-optional Colors with a safe black fallback
    //     so the views never force-unwrap an optional Color). ---
    static let loadingBackgroundHex = "#0C0C10"   // loading brand backdrop
    static let chromeFillHex = "#141418"          // rgba(20,20,24,…) chrome capsules
    static let loadingBackground = Color(hex: loadingBackgroundHex) ?? .black
    static let chromeFill = Color(hex: chromeFillHex) ?? .black

    // --- .loading ---
    // `.loading` cover backdrop dark mask (rgba(0,0,0,0.35)) — design provenance
    // `UpcomingCountdownView` cover+mask. Only drawn on the `live == true` cover path.
    static let loadingCoverMaskOpacity: Double = 0.35
    // The wordmark (accent dot + "Livebuy") + 「載入中…」caption tokens that used to
    // live here were REMOVED (design re-sync `c3c98733`, `rb-ios-loading-announce-
    // restyle`) — `.loading` now renders only `LoadingMarkAnimationView()`.

    // --- .buffering: intentionally not rendered (rb-ios-hide-start-buffering-spinner) ---
    // (the former central buffering pill / spinner tokens were removed — `.buffering`
    //  now renders `EmptyView` to avoid a stuck stall indicator.)

    // --- .splash「略過介紹」skip button (design `LBPSkipIntroButton`, bottom-right) ---
    // The intro plays through the normal path with subject chrome visible; the only added
    // UI is this bottom-right skip button. 片頭 tag / muted indicator / brand backdrop /
    // lower-third title card / progress bar are all REMOVED per the latest design.
    static let skipLabel = "略過介紹"                  // was 略過介紹 (design rename)
    static let skipFontSize: CGFloat = 13             // fontSize 13 / fontWeight 600
    static let skipGlyphGap: CGFloat = 6
    static let skipGlyphSize: CGFloat = 11
    static let skipHPadding: CGFloat = 14             // padding '9px 14px'
    static let skipVPadding: CGFloat = 9
    static let skipFillOpacity: Double = 0.6          // rgba(20,20,24,0.6)
    static let skipTrailing: CGFloat = 12             // right: 12
    static let skipBottom: CGFloat = 16               // bottom: 16 (+ host safe-area)
    static let skipShadowOpacity: Double = 0.3        // boxShadow rgba(0,0,0,0.3)
    static let skipShadowRadius: CGFloat = 14         // blur 14
    static let skipShadowY: CGFloat = 4               // y-offset 4
}

// MARK: - Deterministic demo data (previews + snapshot test)

public extension StartScreenView {

    /// A deterministic demo instance of the start surface. The minimal-palette theme
    /// is supplied by the caller; the phase defaults to `.splash` (the richest
    /// branch — exercises every chrome layer). Action-free (no `onSkip`) so previews
    /// / snapshot tests render statically.
    static func demo(
        theme: ReferenceUITheme = ReferenceUIThemePalette.minimal,
        phase: LBStartScreenPhase = .splash,
        cleanMode: Bool = false,
        introPosition: Double = 0,
        introDuration: Double = 0,
        isIntroPlaying: Bool = false,
        isIntroScrubbing: Bool = false
    ) -> StartScreenView {
        StartScreenView(theme: theme, phase: phase, cleanMode: cleanMode,
                        introPosition: introPosition, introDuration: introDuration,
                        isIntroPlaying: isIntroPlaying, isIntroScrubbing: isIntroScrubbing)
    }
}

// MARK: - Preview (deterministic demo)

#if DEBUG
struct StartScreenView_Previews: PreviewProvider {
    static var previews: some View {
        StartScreenView.demo()
            .frame(width: 393, height: 852)
            .previewLayout(.sizeThatFits)
    }
}
#endif
