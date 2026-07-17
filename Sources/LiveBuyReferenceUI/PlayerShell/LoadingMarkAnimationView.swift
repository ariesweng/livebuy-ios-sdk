import SwiftUI
import UIKit
import Foundation

// MARK: - LoadingMarkAnimationView — iOS `.loading` brand PNG-sequence loader
//
// Spec: `reference-ui-rendering/spec.md`
//   § "iOS reference-ui `.loading` 品牌動畫改用 PNG 序列幀播放"
// Design: `rb-ios-loading-mark-png-sequence` design.md 決策 1-4 (決策 1 corrected
//   during apply — see note below).
// Change: rb-ios-loading-mark-png-sequence.
//
// Plays the 17-frame brand loading-mark PNG sequence (500×500 RGBA, losslessly
// extracted from `design/brands/livebuy/assets/livebuy-loading.webp`): the "!"
// mark growing in, combined with the "L" mark's 3D flip. Replaces the generic
// procedural `StartScreenView.spinnerRing()` call in `.loading`'s `loadingScreen`.
//
// Timeline (decision-locked, matches the original webp extraction): frame 0 →
// 68ms, frames 1-15 → 34ms each, frame 16 → 476ms hold. Total loop 1054ms, then
// repeats from frame 0.
//
// TIMING MECHANISM — corrected from design.md decision 1 during apply:
// design.md originally picked `TimelineView(.animation)`, but that API is
// iOS-15+-only and this package's floor is iOS 14 (`Package.swift`:
// `platforms: [.iOS(.v14)]`; CLAUDE.md "ios/ Swift Package (iOS 14+)"). This exact
// file family already holds that floor deliberately elsewhere — see
// `RemoteStillImageView` (`CarouselCardView.swift`), which explicitly avoids
// `AsyncImage` (also iOS 15+) for the identical reason. `xcodebuild test` caught
// the `TimelineView` availability error at apply time. Fixed by driving the frame
// clock with `Timer.scheduledTimer` + `@State`, scoped to `.onAppear`/`.onDisappear`
// (mirrors the existing `refreshTimer` precedent in `LivebuyWidget.swift`) and added
// to the run loop's `.common` mode so it keeps ticking during scroll/gesture
// tracking. This is exactly the alternative design.md's decision 1 had (incorrectly)
// rejected — the rejection's premise (no compatibility cost either way) didn't hold.
// The pure `frameIndex(elapsed:)` function below is UNCHANGED from the original
// decision: independently unit-testable, no live View required.
//
// All 17 frames are preloaded into an array at `init` — not lazily decoded per
// frame (design.md 決策 2; ~17MB unpacked, released with the rest of this View when
// `.loading` phase exits and it leaves the view tree).
struct LoadingMarkAnimationView: View {

    /// All 17 frames, preloaded once (design.md 決策 2 — no lazy / on-demand
    /// per-frame decode). Loaded via `Bundle.module.url(forResource:withExtension:)`
    /// + `UIImage(contentsOfFile:)` — NOT `Image(_:bundle:)`, which only resolves
    /// asset-catalog entries and fails at runtime ("No image named … found in asset
    /// catalog …") for loose `.process("Resources")`-bundled PNG files like these
    /// (caught by the `.loading` snapshot test at apply time).
    private let frames: [Image] = LoadingMarkAnimationView.loadFrames()

    private static func loadFrames() -> [Image] {
        (0..<frameCount).map { index in
            let name = String(format: "frame_%02d", index)
            if let url = Bundle.module.url(forResource: name, withExtension: "png"),
               let uiImage = UIImage(contentsOfFile: url.path) {
                return Image(uiImage: uiImage)
            }
            // Defensive fallback — should be unreachable once the 17 PNGs are
            // correctly bundled under `Resources/LoadingMark/`.
            return Image(systemName: "circle")
        }
    }

    /// The frame currently displayed. Driven by `timer` below; only reassigned when
    /// the computed index actually changes (avoids redundant view invalidations).
    @State private var currentIndex = 0

    /// The active frame-clock timer, owned for the lifetime this view is on-screen.
    /// `nil` while off-screen — started in `.onAppear`, invalidated in `.onDisappear`
    /// (mirrors `LivebuyWidget.swift`'s `refreshTimer` start/stop lifecycle).
    @State private var timer: Timer?

    var body: some View {
        frames[currentIndex]
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: Self.frameSize, height: Self.frameSize)
            .onAppear(perform: startTicking)
            .onDisappear(perform: stopTicking)
    }

    /// Starts the frame clock: anchors `start` at the current time (so `frameIndex`
    /// sees elapsed-since-appeared, not elapsed-since-epoch), snaps immediately to
    /// frame 0, then polls at `Self.tickIntervalSeconds` — comfortably oversampling
    /// the shortest 34ms frame window so no frame is silently skipped under normal
    /// conditions. Idempotent (guards against a second timer if called twice).
    private func startTicking() {
        guard timer == nil else { return }
        currentIndex = 0
        let start = Date()
        let newTimer = Timer(timeInterval: Self.tickIntervalSeconds, repeats: true) { _ in
            let elapsed = Date().timeIntervalSince(start)
            let index = Self.frameIndex(elapsed: elapsed)
            if index != currentIndex {
                currentIndex = index
            }
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    /// Stops and releases the frame clock when this view leaves the tree (`.loading`
    /// phase exit) — no dangling `Timer` keeps firing off-screen.
    private func stopTicking() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Pure frame-index function (unit-tested independently of the View)

    /// Maps elapsed time (seconds, since the animation loop started) to the frame
    /// index (`0...16`) that MUST be displayed, per the locked timeline: frame 0 →
    /// 68ms, frames 1-15 → 34ms each, frame 16 → 476ms hold, total loop 1054ms —
    /// then wraps back to frame 0 (e.g. `elapsed = 1.054 + 0.017` MUST equal
    /// `elapsed = 0.017`). Negative `elapsed` also wraps (defensive; not expected
    /// from the monotonic `Date()` reads driving this view).
    static func frameIndex(elapsed: TimeInterval) -> Int {
        let elapsedMs = elapsed * 1_000
        var t = elapsedMs.truncatingRemainder(dividingBy: totalLoopMs)
        if t < 0 { t += totalLoopMs }

        if t < frame0DurationMs {
            return 0
        }
        let afterFrame0 = t - frame0DurationMs
        let midFramesTotalMs = midFrameDurationMs * Double(midFrameCount)
        if afterFrame0 < midFramesTotalMs {
            let offset = Int(afterFrame0 / midFrameDurationMs)
            return 1 + min(offset, midFrameCount - 1)
        }
        return frameCount - 1
    }

    // MARK: - Timeline tokens (locked — matches the original `livebuy-loading.webp`
    //         extraction; see design.md Context)

    static let frameCount = 17
    static let frame0DurationMs: Double = 68
    static let midFrameDurationMs: Double = 34
    static let midFrameCount = 15   // frames 1-15
    static let lastFrameHoldMs: Double = 476
    static let totalLoopMs: Double =
        frame0DurationMs + midFrameDurationMs * Double(midFrameCount) + lastFrameHoldMs

    /// Frame-clock poll interval — ~60Hz, well under the shortest (34ms) frame
    /// window so no frame is silently skipped under normal conditions.
    static let tickIntervalSeconds: TimeInterval = 1.0 / 60.0

    /// Rendered size — matches the `spinnerRing()` call site it replaces
    /// (`StartScreenView.loadingSpinnerSize`, 76pt).
    static let frameSize: CGFloat = 76
}

// MARK: - Preview (deterministic first frame — SwiftUI previews don't animate)

#if DEBUG
struct LoadingMarkAnimationView_Previews: PreviewProvider {
    static var previews: some View {
        LoadingMarkAnimationView()
            .frame(width: 76, height: 76)
            .background(Color.black)
            .previewLayout(.sizeThatFits)
    }
}
#endif
