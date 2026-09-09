import Foundation
import LivebuySDK

// MARK: - LiveNowFetchCache — cross-controller short-TTL fetch dedup (ios-live-now-poll-fetch-cache)
//
// `LiveNowPollController`（LivebuyPlayer 內嵌 pill）與 `LivebuyLiveEntryController`（app 根層級浮動
// 入口卡）是兩個各自獨立、host 可各自 opt-in 的 drop-in 面，MUST NOT 共用 instance/lifecycle/state
// （見 LiveNowPollController.swift 檔頭）——但依 host 慣例兩者在掛載時機上互斥（player 在前景時
// entry 不掛載，反之亦然），這代表「entry 剛卸載、player 的 pill 剛掛載」這個切換瞬間，新掛載的
// controller 會立刻打一次跟舊 controller 剛剛才打過、答案幾乎不可能變的同一支 API
// （`Livebuy.fetchLatestLive(id:)`）。
//
// 這個類別解決的**只有**這一件事：一個極窄、唯讀的「[shopId: 最近一次真實 fetch 結果]」快取，
// TTL 5 秒。共用**快取內容**與共用**instance/lifecycle**是兩件不同的事——本類別 MUST NOT
// 被誤用成兩個 controller 之間傳遞 state 或耦合生命週期的手段，兩個 controller 讀寫這個快取後，
// 各自的輪詢 Task、@Published state、start()/stop() 生命週期完全不受影響、完全獨立。
//
// ⚠️ 只有每個 controller instance 自己生命週期的**第一輪**輪詢才會讀這個快取（見
// `LiveNowPollController.pollLoop` / `LivebuyLiveEntryController.pollLoop` 的 `hasAppliedFirstRound`
// 旗標）——第二輪以後永遠是真實 fetch，不管快取內容為何。這條限制是為了保護
// `LiveNowPollControllerTests.testStartIsIdempotent_stopFullyHaltsPollingWithNoOrphanedTask`
// 既有的鑑別力：那個測試用極短 `pollInterval` 讓同一個 controller 在測試視窗內真的跑很多輪，靠數
// fetch 呼叫次數證明 idempotency guard 有效——若每一輪都讀快取，該 controller 自己的第 2、3…輪
// （都在 5s TTL 內）會全部變成快取命中、fetch 呼叫次數在第一輪後就凍結，讓那個測試失去鑑別力。
// 任何新測試若要真的驅動 `pollLoop()` 跑（而非直接呼叫 `apply(_:)`），MUST 注入私有的
// `LiveNowFetchCache()` instance，而不是 `.shared`——見本檔測試（`LiveNowFetchCacheTests.swift`）
// 與兩個 controller 測試檔案的示範。

/// Pure：`fetchedAt` 距 `now` 是否仍在 `ttlSeconds` 內（`<`，不含邊界）。抽成純函式方便單測窮舉。
func liveNowCacheIsFresh(fetchedAt: Date, now: Date, ttlSeconds: TimeInterval) -> Bool {
    now.timeIntervalSince(fetchedAt) < ttlSeconds
}

/// ⚠️ `public`（連同 `.shared`）是 Swift 語言強制的最小可見度——`LiveNowPollController.init` /
/// `LivebuyLiveEntryController.init` 的 `cache: LiveNowFetchCache = .shared` 參數帶預設值出現在
/// **public** ctor 簽名裡（`LiveNowPollController.init` 是 public API），Swift 要求出現在 public
/// 簽名裡的型別、以及預設值表達式引用到的 symbol，可見度都不得低於該簽名本身。這**不是**要把整個
/// 快取的讀寫操作對外開放——`cached(_:)` / `record(_:)` / `resetForTesting()` 與 `init` 本身仍是
/// `internal`（模組內部，測試 target 靠 `@testable import` 存取），只有型別名稱與 `.shared`
/// 這一個 static 值需要 public 可見度，一般 host 不會、也不需要直接操作這個類別。
public final class LiveNowFetchCache {

    /// Production 用的 process-wide 共用快取。
    public static let shared = LiveNowFetchCache()

    /// ⚠️ 刻意**不是** `private init()`（跟同檔案系列的 `LivebuyLiveEntryCloseGate` /
    /// `LivebuyLiveEntryDismissMemory` 慣例不同）——測試需要能建構自己的**私有**、跟 `.shared`
    /// 完全隔離的 instance，避免不同測試之間透過 `.shared` 互相汙染（尤其是任何真的驅動
    /// `pollLoop()` 跑的測試——見檔頭說明）。
    init(ttlSeconds: TimeInterval = 5.0) {
        self.ttlSeconds = ttlSeconds
    }

    private let ttlSeconds: TimeInterval
    private struct Entry { let video: LBVideoItem?; let fetchedAt: Date }
    private var entries: [String: Entry] = [:]

    enum Lookup {
        case hit(LBVideoItem?)
        case miss
    }

    /// 讀一筆 `shopId` 的快取結果。`now` 預設真實 `Date()`，測試可注入。
    func cached(shopId: String, now: Date = Date()) -> Lookup {
        guard let entry = entries[shopId],
              liveNowCacheIsFresh(fetchedAt: entry.fetchedAt, now: now, ttlSeconds: ttlSeconds) else {
            return .miss
        }
        return .hit(entry.video)
    }

    /// 記錄一筆**真實** fetch 的原始結果（gate 前，兩個 controller 都各自呼叫同一顆
    /// `lbLiveEntryGate` 純函式對同一筆原始資料做 gate，故快取存原始值即可，不需存 gate 後的值）。
    func record(shopId: String, video: LBVideoItem?, now: Date = Date()) {
        entries[shopId] = Entry(video: video, fetchedAt: now)
    }

    /// Test-only reset（internal-testability，比照 `LivebuyLiveEntryCloseGate.resetForTesting()`）。
    func resetForTesting() {
        entries = [:]
    }
}
