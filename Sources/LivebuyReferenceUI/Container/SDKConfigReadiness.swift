import Foundation
import LivebuySDK

// MARK: - Configure-wait schedule shared by the Tier B containers
// (rb-ios-container-configure-wait-extend)
//
// A host may mount `LivebuyWidget` / `LivebuyLiveEntry` before its `Livebuy.configure(...)`
// call has finished (e.g. configure is kicked off without awaiting it). The containers
// therefore wait for the SDK on the SAME schedule RN (`container/sdkConfigResolution.ts`)
// and Flutter (`container/sdk_config_resolution.dart`) use: one immediate check, then retry
// #0..#3 after 100 / 200 / 400 / 800 ms, every later retry after 1000 ms, at most 34 retries
// (≈ 31.5 s in total).
//
// Two DIFFERENT readiness signals exist on iOS (see the change's design.md):
//   • API-ready — `Livebuy.shared != nil`. `configure()` assigns `shared` BEFORE it fetches
//     `/sdk/config`, so the API client exists early; this is all `loadFirstPage()` needs
//     (it otherwise hits `requireAPIClient()`'s fatalError).
//   • config-ready — `Livebuy.sdkConfig()` stops throwing. It needs both `shared` AND the
//     `SDKConfigStore` value, which is set on a cache hit immediately, otherwise only after
//     the blocking `/sdk/config` fetch (≤ the configure timeout) or its fallback.
// The first load waits on API-ready; the theme waits on config-ready.

/// Delay before retry #0, #1, #2, #3 (milliseconds). Later retries use
/// `lbSdkConfigRetrySteadyMs`. Values mirror RN `SDK_CONFIG_RETRY_RAMP_MS`.
let lbSdkConfigRetryRampMs: [UInt64] = [100, 200, 400, 800]

/// Delay between retries once the ramp is exhausted (milliseconds).
let lbSdkConfigRetrySteadyMs: UInt64 = 1000

/// Maximum number of retries after the immediate first check.
let lbSdkConfigMaxRetries = 34

/// Delay in **milliseconds** before retry number `attempt` (0-based), or `nil` once the
/// retry budget is spent (or for a negative attempt). Pure.
func lbSdkConfigRetryDelay(attempt: Int) -> UInt64? {
    guard attempt >= 0, attempt < lbSdkConfigMaxRetries else { return nil }
    if attempt < lbSdkConfigRetryRampMs.count { return lbSdkConfigRetryRampMs[attempt] }
    return lbSdkConfigRetrySteadyMs
}

/// The side effects a container reads while waiting for the SDK, injected so tests can run
/// the wait without global SDK state or real sleeping (internal-testability).
struct LBSdkReadiness {
    /// API-ready: the SDK instance (and its API client) exists.
    var isApiReady: () -> Bool
    /// config-ready: the resolved `SDKConfig`, or `nil` while `Livebuy.sdkConfig()` throws.
    var sdkConfig: () -> SDKConfig?
    /// Sleeps for the given number of milliseconds (returns early when the task is cancelled).
    var sleep: (UInt64) async -> Void

    /// Production wiring: the real SDK globals and `Task.sleep`.
    static let live = LBSdkReadiness(
        isApiReady: { Livebuy.shared != nil },
        sdkConfig: { try? Livebuy.sdkConfig() },
        sleep: { ms in try? await Task.sleep(nanoseconds: ms * 1_000_000) })
}

/// Checks `condition` immediately, then after each delay of `lbSdkConfigRetryDelay`.
/// Returns `true` as soon as `condition` holds; `false` once every retry is spent or the
/// surrounding task is cancelled.
func lbAwaitSdkCondition(_ condition: () -> Bool,
                         sleep: (UInt64) async -> Void) async -> Bool {
    var attempt = 0
    while !condition() {
        guard !Task.isCancelled, let delay = lbSdkConfigRetryDelay(attempt: attempt) else {
            return false
        }
        await sleep(delay)
        attempt += 1
    }
    return true
}

/// The container theme for a resolved (or missing) `SDKConfig`: `sdkConfig.theme` → minimal
/// palette. Pure; the same resolver call the containers used at init before this change.
func lbContainerTheme(for config: SDKConfig?) -> ReferenceUITheme {
    ReferenceUIThemeResolver.resolve(coreTheme: config?.theme, hostOptions: nil)
}

/// Waits (on the shared schedule) for config-ready, then hands the resolved theme to `apply`
/// on the main actor. Gives up silently — the container keeps its current theme. Cancel the
/// returned task to stop waiting.
func lbStartContainerThemeResolution(
    readiness: LBSdkReadiness,
    apply: @escaping @MainActor (ReferenceUITheme) -> Void
) -> Task<Void, Never> {
    Task { @MainActor in
        let ready = await lbAwaitSdkCondition({ readiness.sdkConfig() != nil },
                                              sleep: readiness.sleep)
        guard ready, !Task.isCancelled else { return }
        apply(lbContainerTheme(for: readiness.sdkConfig()))
    }
}
