import SwiftUI
import LivebuySDK

// MARK: - LiveNowPollController — lightweight "is another live in progress" poller
//
// Change: rb-ios-live-now-pill.
// Depends On: `dropin-live-entry-container`（reuses `Livebuy.fetchLatestLive` + the existing
//   `lbLiveEntryGate` purity — see `LivebuyLiveEntry.swift`）.
//
// `LivebuyPlayer` needs to know "is there currently another live in progress" so it can show
// `LiveNowPillView`. `LivebuyLiveEntryController` (in `LivebuyLiveEntry.swift`) already owns a
// PROVEN poll/gate lifecycle for exactly this signal — but `LivebuyLiveEntry` is a SEPARATE,
// independently-mountable drop-in surface (a floating corner entry card); `LivebuyPlayer` MUST
// NOT share its `LivebuyLiveEntryController` instance (that would couple two otherwise-decoupled
// drop-in surfaces the host can each opt into independently — headless / single-source-of-truth
// invariants).
//
// This controller is the DELIBERATELY LIGHTER counterpart: it owns ONLY the three things
// `LiveNowPillView` actually needs — poll interval, failure fast-retry, and the `liveStatus == 1`
// gate (reusing the existing pure `lbLiveEntryGate(_:)`, not a re-implementation) — none of
// `LivebuyLiveEntryController`'s dismiss / drag-clamp / entrance-animation / live-end-notification
// machinery, which is specific to a user-dismissible floating card and has no equivalent concept
// for a pill embedded in the player chrome.
//
// ios-live-now-poll-fetch-cache: the MUST-NOT-share-instance invariant above is UNCHANGED — this
// controller and `LivebuyLiveEntryController` remain fully independent `ObservableObject`
// instances, each owning its own poll `Task` / `@Published` state / `start()`/`stop()`
// lifecycle. What's new is narrower: both controllers now read/write a shared, read-only,
// 5-second-TTL `LiveNowFetchCache` (`.shared` by default) of "most recent real fetch result per
// shopId" — purely to skip one redundant network round trip at the moment a host switches
// between the mutually-exclusive-by-convention pill (this controller) and the floating entry
// card (`LivebuyLiveEntryController`). Each controller instance consults the cache ONLY on its
// own first poll round (`hasAppliedFirstRound`); every later round is unconditionally a real
// fetch. See `LiveNowFetchCache.swift`'s header for the full rationale.
public final class LiveNowPollController: ObservableObject {

    /// The currently detected "another live in progress" video, or `nil`. Drives
    /// `PlayerShellView.hasLiveNow` (→ `LiveNowPillView`'s presence). Always `nil` when `shopId`
    /// is unset (`start()` never actually polls) or the backend currently has no
    /// `liveStatus == 1` live for this shop.
    @Published public private(set) var liveNow: LBVideoItem?

    private let shopId: String?
    private let pollInterval: TimeInterval
    /// Injected fetch side effect (internal-testability: ctor-injected, default
    /// `Livebuy.fetchLatestLive(id:)`) — a test substitutes a `Fake*` closure instead of hitting
    /// the network, mirroring `LivebuyLiveEntryController`'s identical seam.
    private let fetch: (String) async throws -> LBVideoItem?
    /// ios-live-now-poll-fetch-cache: read-only, short-TTL cross-controller fetch cache. Default
    /// `.shared` for production; tests that drive a REAL `pollLoop()` run (via `start()`) MUST
    /// inject a private `LiveNowFetchCache()` instance to stay isolated from `.shared` and from
    /// any other test — see `LiveNowFetchCache.swift`'s header.
    private let cache: LiveNowFetchCache

    private var pollTask: Task<Void, Never>?
    /// ios-live-now-poll-fetch-cache: only this instance's first poll round may read `cache`;
    /// every subsequent round is unconditionally a real fetch. NOT set inside `pollLoop`'s
    /// `catch` branch — a failed first attempt keeps this `false` so the fast-retry round can
    /// still consult the cache. See `LiveNowFetchCache.swift`'s header for the full rationale.
    private var hasAppliedFirstRound = false

    public init(shopId: String?,
                pollInterval: TimeInterval = 30,
                cache: LiveNowFetchCache = .shared,
                fetch: @escaping (String) async throws -> LBVideoItem? = { try await Livebuy.fetchLatestLive(id: $0) }) {
        self.shopId = shopId
        self.pollInterval = pollInterval
        self.cache = cache
        self.fetch = fetch
    }

    // MARK: - 輪詢生命週期

    /// 起輪詢（冪等：已在跑就跳過）。`shopId == nil`（host 沒有 opt-in `LivebuyPlayerConfig.shopId`）
    /// → 永遠不會真的打任何 API、`liveNow` 永遠停在 `nil`、`LBLiveNowPill` 永遠不出現——headless
    /// 慣例：host 沒有明確 opt-in 就零額外副作用。
    public func start() {
        guard let shopId = shopId, pollTask == nil else { return }
        pollTask = Task { [weak self] in await self?.pollLoop(shopId: shopId) }
    }

    /// 停輪詢（容器 dismantle 時呼叫，對稱 `start()`）。
    public func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// `do/catch`（非 `try?`）比照 `LivebuyLiveEntryController.pollLoop`：區分「目前沒有直播」
    /// （`nil` → 清空鈕）與「請求失敗 / 尚未 configure」（throw → **保留**上一輪的值、3s 快重試）——
    /// 一次暫時的網路抖動不該讓鈕閃爍消失又出現。
    ///
    /// ios-live-now-poll-fetch-cache：只有 `!hasAppliedFirstRound` 這一輪才會先查 `cache`——命中
    /// 就直接用（跳過真實 `fetch`），沒命中才真的 `fetch` 再寫回 `cache`。不論走哪條路，這輪跑完
    /// （成功）後 `hasAppliedFirstRound` 恆設 `true`，之後每一輪都無條件真實 `fetch`（仍持續寫回
    /// `cache` 供其他 controller 受益）。`catch` 分支不設 `hasAppliedFirstRound`，讓快重試那一輪
    /// 仍有機會查快取。
    private func pollLoop(shopId: String) async {
        while !Task.isCancelled {
            do {
                let video: LBVideoItem?
                if !hasAppliedFirstRound, case .hit(let cached) = cache.cached(shopId: shopId) {
                    video = cached
                } else {
                    video = try await fetch(shopId)
                    cache.record(shopId: shopId, video: video)
                }
                hasAppliedFirstRound = true
                let gated = lbLiveEntryGate(video)
                await MainActor.run { self.apply(gated) }
                try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
            } catch {
                try? await Task.sleep(nanoseconds: 3_000_000_000)   // 3s 快重試（pre-configure / 網路）
            }
        }
    }

    /// Test-only / internal seam：直接套用一筆**已 gate** 的結果（比照
    /// `LivebuyLiveEntryController.apply`），讓單測能驅動狀態轉移而不需要真的跑輪詢 `Task` 迴圈 /
    /// 等待 `Task.sleep`。
    func apply(_ gated: LBVideoItem?) {
        liveNow = gated
    }

    deinit {
        pollTask?.cancel()
    }
}
