import SwiftUI

// MARK: - PlaybackProgressBarView — VOD / replay playback-progress transport bar
//
// Spec: `reference-ui-rendering/spec.md` "LivebuyReferenceUI 渲染 VOD/回放播放進度條
//   （PlaybackProgressBarView）"
// Design: Claude Design「LiveBuy SDK Design Canvas」`screens.jsx` `LBPPlayerScreen`
//   "Playback progress bar — VOD and replay only" block.
// Change: rb-ios-restore-vod-playback-progress-bar (SUPERSEDES rb-ios-retire-vod-progress-bar,
//   2026-06-10 — product now wants the bar back, covering both pure VOD and a finished-live
//   replay `model.isFinishedLiveReplay`). It is composed by `PlayerShellView`, which decides
//   WHICH state feeds it — this view itself has no opinion on live-vs-replay semantics.
//
// Two visual states, ONE structurally-stable gesture-carrying track view:
//   - IDLE (not scrubbing): a 2pt thin line pinned to the bottom edge, with an invisible ~20pt
//     hit-area so a tap/press anywhere in that strip (not just exactly on the 2pt line) starts
//     a scrub.
//   - EXPANDED (touch-down through 2.8s after release): a full transport bar — a play/pause
//     button (a SEPARATE sibling, only present while expanded) + the SAME track view, now taller
//     with a white handle. While the finger is actually down (`isScrubbing`) a centered
//     `HH:MM:SS / HH:MM:SS` timestamp readout floats above the bar; it disappears the instant
//     the finger lifts even though the bar itself stays expanded for the remainder of the 2.8s
//     hold (`PlayerShellView` owns that timer — see its `isScrubbing` vs `scrubBarExpanded`
//     `@State`).
//
// GESTURE CONTINUITY: the track view (`trackAndFill`) is NEVER itself wrapped in an `if/else`
// that swaps it for a different view when `isExpanded` flips — SwiftUI drops an in-flight touch
// when the view instance under the finger is removed from the hierarchy. Only its VISUAL styling
// (height / background opacity / handle presence) reacts to `isExpanded`; the play/pause button
// is a separate sibling that only APPEARS when expanded (adding a new sibling does not disturb
// the track's already-active gesture).
//
// SNAPSHOT-SAFE: the track measures its own width via a SYNCHRONOUS `.overlay(GeometryReader {
// proxy in … })` attached to a base view whose OWN size is set by ordinary `.frame(...)`
// modifiers (never derived FROM the GeometryReader) — proven safe by
// `PlayerHeaderBarView.titleView` (reads `proxy.size` in the SAME render pass, no `@State` round
// trip). `NowIntroducingCarouselView` documents that `GeometryReader` used as the PRIMARY sizing
// container renders BLANK through the `ImageRenderer` snapshot path — avoided here by keeping
// the base view's size independent of the reader.
//
// One-way data flow: this view reads ONLY its passed-in snapshot values and calls ONLY the
// action closures it is given (which `PlayerShellView` wires to `PlayerShellModel`'s EXISTING
// `togglePlayPause()` / `seek(to:)` forwarders — no new core / view-model API).
//
// iOS-14-safe: `ZStack` / `VStack` / `HStack` / `DragGesture` / `GeometryReader` / `Capsule` /
// `Circle` are all iOS-13+.

/// The VOD / replay playback-progress transport bar. `PlayerShellView` composes this as a
/// top-level `ZStack` sibling (over BOTH the VOD chrome and the LIVE-chrome-family branch),
/// gated on `showsPlaybackProgressBar`.
public struct PlaybackProgressBarView: View {

    /// The resolved reference-ui theme (first positional argument, always).
    public let theme: ReferenceUITheme

    /// Current playhead, seconds. Ignored for the fill/readout while dragging (the drag uses its
    /// own local live ratio instead — see `dragRatio` below).
    public let position: Double

    /// Total duration, seconds.
    public let duration: Double

    /// Whether the stream is currently playing — drives the play/pause button's icon.
    public let isPlaying: Bool

    /// `true` while the finger is actually down (touch-down…touch-up). Drives: the centered
    /// timestamp readout, and (via the caller) which other chrome is hidden. Distinct from
    /// `isExpanded` — the transport-bar visual stays expanded ~2.8s LONGER than this.
    public let isScrubbing: Bool

    /// `true` from touch-down through the 2.8s post-release hold. Drives the thin-line vs
    /// full-transport-bar visual. `PlayerShellView` owns the hold timer.
    public let isExpanded: Bool

    /// Play/pause button tap → host-wired `model.togglePlayPause()`. nil → inert (demo/snapshot).
    private let onTogglePlayPause: (() -> Void)?

    /// Touch-down on the track → host reports scrub start. nil → inert.
    private let onScrubStarted: (() -> Void)?

    /// Drag moved → the new ratio `[0, 1]`. Host forwards to `model.seek(to: ratio * duration)`.
    /// nil → inert (demo / snapshot; the visual still tracks locally via `dragRatio`).
    private let onScrub: ((Double) -> Void)?

    /// Finger lifted → host reports scrub end (starts the 2.8s hold timer). nil → inert.
    private let onScrubEnded: (() -> Void)?

    /// Local, optimistic drag ratio `[0, 1]` — non-nil only while a live drag gesture is being
    /// tracked by THIS view. Used for both the track fill and the timestamp readout so both
    /// track the finger with zero jitter, independent of the async `position` round-trip through
    /// core's `onPlaybackProgressChange` (mirrors the design's own local `progress *
    /// TOTAL_DURATION_SEC` formula).
    @State private var dragRatio: Double?

    public init(theme: ReferenceUITheme,
                position: Double,
                duration: Double,
                isPlaying: Bool,
                isScrubbing: Bool,
                isExpanded: Bool,
                onTogglePlayPause: (() -> Void)? = nil,
                onScrubStarted: (() -> Void)? = nil,
                onScrub: ((Double) -> Void)? = nil,
                onScrubEnded: (() -> Void)? = nil) {
        self.theme = theme
        self.position = position
        self.duration = duration
        self.isPlaying = isPlaying
        self.isScrubbing = isScrubbing
        self.isExpanded = isExpanded
        self.onTogglePlayPause = onTogglePlayPause
        self.onScrubStarted = onScrubStarted
        self.onScrub = onScrub
        self.onScrubEnded = onScrubEnded
    }

    public var body: some View {
        VStack(spacing: Self.readoutSpacing) {
            if isScrubbing {
                timestampReadout
            }
            HStack(spacing: Self.transportSpacing) {
                if isExpanded {
                    playPauseButton
                }
                trackAndFill
            }
            .padding(.horizontal, isExpanded ? Self.transportHorizontalPadding : 0)
        }
        // rb-ios-intro-progress-bar-followup-fix: this is now a DEFENSIVE FALLBACK only — the
        // MAIN reset path is `endScrub()` (fires synchronously on `DragGesture.onEnded`,
        // independent of `isExpanded`; see below). This `.onChange` still matters for the one
        // case `endScrub()` cannot cover: a scrub interrupted by the app backgrounding (incl.
        // auto-PiP) delivers `touchesCancelled`, which `DragGesture` has no callback for at all —
        // `PlayerShellView.handleDidEnterBackground()` ends the scrub by changing the
        // `isScrubbing`/`isExpanded` PROPS fed into a new render of this view, never by invoking
        // this view's own gesture closures. Both resets are idempotent no-ops once `dragRatio`
        // is already `nil`, so they safely coexist (see design.md D1).
        .onChange(of: isExpanded) { expanded in
            if !expanded { dragRatio = nil }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(LBAccessibilityID.playbackProgressBar)
    }

    // MARK: - Play/pause button (separate sibling — only present while expanded)

    private var playPauseButton: some View {
        Button(action: { onTogglePlayPause?() }) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: Self.playPauseIconSize, weight: .bold))
                .foregroundColor(.white)
                .frame(width: Self.playPauseButtonSize, height: Self.playPauseButtonSize)
        }
        .buttonStyle(PlainButtonStyle())
        // rb-ios-intro-progress-bar-followup-fix: enlarge the tap target without touching any
        // rendered pixel — same `.contentShape(Rectangle().inset(by: -N))` pattern already used
        // elsewhere in this module (WinClaimModalView / NowIntroducingCarouselView /
        // LiveOverlayChromeView). `N` (`playPauseHitAreaExpansion`) is kept < `transportSpacing`
        // (see that token's doc comment) so the expanded hit-rect cannot reach into
        // `trackAndFill`'s own (unexpanded) `contentShape`.
        .contentShape(Rectangle().inset(by: -Self.playPauseHitAreaExpansion))
        .accessibilityIdentifier(LBAccessibilityID.playbackProgressPlayPause)
    }

    // MARK: - Track (structurally stable across idle ⇄ expanded — see file header)

    /// The track: a base `Color.clear` whose height is set EXPLICITLY (never derived from a
    /// `GeometryReader`), overlaid with the visual thin line and a synchronous
    /// `GeometryReader`-driven fill/handle + drag gesture. This is the ONE view instance that
    /// exists in BOTH the idle and expanded states — never swapped away — so an in-flight touch
    /// survives the idle→expanded transition.
    private var trackAndFill: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: isExpanded ? max(Self.trackHeight, Self.handleSize) : Self.hitAreaHeight)
            .overlay(
                Capsule()
                    .fill(Color.white.opacity(isExpanded ? Self.expandedTrackBackgroundOpacity : Self.trackBackgroundOpacity))
                    .frame(height: isExpanded ? Self.trackHeight : Self.idleLineHeight),
                // rb-ios-playback-progress-bar-bottom-flush-fix: idle SHALL sit flush against the
                // bottom edge of the 20pt hit-area, not centered (SwiftUI's `.overlay` default).
                // Expanded keeps the pre-existing `.center` explicitly unchanged — here the
                // capsule (trackHeight, 3pt) genuinely is smaller than the outer frame
                // (max(trackHeight, handleSize), 14pt), so alignment is NOT a no-op in that
                // state; we deliberately preserve `.center` (the old implicit default) rather
                // than also flipping it to `.bottom`, since only the IDLE state has the
                // documented gap.
                alignment: isExpanded ? .center : .bottom
            )
            .overlay(trackGestureOverlay)
            .accessibilityIdentifier(LBAccessibilityID.playbackProgressTrack)
    }

    /// Reads the track's proposed size SYNCHRONOUSLY (same render pass — see file header) to
    /// draw the fill + handle and to attach the ONE drag gesture. `proxy.size` here equals the
    /// base `Color.clear`'s resolved size (full width, the explicit idle/expanded height).
    private var trackGestureOverlay: some View {
        GeometryReader { proxy in
            let trackWidth = proxy.size.width
            let ratio = dragRatio ?? Self.progressRatio(position: position, duration: duration)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white)
                    .frame(width: trackWidth * CGFloat(ratio),
                           height: isExpanded ? Self.trackHeight : Self.idleLineHeight)
                if isExpanded {
                    Circle()
                        .fill(Color.white)
                        .frame(width: Self.handleSize, height: Self.handleSize)
                        .shadow(color: Color.black.opacity(0.4), radius: 3, x: 0, y: 1)
                        .offset(x: trackWidth * CGFloat(ratio) - Self.handleSize / 2)
                }
            }
            // rb-ios-playback-progress-bar-bottom-flush-fix: this positions the ACTUAL VISIBLE
            // white fill (+ handle, when expanded) — the background capsule above is only the
            // translucent track behind it. Idle SHALL be flush against the bottom of the 20pt
            // hit-area (`.bottomLeading` = horizontal-leading unchanged + vertical-bottom), not
            // vertical-centered (the old hardcoded `.leading` = horizontal-leading +
            // vertical-CENTER). Expanded keeps `.leading` unchanged — the ZStack's natural
            // height there already equals `proxy.size.height` (both driven by
            // max(trackHeight, handleSize)), so the alignment choice cannot move any pixel.
            .frame(width: trackWidth, height: proxy.size.height,
                   alignment: isExpanded ? .leading : .bottomLeading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragRatio == nil { beginScrub() }
                        let newRatio = Self.dragRatio(offsetX: value.location.x, trackWidth: trackWidth)
                        dragRatio = newRatio
                        onScrub?(newRatio)
                    }
                    .onEnded { _ in endScrub() }
            )
        }
    }

    // MARK: - Drag-time timestamp readout

    private var timestampReadout: some View {
        let ratio = dragRatio ?? Self.progressRatio(position: position, duration: duration)
        let currentSeconds = ratio * max(duration, 0)
        return Text("\(Self.formatTimestamp(currentSeconds)) / \(Self.formatTimestamp(duration))")
            .font(.system(size: Self.readoutFontSize, weight: .bold))
            .foregroundColor(.white)
            .shadow(color: Color.black.opacity(0.6), radius: 3, x: 0, y: 1)
            .allowsHitTesting(false)
            .accessibilityIdentifier(LBAccessibilityID.playbackProgressReadout)
    }

    // MARK: - Scrub lifecycle helpers

    private func beginScrub() {
        dragRatio = Self.progressRatio(position: position, duration: duration)
        onScrubStarted?()
    }

    /// (default) internal, not `private` — a test can call this directly on a freshly-constructed
    /// struct value to prove the SYNCHRONOUS, state-independent side effect it still has (invoking
    /// `onScrubEnded?()` — a plain closure capture, reliable to observe regardless of view
    /// installation). The `dragRatio = nil` reset itself, below, is NOT independently testable
    /// this way: SwiftUI's `@State` on a struct value that was never installed into a live view
    /// hierarchy behaves as a constant binding fixed to its `init`-time value — writes attempted
    /// before installation are silently discarded (confirmed empirically while authoring this fix:
    /// both a raw post-call property read AND a render-after-the-call pixel comparison failed to
    /// observe the mutation, on a value that was never installed). This is the same class of gap
    /// `PlayerShellScrubBackgroundResetTests.swift` documents for its own async `.onReceive` path;
    /// this reset is verified the same way that file's boundary note describes: source inspection
    /// (see below) + successful build + the full existing `LivebuyReferenceUITests` suite passing
    /// byte-identical (this component's rendering output for every EXISTING call shape is
    /// unchanged — only a new, real-device-only interactive path is added).
    ///
    /// rb-ios-intro-progress-bar-followup-fix: resets `dragRatio` to `nil` FIRST — this is the
    /// MAIN reset path (fires on every normal finger-lift, independent of `isExpanded`). Fixes
    /// the intro/clean-mode caller (`StartScreenView`), which hardcodes `isExpanded: true` (no
    /// "collapsed thin-line" concept during intro playback), so the OTHER reset mechanism
    /// (`.onChange(of: isExpanded)`, kept below in `body` as a defensive fallback for the
    /// backgrounding-interruption path — see its comment) never used to fire there, permanently
    /// pinning `dragRatio` after the user's first drag.
    func endScrub() {
        dragRatio = nil
        onScrubEnded?()
    }

    // MARK: - Design tokens

    static let idleLineHeight: CGFloat = 2
    static let hitAreaHeight: CGFloat = 20
    static let trackBackgroundOpacity: Double = 0.28

    static let transportSpacing: CGFloat = 10
    static let transportHorizontalPadding: CGFloat = 12
    static let playPauseButtonSize: CGFloat = 28
    static let playPauseIconSize: CGFloat = 14
    /// rb-ios-intro-progress-bar-followup-fix: how far `playPauseButton`'s tap target expands
    /// outward on all 4 edges beyond its visual `playPauseButtonSize` frame. MUST stay strictly
    /// less than `transportSpacing` (10pt at the time this was measured — re-check the live
    /// value if it has since changed) so the expanded hit-rect never reaches `trackAndFill`'s own
    /// (unexpanded) `contentShape`, which begins exactly at the end of that gap. `4` leaves a 6pt
    /// buffer before the track's hit area (verified via `PlaybackProgressBarDragResetFollowupTests`).
    static let playPauseHitAreaExpansion: CGFloat = 4
    static let trackHeight: CGFloat = 3
    static let expandedTrackBackgroundOpacity: Double = 0.35
    static let handleSize: CGFloat = 14

    static let readoutSpacing: CGFloat = 6
    static let readoutFontSize: CGFloat = 18

    // MARK: - Pure functions (unit-testable, docs/unit-test-discipline.md)

    /// The idle-line / track fill ratio `[0, 1]`. `duration` non-finite or `<= 0` → `0` (no
    /// timeline to show a ratio of). Pure.
    static func progressRatio(position: Double, duration: Double) -> Double {
        guard duration.isFinite, duration > 0, position.isFinite else { return 0 }
        return min(max(position / duration, 0), 1)
    }

    /// The live drag ratio `[0, 1]` from a horizontal touch offset within a track of the given
    /// width. `trackWidth <= 0` → `0` (nothing to divide by). Pure.
    static func dragRatio(offsetX: CGFloat, trackWidth: CGFloat) -> Double {
        guard trackWidth > 0 else { return 0 }
        return min(max(Double(offsetX / trackWidth), 0), 1)
    }

    /// Format a seconds count as a FIXED 3-segment, zero-padded `HH:MM:SS` — the hour segment is
    /// ALWAYS shown, even when it is `00` (unlike a typical player's "drop the hour under 1h"
    /// convention). Negative / non-finite input clamps to `0`. Pure.
    static func formatTimestamp(_ totalSeconds: Double) -> String {
        let clamped = totalSeconds.isFinite ? max(0, totalSeconds) : 0
        let total = Int(clamped.rounded())
        let hh = total / 3600
        let mm = (total % 3600) / 60
        let ss = total % 60
        return String(format: "%02d:%02d:%02d", hh, mm, ss)
    }
}
