import SwiftUI
import UIKit

// MARK: - HeartBurstView — shared floating-hearts burst (`LBPHeartBurst`)
//
// Spec: `reference-ui-rendering/spec.md` (rb-ios-live-bottom-heart-burst,
//        rb-ios-live-like-burst-restyle, rb-ios-live-like-burst-png-glyphs)
// Design: `design/templates/minimal/sdk-components.jsx` `LBPHeartBurst` (2026-09 rewrite) +
//          `live-chrome.jsx` `LBLiveBottomBar onLike → likeAnimation`.
//
// A `tick`-driven burst: each time `tick` INCREASES, one burst spawns at the origin and flies
// up, fading + scaling + swinging left/right, then self-removes after its lifetime so repeated
// ticks never accumulate state. Pure presentation — never calls core.
//
// `rb-ios-live-like-burst-restyle` (2026-09) rewrite — richer variety, same trigger contract:
// each burst now randomly picks ONE of 4 glyphs (heart / star / arrow / cross) and ONE of 3
// upward-flight paths × 3 left-right swing paths (9 combinations), at one of 2 flight speeds
// (0.8s / 1.0s), disappearing after a fixed 2s lifetime. The glyph/path/swing selection is a
// pure, unit-testable function (`randomBurstVariant`); the per-progress visual values (scale /
// opacity / horizontal swing) are ALSO pure, table-driven interpolation functions
// (`interpolatedValue(_:in:)` over `scaleKeyframes` / `opacityKeyframes` / `swingKeyframes`),
// driven by a single `AnimatableModifier` progress value so SwiftUI's own animation engine
// produces the frame-by-frame interpolation (no per-frame timers). This does NOT reproduce the
// design's CSS keyframe percentages byte-for-byte — it is a visual approximation with the same
// "3 rise curves × 3 swings, randomly combined" richness.
//
// ⚠️ Trigger-count contract is UNCHANGED and is NOT this file's concern: this view still spawns
// exactly ONE burst per ONE `tick` increase. The VOD side rail (`OperationRailView`, driven by
// core `heartBurstTick`) MUST keep that 1-tick-1-burst invariant (reference-ui MUST NOT call
// like on its own — see `reference-ui-rendering/spec.md`'s OperationPanel rail Requirement). The
// LIVE bottom bar's "1–4 hearts per tap" richness lives ENTIRELY in `PlayerShellView` (it bumps
// `liveHeartTick` multiple times, staggered 300ms apart, per like tap) — this shared view still
// only ever reacts to ITS `tick` parameter increasing by exactly 1 at a time.
//
// Extracted from `OperationRailView`'s inline burst so BOTH the VOD side rail (driven by the
// core `heartBurstTick`) and the LIVE bottom bar (driven by `PlayerShellView`'s local
// `liveHeartTick`, bumped on the like tap) share one implementation.
//
// Snapshot-neutral: at rest `bursts` is empty → nothing is drawn. `allowsHitTesting(false)`.
//
// iOS-14-safe: `onChange(of:)` is iOS-14+; `withAnimation` / `Image` / `ForEach` /
// `AnimatableModifier` are iOS-13+.

/// Which pictogram a single burst draws. 4 choices (design R37, `rb-ios-live-like-burst-restyle`):
/// heart / star / arrow-badge / crosshair. ALL 4 render from bundled PNG art
/// (`Resources/LikeBurst/like-{heart,star,arrow,cross}.png`, `rb-ios-live-like-burst-png-glyphs`)
/// — each already a specific, fixed-hue graphic; NONE of them consume the caller-supplied
/// `color` (supersedes the prior "only `.heart` is accent-tintable, the other 3 are hand-drawn"
/// split — that split's premise, the PNGs being unable to land via the design-sync text channel,
/// no longer holds now that the assets are bundled).
enum HeartBurstGlyphKind: CaseIterable, Equatable {
    case heart, star, arrow, cross
}

/// Which of the 3 upward-flight curves a burst follows (design `lbp-heart-fly-1/2/3`). Each
/// pairs a distinct scale sequence with a FIXED rotation applied for the whole flight.
enum HeartBurstPathKind: CaseIterable, Equatable {
    /// 軌跡 1 — no rotation, scale 0.2 → 1.2 (35%) → 0.9 (80%) → 0.6.
    case rise
    /// 軌跡 2 — fixed +20°, scale 0.4 → 1.5 (35%) → 1.0 (80%) → 0.4.
    case riseTiltRight
    /// 軌跡 3 — fixed -30°, scale 0.6 → 1.7 (35%) → 1.1 (80%) → 0.7.
    case riseTiltLeft
}

/// Which of the 3 left-right swing paths a burst follows (horizontal offset multiplier of
/// `HeartBurstView.swingAmplitude`, design `lbp-heart-swing-1/2/3`).
enum HeartBurstSwingKind: CaseIterable, Equatable {
    /// 擺動 1 — symmetric: 0 → -1 (25%) → +1 (75%) → 0.
    case symmetric
    /// 擺動 2 — asymmetric, settles right-of-origin: 0 → -1 (33%) → +0.5 (100%).
    case leftThenSettle
    /// 擺動 3 — mirror of `.symmetric`: 0 → +1 (25%) → -1 (75%) → 0.
    case mirrored
}

/// One resolved random draw: glyph × path × swing × flight duration (design's 2 speeds).
/// Equatable + no I/O → trivially unit-testable.
struct HeartBurstVariant: Equatable {
    let glyph: HeartBurstGlyphKind
    let path: HeartBurstPathKind
    let swing: HeartBurstSwingKind
    /// Flight duration in seconds — one of `HeartBurstView.flyDurationFast` (0.8) /
    /// `.flyDurationSlow` (1.0).
    let duration: Double
}

/// One (time fraction 0...1, value) keyframe point. `time` values within one array are strictly
/// increasing, first == 0, last == 1 — `HeartBurstView.interpolatedValue(_:in:)` linearly
/// interpolates between consecutive points.
struct HeartBurstKeyframe: Equatable {
    let time: Double
    let value: CGFloat
}

/// One in-flight burst. `active == false` is the spawned (at-origin) state; flipping to `true`
/// under `withAnimation` drives the flight via `HeartBurstKeyframeModifier`'s `animatableData`.
private struct HeartBurst: Identifiable, Equatable {
    let id = UUID()
    let variant: HeartBurstVariant
    var active: Bool = false
}

/// The shared floating burst effect. Spawns one burst each time `tick` increases.
struct HeartBurstView: View {

    /// Monotonic trigger — each increase spawns one burst.
    let tick: Int

    /// Formerly the `.heart` glyph's tint (accent). Kept ONLY for source compatibility with
    /// existing call sites (`PlayerShellView.swift` / `OperationRailView.swift` both still pass
    /// `theme.accent`) — no longer consumed by rendering: all 4 glyphs now draw from bundled PNG
    /// art with their own baked-in fixed colors (see `HeartBurstGlyphKind`,
    /// `rb-ios-live-like-burst-png-glyphs`).
    let color: Color

    /// Glyph size (design `Icons.heartFill` size 26).
    var glyphSize: CGFloat = 26

    @State private var bursts: [HeartBurst] = []

    var body: some View {
        ZStack {
            ForEach(bursts) { burst in
                Self.glyphView(for: burst.variant.glyph, size: glyphSize)
                    .modifier(HeartBurstKeyframeModifier(
                        progress: burst.active ? 1 : 0,
                        variant: burst.variant,
                        swingAmplitude: Self.swingAmplitude,
                        flyDistance: Self.flyDistance))
            }
        }
        .frame(width: glyphSize, height: glyphSize)
        .allowsHitTesting(false)
        // Observe the monotonic tick; each increase spawns one burst (iOS-14-safe `onChange`).
        .onChange(of: tick) { _ in spawnBurst() }
    }

    /// Spawn one burst with a fresh random variant and animate it. Self-removes after
    /// `burstLifetime` so repeated ticks do not accumulate state. Pure presentation — no core call.
    private func spawnBurst() {
        let variant = Self.randomBurstVariant()
        let burst = HeartBurst(variant: variant)
        bursts.append(burst)

        withAnimation(.easeOut(duration: variant.duration)) {
            if let idx = bursts.firstIndex(where: { $0.id == burst.id }) {
                bursts[idx].active = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.burstLifetime) {
            bursts.removeAll { $0.id == burst.id }
        }
    }

    // MARK: - Glyph rendering (pure — no state)

    /// Draws one of the 4 glyph kinds — ALL 4 now load their bundled PNG art
    /// (`rb-ios-live-like-burst-png-glyphs`, superseding the prior SF-Symbol-heart +
    /// hand-drawn-star/arrow/cross split). Displayed at a fixed `size × size` container with
    /// aspect-fit scaling (design `<img width={28} height={28} style={{objectFit:'contain'}}>`)
    /// — no glyph consumes a caller-supplied color; each PNG carries its own baked-in fixed hue.
    @ViewBuilder
    static func glyphView(for kind: HeartBurstGlyphKind, size: CGFloat) -> some View {
        Self.glyphImage(for: kind)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }

    /// Maps a glyph kind to its bundled PNG resource name under `Resources/LikeBurst/`.
    static func glyphImageName(for kind: HeartBurstGlyphKind) -> String {
        switch kind {
        case .heart: return "like-heart"
        case .star: return "like-star"
        case .arrow: return "like-arrow"
        case .cross: return "like-cross"
        }
    }

    /// Loads one glyph's PNG. Mirrors `LoadingMarkAnimationView.loadFrames()`'s existing
    /// `Bundle.module.url(forResource:withExtension:)` + `UIImage(contentsOfFile:)` technique —
    /// NOT `Image(_:bundle:)`, which only resolves asset-catalog entries and fails at runtime
    /// ("No image named … found in asset catalog …") for loose `.process("Resources")`-bundled
    /// PNG files like these (that file's header comment documents this pitfall directly).
    static func glyphImage(for kind: HeartBurstGlyphKind) -> Image {
        let name = Self.glyphImageName(for: kind)
        if let url = Bundle.module.url(forResource: name, withExtension: "png"),
           let uiImage = UIImage(contentsOfFile: url.path) {
            return Image(uiImage: uiImage)
        }
        // Defensive fallback — should be unreachable once the 4 PNGs are correctly bundled
        // under `Resources/LikeBurst/`.
        return Image(systemName: "heart.fill")
    }

    // MARK: - Random variant selection (pure, injectable RNG for tests)

    /// Pure — draws one of 4 glyphs × 3 paths × 3 swings × 2 durations (72 combinations),
    /// uniformly at random, via a caller-supplied generator (unit-test determinism hook).
    static func randomBurstVariant<G: RandomNumberGenerator>(using generator: inout G) -> HeartBurstVariant {
        HeartBurstVariant(
            glyph: HeartBurstGlyphKind.allCases.randomElement(using: &generator) ?? .heart,
            path: HeartBurstPathKind.allCases.randomElement(using: &generator) ?? .rise,
            swing: HeartBurstSwingKind.allCases.randomElement(using: &generator) ?? .symmetric,
            duration: Bool.random(using: &generator) ? Self.flyDurationFast : Self.flyDurationSlow)
    }

    /// Production entry point — uses the system RNG.
    static func randomBurstVariant() -> HeartBurstVariant {
        var rng = SystemRandomNumberGenerator()
        return randomBurstVariant(using: &rng)
    }

    // MARK: - Keyframe tables (pure lookups — no state, no rendering)

    /// Scale keyframes for one flight path (0 / 35% / 80% / 100% of `variant.duration`).
    static func scaleKeyframes(for path: HeartBurstPathKind) -> [HeartBurstKeyframe] {
        switch path {
        case .rise:
            return [.init(time: 0, value: 0.2), .init(time: 0.35, value: 1.2),
                    .init(time: 0.8, value: 0.9), .init(time: 1.0, value: 0.6)]
        case .riseTiltRight:
            return [.init(time: 0, value: 0.4), .init(time: 0.35, value: 1.5),
                    .init(time: 0.8, value: 1.0), .init(time: 1.0, value: 0.4)]
        case .riseTiltLeft:
            return [.init(time: 0, value: 0.6), .init(time: 0.35, value: 1.7),
                    .init(time: 0.8, value: 1.1), .init(time: 1.0, value: 0.7)]
        }
    }

    /// Opacity keyframes — shared shape across all 3 paths (0 → 1 (35%) → 1 (80%) → 0).
    static func opacityKeyframes(for path: HeartBurstPathKind) -> [HeartBurstKeyframe] {
        [.init(time: 0, value: 0), .init(time: 0.35, value: 1),
         .init(time: 0.8, value: 1), .init(time: 1.0, value: 0)]
    }

    /// The fixed rotation (degrees) applied for the WHOLE flight of a given path.
    static func fixedRotationDegrees(for path: HeartBurstPathKind) -> Double {
        switch path {
        case .rise: return 0
        case .riseTiltRight: return 20
        case .riseTiltLeft: return -30
        }
    }

    /// Horizontal swing keyframes (multiplier of `swingAmplitude`) for one swing path.
    static func swingKeyframes(for swing: HeartBurstSwingKind) -> [HeartBurstKeyframe] {
        switch swing {
        case .symmetric:
            return [.init(time: 0, value: 0), .init(time: 0.25, value: -1),
                    .init(time: 0.75, value: 1), .init(time: 1.0, value: 0)]
        case .leftThenSettle:
            return [.init(time: 0, value: 0), .init(time: 0.33, value: -1),
                    .init(time: 1.0, value: 0.5)]
        case .mirrored:
            return [.init(time: 0, value: 0), .init(time: 0.25, value: 1),
                    .init(time: 0.75, value: -1), .init(time: 1.0, value: 0)]
        }
    }

    /// Pure linear interpolation across a keyframe table. `progress` is clamped to `0...1`;
    /// before the first / after the last keyframe returns that endpoint's value.
    static func interpolatedValue(_ progress: Double, in keyframes: [HeartBurstKeyframe]) -> CGFloat {
        guard let first = keyframes.first else { return 0 }
        let clamped = min(max(progress, 0), 1)
        guard clamped > first.time else { return first.value }
        for i in 1..<keyframes.count {
            let previous = keyframes[i - 1]
            let current = keyframes[i]
            if clamped <= current.time {
                let span = current.time - previous.time
                let localT = span > 0 ? (clamped - previous.time) / span : 1
                return previous.value + (current.value - previous.value) * CGFloat(localT)
            }
        }
        return keyframes[keyframes.count - 1].value
    }

    // MARK: - Design tokens

    static let flyDistance: CGFloat = -90                // upward travel (anchor unchanged)
    static let burstLifetime: Double = 2.0                // "2 秒消失" — array cleanup deadline
    static let swingAmplitude: CGFloat = 16               // ±16px 擺動 (design lbp-heart-swing)
    static let flyDurationFast: Double = 0.8              // design 2 speeds
    static let flyDurationSlow: Double = 1.0
}

/// Drives `HeartBurstView`'s single continuous `progress` (0...1) through SwiftUI's own
/// animation engine (via `withAnimation` on the `active` flag), then, on every interpolated
/// frame, maps that scalar into scale / opacity / rotation / horizontal-swing / vertical-rise
/// using the PURE keyframe tables above. iOS-13-safe (`AnimatableModifier` predates iOS 14).
private struct HeartBurstKeyframeModifier: AnimatableModifier {
    var progress: Double
    let variant: HeartBurstVariant
    let swingAmplitude: CGFloat
    let flyDistance: CGFloat

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let scale = HeartBurstView.interpolatedValue(progress, in: HeartBurstView.scaleKeyframes(for: variant.path))
        let opacity = HeartBurstView.interpolatedValue(progress, in: HeartBurstView.opacityKeyframes(for: variant.path))
        let swingMultiplier = HeartBurstView.interpolatedValue(progress, in: HeartBurstView.swingKeyframes(for: variant.swing))
        content
            .scaleEffect(scale)
            .opacity(Double(opacity))
            .rotationEffect(.degrees(HeartBurstView.fixedRotationDegrees(for: variant.path)))
            .offset(x: swingMultiplier * swingAmplitude, y: CGFloat(progress) * flyDistance)
    }
}
