import SwiftUI
import LiveBuySDK
import LiveBuyUI

// MARK: - LiveBuyPlayerPresenter — collapsible player presentation convenience
//
// Spec: `reference-ui-rendering/spec.md`
//   § "LiveBuyReferenceUI 提供 collapsible 播放器 presenter（一行 sheet + minimize→懸浮預覽）".
//
// `LiveBuyPlayer` is a `UIViewControllerRepresentable` — the host decides HOW it is
// presented, so the container cannot own the minimize→floating-preview collapse (it can
// neither dismiss its presenter nor raise a sibling overlay in the host's tree). That is
// why `LiveBuyPlayer.onMinimize` defaults to the core `player.minimize()` seam and each
// host re-implements the in-app floating preview itself.
//
// This modifier PROMOTES that wiring into the package: `someHostView.liveBuyPlayer(video:
// $presented)` gives a host a full-screen turnkey player that collapses to a bottom-right
// `FloatingWidgetView` on minimize — in ONE line. It composes ONLY existing pieces
// (`LiveBuyPlayer` + the family-5 `FloatingWidgetView`); it adds NO view-model, NO pixels,
// and does NOT change `LiveBuyPlayer`. Dependency direction stays one-way
// `reference-ui → template → core`.

/// The presentation phase of a collapsible player, derived purely from the host binding +
/// the minimized flag (extracted for unit testing — internal-testability).
public enum CollapsiblePlayerPhase: Equatable {
    /// No session (`video == nil`).
    case closed
    /// Full-screen player presented.
    case full
    /// Collapsed to the bottom-right floating preview.
    case floating
}

/// Pure phase derivation: no video → closed; minimized → floating; else full. The SwiftUI
/// wiring is a thin shell around this so the state logic is deterministically testable.
public func collapsiblePhase(hasVideo: Bool, isMinimized: Bool) -> CollapsiblePlayerPhase {
    guard hasVideo else { return .closed }
    return isMinimized ? .floating : .full
}

/// Whether a change of the bound video's id should auto-restore the full-screen player.
/// True ONLY when a new (non-nil) video arrives while the presenter is currently minimized
/// (collapsed to the floating preview) — i.e. the host swapped in another video (tapping a
/// different carousel card) and we must close the floating card and re-present full-screen.
/// Restoring from the floating card keeps the SAME id (it only flips `isMinimized`), so that
/// path returns false here. First open (nil→id while not minimized), close (id→nil), and a
/// swap while already full-screen all return false (no action needed). Pure for unit testing
/// (internal-testability).
public func shouldReopenOnVideoChange(newVideoId: String?, isMinimized: Bool) -> Bool {
    newVideoId != nil && isMinimized
}

/// Clamp the floating preview card's committed-plus-live drag offset so the card can be
/// dragged to reposition but never pushed off-screen. The card is anchored bottom-right
/// (`alignment: .bottomTrailing` + `bottomTrailingInset` padding), so its resting offset is
/// `.zero`: it cannot move further right / down (that would go off-screen → upper bound 0),
/// and it can move left / up only until the card's far edge reaches the opposite inset
/// (lower bound, negative). Extracted as a pure function (internal-testability) so the drag
/// bounds are unit-testable without UIKit gesture plumbing.
///
/// - Parameters:
///   - committed: the already-accumulated offset (committed on the previous drag end).
///   - translation: the live drag translation being applied this gesture.
///   - cardSize: the floating card's rendered size.
///   - containerSize: the presenter overlay container's size.
///   - inset: the bottom-trailing resting padding (matches the overlay padding).
/// - Returns: the clamped `committed + translation` offset.
public func clampFloatingOffset(
    committed: CGSize,
    translation: CGSize,
    cardSize: CGSize,
    containerSize: CGSize,
    inset: CGSize
) -> CGSize {
    let desiredX = committed.width + translation.width
    let desiredY = committed.height + translation.height

    // Anchored bottom-right: x/y == 0 is the resting position (hard upper bound — can't go
    // further off the right/bottom edge). The most-negative offset keeps the card's far
    // (left/top) edge inside the container: the card occupies `cardSize` plus `inset` from
    // the right/bottom, so it can travel left/up by `containerSize - cardSize - inset`.
    let minX = min(0, -(containerSize.width - cardSize.width - inset.width))
    let minY = min(0, -(containerSize.height - cardSize.height - inset.height))

    let clampedX = max(minX, min(0, desiredX))
    let clampedY = max(minY, min(0, desiredY))
    return CGSize(width: clampedX, height: clampedY)
}

/// Presents the turnkey `LiveBuyPlayer` full-screen for the bound `video`, with a built-in
/// minimize→bottom-right floating preview. Attach with `View.liveBuyPlayer(video:…)`.
public struct LiveBuyPlayerPresenter: ViewModifier {

    /// The host's session source of truth: non-nil → present; nil → fully closed. The
    /// `LBVideoItem` provides `id` (for `load`) AND `cover`/`preview` (for the floating
    /// card thumbnail). A host with only an id passes `LBVideoItem.demo(id:live:true)`.
    @Binding var video: LBVideoItem?

    /// The host's player config. The presenter OWNS `onMinimize` / `onDismiss` (the
    /// collapse / clear); every other seam (`eventListener` / `onProductTap` / `onShare` /
    /// `onOpenProductList` / `onComment` …) passes through unchanged.
    let config: LiveBuyPlayerConfig

    /// Optional theme override for the floating card. nil → resolve via the same
    /// `sdkConfig.theme > host options > minimal palette` order `LiveBuyPlayer` uses.
    let themeOverride: ReferenceUITheme?

    /// Full vs floating. `video == nil` is fully closed (this flag is only meaningful while
    /// a session exists). Reset on close.
    @State private var isMinimized: Bool = false

    /// The accumulated drag offset of the floating preview, committed on each drag end.
    /// `.zero` is the bottom-right resting position. Reset on close (so the next session
    /// re-opens at the default corner).
    @State private var committedOffset: CGSize = .zero

    /// The live drag translation while a drag is in progress (added to `committedOffset`).
    /// Reset to `.zero` on drag end (after committing into `committedOffset`).
    @State private var dragTranslation: CGSize = .zero

    /// The measured floating card size (from the card's own geometry), used to clamp the
    /// drag offset so the card can't be dragged fully off-screen. nil until first measured.
    @State private var floatingCardSize: CGSize = .zero

    public func body(content: Content) -> some View {
        content
            // KEEP-ALIVE full player overlay (issue 5): the player is composed as a PERSISTENT
            // full-bleed overlay (NOT a `fullScreenCover`). It stays MOUNTED the whole time a
            // session exists (`video != nil`); minimize only HIDES it (opacity 0 + no hit-testing)
            // behind the floating preview card. Because the mounted `LiveBuyPlayer.videoId` does
            // not change across minimize/restore, SwiftUI never rebuilds the player VC — so
            // playback CONTINUES while minimized and tapping the card to restore is an instant
            // RESUME, not a fresh `load`. (The prior `fullScreenCover` dismissed on minimize,
            // releasing the VC and restarting playback on restore.)
            .overlay(playerLayer)
            // Bottom-right floating preview while minimized. A full-bleed `GeometryReader`
            // layer anchors the card bottom-right and applies the (clamped) drag offset, so
            // the user can drag it anywhere on screen. iOS-14-safe overlay form.
            .overlay(floatingPreviewLayer)
            // A newly-bound video (different id) while minimized → close the floating preview
            // and re-present full-screen for the new video (e.g. tapping another carousel
            // card). Tapping the floating card to RESTORE keeps the same id (it only flips
            // `isMinimized` via the card's own onTap), so it never trips this. Reset the drag
            // offset so the new video re-minimizes at the default corner.
            .onChange(of: video?.id) { newId in
                if shouldReopenOnVideoChange(newVideoId: newId, isMinimized: isMinimized) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        isMinimized = false
                    }
                    committedOffset = .zero
                    dragTranslation = .zero
                }
            }
    }

    /// The KEEP-ALIVE full player overlay (issue 5). Mounted whenever a session exists
    /// (`video != nil`) — it is NOT torn down on minimize (that was the `fullScreenCover`
    /// teardown that restarted playback). Minimize only hides it: `opacity 0` (invisible behind
    /// the floating card) + `allowsHitTesting(false)` (so the host content behind stays
    /// interactive). Because the mounted `LiveBuyPlayer.videoId` is unchanged across
    /// minimize/restore, SwiftUI keeps the SAME player VC alive → playback continues and restore
    /// is a resume. A new bound video id (auto-restore) still drives an in-place `load`.
    @ViewBuilder
    private var playerLayer: some View {
        if let v = video {
            LiveBuyPlayer(videoId: v.id, config: composedConfig)
                .ignoresSafeArea()
                .opacity(isMinimized ? 0 : 1)
                .allowsHitTesting(!isMinimized)
        }
    }

    /// The host config with `onMinimize` / `onDismiss` taken over by the presenter; all
    /// other seams pass through.
    private var composedConfig: LiveBuyPlayerConfig {
        var c = config
        // Minimize → collapse to the floating preview (dismiss full, keep the session).
        c.onMinimize = {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { isMinimized = true }
        }
        // Fatal moment dismiss (end-screen close / unrecoverable error close) → close all.
        // Reset the floating drag offset so the next session re-opens at the default corner.
        c.onDismiss = { _ in
            video = nil
            isMinimized = false
            committedOffset = .zero
            dragTranslation = .zero
        }
        return c
    }

    /// Resting bottom-right padding of the floating card (matches the historical anchor —
    /// keeps the default position pixel-identical so snapshot baselines are unchanged).
    private static let floatingInset = CGSize(width: 12, height: 24)

    /// Full-bleed layer that anchors the floating preview card bottom-right and applies the
    /// (clamped) drag offset. A `GeometryReader` provides the container size for clamping.
    @ViewBuilder
    private var floatingPreviewLayer: some View {
        if isMinimized, let v = video {
            GeometryReader { geo in
                floatingCard(v)
                    .offset(
                        x: committedOffset.width + dragTranslation.width,
                        y: committedOffset.height + dragTranslation.height)
                    // Anchor the card bottom-right; the offset moves it from that resting spot.
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    // `.highPriorityGesture` (NOT `.simultaneousGesture`): once the drag is
                    // RECOGNIZED (movement ≥ `minimumDistance: 8`) it OWNS the touch sequence, so
                    // releasing after a reposition does NOT also fire the card's restore tap / the
                    // close button (issue 4: drag used to trigger the tap). A sub-threshold touch
                    // (< 8pt) fails the drag and falls through to the card's tap (restore) / close —
                    // so taps still work, the drag just no longer leaks into them.
                    .highPriorityGesture(dragGesture(containerSize: geo.size))
            }
        }
    }

    /// The minimized floating preview card itself, composed via the design (default
    /// `MinimalDesign` → `FloatingWidgetView`), reusing the SAME design as the full-screen
    /// player (`config.design`, passed through by `composedConfig`) so the card matches.
    /// Measures its own size into `floatingCardSize` (for drag clamping).
    private func floatingCard(_ v: LBVideoItem) -> some View {
        let context = FloatingCardContext(
            video: v,
            theme: resolvedTheme,
            live: true,
            onTap: { _ in
                // Restore the full player (re-presents → a fresh load, like a sheet
                // re-present; the floating card is a minimized representation, not PiP).
                withAnimation { isMinimized = false }
            },
            onClose: {
                // Close everything.
                withAnimation {
                    isMinimized = false
                    video = nil
                    committedOffset = .zero
                    dragTranslation = .zero
                }
            })
        return config.design.floatingPlayerCard(context)
            .padding(.trailing, Self.floatingInset.width)
            .padding(.bottom, Self.floatingInset.height)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: FloatingCardSizeKey.self, value: proxy.size)
                })
            .onPreferenceChange(FloatingCardSizeKey.self) { floatingCardSize = $0 }
            .transition(.scale.combined(with: .opacity))
    }

    /// Drag-to-reposition gesture for the floating card. A non-zero `minimumDistance` keeps
    /// short touches as taps (tap → restore; the close button → close), so dragging does NOT
    /// swallow the card's own `Button` interactions (attached via `.simultaneousGesture`).
    /// On end the accumulated offset is clamped so the card stays on-screen.
    private func dragGesture(containerSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                dragTranslation = value.translation
            }
            .onEnded { value in
                committedOffset = clampFloatingOffset(
                    committed: committedOffset,
                    translation: value.translation,
                    cardSize: floatingCardSize,
                    containerSize: containerSize,
                    inset: Self.floatingInset)
                dragTranslation = .zero
            }
    }

    /// The floating card's theme: the explicit override, else the resolved
    /// `sdkConfig.theme > host options > minimal palette` (same resolver `LiveBuyPlayer` uses).
    private var resolvedTheme: ReferenceUITheme {
        themeOverride
            ?? ReferenceUIThemeResolver.resolve(
                coreTheme: (try? LiveBuy.sdkConfig())?.theme,
                hostOptions: nil)
    }
}

/// Measures the rendered floating card size so the drag offset can be clamped on-screen.
private struct FloatingCardSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

public extension View {
    /// Present the turnkey `LiveBuyPlayer` full-screen for the bound `video`, with a
    /// built-in minimize→bottom-right floating preview (`FloatingWidgetView`). ONE line:
    ///
    ///     someHostView.liveBuyPlayer(video: $presentedVideo, config: cfg)
    ///
    /// `video` non-nil → present full-screen; minimize collapses to the floating card;
    /// tapping it restores; closing it (or a fatal moment dismiss) clears `video`.
    ///
    /// The presenter OWNS `config.onMinimize` / `config.onDismiss` (the collapse / clear);
    /// every other `LiveBuyPlayerConfig` seam passes through. A host that needs custom
    /// minimize / dismiss should use the raw `LiveBuyPlayer` view instead.
    ///
    /// `video` carries the `LBVideoItem` so the floating card can show its thumbnail; a host
    /// with only a video id passes `LBVideoItem.demo(id: theId, live: true)`.
    ///
    /// NOTE: restoring from the floating preview re-presents the player (a fresh `load`),
    /// not a resume — the floating card is a minimized card representation, not OS PiP.
    func liveBuyPlayer(
        video: Binding<LBVideoItem?>,
        config: LiveBuyPlayerConfig = LiveBuyPlayerConfig(),
        theme: ReferenceUITheme? = nil
    ) -> some View {
        modifier(LiveBuyPlayerPresenter(video: video, config: config, themeOverride: theme))
    }
}
