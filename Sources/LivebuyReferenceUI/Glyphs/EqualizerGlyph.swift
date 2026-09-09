import SwiftUI

// MARK: - EqualizerGlyph — hand-drawn 3-bar equalizer (design「介紹中」mark)
//
// Spec: `reference-ui-rendering/spec.md` (rb-ios-product-list-introducing-banner,
//   rb-ios-live-equalizer-motion)
// Design: `design/templates/minimal/live-chrome.jsx` `LBLivePinnedCard` +
//   `sdk-components.jsx` `LBPProductRow` introBadge (now `Icons.equalizerLive`, design R40) —
//   <rect x3   y14 w3 h7  rx0.5/>
//   <rect x10.5 y9 w3 h12 rx0.5/>
//   <rect x18  y4  w3 h17 rx0.5/>   (24px viewBox, fill)
// Motion contract: `design/contract/equalizer-motion.json` (cross-platform authority for the
//   breathing formula / period / phases / resting heights — the geometry constants below are
//   verified (see doc comments) to numerically match this file's PRE-EXISTING static geometry).
//
// Three bottom-aligned bars now BREATHE between a min and max height (design R40 replaced the
// static mark with an animated one, `Icons.equalizerLive`) — the「介紹中」(now-introducing)
// vocabulary shared by the LIVE pinned card tag, the product-list banner, and the VOD mask. SF
// Symbols has no faithful equalizer of this exact shape, so we hand-draw it (as with
// ShareGlyph), scaled by `size / 24`.
//
// Public API (`size` / `color`, now + an additive optional `paused`) stays source-compatible —
// every existing call site (`LiveOverlayChromeView`, `ProductRowView` ×2) keeps compiling with
// zero edits. iOS-14-safe (`Path` / `.fill` / `.frame` / `AnimatableModifier`+`Shape`, all
// iOS 13+; `.onChange(of:)` is iOS 14+, matching this module's existing floor).

/// The design's 3-bar equalizer mark, hand-drawn to match the「介紹中」badge. Breathes
/// (design R40 `Icons.equalizerLive`) unless Reduce Motion, the shared continuous-animation
/// gate, or an explicit `paused` override says otherwise — see `equalizer-motion.json`.
public struct EqualizerGlyph: View {

    /// The glyph box size (pt). The design proportions scale by `size / 24`.
    public let size: CGFloat

    /// The fill color.
    public let color: Color

    /// Host-driven pause override (e.g. player paused / buffering) — bars freeze at
    /// `restingHeightFractions` while `true`, same as Reduce Motion. Defaults to `false`
    /// (source-compatible with every existing call site). None of this glyph's 3 current call
    /// sites (`LiveOverlayChromeView` pinned-card tag, `ProductRowView` LIVE banner / VOD mask)
    /// currently have a convenient playback-state signal threaded down to them — see
    /// `design.md` for why wiring one is left as a documented follow-up rather than forced here.
    public let paused: Bool

    public init(size: CGFloat, color: Color, paused: Bool = false) {
        self.size = size
        self.color = color
        self.paused = paused
    }

    // MARK: - Motion constants (`equalizer-motion.json` `motion` + `restingHeights`)

    /// One full breathe cycle. `equalizer-motion.json` `motion.periodMs` (900).
    static let periodSeconds: Double = 0.9

    /// `equalizer-motion.json` `motion.phases` — each bar's offset into the cycle (as a
    /// fraction of one period), applied left-to-right.
    static let phases: [Double] = [0, 0.3333, 0.6667]

    /// Exact fractions-of-`size` for the 3 bars' heights AT REST — mathematically identical to
    /// this glyph's ORIGINAL static geometry (7 / 12 / 17 units in the 24px design viewBox,
    /// i.e. `7/24`, `12/24`, `17/24`), which is what keeps every EXISTING snapshot baseline
    /// (LIVE banner / VOD mask / pinned-card tag) byte-identical whenever the bars are not
    /// animating (the default state a freshly-constructed view starts in, and what
    /// `EqualizerBreathingView.scheduleSync()` defers actually starting the breathing motion
    /// past — see its doc comment for why a deferred, not synchronous, start is required here).
    /// These equal `equalizer-motion.json`'s `restingHeights` (`[0.2917, 0.5, 0.7083]`) to its published
    /// 4-decimal precision; using the exact rational fractions here — rather than those rounded
    /// literals — avoids introducing sub-pixel drift into geometry this file has rendered
    /// unchanged since before this animation existed. Doubles as `motion.minHeight` (index 0)
    /// / `motion.maxHeight` (index 2) for the breathing formula below.
    static let restingHeightFractions: [CGFloat] = [7.0 / 24.0, 12.0 / 24.0, 17.0 / 24.0]
    static let minHeightFraction: CGFloat = restingHeightFractions[0]
    static let maxHeightFraction: CGFloat = restingHeightFractions[2]

    /// `equalizer-motion.json` `geometry` — bar width / gap / side inset / bottom inset /
    /// corner radius, each a fraction of `size`. Exact binary fractions (1/8, 3/16, 1/48), so
    /// deriving bar x-positions from them below carries zero rounding risk relative to the
    /// original hand-picked pixel values (3 / 10.5 / 18, width 3, corner 0.5 in the 24px
    /// viewBox).
    static let barWidthFraction: CGFloat = 0.125
    static let gapFraction: CGFloat = 0.1875
    static let sideInsetFraction: CGFloat = 0.125
    static let bottomInsetFraction: CGFloat = 0.125
    static let cornerRadiusFraction: CGFloat = 0.5 / 24.0

    /// Bar x-origin (fraction of `size`), left to right: `sideInset + index*(barWidth + gap)`.
    static func barXFraction(index: Int) -> CGFloat {
        sideInsetFraction + CGFloat(index) * (barWidthFraction + gapFraction)
    }

    /// Pure formula, verbatim from `equalizer-motion.json` `motion.formula`:
    /// `h = minHeight + (maxHeight - minHeight) * (0.5 - 0.5 * cos(2*PI*(t/periodMs + phase)))`.
    /// `progress` stands in for `t / periodMs` — any real value works, since cosine is
    /// 1-periodic (a `progress` that loops `0...1` produces a seamless breathing cycle with no
    /// visible snap at the wrap point). Pure / deterministic — no View, no clock — directly
    /// unit-testable.
    static func barHeightFraction(
        progress: Double,
        phase: Double,
        minHeight: CGFloat = minHeightFraction,
        maxHeight: CGFloat = maxHeightFraction
    ) -> CGFloat {
        let raisedCosine = 0.5 - 0.5 * cos(2 * Double.pi * (progress + phase))
        return minHeight + (maxHeight - minHeight) * CGFloat(raisedCosine)
    }

    /// Whether the breathing animation may run at all: Reduce Motion, the shared
    /// `ContinuousAnimationGate` (power profile / off-screen — `visible` supplied by the
    /// caller), and this glyph's own `paused` override all gate independently; ANY of them
    /// saying "no" freezes the bars at `restingHeightFractions`. Pure / unit-testable.
    static func shouldAnimate(paused: Bool, gateAllowsAnimation: Bool) -> Bool {
        !paused && gateAllowsAnimation
    }

    /// One bar's frame, expressed as fractions of `size` (multiply by `size` — or by
    /// `rect.width` for a square rect, as `EqualizerBarsShape` does — to get points). Pure data,
    /// no SwiftUI `Path` dependency, so geometry can be asserted directly in unit tests without
    /// walking a rendered path.
    struct BarFrame: Equatable {
        let xFraction: CGFloat
        let yFraction: CGFloat
        let widthFraction: CGFloat
        let heightFraction: CGFloat
    }

    /// All 3 bars' frames for a given animation state. `animating == false` uses the fixed
    /// `restingHeightFractions` (Reduce Motion / gated off / `paused`); `animating == true`
    /// evaluates `barHeightFraction` per bar at the current `progress`. Pure / unit-testable.
    static func barFrames(progress: Double, animating: Bool) -> [BarFrame] {
        phases.enumerated().map { index, phase in
            let heightFraction = animating
                ? barHeightFraction(progress: progress, phase: phase)
                : restingHeightFractions[index]
            let bottomFraction = 1 - bottomInsetFraction
            return BarFrame(
                xFraction: barXFraction(index: index),
                yFraction: bottomFraction - heightFraction,
                widthFraction: barWidthFraction,
                heightFraction: heightFraction
            )
        }
    }

    public var body: some View {
        EqualizerBreathingView(size: size, color: color, paused: paused)
    }
}

// MARK: - Animation driver (internal — kept out of `EqualizerGlyph`'s own body so its public
// surface stays exactly `size` / `color` / `paused`; `internal` rather than `private` so
// `@testable import` can exercise `EqualizerBarsShape` directly, matching this test target's
// established convention).

struct EqualizerBreathingView: View {
    let size: CGFloat
    let color: Color
    let paused: Bool

    /// `0...1`, standing in for `t / periodMs`; animated continuously via `withAnimation` /
    /// `repeatForever` once (and only once) animation is allowed. `Shape.animatableData`
    /// interpolates this every frame — see `EqualizerBarsShape`.
    @State private var progress: Double = 0
    @State private var isAnimating = false

    /// `ios-power-profile-animation-throttle-reference-ui` gate — the SAME environment key this
    /// module's other continuous decorative loops (`MarqueeTitleLoopView`, `SpinnerRingView`)
    /// already read, reused rather than inventing a second throttling mechanism. Defaults to a
    /// neutral "animate" value when unset (snapshot / preview fixtures constructed without
    /// `PowerProfileMotionEnvironment`).
    @Environment(\.continuousAnimationGate) private var motionGate

    var body: some View {
        EqualizerBarsShape(progress: progress, animating: isAnimating)
            .fill(color)
            .frame(width: size, height: size)
            .onAppear { scheduleSync() }
            // Re-evaluate on every axis that can flip the decision (heat/cool, Reduce Motion
            // toggle, host-driven pause/resume). `ContinuousAnimationGate` is `Equatable`.
            .onChange(of: motionGate) { _ in scheduleSync() }
            .onChange(of: paused) { _ in scheduleSync() }
            // Off-screen (cell recycled / view leaves the hierarchy): reset to the resting
            // frame WITHOUT animating the snap-back, so no `repeatForever` driver keeps running
            // for a detached view (mirrors `MarqueeTitleLoopView.onDisappear`).
            .onDisappear { stop() }
    }

    /// Defers the actual start (or stop) of the animation to the NEXT main-thread run-loop turn
    /// rather than reacting synchronously inside `.onAppear`/`.onChange`. This is deliberate,
    /// not incidental: unlike this module's other continuous decorative loops
    /// (`MarqueeTitleLoopView` / `SpinnerRingView`), whose "just-appeared" resting frame happens
    /// to coincide exactly with their animation's own t=0 value (rotation 0 / offset 0), this
    /// glyph's hand-picked `restingHeightFractions` ([min, mid, max]) do NOT lie on the
    /// breathing formula's curve at a single shared `progress` for every phase (only the phase
    /// `0` bar's minimum coincides with `progress == 0`; the other two phases briefly render at
    /// a different, non-resting height at that same progress). `ReferenceUISnapshotHelper`'s
    /// `ImageRenderer`-based capture calls straight through to `.onAppear` synchronously with NO
    /// run-loop turn in between — so reacting synchronously would make even a static snapshot
    /// capture that mid-formula frame instead of the resting one, breaking every existing
    /// baseline this glyph appears in. Deferring via `DispatchQueue.main.async` guarantees any
    /// zero-time synchronous render (test harness or otherwise) still sees the state exactly as
    /// constructed (`isAnimating == false`, `progress == 0` → resting fractions); on a live
    /// device a run-loop turn follows `.onAppear` almost immediately, so the perceptible delay
    /// before the glyph starts breathing is negligible.
    private func scheduleSync() {
        DispatchQueue.main.async { self.syncAnimating() }
    }

    private func syncAnimating() {
        guard EqualizerGlyph.shouldAnimate(
            paused: paused,
            gateAllowsAnimation: motionGate.allowsAnimation(visible: true)
        ) else {
            stop()
            return
        }
        guard !isAnimating else { return }
        isAnimating = true
        progress = 0
        withAnimation(.linear(duration: EqualizerGlyph.periodSeconds).repeatForever(autoreverses: false)) {
            progress = 1
        }
    }

    private func stop() {
        isAnimating = false
        progress = 0
    }
}

/// The 3 rounded bars. `progress` is the ONLY animatable field — `animating` is a plain constant
/// for whichever transaction is currently in flight (this module's existing
/// `HeartBurstKeyframeModifier` idiom: a single animated scalar driving pure-function lookups).
struct EqualizerBarsShape: Shape {
    var progress: Double
    let animating: Bool

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let cornerSize = CGSize(
            width: EqualizerGlyph.cornerRadiusFraction * rect.width,
            height: EqualizerGlyph.cornerRadiusFraction * rect.width
        )
        var path = Path()
        for frame in EqualizerGlyph.barFrames(progress: progress, animating: animating) {
            let bar = CGRect(
                x: frame.xFraction * rect.width,
                y: frame.yFraction * rect.width,
                width: frame.widthFraction * rect.width,
                height: frame.heightFraction * rect.width
            )
            path.addRoundedRect(in: bar, cornerSize: cornerSize)
        }
        return path
    }
}
