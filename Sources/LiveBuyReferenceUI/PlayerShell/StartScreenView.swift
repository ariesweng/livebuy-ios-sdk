import SwiftUI
import LiveBuySDK
import LiveBuyUI

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
//   • `.loading`   → full-bleed brand background + centered spinner + wordmark +
//                    「載入中…」 caption.
//   • `.buffering` → renders NOTHING (`EmptyView`). The former central over-content
//                    spinner was removed (rb-ios-hide-start-buffering-spinner): a stalled
//                    engine keeps the phase at `.buffering`, which left the spinner stuck
//                    on screen. Initial-load feedback is the `.loading` brand loader.
//   • `.splash`    → the opening video plays through the NORMAL path with the family-1
//                    subject chrome (LIVE / VOD) visible; the ONLY added UI is a
//                    bottom-right「略過介紹」skip button (`onSkip`). NO 片頭 tag / muted
//                    indicator / brand backdrop / lower-third card / progress bar (design
//                    `LBPSkipIntroButton`; 開場不接管畫面 + 開場影片有聲).
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

    /// Splash「略過介紹」open intent. This surface does NOT own the skip — the
    /// container / host funnels it to core `skipStart()` (design §1). Default `nil`
    /// so demo / snapshot instances construct action-free.
    public let onSkip: (() -> Void)?

    /// Local spinner rotation state. Driven purely by the on-appear forever-repeat
    /// toggle below (never by a core call). Mirrors the design's `lbp-spin` ring.
    @State private var spinning = false

    public init(
        theme: ReferenceUITheme,
        phase: LBStartScreenPhase,
        onSkip: (() -> Void)? = nil
    ) {
        self.theme = theme
        self.phase = phase
        self.onSkip = onSkip
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

    /// First load: a full-bleed dark brand background with a centered spinner, the
    /// brand wordmark, and a「載入中…」caption. `background: '#0C0C10'`.
    private var loadingScreen: some View {
        ZStack {
            // Full-bleed brand backdrop (`#0C0C10`).
            Self.loadingBackground
                .ignoresSafeArea()

            VStack(spacing: Self.loadingStackSpacing) {
                spinnerRing(size: Self.loadingSpinnerSize, lineWidth: Self.loadingSpinnerWidth)

                // Brand wordmark (`LBLogo variant="wordmark"`). The design renders a
                // dark wordmark; we mirror its read as a white brand name with the
                // accent applied to the leading mark dot.
                wordmark

                // Letter-spacing in the design (`letterSpacing: 1`) is omitted —
                // `Text.tracking(_:)` is iOS-16+, and this layer's floor is iOS-14
                // (design §"守住的不變式": iOS-14 樓地板). The caption reads the same.
                Text(Self.loadingCaption)
                    .font(.system(size: Self.loadingCaptionFontSize))
                    .foregroundColor(.white.opacity(Self.loadingCaptionOpacity))
            }
        }
    }

    /// The brand wordmark used by `.loading` (`LBLogo variant="wordmark"`): an
    /// accent mark dot + the brand name. Plain `HStack` (no lazy/scroll).
    private var wordmark: some View {
        HStack(spacing: Self.wordmarkSpacing) {
            Circle()
                .fill(theme.accent)
                .frame(width: Self.wordmarkDotSize, height: Self.wordmarkDotSize)
            Text(Self.brandName)
                .font(.system(size: Self.wordmarkFontSize, weight: .heavy))
                .foregroundColor(.white)
        }
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
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                skipIntroButton
            }
        }
        .padding(.trailing, Self.skipTrailing)
        .padding(.bottom, Self.skipBottom)
    }

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
                Image(systemName: "forward.fill")
                    .font(.system(size: Self.skipGlyphSize, weight: .bold))
                    .foregroundColor(.white)
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
    }

    // MARK: - Spinner ring (iOS-14-safe, mirrors design `lbp-spin`)

    /// A rotating accent/white ring drawn with `Circle().trim` and a forever-repeat
    /// rotation — the iOS-14-safe stand-in for the design's `lbp-spin` border
    /// spinner (and avoids relying on `ProgressView(.circular)` styling, which is
    /// inconsistent across OS versions). A faint full ring + a bright trimmed arc.
    private func spinnerRing(size: CGFloat, lineWidth: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(Self.spinnerTrackOpacity), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: Self.spinnerArcFraction)
                .stroke(
                    Color.white,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(spinning ? 360 : 0))
        }
        .frame(width: size, height: size)
        // Forever-repeat rotation (iOS-14-safe). Under `ImageRenderer` the frame is
        // captured at the seed (deterministic baseline); on a live player it spins.
        .onAppear {
            withAnimation(.linear(duration: Self.spinnerDuration).repeatForever(autoreverses: false)) {
                spinning = true
            }
        }
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
    static let loadingStackSpacing: CGFloat = 18  // gap 18
    static let loadingSpinnerSize: CGFloat = 76   // LBLoading size 76
    static let loadingSpinnerWidth: CGFloat = 4
    static let loadingCaption = "載入中…"
    static let loadingCaptionFontSize: CGFloat = 12
    static let loadingCaptionOpacity: Double = 0.5  // rgba(255,255,255,0.5)

    // Wordmark (`LBLogo variant="wordmark" size=26`)
    static let brandName = "LiveBuy"
    static let wordmarkSpacing: CGFloat = 7
    static let wordmarkDotSize: CGFloat = 9
    static let wordmarkFontSize: CGFloat = 22

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

    // Spinner ring
    static let spinnerTrackOpacity: Double = 0.22     // rgba(255,255,255,0.22)
    static let spinnerArcFraction: CGFloat = 0.25     // bright top arc
    static let spinnerDuration: Double = 0.8          // lbp-spin 0.8s
}

// MARK: - Deterministic demo data (previews + snapshot test)

public extension StartScreenView {

    /// A deterministic demo instance of the start surface. The minimal-palette theme
    /// is supplied by the caller; the phase defaults to `.splash` (the richest
    /// branch — exercises every chrome layer). Action-free (no `onSkip`) so previews
    /// / snapshot tests render statically.
    static func demo(
        theme: ReferenceUITheme = ReferenceUIThemePalette.minimal,
        phase: LBStartScreenPhase = .splash
    ) -> StartScreenView {
        StartScreenView(theme: theme, phase: phase)
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
