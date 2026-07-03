import SwiftUI
import LiveBuySDK
import LiveBuyUI

// MARK: - LiveBuyLiveEntry — turnkey drop-in「現正直播」浮窗入口容器（Tier B）
//
// 「全店現正有直播時，畫面角落浮一張入口卡，點了開播放器」是直播導流的主入口。SDK 從
// 未把它做成 drop-in：`quickstart §8.1` 要 host「自組」——自己 30s 輪詢
// `LiveBuy.fetchLatestLive`、自己 gate `liveStatus == 1`、自己組裸 `FloatingWidgetView`、
// 自己接 dismiss / live_end 即時隱藏 / 拖曳 clamp。這段邏輯已在四端 Example 各自重抄一遍
// （`ContentView.FloatingLiveModel` ＋拖曳手勢＋`.lbLiveEnded` 監聽＋`dismissed` 狀態）。
//
// `LiveBuyLiveEntry` 把它 PROMOTE 進套件，比照既有 `LiveBuyWidget` / `LiveBuyPlayer`
// （archive `introduce-dropin-widget-container`）的「Example 控制器 → 一行 drop-in」模式，
// 讓 host 一行接好：
//
//     YourHomeView()
//         .overlay(alignment: .bottomTrailing) {
//             LiveBuyLiveEntry(shopId: "Pw8PJ99J")               // 全預設
//         }
//
//     // 或帶 config：
//     LiveBuyLiveEntry(shopId: "Pw8PJ99J", config: cfg)
//
// 與 `LiveBuyWidget(mode: .floating)` 的差異（避免混淆）：
//   • `LiveBuyWidget(mode: .floating)` ＝「指定**單一 videoId** 的迷你播放器浮窗」。
//   • `LiveBuyLiveEntry` ＝「**自動偵測全店現正直播**的入口卡」——host 不指定 video，
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

/// 把拖曳後的 offset clamp 在容器邊界內——與 reference-ui `LiveBuyPlayerPresenter`
/// 的 `clampFloatingOffset` 同語義（bottom-trailing 錨點：x/y ≤ 0；下界讓卡片的左/上緣
/// 留在容器內、扣掉靜止 inset）。純函式（無狀態），幾何易於推理。
func lbLiveEntryClampOffset(
    committed: CGSize, translation: CGSize,
    cardSize: CGSize, containerSize: CGSize, inset: CGSize
) -> CGSize {
    let desiredX = committed.width + translation.width
    let desiredY = committed.height + translation.height
    let minX = min(0, -(containerSize.width - cardSize.width - inset.width))
    let minY = min(0, -(containerSize.height - cardSize.height - inset.height))
    let clampedX = max(minX, min(0, desiredX))
    let clampedY = max(minY, min(0, desiredY))
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

// MARK: - Controller（生命週期：輪詢 / gate / dismissed / live-end，對稱 LiveBuyWidgetController）

/// 擁有「現正直播」入口的生命週期：輪詢 `LiveBuy.fetchLatestLive` → 經 `lbLiveEntryGate`
/// 只認 `liveStatus == 1` → 換場重置 `dismissed` → 監聽 `.lbLiveEnded` 即時隱藏。所有副作用
/// （輪詢 Task、通知訂閱、dismissed 狀態）收在這裡，view 透過 `@Published` 綁定（對稱
/// `LiveBuyWidgetController`）。`fetch` 由 ctor 注入（internal-testability：副作用注入），
/// 預設綁 `LiveBuy.fetchLatestLive(id:)`，單測可換 `Fake*`。
final class LiveBuyLiveEntryController: ObservableObject {

    /// 目前要預覽的現正直播，或 nil（無直播 / 被 gate 吸收 / 已結束）。驅動入口的存在與否。
    @Published private(set) var live: LBVideoItem?
    /// 使用者是否關閉了「目前這一場」的入口。換新一場 `id` 時重置（見 `apply`）。
    @Published private(set) var dismissed: Bool = false

    /// 解析後的 reference-ui theme（`sdkConfig.theme` → minimal palette），與
    /// `LiveBuyPlayer` / 最小化播放器卡同一 resolver，讓入口卡與播放器品牌一致。
    let theme: ReferenceUITheme

    private let shopId: String
    private let pollInterval: TimeInterval
    /// 注入的 fetch 副作用（預設 `LiveBuy.fetchLatestLive(id:)`）。
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
         fetch: @escaping (String) async throws -> LBVideoItem? = { try await LiveBuy.fetchLatestLive(id: $0) }) {
        self.shopId = shopId
        self.pollInterval = pollInterval
        self.fetch = fetch
        self.theme = ReferenceUIThemeResolver.resolve(
            coreTheme: (try? LiveBuy.sdkConfig())?.theme, hostOptions: nil)
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

    // 對稱 `LiveBuyWidgetController.deinit`：invalidate 輪詢、移除通知觀察者，避免洩漏。
    deinit {
        pollTask?.cancel()
        if let obs = liveEndObserver { NotificationCenter.default.removeObserver(obs) }
    }
}

// MARK: - Config（全選填、production-safe 預設）

/// `LiveBuyLiveEntry` 的逐實例接線。每個互動 closure 皆 OPTIONAL 且有文件化預設；
/// 行為旗標帶 production-safe 預設。Promote 自 Example 的 floating-live 樣板參數。
public struct LiveBuyLiveEntryConfig {

    /// 點整張浮窗。DEFAULT `nil` → 容器**預設以 `fullScreenCover` 開全螢幕 in-app `LiveBuyPlayer`**
    /// （載入該浮窗影片；對齊 `LiveBuyWidget.onTapVideo` 的預設開播放器，dropin-live-entry-default-open-player）。
    /// host 設了 → 完全覆蓋預設導頁；`{ _ in }` = 真 no-op。外部平台直播（`externalLiveWatchURL` 非 nil）
    /// → **預設開平台 URL**（優先序最高，與 widget 一致）；host 想自管外部直播設 `onTap` 即覆蓋整條。
    public var onTap: ((LBVideoItem) -> Void)?

    /// 關閉鈕。DEFAULT `nil`。預設行為＝隱藏到「下一場」（換新 `video.id` 才重新出現）；
    /// host 想完全永久關閉可在 `onClose` 自記旗標再條件式掛載容器。
    public var onClose: (() -> Void)?

    /// 輪詢間隔（秒）。DEFAULT `30`（`fetchLatestLive` 失敗則 3s 快重試）。
    public var pollInterval: TimeInterval = 30

    /// 可拖曳＋邊界 clamp。DEFAULT `true`（比照 Example floating-live-draggable）；
    /// host 不想要可關（固定 bottom-trailing）。
    public var draggable: Bool = true

    /// 浮窗寬度（pt）。DEFAULT `132`（沿用 `FloatingWidgetView` 預設）。
    public var width: CGFloat = 132

    /// 可拖曳模式的靜止角落 inset：`width` = trailing、`height` = bottom。DEFAULT
    /// `CGSize(width: 12, height: 24)`（沿用原寫死值，行為不變）。**單一來源**同時驅動靜止
    /// padding 與拖曳邊界 clamp 下界，故靜止位置與可拖範圍恆一致。host 有底部 chrome
    /// （TabBar / toolbar）時設 `CGSize(width: 12, height: 70)` 即可避位，無需外補 padding。
    /// 不可拖曳模式不適用（該模式由 host 自行以 `.overlay(alignment:)` + padding 定位）。
    public var inset: CGSize = CGSize(width: 12, height: 24)

    public init() {}
}

// MARK: - 量測卡片尺寸（拖曳 clamp 用）

/// 量測浮窗卡的尺寸，讓拖曳 clamp 知道卡片範圍（把左/上緣留在容器內）。
/// 對應 Example `FloatingLiveCardSizeKey` / reference-ui `LiveBuyPlayerPresenter.FloatingCardSizeKey`。
private struct LiveEntryCardSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

// MARK: - LiveBuyLiveEntry（public turnkey 容器）

/// Turnkey drop-in「現正直播」浮窗入口。內含 `@StateObject` controller 持有輪詢 / gate /
/// dismissed / live-end 生命週期；`onAppear` 起輪詢、`onDisappear` 停。無直播 / 已關閉 /
/// 尚未偵測到直播時渲染 `EmptyView`（不佔可見表面）。像素 reuse `FloatingWidgetView`。
public struct LiveBuyLiveEntry: View {

    @StateObject private var controller: LiveBuyLiveEntryController
    private let config: LiveBuyLiveEntryConfig

    // 拖曳狀態（比照 Example floating-live：committed offset + 進行中位移 + 量測卡片尺寸）。
    @State private var offset: CGSize = .zero
    @State private var dragTranslation: CGSize = .zero
    @State private var cardSize: CGSize = .zero

    /// Default-open player presentation (dropin-live-entry-default-open-player)：點非外部浮窗
    /// 只在 host **未接** `config.onTap` 時設此 → body 的 `.fullScreenCover` 開全螢幕 `LiveBuyPlayer`。
    /// 用 `fullScreenCover`（而非 self-attach 持久 `.liveBuyPlayer` overlay）讓 player 不被浮窗的小尺寸
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

    public init(shopId: String, config: LiveBuyLiveEntryConfig = LiveBuyLiveEntryConfig()) {
        _controller = StateObject(wrappedValue: LiveBuyLiveEntryController(
            shopId: shopId, pollInterval: config.pollInterval))
        self.config = config
    }

    public var body: some View {
        content
            .onAppear { controller.start() }
            .onDisappear { controller.stop() }
            // Default-open player (dropin-live-entry-default-open-player)。`defaultPresented == nil`
            // 時 inert（host 接了 onTap，或尚未點）→ 靜止時不加任何可見像素，既有 live-entry /
            // FloatingWidgetView baseline byte-identical。
            .fullScreenCover(item: $defaultPresented) { p in
                LiveBuyPlayer(videoId: p.id, config: defaultPlayerConfig)
                    .ignoresSafeArea()
            }
    }

    /// `dismissed == false` 且 `live != nil` 才渲染入口，否則（含 live == nil）為 `EmptyView`。
    @ViewBuilder
    private var content: some View {
        if !controller.dismissed, let live = controller.live {
            entry(live)
        } else {
            EmptyView()
        }
    }

    /// 入口卡：`draggable` 時包 `GeometryReader` + drag 手勢 + 邊界 clamp；否則固定 bottom-trailing。
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
                    // 自靜止角落的位移（committed + 進行中），再錨定 bottom-trailing。
                    .offset(x: offset.width + dragTranslation.width,
                            y: offset.height + dragTranslation.height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, config.inset.width)
                    .padding(.bottom, config.inset.height)
                    // minDistance 8：< 8pt 觸碰保持為 tap（onTap / onClose 照常觸發）；
                    // 確實拖曳才移位。highPriority 讓它勝過卡片本體（drag / tap 門檻分離）。
                    .highPriorityGesture(dragGesture(containerSize: geo.size))
            }
        } else {
            card(live)
        }
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
    /// 收合需 root 級 `.liveBuyPlayer` presenter，design D1 取捨），故 minimize 即關；player 自身的
    /// `dismiss(animated:)` 預設無法關 SwiftUI cover。
    private var defaultPlayerConfig: LiveBuyPlayerConfig {
        var c = LiveBuyPlayerConfig()
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
                    inset: config.inset)
                dragTranslation = .zero
            }
    }
}
