import SwiftUI
import LivebuySDK
import LivebuyUI

// MARK: - LivebuyLiveEntry — turnkey drop-in「現正直播」浮窗入口容器（Tier B）
//
// 「全店現正有直播時，畫面角落浮一張入口卡，點了開播放器」是直播導流的主入口。SDK 從
// 未把它做成 drop-in：`quickstart §8.1` 要 host「自組」——自己 30s 輪詢
// `Livebuy.fetchLatestLive`、自己 gate `liveStatus == 1`、自己組裸 `FloatingWidgetView`、
// 自己接 dismiss / live_end 即時隱藏 / 拖曳 clamp。這段邏輯已在四端 Example 各自重抄一遍
// （`ContentView.FloatingLiveModel` ＋拖曳手勢＋`.lbLiveEnded` 監聽＋`dismissed` 狀態）。
//
// `LivebuyLiveEntry` 把它 PROMOTE 進套件，比照既有 `LivebuyWidget` / `LivebuyPlayer`
// （archive `introduce-dropin-widget-container`）的「Example 控制器 → 一行 drop-in」模式，
// 讓 host 一行接好：
//
//     YourHomeView()
//         .overlay(alignment: .bottomTrailing) {
//             LivebuyLiveEntry(shopId: "Pw8PJ99J")               // 全預設
//         }
//
//     // 或帶 config：
//     LivebuyLiveEntry(shopId: "Pw8PJ99J", config: cfg)
//
// 落點與出現時機（rb-ios-floating-entry-position-timing）：**可拖曳**模式（預設）下靜止角落由
// `config.position` 決定（右下 / 左下，預設右下），host 傳給 `.overlay(alignment:)` 的 alignment
// 在該模式下**不決定**入口落點——容器自己在 host 給的空間裡靠 `.frame(alignment:)` + `inset` 貼角
// （上面範例用 `.bottomTrailing` 只是讓 overlay 佔滿版面的慣用寫法，換成別的 alignment 也不影響
// 入口位置）。**不可拖曳**模式（`config.draggable = false`）則相反：容器不加任何定位 chrome，
// 落點完全由 host 的 `.overlay(alignment:)` + padding 決定，`config.position` / `config.inset`
// 在該模式皆不適用。出現時機（`config.timing` / `config.delay`）兩種模式都適用。
//
// 與 `LivebuyWidget(mode: .floating)` 的差異（避免混淆）：
//   • `LivebuyWidget(mode: .floating)` ＝「指定**單一 videoId** 的迷你播放器浮窗」。
//   • `LivebuyLiveEntry` ＝「**自動偵測全店現正直播**的入口卡」——host 不指定 video，
//     容器自己輪詢 `fetchLatestLive` 找出當前 `liveStatus == 1` 的那一場。
//
// PURE ASSEMBLY（governance）：像素層 100% reuse 既有 `FloatingWidgetView`
// （`Widget/FloatingWidgetView.swift`，`public init(video:theme:width:live:onTap:onClose:)`）。
// 本容器**不新增任何像素 surface、不新增 view-model、不動 template / core**。依賴維持單向
// `reference-ui → template → core`。

// MARK: - Pure helpers（testable；先寫好給單測）

/// Gate：一筆 `fetchLatestLive` 結果只在 `liveStatus == 1` 時算「現正直播」。吸收 nil /
/// `liveStatus == 3`（外部平台直播，如 Facebook）/ `ty:"live"` 退而求其次的 VOD fallback
/// （`liveStatus != 1`）→ 全部回 nil。純函式（無副作用），容器與單測共用同一實作。
func lbLiveEntryGate(_ video: LBVideoItem?) -> LBVideoItem? {
    video?.liveStatus == 1 ? video : nil
}

/// 換場重置判定：新一場（`newId` 與目前 `currentId` 不同，含 nil → id）即回 true，讓
/// 容器把使用者的 `dismissed` 重置（關掉一場直播不會連帶隱藏下一場）。純函式。
func lbLiveEntryShouldResetDismiss(currentId: String?, newId: String?) -> Bool {
    currentId != newId
}

// MARK: - 浮動入口的落點 / 時機（rb-ios-floating-entry-position-timing）
//
// 來源是 `POST /sdk/config` 回應的 `data.extensions.floating_setting`（扁平八欄）裡與像素相關的
// master 四欄。`extensions` 是 **opaque raw bag**，`sdk-config` capability 明文規定 SDK 不解讀其
// 語意——所以這些值一律由 **host** 讀出後注入 `LivebuyLiveEntryConfig`，容器自己**不碰**
// `sdkConfig.extensions`。四欄裡的 `enable`（要不要掛載本容器）同樣是 host 的決定，本層不處理；
// app scope 的 `live` / `video` / `video_source` / `video_id` 是選片邏輯、不影響像素，不在此範圍。

/// 浮動入口的靜止落點。raw value 就是 wire 上的字串，方便 host 想自己判斷時對照。
public enum LBFloatingEntryPosition: String {
    /// 右下（**本層 fallback**，也是 iOS 一直以來的落點）。
    case rightBottom = "right_bottom"
    /// 左下。
    case leftBottom = "left_bottom"

    /// 唯一一處把 raw `position` 變成落點的地方。對齊設計稿的
    /// `normalizeFloatingPosition(raw)`（`raw === 'left_bottom' ? 'left_bottom' : 'right_bottom'`）
    /// **逐字**：比較是嚴格相等，**不 trim、不 case-fold、不做別名對照**，所以 `" left_bottom "` /
    /// `"LEFT_BOTTOM"` 與任何白名單外字串一樣落回 `.rightBottom`。刻意跟設計稿一樣嚴格，是為了讓
    /// 四端在**後端送出畸形值時**（分歧最難察覺的時候）落點完全一致——後端對 `position` 是 raw
    /// 透傳、不做列舉正規化（來源 `shop_meta` 是 JSON，可能留有舊資料或被直接改寫的值）。
    ///
    /// ⚠️ default 分支是 `.rightBottom`，而**不是**後端「商家沒設定時補進 wire 的預設值」
    /// （後端補的是 `left_bottom`，見 `openspec/specs/backend/sdk-config.md`）。兩者回答的是不同
    /// 問題：後端補的是「wire 上要送什麼」，這裡處理的是「host 什麼都沒注入 / 注入了白名單外字串時，
    /// 畫面要長怎樣」——後者必須落在 **iOS 既有行為**（右下），既有 host 才會零改動、畫面才不變。
    /// 這不是分歧，是分層；請勿「順手改成跟後端一致」。
    public static func normalized(_ raw: String?) -> LBFloatingEntryPosition {
        raw == LBFloatingEntryPosition.leftBottom.rawValue ? .leftBottom : .rightBottom
    }
}

/// 浮動入口的出現時機。raw value 就是 wire 上的字串。
public enum LBFloatingEntryTiming: String {
    /// 立即出現（**本層 fallback**，也是 iOS 一直以來的時機：偵測到直播就畫、無等待無動畫）。
    case immediate
    /// 延遲 `delay` 秒後才出現，並播一段進場動畫。
    case delay

    /// 唯一一處把 raw `timing` 變成時機的地方。與 `LBFloatingEntryPosition.normalized(_:)`
    /// 同紀律：嚴格相等，不 trim、不 case-fold；`nil` / `""` / `"DELAY"` / `" delay "` / 白名單外
    /// 字串一律 `.immediate`（＝零行為變動的那一邊）。
    public static func normalized(_ raw: String?) -> LBFloatingEntryTiming {
        raw == LBFloatingEntryTiming.delay.rawValue ? .delay : .immediate
    }
}

/// 入口從「第一次變成可顯示」到「真的畫出來」要等多久（秒）。純函式：`.immediate` 恆 `0`
/// （連帶讓 `delay` 欄位在 immediate 下完全無作用）；`.delay` 取 `max(0, delay)`，並吸收非有限值
/// （NaN / ±inf → `0`）——wire 上的 `delay` 是 Int 秒，但 host 注入的是 `TimeInterval`，
/// 髒值由這裡收斂，view 不再判斷。
func lbLiveEntryAppearDelay(timing: LBFloatingEntryTiming, delay: TimeInterval) -> TimeInterval {
    guard timing == .delay, delay.isFinite else { return 0 }
    return max(0, delay)
}

/// 出現時機閘 `appeared` 的**初值**：`.immediate`（含所有 fallback 輸入）→ `true`，一建構就算
/// 已現身、完全不進排程；`.delay` → `false`，從隱藏開始等倒數。
///
/// ⚠️ 這是本 change **風險最高的一行**：把它（或呼叫它的 `State(initialValue:)`）改成恆 `false`，
/// 預設（`.immediate`）host 的入口就**永遠不會出現**。抽成純函式正是為了讓它可被單測直接打；
/// `LivebuyLiveEntry` 兩個 init 的 `_appeared` initialValue **只能**經由這個函式取得，
/// MUST NOT 在呼叫點自行寫死布林或重複判斷 timing。
func lbLiveEntryInitialAppeared(timing raw: String?) -> Bool {
    LBFloatingEntryTiming.normalized(raw) == .immediate
}

/// 把拖曳後的 offset clamp 在容器邊界內——與 reference-ui `LivebuyPlayerPresenter`
/// 的 `clampFloatingOffset` 同語義。`offset` 的語意是「自**靜止角落**的螢幕座標位移」，故可位移
/// 的方向由 `position` 決定：錨右下時只能離開右邊（往左，x ≤ 0）、錨左下時只能離開左邊
/// （往右，x ≥ 0）；垂直方向兩側相同（皆錨底，y ≤ 0）。可位移幅度兩側共用同一式子
/// `span = max(0, 容器邊長 − 卡片邊長 − inset)`，讓卡片的外緣留在容器內、並扣掉靜止 inset
/// ——「同一個 `inset` 同時定義靜止位置與拖曳邊界」這條保證在兩個落點下都成立。
/// `span` 的 `max(0, …)` 吸收「卡片 + inset 比容器還大」的退化情況（兩側都夾成不能動）。
/// 純函式（無狀態），幾何易於推理。`position` 帶預設值 `.rightBottom` → 既有呼叫端行為不變。
func lbLiveEntryClampOffset(
    committed: CGSize, translation: CGSize,
    cardSize: CGSize, containerSize: CGSize, inset: CGSize,
    position: LBFloatingEntryPosition = .rightBottom
) -> CGSize {
    let desiredX = committed.width + translation.width
    let desiredY = committed.height + translation.height
    let spanX = max(0, containerSize.width - cardSize.width - inset.width)
    let spanY = max(0, containerSize.height - cardSize.height - inset.height)
    let clampedX: CGFloat
    switch position {
    case .rightBottom: clampedX = max(-spanX, min(0, desiredX))
    case .leftBottom:  clampedX = min(spanX, max(0, desiredX))
    }
    let clampedY = max(-spanY, min(0, desiredY))
    return CGSize(width: clampedX, height: clampedY)
}

// MARK: - Host / player live-end 通知

extension Notification.Name {
    /// 「直播已結束」即時隱藏訊號（raw `"lb_live_ended"`）。由 host 的 event listener
    /// （Example `EventListenerImpl` 收到 `POLL_RECEIVED` + `live_end == 1` 時 post）或執行
    /// drop-in 播放器的 host 發出——core 本身不發此通知。`internal` 範圍：raw value 與
    /// host 端既有定義一致以便互通，但不外露為 public symbol，避免與 host module 自己的
    /// 同名定義在編譯時撞名（升 public + 去重屬後續 example 層 change）。
    static let lbLiveEnded = Notification.Name("lb_live_ended")
}

// MARK: - Controller（生命週期：輪詢 / gate / dismissed / live-end，對稱 LivebuyWidgetController）

/// 擁有「現正直播」入口的生命週期：輪詢 `Livebuy.fetchLatestLive` → 經 `lbLiveEntryGate`
/// 只認 `liveStatus == 1` → 換場重置 `dismissed` → 監聽 `.lbLiveEnded` 即時隱藏。所有副作用
/// （輪詢 Task、通知訂閱、dismissed 狀態）收在這裡，view 透過 `@Published` 綁定（對稱
/// `LivebuyWidgetController`）。`fetch` 由 ctor 注入（internal-testability：副作用注入），
/// 預設綁 `Livebuy.fetchLatestLive(id:)`，單測可換 `Fake*`。
final class LivebuyLiveEntryController: ObservableObject {

    /// 目前要預覽的現正直播，或 nil（無直播 / 被 gate 吸收 / 已結束）。驅動入口的存在與否。
    @Published private(set) var live: LBVideoItem?
    /// 使用者是否關閉了「目前這一場」的入口。換新一場 `id` 時重置（見 `apply`）。
    @Published private(set) var dismissed: Bool = false

    /// 解析後的 reference-ui theme（`sdkConfig.theme` → minimal palette），與
    /// `LivebuyPlayer` / 最小化播放器卡同一 resolver，讓入口卡與播放器品牌一致。
    let theme: ReferenceUITheme

    private let shopId: String
    private let pollInterval: TimeInterval
    /// 注入的 fetch 副作用（預設 `Livebuy.fetchLatestLive(id:)`）。
    private let fetch: (String) async throws -> LBVideoItem?

    /// 最後套用的直播 id——偵測「新一場」以重置 `dismissed`。
    private var lastLiveId: String?
    /// 已被 live_end 標記結束的直播 id：被 `apply` 視為「無直播」，避免後端 lag 的
    /// 過時 `fetchLatestLive`（剛結束那一刻仍回該場）把已結束直播重新浮出。
    private var endedLiveIds: Set<String> = []

    private var pollTask: Task<Void, Never>?
    private var liveEndObserver: NSObjectProtocol?

    init(shopId: String,
         pollInterval: TimeInterval = 30,
         fetch: @escaping (String) async throws -> LBVideoItem? = { try await Livebuy.fetchLatestLive(id: $0) }) {
        self.shopId = shopId
        self.pollInterval = pollInterval
        self.fetch = fetch
        self.theme = ReferenceUIThemeResolver.resolve(
            coreTheme: (try? Livebuy.sdkConfig())?.theme, hostOptions: nil)
        observeLiveEnd()
    }

    // MARK: 輪詢生命週期

    /// 起輪詢（`onAppear`）。冪等：已在跑就跳過。
    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in await self?.pollLoop() }
    }

    /// 停輪詢（`onDisappear`）。
    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// `do/catch`（非 `try?`）區分「無直播」（nil → 清空入口）與「請求失敗 / 尚未
    /// configure」（throw → 保留狀態、3s 快重試）。成功則 `pollInterval`（預設 30s）穩定節奏。
    private func pollLoop() async {
        while !Task.isCancelled {
            do {
                let video = try await fetch(shopId)
                let gated = lbLiveEntryGate(video)
                await MainActor.run { self.apply(gated) }
                try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
            } catch {
                try? await Task.sleep(nanoseconds: 3_000_000_000)   // 3s 快重試（pre-configure / 網路）
            }
        }
    }

    // MARK: 狀態轉移（在 main thread 上呼叫——更動 @Published）

    /// 套用一筆**已 gate** 的結果。已被標記結束的 id 視為無直播（避免重新浮出）；換場
    /// （`id` 改變）時重置 `dismissed`、更新 `lastLiveId`，最後更新 `live`。
    func apply(_ gated: LBVideoItem?) {
        var next = gated
        if let id = next?.id, endedLiveIds.contains(id) { next = nil }   // 已結束 → 不再浮出
        if lbLiveEntryShouldResetDismiss(currentId: lastLiveId, newId: next?.id) {
            dismissed = false
            lastLiveId = next?.id
        }
        live = next
    }

    /// 記錄使用者關閉了目前這一場的入口。
    func dismiss() { dismissed = true }

    /// 收到 `.lbLiveEnded`：若目前正顯示的是一場現正直播（`liveStatus == 1`），立即清空
    /// `live`（即時隱藏，不等下一輪輪詢），並記住其 id 以免過時 fetch 把它重新浮出。
    /// 非直播時不動作（與這場 live-end 無關）。
    func handleLiveEnded() {
        guard live?.liveStatus == 1 else { return }
        if let id = live?.id { endedLiveIds.insert(id) }
        live = nil
        lastLiveId = nil
    }

    // MARK: live-end 通知訂閱

    private func observeLiveEnd() {
        liveEndObserver = NotificationCenter.default.addObserver(
            forName: .lbLiveEnded, object: nil, queue: nil) { [weak self] _ in
                guard let self = self else { return }
                if Thread.isMainThread {
                    self.handleLiveEnded()
                } else {
                    DispatchQueue.main.async { self.handleLiveEnded() }
                }
            }
    }

    // 對稱 `LivebuyWidgetController.deinit`：invalidate 輪詢、移除通知觀察者，避免洩漏。
    deinit {
        pollTask?.cancel()
        if let obs = liveEndObserver { NotificationCenter.default.removeObserver(obs) }
    }
}

// MARK: - Config（全選填、production-safe 預設）

/// `LivebuyLiveEntry` 的逐實例接線。每個互動 closure 皆 OPTIONAL 且有文件化預設；
/// 行為旗標帶 production-safe 預設。Promote 自 Example 的 floating-live 樣板參數。
public struct LivebuyLiveEntryConfig {

    /// 點整張浮窗。DEFAULT `nil` → 容器**預設以 `fullScreenCover` 開全螢幕 in-app `LivebuyPlayer`**
    /// （載入該浮窗影片；對齊 `LivebuyWidget.onTapVideo` 的預設開播放器，dropin-live-entry-default-open-player）。
    /// host 設了 → 完全覆蓋預設導頁；`{ _ in }` = 真 no-op。外部平台直播（`externalLiveWatchURL` 非 nil）
    /// → **預設開平台 URL**（優先序最高，與 widget 一致）；host 想自管外部直播設 `onTap` 即覆蓋整條。
    public var onTap: ((LBVideoItem) -> Void)?

    /// 關閉鈕。DEFAULT `nil`。預設行為＝隱藏到「下一場」（換新 `video.id` 才重新出現）；
    /// host 想完全永久關閉可在 `onClose` 自記旗標再條件式掛載容器。
    public var onClose: (() -> Void)?

    /// 輪詢間隔（秒）。DEFAULT `30`（`fetchLatestLive` 失敗則 3s 快重試）。
    public var pollInterval: TimeInterval = 30

    /// 可拖曳＋邊界 clamp。DEFAULT `true`（比照 Example floating-live-draggable）；
    /// host 不想要可關——關掉後容器**不加任何定位 chrome**，落點完全由 host 自己的
    /// `.overlay(alignment:)` + padding 決定（`position` / `inset` 皆不適用，見兩者的說明）。
    public var draggable: Bool = true

    /// 浮窗寬度（pt）。DEFAULT `132`（沿用 `FloatingWidgetView` 預設）。
    public var width: CGFloat = 132

    /// 可拖曳模式的靜止角落 inset：`width` = 距**所屬邊**（`position` 為右下 → trailing、
    /// 左下 → leading）、`height` = bottom（兩個落點相同）。DEFAULT
    /// `CGSize(width: 12, height: 24)`（沿用原寫死值，行為不變）。**單一來源**同時驅動靜止
    /// padding 與拖曳邊界 clamp 下界，故靜止位置與可拖範圍恆一致。host 有底部 chrome
    /// （TabBar / toolbar）時設 `CGSize(width: 12, height: 70)` 即可避位，無需外補 padding。
    /// 不可拖曳模式不適用（該模式由 host 自行以 `.overlay(alignment:)` + padding 定位）。
    public var inset: CGSize = CGSize(width: 12, height: 24)

    // MARK: floating_setting（host 注入的 raw wire 值；容器不自行讀 sdkConfig.extensions）

    /// 初始落點的 **raw** wire 值——host 從 `sdkConfig.extensions["floating_setting"]` 的
    /// `position` 取出後原樣指派（iOS 的 `extensions` 值型別是 `AnyEquatable`，需先解一層
    /// `.value`，見 `sdk-config` capability）。DEFAULT `nil` → 經
    /// `LBFloatingEntryPosition.normalized(_:)` 落回 `.rightBottom`，即 iOS 既有落點，
    /// **既有 host 呼叫端零改動、行為不變**。收 raw `String?`（而非 enum）是刻意的：值從 opaque
    /// bag 撈出來本來就是字串，正規化 / fallback 由本層獨佔，四端邊界才會一致。
    /// **僅可拖曳模式適用**——`draggable == false` 時容器不定位，落點屬 host。
    public var position: String?

    /// 出現時機的 **raw** wire 值（同上來源的 `timing`）。DEFAULT `nil` → 落回 `.immediate`，
    /// 即 iOS 既有時機（偵測到直播就畫、無等待無動畫）。**兩種 `draggable` 模式皆適用**：
    /// 它決定入口「存不存在」而非「畫在哪」，不影響 host 的版面。
    public var timing: String?

    /// `timing` 正規化為 `.delay` 時的等待秒數（同上來源的 `delay`，wire 是 Int 秒）。
    /// DEFAULT `3`（對齊後端該欄位預設）。負值 / 非有限值由 `lbLiveEntryAppearDelay` 收斂為 `0`。
    /// `.immediate` 時本欄位完全無作用。
    public var delay: TimeInterval = 3

    public init() {}
}

// MARK: - 量測卡片尺寸（拖曳 clamp 用）

/// 量測浮窗卡的尺寸，讓拖曳 clamp 知道卡片範圍（把離開靜止角落那一側的外緣留在容器內：
/// 錨右下時是左/上緣、錨左下時是右/上緣）。
/// 對應 Example `FloatingLiveCardSizeKey` / reference-ui `LivebuyPlayerPresenter.FloatingCardSizeKey`。
private struct LiveEntryCardSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

// MARK: - LivebuyLiveEntry（public turnkey 容器）

/// Turnkey drop-in「現正直播」浮窗入口。內含 `@StateObject` controller 持有輪詢 / gate /
/// dismissed / live-end 生命週期；`onAppear` 起輪詢、`onDisappear` 停。無直播 / 已關閉 /
/// 尚未偵測到直播 / `timing` 為 `.delay` 且尚在倒數時渲染 `EmptyView`（不佔可見表面）。
/// 像素 reuse `FloatingWidgetView`。落點（`config.position`）與出現時機（`config.timing` /
/// `config.delay`）的完整語意見型別檔頭與各 config 欄位說明。
public struct LivebuyLiveEntry: View {

    @StateObject private var controller: LivebuyLiveEntryController
    private let config: LivebuyLiveEntryConfig

    // 拖曳狀態（比照 Example floating-live：committed offset + 進行中位移 + 量測卡片尺寸）。
    @State private var offset: CGSize = .zero
    @State private var dragTranslation: CGSize = .zero
    @State private var cardSize: CGSize = .zero

    /// 出現時機閘（rb-ios-floating-entry-position-timing）。`.immediate` 下由兩個 init **恆設為
    /// `true`**——不依賴 `.onAppear`、不進任何排程，故該模式下這個閘等於不存在，行為與本 change
    /// 之前逐位元相同。`.delay` 下初值 `false`，由 `scheduleAppearance(eligible:)` 在倒數結束時翻起。
    @State private var appeared: Bool
    /// 待執行的延遲出現排程；每次重新排程前先 `cancel()`（沿用同層 `ActivityToastView.dismissWork`
    /// 的 iOS-14-safe 形狀：`DispatchWorkItem` + `asyncAfter`，不用 iOS 15 的 `.task`）。
    @State private var appearWork: DispatchWorkItem?

    /// Test-only 讀取窗（internal-testability；`internal`，host app 看不到）：讓單測能對一個
    /// **剛建構、尚未 mount** 的容器讀出出現時機閘的初值，藉此釘住「`.immediate` 一建構就已現身」
    /// 這條——若把兩個 init 的 `initialValue` 改成恆 `false`，預設 host 的入口會永遠不出現，
    /// 而純函式層級的測試抓不到那個突變（呼叫點沒被釘住）。
    var appearedForTesting: Bool { appeared }

    /// Default-open player presentation (dropin-live-entry-default-open-player)：點非外部浮窗
    /// 只在 host **未接** `config.onTap` 時設此 → body 的 `.fullScreenCover` 開全螢幕 `LivebuyPlayer`。
    /// 用 `fullScreenCover`（而非 self-attach 持久 `.livebuyPlayer` overlay）讓 player 不被浮窗的小尺寸
    /// 框限、全螢幕呈現（design D1，同 widget change）。host 設了 `onTap` → 永不設此（cover 不 arm）。
    /// `LBVideoItem` 非 `Identifiable` → 私有 wrapper。
    @State private var defaultPresented: PresentedVideo?

    /// `fullScreenCover(item:)` 用的 `Identifiable` wrapper（`LBVideoItem` 本身非 Identifiable）。
    private struct PresentedVideo: Identifiable {
        let id: String
        let item: LBVideoItem
    }

    /// Public host-facing 「直播已結束」即時隱藏訊號入口。host 在自家 live-end 判斷成立時
    /// （例如 event listener 收到 core `POLL_RECEIVED` + `live_end == 1`）呼叫此型別安全入口，
    /// 讓正顯示中的容器立即隱藏，**取代硬寫 `Notification.Name("lb_live_ended")`**。內部 post
    /// 既有 internal `.lbLiveEnded`（raw value 不變、容器 observer 不變），故對 drop-in player 的
    /// 既有 ambient 路徑零影響。使用 turnkey 容器時此訊號為**選用**（immediacy-only）：即使 host
    /// 從不呼叫，容器自身 30s 輪詢 + `liveStatus == 1` gate 仍會在一個 `pollInterval` 內隱藏。
    public static func signalLiveEnded() {
        NotificationCenter.default.post(name: .lbLiveEnded, object: nil)
    }

    public init(shopId: String, config: LivebuyLiveEntryConfig = LivebuyLiveEntryConfig()) {
        _controller = StateObject(wrappedValue: LivebuyLiveEntryController(
            shopId: shopId, pollInterval: config.pollInterval))
        _appeared = State(initialValue: lbLiveEntryInitialAppeared(timing: config.timing))
        self.config = config
    }

    /// Test-only injection point（internal-testability；NOT public，host app 只看得到
    /// 上面 `init(shopId:config:)`）：讓 `@testable` 測試能用假 `fetch` 真的 mount 這個
    /// `body`（透過 `UIHostingController` 走一輪真的 SwiftUI render pass），而不是直接呼叫
    /// controller 方法——這是唯一能證明 `.onAppear` 真的被 SwiftUI 觸發的方式
    /// （live-entry-onappear-poll-start-fix regression coverage）。
    init(shopId: String,
         config: LivebuyLiveEntryConfig = LivebuyLiveEntryConfig(),
         fetchForTesting: @escaping (String) async throws -> LBVideoItem?) {
        _controller = StateObject(wrappedValue: LivebuyLiveEntryController(
            shopId: shopId, pollInterval: config.pollInterval, fetch: fetchForTesting))
        _appeared = State(initialValue: lbLiveEntryInitialAppeared(timing: config.timing))
        self.config = config
    }

    // live-entry-onappear-poll-start-fix：`content` 第一次 render 必然是 `EmptyView()`
    // （controller 剛建構、`live` 必為 nil，還沒 poll 過），若 `.onAppear` 直接掛在 `content`
    // 上，SwiftUI 對「當下解析成 EmptyView() 的分支」不保證觸發 `.onAppear`——已用 lldb 對
    // 實機驗證：`body` / `content` getter 都有被呼叫，但 `.onAppear` closure 永遠不執行，
    // 造成 `controller.start()` 永遠不跑、輪詢永遠不開始的死鎖。改把 `content` 包進一個「不論
    // `controller.live` 是否為 nil 都恆不是 EmptyView()」的 `ZStack`（恆存在的 `Color.clear`
    // sibling），`.onAppear`/`.onDisappear` 改掛在這個 `ZStack` 上——保證輪詢一掛載就必定起
    // 跑，不受目前有沒有偵測到直播影響。當時該 fix **沒有動** `content` 自身的
    // `EmptyView()` / `entry(live)` 分支；後續 rb-ios-floating-entry-position-timing 在該分支的
    // 條件前加了出現時機閘 `appeared`（`.immediate` 下恆 true），這不影響上述 `.onAppear` 掛在
    // `ZStack` 上的結論——`content` 仍可能解析成 `EmptyView()`，`ZStack` 仍恆不是。
    public var body: some View {
        ZStack {
            Color.clear   // 恆存在、零視覺足跡——只為讓這一層永遠不是 EmptyView()。
            content
        }
        .onAppear { controller.start() }
        .onDisappear { controller.stop() }
        // 延遲出現（rb-ios-floating-entry-position-timing）：倒數從「入口第一次變成可顯示」起算，
        // 不是從容器掛載起算——容器是 host 常駐掛載的，偵測不到直播時渲染 EmptyView；若從掛載
        // 起算，開播晚於倒數的場次會讓 `.delay` 靜默退化成 `.immediate`。`.immediate` 下
        // `scheduleAppearance` 立刻 return，這條 onChange 等於不存在。
        .onChange(of: hasEligibleEntry) { eligible in scheduleAppearance(eligible: eligible) }
        // Default-open player (dropin-live-entry-default-open-player)。`defaultPresented == nil`
        // 時 inert（host 接了 onTap，或尚未點）→ 靜止時不加任何可見像素，既有 live-entry /
        // FloatingWidgetView baseline byte-identical。
        .fullScreenCover(item: $defaultPresented) { p in
            LivebuyPlayer(videoId: p.id, config: defaultPlayerConfig)
                .ignoresSafeArea()
        }
    }

    /// `appeared`（出現時機閘）、`dismissed == false` 且 `live != nil` 三者皆成立才渲染入口，
    /// 否則為 `EmptyView`。`.immediate` 下 `appeared` 恆 `true`，條件等同本 change 之前。
    @ViewBuilder
    private var content: some View {
        if appeared, !controller.dismissed, let live = controller.live {
            entryWithEntrance(live)
        } else {
            EmptyView()
        }
    }

    /// `.delay` 才掛進場 transition；`.immediate` 回傳**未加任何 transition** 的原樣入口
    /// （不是掛 `.identity`——沒掛 transition 與掛 `.identity` 在被外部動畫交易包住時語意不同，
    /// 這裡要的是「與本 change 之前逐位元相同」）。
    @ViewBuilder
    private func entryWithEntrance(_ live: LBVideoItem) -> some View {
        if resolvedTiming == .delay {
            entry(live).transition(Self.entranceTransition(for: resolvedPosition))
        } else {
            entry(live)
        }
    }

    /// 入口卡：`draggable` 時包 `GeometryReader` + drag 手勢 + 邊界 clamp，靜止角落依
    /// `config.position`；否則回傳裸卡片、不加任何定位 chrome（落點屬 host，見型別檔頭）。
    @ViewBuilder
    private func entry(_ live: LBVideoItem) -> some View {
        if config.draggable {
            GeometryReader { geo in
                card(live)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(key: LiveEntryCardSizeKey.self, value: proxy.size)
                        })
                    .onPreferenceChange(LiveEntryCardSizeKey.self) { cardSize = $0 }
                    // 自靜止角落的位移（committed + 進行中），再錨定該角落（右下 / 左下）。
                    .offset(x: offset.width + dragTranslation.width,
                            y: offset.height + dragTranslation.height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: restingAlignment)
                    .padding(restingEdge, config.inset.width)
                    .padding(.bottom, config.inset.height)
                    // minDistance 8：< 8pt 觸碰保持為 tap（onTap / onClose 照常觸發）；
                    // 確實拖曳才移位。highPriority 讓它勝過卡片本體（drag / tap 門檻分離）。
                    .highPriorityGesture(dragGesture(containerSize: geo.size))
            }
        } else {
            card(live)
        }
    }

    // MARK: - 落點 / 時機解析（唯一呼叫 normalized(_:) 的地方）

    /// raw `config.position` → 落點。view body 內 MUST NOT 再出現任何 raw 字串比較。
    private var resolvedPosition: LBFloatingEntryPosition { .normalized(config.position) }
    /// raw `config.timing` → 時機。
    private var resolvedTiming: LBFloatingEntryTiming { .normalized(config.timing) }
    /// 靜止角落（可拖曳模式）。
    private var restingAlignment: Alignment {
        resolvedPosition == .leftBottom ? .bottomLeading : .bottomTrailing
    }
    /// `inset.width` 貼的那一邊（可拖曳模式）。
    private var restingEdge: Edge.Set {
        resolvedPosition == .leftBottom ? .leading : .trailing
    }
    /// 入口目前「有東西可顯示」——延遲倒數的起算條件（與 `content` 的另外兩個條件同源）。
    private var hasEligibleEntry: Bool { !controller.dismissed && controller.live != nil }

    // MARK: - 延遲出現排程

    /// 可顯示狀態翻轉時重排延遲出現。`.immediate` 直接 return（該模式完全不進排程）。
    /// 不可顯示 → 取消排程並收回閘（下一場重新倒數）；可顯示 → 取消舊排程、收回閘、等
    /// `lbLiveEntryAppearDelay` 秒後在 `withAnimation` 交易裡翻起（讓 `.transition` 真的播）。
    /// 起算條件刻意用「可不可顯示」這個布林，而非直播 id：A 場**無縫**接 B 場（中間沒有一刻
    /// 不可顯示）時只換內容、不重播延遲進場——延遲進場是給「入口從無到有」用的，中途換場再等
    /// 一次反而像卡住。有空窗（結束 / 被關閉）才會重新倒數。
    /// 即使排程漏了作廢也畫不出東西：`appeared` 只是 `content` 三個條件之一。
    private func scheduleAppearance(eligible: Bool) {
        guard resolvedTiming == .delay else { return }
        appearWork?.cancel()
        appearWork = nil
        appeared = false
        guard eligible else { return }
        let work = DispatchWorkItem {
            withAnimation(Self.entranceAnimation) { appeared = true }
        }
        appearWork = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + lbLiveEntryAppearDelay(timing: .delay, delay: config.delay),
            execute: work)
    }

    // MARK: - 進場動畫常數（對齊設計稿 `lbp-float-in`；四端 parity 照抄同一組數值）

    /// 設計稿 `animation: lbp-float-in 0.42s cubic-bezier(0.22,1,0.36,1) both` 的時間曲線與時長。
    static let entranceAnimation = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.42)
    /// 設計稿 keyframe `0% { transform: scale(0.78) }` 的縮放起點。
    static let entranceScale: CGFloat = 0.78
    /// 設計稿 keyframe `0% { transform: translateY(16px) }` 的垂直位移起點。
    static let entranceOffsetY: CGFloat = 16
    /// 設計稿 `transformOrigin: side === 'left' ? 'left bottom' : 'right bottom'`（縮放錨點跟著落點）。
    static func entranceTransition(for position: LBFloatingEntryPosition) -> AnyTransition {
        let anchor: UnitPoint = position == .leftBottom ? .bottomLeading : .bottomTrailing
        return AnyTransition.scale(scale: entranceScale, anchor: anchor)
            .combined(with: .opacity)
            .combined(with: .offset(y: entranceOffsetY))
    }

    /// reuse 既有 `FloatingWidgetView` 像素。`onTap` 路由（dropin-live-entry-default-open-player）：
    /// 外部平台直播 → 開平台 URL（`externalLiveAwareTap`，優先序最高，與 widget 一致）；非外部 →
    /// host `config.onTap` 若接、否則預設開 in-app player（`effectiveOnTap`）。`onClose` 轉交 host 後
    /// 標記 dismissed。
    private func card(_ live: LBVideoItem) -> some View {
        FloatingWidgetView(
            video: live,
            theme: controller.theme,
            width: config.width,
            live: true,
            onTap: externalLiveAwareTap(effectiveOnTap),
            onClose: {
                config.onClose?()
                controller.dismiss()
            })
    }

    /// 非外部浮窗的點擊 handler（dropin-live-entry-default-open-player）：host 的 `config.onTap`
    /// 若接（完全覆蓋，預設 cover 永不 arm），否則預設開 in-app player（`fullScreenCover`）。host 想讓
    /// 點擊真 no-op 設 `onTap = { _ in }`。外部平台直播不會走到這（由外層 `externalLiveAwareTap` 處理）。
    private var effectiveOnTap: (LBVideoItem) -> Void {
        if let hostTap = config.onTap { return hostTap }
        return { item in defaultPresented = PresentedVideo(id: item.id, item: item) }
    }

    /// 預設開播放器的 config。entry 無 `design` 欄位（用 sdkConfig theme 同源 resolver 解析），故
    /// player 沿用預設 `MinimalDesign`，品牌與入口卡一致。`onDismiss` / `onMinimize` 清
    /// `defaultPresented` 以關 `fullScreenCover`——cover 無 floating-preview target（minimize→floating
    /// 收合需 root 級 `.livebuyPlayer` presenter，design D1 取捨），故 minimize 即關；player 自身的
    /// `dismiss(animated:)` 預設無法關 SwiftUI cover。
    private var defaultPlayerConfig: LivebuyPlayerConfig {
        var c = LivebuyPlayerConfig()
        c.onDismiss = { _ in defaultPresented = nil }
        c.onMinimize = { defaultPresented = nil }
        return c
    }

    /// 拖曳手勢——比照 Example floating-live / 最小化播放器卡：進行中追位移，結束時 clamp 後 commit
    /// （未達門檻的觸碰是 tap，不是 drag）。
    private func dragGesture(containerSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in dragTranslation = value.translation }
            .onEnded { value in
                offset = lbLiveEntryClampOffset(
                    committed: offset,
                    translation: value.translation,
                    cardSize: cardSize,
                    containerSize: containerSize,
                    inset: config.inset,
                    position: resolvedPosition)
                dragTranslation = .zero
            }
    }
}
