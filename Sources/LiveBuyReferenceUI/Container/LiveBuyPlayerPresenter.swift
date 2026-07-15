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

/// Whether the presenter, at the given phase, SHALL declare the home `LiveBuyWidget` previews
/// COVERED via the opt-in `LiveBuyWidgetVisibility.setWidgetsCovered` bridge — driving the
/// preview play-gate's third axis (`ios-refui-presenter-widget-cover-by-phase`).
///
/// `covered ⟺ phase == .full` (i.e. `hasVideo && !isMinimized`). The full-screen player is a
/// KEEP-ALIVE overlay (`playerLayer`): while `.full` it is decoding a live/VOD stream and, being
/// kept alive, KEEPS decoding even after minimize — so the N home carousel previews (each its own
/// `AVQueuePlayer`) contend for the finite hardware video decoders and stall. Declaring the home
/// previews COVERED only while `.full` makes them yield those decoders; on minimize (`.floating`)
/// the previews resume (still gated by foreground / on-screen) because the small floating card
/// alone frees enough decoding headroom, and `.closed` has no session. This is what fixes
/// "shrink the full-screen live player → home previews still don't play": the residual gap left by
/// `ios-refui-widget-host-visibility-pause` (the bridge existed but NOTHING in production ever
/// called `setWidgetsCovered`, since only THIS presenter knows the full/floating/closed phase —
/// `isMinimized` is its private `@State`, invisible to the host). Pure so the phase→cover mapping
/// is unit-testable without SwiftUI (internal-testability).
func presenterWidgetCovered(hasVideo: Bool, isMinimized: Bool) -> Bool {
    collapsiblePhase(hasVideo: hasVideo, isMinimized: isMinimized) == .full
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

/// Whether `onChange(of: video?.id)` SHALL auto-restore full-screen on a `video` id change.
/// True ONLY for a HOST-driven swap (`isInternalSwitch == false`) that
/// `shouldReopenOnVideoChange` accepts (a new, non-nil video while minimized). An in-player
/// in-place switch we caused (`isInternalSwitch == true`) MUST NOT auto-restore — it keeps the
/// current minimize/full phase and only re-binds the shown video (D-2). Pure so the gate is
/// unit-testable without SwiftUI (internal-testability).
func shouldAutoRestoreOnBindingChange(
    isInternalSwitch: Bool,
    newVideoId: String?,
    isMinimized: Bool
) -> Bool {
    guard !isInternalSwitch else { return false }
    return shouldReopenOnVideoChange(newVideoId: newVideoId, isMinimized: isMinimized)
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

/// Rebuilds a DISPLAY-ONLY copy of `video` with `liveStatus` (and the paired `type`, using the
/// SAME `type: isLive ? 2 : 1` convention `LiveBuyPlayer.switchedVideoItem` already establishes)
/// overridden to match `isLive` — the CURRENT authoritative live-status signal
/// (`PlayerShellModel.onLiveStatusChange`, channel-load-driven) — instead of `video.liveStatus`'s
/// switch-time GUESS (baked in synchronously at switch-initiation from PRE-switch adjacency
/// data; see `LiveBuyPlayer.switchedVideoItem`). Every OTHER field (`cover` / `title` / `preview`
/// / `goods` / …) passes through UNCHANGED — `PlayerShellModel` doesn't carry those, so `video`
/// stays their only source. Returns `video` unchanged when its `liveStatus` already matches
/// `isLive` (no unnecessary copy). This is what fixes the live→VOD-in-place-switch-then-minimize-
/// still-shows-LIVE bug (rb-ios-floating-card-live-status-sync): `video` itself keeps carrying
/// the switch-time guess (still fine for cover/title), only the FLOATING CARD's badge derivation
/// is redirected to this single, self-correcting source of truth. Pure (no I/O) — unit-testable
/// (internal-testability).
func floatingCardDisplayItem(_ video: LBVideoItem, isLive: Bool) -> LBVideoItem {
    let targetLiveStatus = isLive ? 1 : 0
    guard video.liveStatus != targetLiveStatus else { return video }
    return LBVideoItem(
        id: video.id, type: isLive ? 2 : 1, title: video.title, sessionName: video.sessionName,
        cover: video.cover, preview: video.preview, duration: video.duration,
        publishAt: video.publishAt, watchNum: video.watchNum, pvNum: video.pvNum,
        liveStatus: targetLiveStatus, pin: video.pin, showPvNum: video.showPvNum,
        liveurl: video.liveurl, playbackurl: video.playbackurl, previewTime: video.previewTime,
        showStock: video.showStock, goods: video.goods)
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

    /// Latch distinguishing a `video` id change WE caused (an in-player in-place switch —
    /// swipe / hot-pick / watch-next, synced via the composed `onVideoSwitched`) from a
    /// HOST-driven swap (the host setting the binding to another video). Set right before we
    /// mutate `video` on an internal switch; consumed (and cleared) in `onChange(of: video?.id)`
    /// so an internal switch does NOT trip the host-swap auto-restore (D-2). False at rest.
    @State private var isInternalSwitch: Bool = false

    /// The CURRENT authoritative live-status of the shown video
    /// (`PlayerShellModel.onLiveStatusChange`, channel-load-driven), used ONLY to correct the
    /// floating card's LIVE/VOD badge (see `floatingCardDisplayItem`). Seeded from the bound
    /// `video.liveStatus` on every id change (`.onChange(of: video?.id)`) — a reasonable guess
    /// for the brief window before the authoritative signal arrives — and corrected thereafter.
    /// `video` itself keeps carrying the switch-time guess unchanged (still fine for cover /
    /// title); only this mirror redirects the badge derivation (rb-ios-floating-card-live-status-sync).
    @State private var isVideoLive: Bool = false

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
                // Reseed the floating card's live-status guess for the newly bound video (first
                // open / host swap / internal switch): a fresh guess from `liveStatus` until the
                // authoritative `onLiveStatusChange` corrects it once real channel data loads (or
                // immediately, if it's already loaded — e.g. a host swap to a DIFFERENT,
                // already-known video). rb-ios-floating-card-live-status-sync.
                isVideoLive = video?.liveStatus == 1
                // An IN-PLAYER in-place switch (swipe / hot-pick / watch-next) updates `video`
                // OURSELVES (composed `onVideoSwitched`) and latches `isInternalSwitch`. That is
                // NOT a host-driven swap, so it MUST NOT auto-restore full-screen — it keeps the
                // current minimize/full phase and only re-binds the shown video (D-2). Consume the
                // latch and bail. (A host swap leaves the latch false → falls through to restore.)
                let restore = shouldAutoRestoreOnBindingChange(
                    isInternalSwitch: isInternalSwitch,
                    newVideoId: newId,
                    isMinimized: isMinimized)
                isInternalSwitch = false   // consume the latch on every id change
                if restore {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        isMinimized = false
                    }
                    committedOffset = .zero
                    dragTranslation = .zero
                }
                // Drive the opt-in cover bridge from the resulting phase (open / close / host-swap
                // auto-restore / internal switch all change `video?.id`). Placed at the TAIL so a
                // just-applied auto-restore (`isMinimized = false` above) is already reflected.
                syncWidgetCover()
            }
            // full ⇄ floating phase flips (minimize / restore-tap) drive the cover bridge too.
            .onChange(of: isMinimized) { _ in syncWidgetCover() }
            // First mount: `.onChange` never fires for an initial value, so seed the cover state
            // for "host mounts the presenter already carrying a non-nil video → open full-screen".
            .onAppear { syncWidgetCover() }
            // Presenter removed while covered (`.full`): release the cover so the home previews are
            // NOT left permanently paused (important edge case — the bridge is a stateful level).
            .onDisappear { LiveBuyWidgetVisibility.setWidgetsCovered(false) }
    }

    /// Drive the opt-in `LiveBuyWidgetVisibility` cover bridge from the CURRENT presentation phase:
    /// `covered ⟺ .full` (`presenterWidgetCovered`). Called from every phase-affecting hook
    /// (`onAppear` / `onChange(of: isMinimized)` / the tail of `onChange(of: video?.id)`). The
    /// presenter is the SINGLE owner of this call — it is the only place that knows the
    /// full/floating/closed phase (`isMinimized` is private `@State`, invisible to the host), so no
    /// host wiring is needed. `setWidgetsCovered` is edge-triggered (same value → no-op), so being
    /// called from several hooks (and re-entrantly via `withAnimation` state writes) is safe and
    /// never churns; the settled invariant is `covered == (video != nil && !isMinimized)`.
    private func syncWidgetCover() {
        LiveBuyWidgetVisibility.setWidgetsCovered(
            presenterWidgetCovered(hasVideo: video != nil, isMinimized: isMinimized))
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
        // In-player in-place switch (swipe / hot-pick / watch-next) → re-bind `video` to the
        // SWITCHED video as the REAL item the container resolved (id + REAL `cover` / `title`
        // from the adjacency nav / hot / next item that drove the switch), so the floating
        // preview card shows the switched video's REAL thumbnail — NOT a placeholder. Without
        // this the binding stays on the ENTRY video: the keep-alive player gets reloaded back to
        // it on the next re-render (`updateUIViewController` cover-guard mismatch) and the floating
        // card shows the wrong (entry) thumbnail. The container fires this on every in-place switch
        // (alongside the host's id-only `config.onVideoSwitched`, which passes through unchanged).
        // Latch `isInternalSwitch` so `onChange(of: video?.id)` keeps the current minimize/full
        // phase instead of treating it as a host-driven swap (D-2). Guard `item.id != current` so a
        // same-id no-op neither re-binds nor leaks the latch (onChange wouldn't fire to clear it).
        // Keep-alive does NOT double-load: `LiveBuyPlayer`'s coordinator already set its cover/
        // current id to the new id before firing this, so the new `videoId` prop makes
        // `updateUIViewController`'s cover-guard a no-op (D-4).
        c.onVideoSwitchedItem = { item in
            guard item.id != video?.id else { return }
            isInternalSwitch = true
            video = item
        }
        // Authoritative live-status mirror (rb-ios-floating-card-live-status-sync): corrects
        // `isVideoLive` whenever the CURRENTLY SHOWN video's real live status changes — fixing
        // the switch-time `onVideoSwitchedItem` guess once the real post-switch channel data
        // loads (e.g. live→VOD no longer stays permanently stuck showing LIVE). Fully owned by
        // the presenter, same as `onMinimize` / `onDismiss` / `onVideoSwitchedItem` above.
        c.onLiveStatusChange = { live in isVideoLive = live }
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
        // The card's LIVE/VOD badge reads the AUTHORITATIVE `isVideoLive` mirror (not `v`'s own
        // possibly-stale switch-time `liveStatus` guess) — cover / title / preview / goods still
        // come from `v` unchanged (rb-ios-floating-card-live-status-sync).
        let displayVideo = floatingCardDisplayItem(v, isLive: isVideoLive)
        let context = FloatingCardContext(
            video: displayVideo,
            theme: resolvedTheme,
            live: true,
            onTap: { _ in
                // Restore the full player: a keep-alive RESUME, NOT a fresh load / sheet
                // re-present. The same mounted player VC (never torn down on minimize) just
                // flips back from `opacity 0` / hitTesting off to visible — playback continues
                // uninterrupted, nothing reloads (see the keep-alive doc on `playerLayer`). The
                // floating card is a minimized representation, not OS PiP.
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
    /// NOTE: restoring from the floating preview is a keep-alive RESUME — the same mounted
    /// player VC stays alive across minimize/restore, so playback continues uninterrupted; it is
    /// NOT a fresh `load` / re-present. The floating card is a minimized card representation,
    /// not OS PiP.
    func liveBuyPlayer(
        video: Binding<LBVideoItem?>,
        config: LiveBuyPlayerConfig = LiveBuyPlayerConfig(),
        theme: ReferenceUITheme? = nil
    ) -> some View {
        modifier(LiveBuyPlayerPresenter(video: video, config: config, themeOverride: theme))
    }
}
