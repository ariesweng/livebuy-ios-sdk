import Foundation
import UIKit
import LivebuySDK

// MARK: - VodEndedCloseGate — debounced「VOD／回放播完、無下一支」自動關閉
// (rb-ios-vod-ended-no-next-close)
//
// Spec: `component-contracts/spec.md`「EndScreen 元件契約」— VOD（非直播）自然播完且無 next →
// 不進 `endScreenShown`、維持 `.ended`，由 reference-ui 容器直接觸發播放器關閉。core
// `vod-end-loop-ios-core` 之後：`.loop`（預設）會短暫 surface `.ended` 再 seek 0 重播；`.advance`
// 有 next → 直接 load 下一支；`.advance` 無 next → 停在 `.ended`。iOS 既有的
// `MomentsOverlayView.shouldCloseInsteadOfEndScreen` 只在 end moment（countdown / endScreen）出現時
// 才判斷，這條路徑兩者皆不出現 → 從不關閉。本 gate 補上這個缺口。
//
// Parity 範本：Flutter `flutter-reference-ui/lib/src/container/live_buy_player.dart`
// `VodEndedCloseGate`（400ms debounce、`isLive` 在 `ended` 到達當下決定）。iOS 額外要求
// `behavior == .advance`：`.loop` 在實機 seek 卡頓時 `.ended` 可能停留超過 debounce，不得誤關。

/// Testable seam for `VodEndedCloseGate`'s debounce delay (docs/unit-test-discipline.md §4 —
/// side effects injected). Production default is `DispatchQueue.main.asyncAfter`; a unit test
/// injects a `Capturing*` fake that records `(delay, callback)` and runs `callback` on its own
/// schedule — no real wait.
typealias VodEndedCloseScheduler = (_ delay: TimeInterval, _ callback: @escaping () -> Void) -> Void

/// PRODUCTION DEFAULT `VodEndedCloseScheduler`: main-queue `asyncAfter`.
func defaultVodEndedCloseScheduler(_ delay: TimeInterval, _ callback: @escaping () -> Void) {
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: callback)
}

/// Debounced close decision fed every player state change via `handleStateChange`. Plain object
/// (no UIKit / SwiftUI) with injected `scheduler` + `onClose` — directly unit-testable.
///
/// **Ended episode latch.** The FIRST `.ended` after any non-`.ended` state opens an「ended
/// episode」and the arm/no-arm decision is made ONCE, from the inputs at that instant (`isLive`
/// in particular — mirrors the `latchedIsLiveChannel` spirit of `rb-ios-endscreen-live-gate-latch`).
/// Further `.ended` feeds inside the same episode are no-ops (they neither re-arm nor cancel nor
/// extend the debounce) — iOS feeds this gate from the process-global `VIDEO_STATE_CHANGE`
/// dispatcher, so a repeated `.ended` re-feed is expected and must not flip the latched decision.
/// ANY non-`.ended` state ends the episode and invalidates a pending close.
///
/// Main-thread contract: call `handleStateChange` / `cancel` from the main thread.
final class VodEndedCloseGate {

    /// Same debounce as Flutter's `VodEndedCloseGate` (400ms): long enough for the `.loop`
    /// restart / `.advance` load's follow-up state to arrive and cancel, short enough that a
    /// genuine dead end does not sit frozen.
    static let defaultDebounce: TimeInterval = 0.4

    let debounce: TimeInterval
    private let scheduler: VodEndedCloseScheduler
    private let onClose: () -> Void

    /// Identity token of the currently pending close, `nil` when none. Replaced / cleared on every
    /// invalidation so a stale scheduled callback's identity check fails → silent no-op.
    private var pending: NSObject?
    /// `true` while inside an ended episode (decision already latched).
    private var inEndedEpisode = false

    init(debounce: TimeInterval = VodEndedCloseGate.defaultDebounce,
         scheduler: @escaping VodEndedCloseScheduler = defaultVodEndedCloseScheduler,
         onClose: @escaping () -> Void) {
        self.debounce = debounce
        self.scheduler = scheduler
        self.onClose = onClose
    }

    /// Pure arm decision for the moment an ended episode opens. `hasChannel == false` (e.g. core
    /// `unload()` clears `channel` then sets `.ended`) never arms — that `.ended` is a teardown,
    /// not a natural playback end. `isLive` is `channel.liveStatus == 1`; a finished-live 回放
    /// (`liveStatus == 3`) is NOT live and therefore closes like any VOD.
    static func shouldArmClose(state: LBPlayerState,
                               hasChannel: Bool,
                               isLive: Bool,
                               hasNext: Bool,
                               behavior: LBVodEndBehavior) -> Bool {
        state == .ended && hasChannel && !isLive && !hasNext && behavior == .advance
    }

    /// Feed one player state change (see the type doc for the episode-latch rules).
    func handleStateChange(_ state: LBPlayerState,
                           hasChannel: Bool,
                           isLive: Bool,
                           hasNext: Bool,
                           behavior: LBVodEndBehavior) {
        guard state == .ended else {
            inEndedEpisode = false
            pending = nil
            return
        }
        guard !inEndedEpisode else { return }   // same episode: decision already latched
        inEndedEpisode = true
        guard Self.shouldArmClose(state: state, hasChannel: hasChannel, isLive: isLive,
                                  hasNext: hasNext, behavior: behavior) else { return }
        let token = NSObject()
        pending = token
        scheduler(debounce) { [weak self] in
            guard let self = self, self.pending === token else { return }
            self.pending = nil
            self.onClose()
        }
    }

    /// Invalidate any pending close (container teardown). Idempotent.
    func cancel() {
        pending = nil
        inEndedEpisode = false
    }

    /// Test-only read window (`*ForTesting` naming per docs/unit-test-discipline.md).
    var hasPendingCloseForTesting: Bool { pending != nil }
}

/// Auxiliary (non-primary) `LivebuyEventListener` forwarding every `VIDEO_STATE_CHANGE`
/// (`LBEvent.videoStateChange`) as a bare "state changed" ping. Mirrors `PiPStateAuxListener`: it
/// NEVER intercepts (returns `false`), so the host's primary listener is untouched. The payload is
/// deliberately ignored — `EventDispatcher` is process-global, so the receiver re-reads ITS OWN
/// player's `playerState` / `channel` on the main thread instead of trusting a possibly-foreign
/// event. Held STRONGLY by `Coordinator` (core holds aux listeners weakly).
final class VideoStateAuxListener: NSObject, LivebuyEventListener {

    /// Invoked (on the dispatcher's background queue) on every `VIDEO_STATE_CHANGE`, with whether
    /// that event carried `advance_exhausted: true` (rb-ios-vod-advance-exhausted-close — the core
    /// skipped every unplayable `next` candidate, vod-advance-skip-unplayable-ios-core).
    var onVideoStateChange: ((_ advanceExhausted: Bool) -> Void)?

    func onEventTriggered(
        eventName: String,
        params: [String: Any],
        cartCallback: LBCartResultCallback?,
        shareContext: LBShareContext?
    ) -> Bool {
        if eventName == LBEvent.videoStateChange {
            onVideoStateChange?((params["advance_exhausted"] as? Bool) == true)
        }
        return false   // non-primary aux listener: never intercept
    }
}

/// The container's single dismiss resolution (`rb-ios-endscreen-live-empty-state`): the host's
/// `config.onDismiss` override, else the raw UIKit `dismiss(animated:)`. Shared by the moment
/// `onDismiss` / `onCancel` seams AND the `VodEndedCloseGate` close, so every "close the player"
/// exit agrees for a given `LivebuyPlayerConfig` (bare `LivebuyPlayer` vs.
/// `LivebuyPlayerPresenter`'s `composedConfig.onDismiss` → `closeSession()`).
func resolvedPlayerDismiss(onDismiss: ((LivebuyPlayerViewController) -> Void)?,
                           player: LivebuyPlayerViewController) {
    if let custom = onDismiss { custom(player) } else { player.dismiss(animated: true) }
}
