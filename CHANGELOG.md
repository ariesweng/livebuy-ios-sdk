# Changelog

All notable changes to the Livebuy iOS SDK will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [4.18.0] - 2026-09-11

> **Minor.** 自 `4.17.0` 以來累積 169 個 commit（iOS 14 個獨立行為——含發版準備期間追加的
> 「靜音偏好跨 App session 持久化」與「回放聊天室隱藏公式補上 subtitleAvailable 判斷」兩批，
> 另 1 個 QA 工具腳本 commit 與 1 個支援性 baseline 重生 commit 不計入本檔）。主軸是 CC 字幕鈕圖示重新設計
> （design R42：3-state Font Awesome closed-captioning glyph，不可用時恆渲染＋提示
> tooltip）、主播斷線後的確認式恢復、字幕疊層對齊與底部安全間隙收斂、EndScreen 直播結束
> 畫面 gate 鎖存修復。**含 1 項 ⚠️ BREAKING**（CC 字幕圖示重新設計，iOS + Android 皆有）——
> 比照 v4.5.0/v4.8.0/v4.9.0/v4.11.0/v4.13.0/v4.14.0/v4.15.0/v4.16.0/v4.17.0 先例，整輪仍
> 判定 minor。完整敘述見 [`docs/release-notes/v4.18.0.md`](../docs/release-notes/v4.18.0.md)。

### Added

- **主播斷線重試耗盡後的確認式恢復**（core）：既有 20 秒 channel-refresh 確認頻道仍在線即
  自動重新載入，取代過去卡在錯誤畫面直到手動離開重進。
- **靜音偏好跨 App session 於 Player instance 重建後持久化**（core）：新增 process-wide、
  純記憶體的 `MutePreferenceStore`，讓關閉播放器再重新開啟的新 instance 沿用使用者剛
  設定的靜音偏好，補齊既有「僅同一 instance 內 in-place 換片沿用」的空白；新增 public
  `isMuted` getter，供 host / template 層查詢目前實際的靜音狀態。

### Changed

- **開場片播放期間 `setMuted` 現在會延續到主播放**（core），反轉先前「intro 交棒不延續」
  的規則（`play` / `pause` 不受影響，仍不延續）；開場片本身也改為一律套用目前的
  `userMuted`，取代下方「依首次開啟／換片分流」的舊規則。
- **⚠️ BREAKING — CC 字幕鈕圖示重新設計**（design R42，reference-ui）：反轉既有「不可用時
  整個省略 pill」的 MUST 規則，改為恆渲染 + 點擊顯示自動消失 tooltip；3-state glyph 取代
  舊版單一手繪樣式。純視覺/互動行為變更，不影響任何 public API 簽章或事件契約。
- **字幕疊層從 leading-align 改為對齊設計稿的窄框內水平置中**（reference-ui），回放開字幕
  時同步隱藏聊天室。
- **`LivebuyLiveEntry` 浮動入口卡隱藏觀看人數徽章**（reference-ui）。

### Fixed

- **EndScreen 直播結束畫面 gate 鎖存 `isLiveChannel`**（reference-ui），避免背景 channel
  刷新的無關改動誤判為關閉 player。
- **開場片改依「首次開啟／換片」分流靜音**（core），修復真機回報「靜音切片後開場片跑出
  聲音」（本輪已被上方「跨 App session 持久化」進一步取代，開場片改為一律套用
  `userMuted`，不再需要分流）。
- **靜音圖示 attach 種子改讀新的 `isMuted` getter**（template），修復真機實測回報「音訊
  已正確依偏好靜音，但音量圖示沒套用到，需手動點一次才同步」。
- **字幕疊層/釘選卡/公告底部安全間隙改為單一事實來源**（reference-ui）。
- **VOD 字幕疊層改為獨立疊層，固定預留商品卡空間**（reference-ui，iOS-only）。
- **回放聊天室隱藏公式補上 `subtitleAvailable` 判斷**（reference-ui），修復 CC 開關跨影片
  保留但切到沒有字幕的影片時無法關閉、導致聊天室在沒有任何字幕顯示的情況下永久隱藏、
  使用者無法恢復的缺口。
- **CC「未提供字幕」tooltip 邊界夾制後箭頭改為反向補償**（reference-ui）。
- **CC「未提供字幕」tooltip 補上邊界夾制**（reference-ui），回放不再超出螢幕右緣。
- **CC 不可用 tooltip 補上外部定位邏輯**（reference-ui，iOS-only）。
- **LIVE 底部列 CC 切換鈕啟用時改 active 填色態**（reference-ui，iOS-only）。

## [4.17.0] - 2026-09-10

> **Minor.** 自 `4.16.0` 以來累積 69 個 commit（iOS 14 個獨立行為，另 1 個支援性 baseline
> 重生 commit，另 2 個 Example demo app 修復不計入本檔）。主軸是現正直播 pill turnkey 化＋
> 輪詢短 TTL 快取、EndScreen 直播結束畫面重新設計（design R41）、直播公告橫幅圖示改 bullhorn
> 向量、聊天室「最新訊息」pill 改白底 accent 字、CC 字幕 icon 啟用 active 填色態，以及一系列
> 使用者實機回報後的修復。**含 1 項 ⚠️ BREAKING（僅 iOS）**——比照
> v4.5.0/v4.8.0/v4.9.0/v4.11.0/v4.13.0/v4.14.0/v4.15.0/v4.16.0 先例，整輪仍判定 minor。完整
> 敘述見 [`docs/release-notes/v4.17.0.md`](../docs/release-notes/v4.17.0.md)。

### Added

- **`LivebuySDK.currentShopId() -> String?`**（core）：`configure()` 最後一次呼叫帶入 shopId
  的唯讀回讀，仿照既有 `currentFbc()`/`currentFbp()` 回讀對。
- **現正直播 pill／浮動入口輪詢加一層唯讀短 TTL（5 秒）快取**（reference-ui），省下切換瞬間
  的重複 API call。
- **CC 字幕 icon 啟用時改 active 填色態**（reference-ui）。
- **直播模式點商品縮圖跳過關閉商品列表抽屜**（reference-ui）。
- **聊天室加入活動列改顯示訊息自帶主播名**（template + reference-ui）。
- **商品照片載入體驗優化**：提早 prefetch + 淡入轉場 + 佔位色改中性灰階（reference-ui）。

### Changed

- **聊天室「最新訊息」pill 改白底 accent 字**（背景/前景色源角色互換，reference-ui）。
- **EndScreen 直播結束畫面重新設計**（design R41）：移除熱門推薦變體卡牆，改為直播限定的
  倒數／無推薦兩態極簡空狀態。
- **直播公告橫幅圖示改為自訂 bullhorn 向量路徑**，取代原本系統 SF Symbol 暫代品。
- **⚠️ BREAKING（僅 iOS）— `LivebuyPlayerConfig` 現正直播 pill 預設改為開啟並自動帶入
  shopId**：新增 `showsLiveNowPill: Bool = true`（預設 on），`shopId == nil` 時改用
  `LivebuySDK.currentShopId()` 自動解析。任何已 `configure(shopId:)` 且未手動設定
  `LivebuyPlayerConfig.shopId` 的 host，升級後會開始看到這顆 pill；想維持舊行為設
  `showsLiveNowPill = false`。純行為預設值翻轉，無 API 簽章破壞。

### Fixed

- **`PollManager` 丟棄換片時飛行中的過期 poll 回應**（core），修復切換直播時聊天室短暫顯示
  前一場快取訊息。
- **換片時補齊商品明細 sheet-stack 五個 view-model 重置**（template：`variantPicker` /
  `qtyStepper` / `miniCart` / `cartCTA` / `productSheet`）。
- **商品明細切換「更多商品」推薦商品時，捲動位置重置回最上方**（reference-ui）。
- **已結束直播回放改用嚴格 `isLive` 排除，讓真正 VTT/CC 字幕可顯示**（reference-ui）。
- **觀眾留言暱稱冒號改回白色，不再誤套暱稱粉色**（reference-ui）。

## [4.16.0] - 2026-09-09

> **Minor.** 自 `4.15.0` 以來累積 109 個 commit（iOS 17 個獨立行為，另 2 個為既有功能的
> snapshot baseline 重生／素材補交支援性 commit）。主軸是商品名稱標籤系統落地（design R39：
> LIVE 直播價/搶購中、VOD/回放熱賣中/即將售完）、讚特效重寫兩輪（design R37 手繪版 → PNG
> 素材版）、「介紹中」等化器呼吸動畫（design R40）、`isFlashSale` 旗標（core，additive）、
> 浮動小卡新增 `inset` host 覆寫、觀眾留言暱稱粉色化＋不限行數等一系列使用者驗收/實機回報
> 後的新增與修復。**含 1 項 ⚠️ BREAKING**（reference-ui-internal 視覺行為）——比照
> v4.5.0/v4.8.0/v4.9.0/v4.11.0/v4.13.0/v4.14.0/v4.15.0 先例，整輪仍判定 minor。完整敘述見
> [`docs/release-notes/v4.16.0.md`](../docs/release-notes/v4.16.0.md)。

### Added

- **`LBChannel.isFlashSale`**（core，additive，解碼 `/sdk/video` 新欄位 `is_flash_sale`）。
- **`DefaultPlayerHeaderState.isFlashSale`**（view-model 投影）。
- **商品名稱標籤系統落地**（design R39）：LIVE 直播價/搶購中、VOD/回放熱賣中/即將售完，
  「搶購中」分支接上真實 `isFlashSale` 資料。
- **浮動小卡新增 `inset` host 覆寫參數**（既有 `position` 覆寫的延伸）。
- **商品 sheet 開啟時抑制垂直滑動換片**（防禦性補強）。

### Changed

- **一般觀眾留言暱稱改固定粉色 `#FBB0B7` + 訊息不限行數**（撤回原先觀眾留言行數上限）。
- **「介紹中」等化器圖示改呼吸動畫**，取代靜態版（design R40）。
- **讚按鈕特效重寫**：4 種隨機圖案×3 種軌跡×3 種擺動 + liked 亮色態（design R37）。
- **⚠️ BREAKING — 讚特效 4 種圖案全改用真實 PNG 素材**：heart 圖案不再吃呼叫端
  `color`/`theme.accent` 染色，改為顯示 PNG 本身烘焙好的固定色（`color` 參數保留供源碼相容，
  純視覺行為，無 API 簽章影響）。

### Fixed

- **乾淨模式退出鈕拿掉重複疊加的動態墊高**（88→52）。
- **商品明細大圖橫向換頁手勢修復阻擋外層 sheet 垂直捲動**。
- **VOD「正在介紹」商品卡輪播出現時機提早於側欄/浮動商品袋**：改為共用同一渲染閘門
  （`showsVodMainChrome`），三者顯示時機一致，不再於開場序列（`.loading`/`.splash`）階段
  提早出現。
- **`bindSession`/`clearUser` 對重疊呼叫改為序列化執行**（core，修復併發競態）。

## [4.15.0] - 2026-09-07

> **Minor.** 自 `4.14.0` 以來累積 67 個 commit（iOS 13 個），主軸是商品列表 sheet 售完/
> 介紹中/回放旗標一系列使用者實機回報後的行為訂正。**含 1 項 ⚠️ BREAKING**
> （reference-ui-internal 視覺行為）——比照 v4.5.0/v4.8.0/v4.9.0/v4.11.0/v4.13.0/v4.14.0
> 先例，整輪仍判定 minor。完整敘述見
> [`docs/release-notes/v4.15.0.md`](../docs/release-notes/v4.15.0.md)。

### Added

- **`VIDEO_OPEN` 事件新增 `prev_video_id` / `next_video_id`**（core，additive，供 RN/Flutter
  後續接線 swipe 換片導覽；iOS 自身行為不受影響）。

### Changed

- **⚠️ BREAKING — 售完商品不再排除「介紹中」效果**：LIVE/回放橫幅、VOD 等化器遮罩、縮圖 HOT
  徽章現在可與「已售完」文字同時顯示，不再互斥（純視覺行為，無 API 簽章影響）。

### Fixed

- **商品明細主圖 cache-hit 時卡在舊版裁切排版**（`RemoteStillImageView` 補上 async 延遲）。
- **直播/回放置頂商品卡售完時顯示「已售完」**，並訂正售完文字顏色 `#6B6775` → `#9A96A3`。
- **直播回放從未介紹過的商品縮圖點擊改為完全 no-op**。
- **直播回放 begin/end 皆為 0 時不顯示看講解/介紹中 UI**。
- **商品列表縮圖覆蓋層模式改讀 `header.isFinishedLiveReplay`**。
- **VOD 商品列表縮圖撤回 v4.14.0（R36）新增的「已結束」第三態**，回到與回放同構的二態。
- **VOD 商品列表 sheet 置頂邏輯排除純 VOD**（只保留直播與直播回放）。

## [4.14.0] - 2026-09-07

> **Minor.** 本輪規模遠大於任何一輪先例（221 個 commit，v4.13.0 只有 25 個），主軸是「四端
> 100% 像素 parity」政策的補課批次。**含 3 項 ⚠️ BREAKING**（1 項 core 行為面 + 2 項
> reference-ui-internal）——比照 v4.5.0/v4.8.0/v4.9.0/v4.11.0/v4.13.0 先例，含 BREAKING 但
> 整輪仍判定 minor。**本輪對 core/template 層有實質觸碰**（與 v4.13.0「零 core」不同），詳見
> `openspec/changes/archive/.../v4-14-0-release-readiness/design.md` Decision 1/3。**iOS +
> Android 兩端 lockstep**；React Native / Flutter 同一批主題已落地於套件本身，不隨本次 tag
> 對外發佈（見
> [`livebuy-android-sdk/CHANGELOG.md`](../livebuy-android-sdk/CHANGELOG.md#4140---2026-09-07)
> 的 Android 對照段）。完整敘述見
> [`docs/release-notes/v4.14.0.md`](../docs/release-notes/v4.14.0.md)。

### Added

- **直播回放版型統一**（`isFinishedLiveReplay`）——已結束直播回放不再誤用 VOD 版型，改與 LIVE
  共用聊天室/留言框/商品卡/底部操作列（僅 disabled 文案不同）。
- **四輪 design 改版**：商品明細主圖改多圖相簿 + 燈箱跟隨選中圖（R34）、聊天/活動訊息列改版
  固定語意色 + 主播 accent 名牌取代「主播」標籤（R30）、直播回放更多選單 + 說明面板依直播/
  點播文案分流（R32）、VOD 商品列縮圖新增左上角編號徽章（介紹中改顯示 HOT，R35）+ 三態播放/
  介紹中/已結束覆蓋層（R36）、輪播卡新增置頂 pin icon + 觀看人數徽章（R33）。
- **直播入口卡新增關閉播放器後 2 秒緩衝**（跟商家 app 冷開延遲設定各自獨立）。
- **`enableDirectCloseButton` 全域預設設定**（新增可選參數本身為 Added；預設值翻轉見下方
  Changed）。
- **VOD 商品列表 sheet 回放/VOD 時介紹中商品也置頂到最前**（template 層）。

### Changed

- **⚠️ BREAKING — `enableDirectCloseButton` 全域預設值 `false → true`**：播放器右上角關閉
  行為改變（不再先進入縮小態）。行為面 BREAKING，非源碼面——既有不帶此參數的呼叫端仍可編譯。
  若依賴舊行為，需在 `configure(...)` 顯式帶 `enableDirectCloseButton: false`。
- **⚠️ BREAKING — VOD/回放輪播卡「▶ 時長」徽章移除**：design R33 明確拍板，推翻
  `docs/contract-governance.md` R8「移除守門」預設保留。同輪商品卡改白卡配色。
- **⚠️ BREAKING — MiniCart「介紹中」tag 機制移除**：`MiniCartView` public init 不再有 `tag`
  參數，對齊設計稿 `LBPMiniCart` 沒有介紹文案欄位的事實。唯一呼叫端
  `NowIntroducingCarouselView.swift` 同輪同步移除。
- **VOD 側欄浮動購物袋 icon 比例校正回 ~70%**。
- **icon 向量化**：CC icon 對齊設計稿、更多 sheet 分享 icon 改實心版、聊天回到最新箭頭改獨立
  向量 glyph、商品明細按鈕改向量 `DetailGlyph`。

### Fixed

- **開場影片播放期間 template 層抑制商品卡顯示**。
- **抽獎活動彈窗 CTA 移除已參加鎖定改可重複點擊**。
- **開場影片結束/手動略過時補發 moment snapshot 防禦性修正**（parity Android）。
- **`PollManager` 首輪立即觸發、不等 5 秒節奏**。
- **播放器頂欄標題/主持人名欄位撐滿可用寬度**。
- **聊天室主播名牌冒號間距修正**。
- **「更多」sheet 被聊天室擋住修正**。
- **公告橫幅配色/避讓區多輪修正**。

## [4.13.1] - 2026-09-03

> **Patch.** 兩項獨立修正：① 補齊 v4.13.0（R29 播放器手勢三度改版）design.md 當時刻意記錄的
> Non-Goals 延後項——乾淨模式退出鈕像素對齊設計稿；② `CollapsibleLivebuyPlayer` 換片轉發修復
> host 回呼被靜默覆蓋的問題。**純 reference-ui 視覺/接線修正，零 core / 零 LivebuyUI
> （template）層觸碰**。**iOS + Android 兩端 lockstep**——Android 尚未跟進第②項（進行中，另行
> 發版）。

### Fixed

- 乾淨模式退出鈕 icon 改為 `DetailGlyph`（對齊設計稿 `Icons.detail`：帶邊框圓角矩形＋3 排
  dot+line 清單造型），取代先前的 SF Symbol `xmark`（X／關閉符號）。
- 退出鈕底部位移改依 `model.isLive` 分流：LIVE 維持 `16pt`；VOD / 已結束直播回放由 `16pt`
  修正為 `52pt`，對齊設計稿座標。
- **`LivebuyPlayerPresenter` 內部組合 `composedConfig.onVideoSwitchedItem` 時，原本直接覆蓋
  掉 host 自己在 `LivebuyPlayerConfig` 設定的同名回呼，host 的設定會被靜默吃掉、永遠不會被
  呼叫**——改為先呼叫 host 原始設定、再執行 presenter 自己更新 binding 的內部邏輯，對齊既有
  RN/Flutter 對等 seam 的 chain 模式。

## [4.13.0] - 2026-09-02

> **Minor.** 延續 v4.12.0，本輪 iOS 主打**播放器手勢三度改版（R29）**：短擊切換「乾淨模式」、
> 雙擊送愛心整段退役（改為 VOD/回放雙擊 seek ±10 秒）、長按 VOD/回放近似 2 倍速快轉、中央暫停
> 覆蓋層移除、商品袋按鈕縮小、頂列新增靜音鈕。含 **1 項 ⚠️ BREAKING**（reference-ui 內部行為
> 契約——手勢觸發語意整個對調，取代 R23 舊模型）——比照 v4.5.0/v4.8.0/v4.9.0/v4.11.0 先例，
> 含 BREAKING 但整輪仍判定 minor。另補齊 v4.12.0 遺留的活動入口多活動分頁 iOS reference-ui
> 視覺缺口，四端現已 parity。**本輪零 core / 零 LivebuyUI（template）層觸碰，對 Tier 0 host
> 讀者零行為變化**。**iOS + Android 兩端 lockstep**；React Native / Flutter 同一批主題已落地
> 於套件本身，不隨本次 tag 對外發佈（見
> [`livebuy-android-sdk/CHANGELOG.md`](../livebuy-android-sdk/CHANGELOG.md#4130---2026-09-02)
> 的 Android 對照段）。

### Added

- **活動入口多活動分頁 reference-ui 視覺補齊** — `LiveActivitySheetView` 補上分頁 UI 消費
  v4.12.0 已曝露的分頁資料，收斂 v4.12.0 遺留的 iOS 平台落差，四端現已 parity。
- **播放器手勢三度改版（R29）新增**：`cleanMode` 期間 `PlayerHeaderBarView` 新增靜音切換鈕
  （補回單擊切靜音手勢退役後的操作管道）；新增「退出乾淨模式」小圓鈕。
- **已結束直播回放雙擊送愛心改延遲 commit 播放/暫停切換**（R29 之前的迭代，同輪一併收工）。
- **縮小按鈕 icon 放大 18 → 20pt**，對齊設計稿。

### Changed

- **⚠️ BREAKING — 播放器手勢觸發語意整個對調**：取代 R23 定的「長按=乾淨模式、單擊=靜音/
  播放暫停」：短擊（不分直播進行中/預告/VOD/回放）切換 `cleanMode`；雙擊（僅 VOD/回放）依左右
  半螢幕 seek ±10 秒；長按（僅 VOD/回放）近似 2 倍速快轉。直播進行中/預告倒數不支援雙擊/長按。
  **受影響對象**：直接呼叫 `handleLiveTap()`/`handleReplayTap()`/`registerLikeableTap()` 等
  已移除內部方法的 host（正常情況下不會，這些非 public API）；走既有 `simulate*` 方法 + 事件
  監聽的 host 不受影響。
- **移除**：中央暫停覆蓋層 `PlaybackPausedOverlayView` 不再被組合；VOD/回放播放/暫停改由
  `PlaybackProgressBarView` 展開態上的小按鈕操作。
- **商品袋按鈕縮小**：48×48pt → 40×40pt，icon 34 → 22pt，對齊設計稿。

### Fixed

- **切換影片/拖曳進度條時中央暫停覆蓋層誤顯示修復**（R29 之前的迭代）。
- **縮小後綁定同一支影片無反應修復**——`LivebuyPlayerPresenter` open-signal 重開判定缺口。
- **現正直播提示鈕漏轉發換片信號導致換片被復原修復**＋對齊設計稿縮小尺寸。

## [4.12.0] - 2026-09-02

> **Minor.** 延續 v4.11.0，本輪 iOS 新增：現正直播「前往直播」提示鈕（VOD/回放偵測到同頻道現正
> 直播時顯示）、VOD 正在介紹中商品訊號（core）、活動入口 modal 曝露完整進行中活動清單+分頁狀態
> （template 層），另加 4 項視覺/缺陷修復。**無 BREAKING**（`grep -rli -i BREAKING` 掃過本輪所有
> 相關 archived 目錄命中 22 個檔案，逐一核實皆為否定敘述或對 v4.11.0 既有 BREAKING 項的引用，
> 無真實命中）。**iOS + Android 兩端 lockstep**；React Native / Flutter 同一批主題已落地於套件
> 本身，不隨本次 tag 對外發佈（見
> [`livebuy-android-sdk/CHANGELOG.md`](../livebuy-android-sdk/CHANGELOG.md#4120---2026-09-02)
> 的 Android 對照段）。

### Added

- **現正直播「前往直播」提示鈕（`LBLiveNowPill`）** — 觀看 VOD / 已結束直播回放時，若偵測到同一
  頻道現正直播中，顯示提示鈕引導前往直播；後續一顆修復排除「正式直播進行中」場景，避免鈕誤疊在
  真實直播畫面上。
- **VOD 正在介紹中商品訊號（core）** — `LivebuyPlayerViewController` 新增 VOD 播放進度對應的
  「正在介紹中商品」訊號，parity 既有 LIVE 行為。
- **活動入口 modal 曝露完整進行中活動清單＋分頁狀態（`LivebuyUI` template 層）** — `DefaultActiveEvent`
  反轉舊版「只取第一筆活動」決策，改曝露完整清單與分頁索引；`currentActivity` 簽章不變、預設分頁
  索引 `0` 時行為與既有等價，純新增。**本輪 reference-ui 尚未消費新分頁 API**（`LiveActivitySheetView`
  尚無分頁 UI，不同於 Android/RN/Flutter 已同步補上 reference-ui 分頁視覺——這是本輪盤點發現的一個
  平台落差，非本 change 造成，如實記錄，待後續獨立 change 補齊）。
- **活動入口切換影片立即隱藏＋換片還原快取（template 層）** — 換片時活動入口立即隱藏，換回原片時
  從快取還原顯示狀態，避免短暫顯示上一部影片的活動資訊。

### Fixed

- **直播雙擊送愛心改延遲 commit 靜音＋可取消**，不再誤觸靜音閃爍。
- **活動入口 modal CTA 接上既有三層閘**，加入成功後自動關閉，被閘攔截時維持開啟。
- **縮小按鈕 icon 放大 18pt＋暫停覆蓋層拖曳中／直播進行中不顯示**。
- **中獎/活動入口 icon 尺寸對齊設計稿 29pt**；**領獎 modal 頂部禮物徽章換成白底圓＋雙路徑向量
  glyph 對齊設計稿**。

## [4.11.0] - 2026-09-01

> **Minor.** 延續 v4.10.0，本輪 iOS 新增多項能力：播放器手勢重寫（乾淨模式）、直播抽獎活動入口、
> VOD/回放播放進度條復原、雙擊送愛心（LIVE + 回放）、字幕 CC 開箱顯示、中獎領獎分頁。含
> **1 項 ⚠️ BREAKING**（`WinClaimModalView.Stage.confirmClose` 移除，reference-ui-internal
> 範圍）——比照 v4.5.0/v4.8.0/v4.9.0 先例，含 BREAKING 但整輪仍判定 minor（理由見
> [release notes](../docs/release-notes/v4.11.0.md)）。
> **iOS + Android 兩端 lockstep**；React Native / Flutter 同一批主題已落地於套件本身，不隨本次
> tag 對外發佈（見
> [`livebuy-android-sdk/CHANGELOG.md`](../livebuy-android-sdk/CHANGELOG.md#4110---2026-09-01)
> 的 Android 對照段）。

### Added

- **播放器手勢重寫：乾淨模式** — 單擊行為依直播/VOD 分流；長按改為切換「乾淨模式」（隱藏頂欄/
  底部 bar/聊天等疊層），取代舊版「按住暫停」手勢。
- **直播抽獎活動入口按鈕與彈窗** — 綁定既有 `activeEvents()`/`ACTIVE_EVENT_STARTED` 資料，首次
  補上 UI 呈現（非新資料契約）。
- **VOD / 直播回放播放進度條復原上線** — 依現行設計稿重新上線（先前刻意移除）。
- **LIVE 進行中雙擊送愛心，擴大到已結束直播回放** — 兩個獨立 change：LIVE 進行中首次落地，同批
  次擴大到回放（parity 既有 LIVE 行為）。
- **字幕 CC 開箱即顯示 VTT 內容** — CC 開關先前存在但看不到實際字幕文字，本輪補上真正渲染顯示。
- **中獎領獎 modal 新增分頁** — 多筆中獎紀錄可翻頁瀏覽；同批活動/中獎入口堆疊順序反轉（活動入口
  改佔主槽，中獎入口讓位）。

### Changed

- **⚠️ BREAKING — 中獎領獎 modal 關閉機制簡化**：`WinClaimModalView.Stage.confirmClose` /
  `LocalPhase.confirmClose` 移除，連同 ✕ 關閉鈕與「關閉視窗」二次確認文字鈕；modal 現在**只能
  透過 scrim（背景遮罩點擊）關閉**。**受影響對象**：直接窮舉 `WinClaimModalView.Stage` enum 的
  host；走 turnkey 容器或不窮舉內部狀態列舉的 host 不受影響。
- **中獎入口按鈕改款**：圓形 → 方形，拿掉脈動動畫與數字徽章。
- **播放進度條平常態細線** `3pt` → `2pt`，消除底部視覺空隙。

### Fixed

- **LIVE 底部 bar 貼底**：拿掉多餘外層 margin，內容真正貼齊底部。
- **頂欄與 LIVE 底部 bar 拿掉裝飾性漸層**。
- **播放進度條真正貼底**：消除先前的 8.5pt 底部空隙。
- **乾淨模式漏隱藏聊天 feed 修復**（範圍遺漏，非 regression）。
- **直播多商品同時介紹漏標 badge 修復**。
- **拖曳進度條中切背景（含觸發自動 PiP）後讀數卡住修復**：切背景視同放開手指，回前景後讀數不再
  卡住。

## [4.10.0] - 2026-08-28

> **Minor.** 延續 v4.9.1，本輪 iOS 這輪未觸碰任何已發佈 `ios/Sources/LivebuyReferenceUI` 原始碼——
> 兩項條目皆為本 repo 內建 `ios/Example` demo app（`ExampleApp` + `ShopHost`）的 host-wiring
> 修復，**不是**套件本身的行為改變（`LivebuyPlayerConfig.showStock` / `.titleScroll` 契約本身
> 早已正確、已有測試覆蓋）。整輪判定 minor 的理由來自本輪 RN/Flutter 套件新增的 `titleScroll`
> 公開能力（不隨本次 iOS/Android tag 對外發佈，見 release notes 說明）。**iOS + Android 兩端
> lockstep**；React Native / Flutter 不在此列車（見
> [`livebuy-android-sdk/CHANGELOG.md`](../livebuy-android-sdk/CHANGELOG.md#4100---2026-08-28)
> 的 Android 對照段）。

### Fixed

- **不顯示庫存設定失效（Example demo app only）**：`ExampleApp` / `ShopHost` 兩個建構
  `LivebuyPlayerConfig` 的 host 端點先前沒有讀取 `sdkConfig.extensions["show_stock"]` 並轉送，
  導致後台「不顯示庫存」設定在這兩個 demo app 上被無視。已補上接線。⚠️ 這不是套件行為改變——
  `LivebuyPlayerConfig.showStock` / `LBShowStock.normalized()` 契約本身一直是對的；如果你自己
  的 host app 有同樣的接線缺口，會踩到一模一樣的靜默失效。
- **標題不跑馬燈設定失效（Example demo app only）**：同上兩個建構點沒有讀取
  `sdkConfig.extensions["video_title_scroll"]` 並轉送進 `LivebuyPlayerConfig.titleScroll`，
  導致商家「標題不捲動」設定在這兩個 demo app 上永遠無效。已補上接線。⚠️ 同樣不是套件行為
  改變。

## [4.9.1] - 2026-08-27

> **Patch.** 延續 v4.9.0，本輪為純 bug fix（3 項 iOS-only 視覺/手勢修復），無新增公開欄位、
> 無行為預設值改變、無 API 簽章變更。**iOS + Android 兩端 lockstep**；React Native / Flutter
> 不在此列車（本輪未被觸及，見
> [`livebuy-android-sdk/CHANGELOG.md`](../livebuy-android-sdk/CHANGELOG.md#491---2026-08-27)
> 的 Android 對照段）。

### Fixed

- **底部 sheet 同手勢調高後反轉關閉視覺瞬跳**：改採 Android 既有的平滑 dismiss 模型
  （`computeDismissExcessPx`），移除峰值折抵造成的單幀瞬間跳動。
- **活動公告 CTA 間距對齊設計稿**：「加入活動」按鈕 / 「已參加」chip 的 top padding
  `4pt` → `7pt`，對齊 `moments.jsx` 與 Android 既有數值。
- **觀眾留言氣泡 padding 加寬**：垂直 padding `3pt` → `4pt`，縮小與 Android 因文字度量機制
  導致的視覺厚度落差。
- **底部 sheet 拖曳調高抖動根因修復（實機驗證）**：定位到 `DragGesture` 座標系統回饋迴路
  根因並修復，適用於全部 5 個經 `.lbBottomSheet(...)` 呈現的底部 sheet。

## [4.9.0] - 2026-08-27

> **Minor.** 延續 v4.8.0，本輪新增訂閱/收藏顯示開關（新公開設定欄位）＋底部 sheet 拖曳一系列
> 穩定化修復（上限收斂 90%→80%、多個手勢邊界 bug）＋一批視覺對齊設計稿。有 1 項 BREAKING
> （host-facing 預設行為改變，見下方 Changed）。**iOS + Android 兩端 lockstep**；React Native /
> Flutter 不在此列車（見
> [`livebuy-android-sdk/CHANGELOG.md`](../livebuy-android-sdk/CHANGELOG.md#490---2026-08-27)
> 的 Android 對照段）。

### Added

- **訂閱/收藏顯示開關 `showSubscribe` / `showFavorite`**：`LivebuyPlayerConfig` 新增兩個 optional
  欄位，控制訂閱角標/pill（同一旗標）與收藏鈕是否顯示，預設 **`false`**（隱藏）。命名/傳遞姿態
  沿用既有 `showViewerCount` / `titleScroll` / `showStock` 先例。
- **商品袋 icon 放大對齊 70% 比例**：主要商品袋按鈕與直播/回放底部 bar 商品袋 icon，兩個獨立
  渲染點皆已放大，12 張既有 baseline 重生。純視覺，不影響互動行為。
- **一般觀眾留言加全形冒號分隔**：暱稱與訊息內容間新增冒號，對齊設計稿更新；2 張既有 baseline
  重生。
- **`product-detail-drag` 實機拖曳震盪調查記錄**（investigation-only，非回歸測試套件一部分）：
  實機逐幀分析證實單一方向連續拖曳仍有重複的衝過頭再修正震盪，根因待查，留待後續 change。

### Changed

- **⚠️ 訂閱/收藏預設隱藏（BREAKING）**：既有 host 若未設定 `showSubscribe` / `showFavorite`，
  升級後訂閱角標、訂閱 pill、收藏鈕會從顯示變為隱藏。不影響任何 public API 簽章，既有呼叫碼零
  改動即可編譯運行；如需保留這些元素，顯式傳入 `true`。
- **底部 sheet 拖曳觸發區域觸控目標調整**：把手列高 16pt → 44pt → 32pt（兩輪迭代，內部視覺 pill
  尺寸不變，只調外層觸控熱區）。
- **底部 sheet 拖曳調高上限收斂 90% → 80%**：全部 5 個 sheet 共用同一個值，計算架構不變。
- **懸浮 widget 移除影片標題**：對齊設計稿無標題元素的版面。
- **`ScrollableCarouselView` 卡片列補底部 6pt padding**：對齊 design 稿。

### Fixed

- **底部 sheet 調高後關不掉**：dismiss 門檻改為相對「調高過程曾到達過的峰值高度」計算（第 2 輪
  修正，第 1 輪修法未真正解決問題，經驗收補正）。
- **`floorFraction` 量測 race**：首次量測可能落在暫態值上，改為持續反映最新量測值直到開始拖曳
  才凍結。
- **`.drawingGroup()` 攤平機制撤銷**：會導致 `LBSheetScaffold` 內部 `@State` 被摧毀重建、body
  內容區塊完全空白，改回原生合成路徑。
- **拖到頂實際超過 90%（上限收斂前）**：把手高度未從上限扣除，已改為精確扣除，整張卡片精確
  ≤ 上限。
- **同一手勢內多次反轉方向導致瞬間跳動**：收合峰值改為每次重新進入調高分支即歸零重算，不沿用
  更早反轉週期的舊峰值。
- **跨手勢往下拖無法先縮小到真實下限**：改為視為調高分支的縮小延續，不直接進入收合分支。
- **一般觀眾留言暱稱/訊息間冒號未套用正確字級**：導致垂直未置中，follow-up 修正。
- **聊天室觀眾留言氣泡文字未垂直置中**：修正。

## [4.8.0] - 2026-08-25

> **Minor.** 延續 v4.7.0 剛上線的「更多商品」推薦格，本輪多項精進＋新增商品選項可購性計算＋
> icon 對齊新版設計稿。有 2 項 package-internal BREAKING（非 public API 簽章變更，見下方
> Changed）：推薦格導覽簡化（移除巢狀 breadcrumb 返回）、拖曳手勢局部回退為調高/收合各自獨立
> 判斷。**iOS + Android 兩端 lockstep**；React Native / Flutter 不在此列車（見
> [`livebuy-android-sdk/CHANGELOG.md`](../livebuy-android-sdk/CHANGELOG.md#480---2026-08-25)
> 的 Android 對照段）。

### Added

- **商品選項不可購性計算＋disabled 攔截**：多層規格選項（如顏色×尺寸）改用精確比對取代先前的
  子字串搜尋，不可購組合顯示 disabled 灰階並攔截點擊。
- **`LBProduct` 新增 `description` 欄位（`String?`）**：承載商品真實介紹文字，tolerant decode
  （缺鍵/型別不符 → `nil`）。
- **「更多商品」推薦格新增原價劃線顯示**：推薦卡片新增原價欄位透傳與劃線渲染。
- **icon 對齊新版設計稿**：14 顆自繪 glyph 對齊 `icons.jsx` 新版設計來源，34 張 snapshot
  baseline 重生。純視覺，不影響互動行為。
- **商品袋 row 播放提示改為「看講解」白底膠囊**：對齊設計稿 R21，tap handler 邏輯不變。
- **商品明細數量列與收藏鈕間補分隔線**：純視覺排版補強。
- **`product-detail-drag` QA 調查用 XCTHitchMetric 量測工具**（Example app 內，investigation-only，
  非回歸測試套件一部分）：量測底部 sheet 拖曳過程的掉幀情況，供人工讀數判讀，不隨 SDK 出貨。

### Changed

- **⚠️ 「更多商品」推薦格導覽簡化（BREAKING，reference-ui 內部行為，非 public API）**：移除
  v4.7.0 引入的 breadcrumb 逐層返回機制，header 關閉鈕永遠是「✕ 全部關閉」；播放圖示換片後
  額外呼叫既有的 `dismissDetail()`，整個商品 sheet stack 隨換片一併關閉（v4.7.0 是「换片不連動
  dismiss」）。如果你的 host 依賴 v4.7.0「推薦格巢狀返回」行為，本版已改變。
- **「更多商品」推薦格上限 4 → 12**。
- **換片時一併關閉外層商品袋/清單抽屜**：先前換片後外層抽屜若已開啟會維持開著，本版起一併關閉。
- **商品介紹文字區改顯示真實資料**：v4.7.0 上線時固定顯示佔位文案，本版接上真實
  `LBProduct.description`；**沒有真實介紹文字時整個區塊（含標題）都不顯示**，不再顯示佔位文案
  （比照既有 `brief` 欄位「空字串不畫」規則對齊）。背景分層同步改為外層灰底＋白色內容卡片。
- **更多商品卡片版面調整**：原價移到售價下方、加購鈕貼齊卡片底部；grid 卡片移除邊框。
- **⚠️ 底部 sheet 拖曳手勢局部回退為各自獨立判斷（BREAKING，iOS-only）**：v4.7.0 剛整併的
  「拖曳調高」與「拖曳收合」單一連續手勢，本版 iOS 端局部撤回，改回各自獨立判斷、不共用連續
  量測狀態機。僅影響 iOS；Android 維持 v4.7.0 的整併手勢不變。使用者體感（上拖調高、下拖收合）
  預期不受影響，差異在內部狀態機是否共用。

### Fixed

- **拖曳調整高度過程中的掉幀式抖動（round-4）**：round-3（v4.7.0 已修）的修法實機重測後抖動並
  未真正消失，本版拖曳期間卡片改用 `.drawingGroup()` 攤平降低陰影/合成成本。待人工實機再次確認
  手感。
- **推薦資料源改從容器持久快取退回提供**：修正特定邊界情況（容器快取命中但欄位為空）下漏抓
  推薦資料的問題；純技術韌性修正，行為對使用者不可見。

## [4.7.0] - 2026-08-25

> **Minor.** 新增 3 項 host-facing 能力——商品明細/加購 sheet 的 Sale 促銷徽章、`LBProduct` 補上
> `videoId` 欄位、商品明細新增「商品介紹」區塊＋「更多商品」2×2 推薦格；另把底部 sheet 的拖曳
> 調高與拖曳收合手勢整併為單一連續手勢並擴大到全部 5 個 sheet。三項新能力皆向後相容、無符號
> 移除；手勢整併使 `.detail` 呈現的預設高度上限由 v4.6.2 的 90% 改回 50%，見下方 Changed。
> **iOS + Android 兩端 lockstep**；React Native / Flutter 不在此列車（見
> [`livebuy-android-sdk/CHANGELOG.md`](../livebuy-android-sdk/CHANGELOG.md#470---2026-08-25)
> 的 Android 對照段）。

### Added

- **商品明細 / 加購 sheet 新增 Sale 促銷徽章**：商品有原價（劃線價）且未售完時，商品圖 / 96×96
  縮圖旁顯示一個「Sale」徽章 chip（accent 底色、白字）；純 reference-ui 視覺渲染，不需任何新的
  資料欄位或 view-model 改動，售完或無原價時不顯示。
- **`LBProduct` 新增 `videoId` 欄位（`String?`）**：承載 `LBChannel.otherGoods[]` 每筆商品所屬的
  影片 id（一般 `goods[]` 內項目此欄位為 `nil`），tolerant decode（缺鍵/型別不符 → `nil`）。補齊
  `component-contracts` 規格先前已要求、但四端從未真正實作的缺口，是下方「更多商品」推薦格能夠
  換片的必要資料來源。
- **商品明細新增「商品介紹」文字區 ＋「更多商品」2×2 推薦格**：`.detail` 呈現底部新增商品介紹
  說明文字（後端 `description` 欄位就緒前，先以固定文案佔位）與最多 4 筆「更多商品」推薦卡片
  （資料源 `LBChannel.otherGoods`，過濾掉目前商品）。點推薦卡的播放圖示會直接換到該商品所屬
  影片（沿用既有「容器層直呼 `player.load(videoId:)`」換片機制，比照 EndScreen 熱門推薦的既有
  模式，不新增換片入口）；點卡片本體或加購鈕會切換到該商品自己的明細/加購畫面——同一個 sheet
  換內容＋本地返回路徑（非疊出第二層 sheet 實例），header 關閉鈕在有返回路徑時變成「返回」；從
  推薦卡加購會帶該商品自己的 `videoId`，確保購物車去重鍵 `(goodsId, videoId)` 正確。商品卡新增
  `hideSub`/`onPlayClick` 兩個渲染參數，grid 呈現的播放鈕改為右上角呼吸動畫圓鈕＋獨立加購圓鈕，
  既有 row 呈現的播放提示改為「看講解」文字膠囊（既有加購鈕不動）。

### Changed

- **底部 sheet 拖曳調高與拖曳收合整併為單一連續手勢，並擴大到全部 5 個 bottom sheet**：先前僅
  商品明細 / 加購 / 補貨通知三張 sheet 可選擇性拖曳調高（下限寫死 25%），本版起商品列表抽屜與
  影片資訊面板也一併具備拖曳調高能力；往上拖調高、往下拖收合合併成同一條手勢——高度下限改為
  「該次呈現實際渲染出的高度」而非寫死值，超出下限才轉為既有的拖曳收合位移（沿用既有 100pt
  累積位移門檻與彈回/滑出動畫，門檻本身不變）。**商品明細（`.detail`）呈現的預設高度上限由
  v4.6.2 的 90% 改回 50%（內容自適應）**——90% 現在只在使用者主動拖曳到頂時才出現，不再是開啟
  就逼近全螢幕的預設值；如果你的 host 依賴 v4.6.2「明細一開啟就是 90%」的行為，這個預設值本版
  已改變。`.addToCart` 與補貨通知既有固定 40% 高度不受影響。

### Fixed

- **拖曳調整高度過程中的掉幀式抖動**（iOS-only）：拖曳期間，`LBSheetScaffold` 先前只丟棄量測
  結果、但排版量測動作本身（4 個 `GeometryReader`）仍隨每次觸控取樣持續執行，慢速拖曳時因此
  明顯掉幀。本版把量測動作本身在拖曳期間整個移出 view tree（而非只丟棄結果），修掉這個
  v4.6.2 的 release-time 抖動修復未觸及的另一個抖動來源。不影響任何計算邏輯或 public API。

## [4.6.2] - 2026-08-24

> **Patch.** 觀看人數進場假 0 修復 + 一批 reference-ui 視覺/互動細節收斂，無新增符號、無破壞性
> 變更。**iOS + Android 兩端 lockstep**；React Native / Flutter 不在此列車（見
> [`livebuy-android-sdk/CHANGELOG.md`](../livebuy-android-sdk/CHANGELOG.md#462---2026-08-24)
> 的 Android 對照段）。

### Fixed

- **觀看人數進場顯示假 0**：`publishMomentState()` 組裝 `viewerCount` 時，`channel` 尚未 resolve
  （含 `unload()` 清空 channel）不再硬編覆寫成 `0`，改為沿用上一個已知值；PlayerHeader 觀看人數
  徽章新增第四道顯示閘——`startPhase == loading`（冷啟動、真實資料尚未到位）期間不渲染任何具體
  數字（含 `0`）。兩者共同解決「一進入直播間先顯示 0、過一陣子才變成正常人數」的症狀。
- **公告分頁為空時不再顯示灰階死路徑**：VideoInfoPanel 的公告分頁在系統公告與商城公告皆空時，
  改為整個不渲染，不再畫出永遠點不動的 disabled 灰階分頁。
- **商品袋縮圖跳轉後自動收合**：商品清單抽屜內點擊商品縮圖跳轉到影片對應時間點時，同步關閉
  商品清單抽屜。
- **PlayerHeader 商家 pill 背景收斂**：移除整塊商家資訊（logo / 標題 / 商家名稱 / LIVE 標籤 /
  觀看人數）共用的半透明灰底，改由觀看人數獨立套用該背景，對齊最新設計稿。
- **Feed 訊息頭像/icon 先隱藏**：聊天 / 活動 feed 每則訊息前方的 24pt 圓形頭像/icon 槽暫時隱藏，
  文字/氣泡貼齊列最左側起點（可逆的暫時性設計決定，繪製邏輯保留）。
- **商品明細 sheet 拖曳調整高度 + 收藏鈕橫排內置 + 明細呈現拉高到 90%**：商品明細 / 加入購物車 /
  補貨通知三個底部 sheet 的把手新增拖曳即時調整高度（25%–90%）能力；收藏鈕從底部操作列移到
  內文區塊置中橫排；商品明細（`.detail`）呈現高度上限由 50% 提高到 90%。
- **直播疊層聊天室左邊距 / 釘選商品卡右邊距對齊底部 icon**：對齊底部功能列購物袋（左）與愛心
  （右）icon 的既有 10pt 邊距。
- **商品搜尋框移除清除鈕，只留取消**：商品清單 sheet 展開態搜尋框移除叉叉清除鈕，只留取消
  （收合整個搜尋列並清空查詢字串）。
- **底部 sheet 拖曳關閉不再跳動**（iOS-only）：下滑放手關閉時，先收斂殘留位移動畫到畫面外，
  再觸發卸載，不再與卸載動畫疊加造成跳動。
- **聊天氣泡間距收緊**（iOS-only）：一般觀眾留言氣泡的垂直間距，收斂至與主播/AI 留言版型既有
  的緊湊間距慣例一致。

### Changed

- **直播進行中停用垂直滑動切影片**：先前任何播放狀態下垂直滑動皆會切換影片，本版起直播正在
  進行中時滑動不再切換影片（拖曳仍會被手勢層吞掉，不會誤觸 tap-to-mute / hold-to-pause）；
  預告倒數（upcoming）與已結束直播的回放（finished-live replay）不受影響，維持可滑動切片。

## [4.6.1] - 2026-08-13

> **Patch.** 補齊一個既有背景繪製語意的缺口，無新增符號、無破壞性變更。**iOS + Android
> 兩端 lockstep**；React Native / Flutter 不在此列車（見
> [`livebuy-android-sdk/CHANGELOG.md`](../livebuy-android-sdk/CHANGELOG.md#461---2026-08-13)
> 的 Android 對照段）。

### Fixed

- **`ScrollableCarouselView`（turnkey 全量水平捲動輪播，`LivebuyWidget` drop-in 容器實際渲染的
  表面）根容器補畫 `widget_bgcolor` 衍生後的背景色**，比照既有「窗口式」`CarouselView`（進階
  host escape hatch）與 `VideoShopGridView` 語意：合法 hex 覆寫背景；缺值 / 空字串 / 不可解析
  維持既有背景不變，不引入新預設色。`widget_color`（文字色反轉）與背景色可同時獨立生效。這是
  v4.6.0 讓「窗口式」`CarouselView` 補畫背景時刻意排除的缺口（該表面是 wrapper tier，內部擁有
  `ScrollView`，不能取得 golden PNG baseline，改用像素取樣行為測試驗收）——本版補上後，drop-in
  容器實際渲染的輪播 widget 才真正會顯示商家設定的背景色。

## [4.6.0] - 2026-08-12

> **Minor.** 兩項 reference-ui 新增設定面，皆 additive，無移除、無破壞性變更。**iOS + Android
> 兩端 lockstep**；React Native / Flutter 不在此列車（見
> [`livebuy-android-sdk/CHANGELOG.md`](../livebuy-android-sdk/CHANGELOG.md#460---2026-08-12)
> 的 Android 對照段）。

### Added

- **`View.livebuyPlayer(video:config:theme:position:)` 新增 `position: String?` 參數**
  （DEFAULT `nil` → 右下角，即既有落點）。縮小後出現的懸浮預覽卡先前恆固定右下角，現在依此
  參數比照「現正直播」入口（`LivebuyLiveEntryConfig.position`）換邊——複用同一套
  `LBFloatingEntryPosition.normalized(_:)` 正規化邏輯（逐字等於 `"left_bottom"` 才是左下，其餘
  一律右下），拖曳夾限邊界同步隨落點換邊。未注入時渲染與現況逐位元組相同。
- **`CarouselView`（輪播 widget）根容器補畫 `widget_bgcolor` 衍生後的背景色**，比照既有
  `VideoShopGridView` 語意：合法 hex 覆寫背景；缺值 / 空字串 / 不可解析維持既有背景不變，不
  引入新預設色。`widget_color`（文字色反轉）與背景色可同時獨立生效。既有未設定情境的 golden
  維持 byte-identical。

## [4.5.0] - 2026-08-12

> **Minor — 一條 BREAKING 移除，但實務衝擊視為零（見下方說明）。** 本版新增一批 reference-ui 視覺
> 設定面（皆 additive）並修一批已出貨的 drop-in 呈現 bug。**iOS + Android 兩端 lockstep**；
> React Native / Flutter 不在此列車（見 [`livebuy-android-sdk/CHANGELOG.md`](../livebuy-android-sdk/CHANGELOG.md#450---2026-08-12)
> 的 Android 對照段）。

### Removed（⚠️ BREAKING）

- **⚠️ 移除 `LBWidgetResponse.showGoods: Int?`**（含 `init` 的 `showGoods:` 參數）。該欄位對應的 wire key
  `show_goods` **後端從未 emit**，因此它永遠是 `nil` —— 留著等於在 public API 上擺一個看起來可用、
  實際永遠沒值的假設定。其原本標註的語意（「0=名後 / 1=影片中 / 2=不顯示」）源自後端 repo 一則
  已被該 repo 自己更正的稽核錯誤，並在 2026-05-29 經由「對照後端權威契約」被抄進本 SDK。
  證據鏈（後端 handler 註解、後端測試的「必須不存在」斷言、後端更正紀錄、正式環境實打回應）見
  [`docs/backend/go-rewrite-wire-contract.md`](../docs/backend/go-rewrite-wire-contract.md) §2.2。
  **遷移**：wire 上真正承載「商品卡顯示模式」的是新增的 `productCard`（見下方 `Added`）。
  讀過 `showGoods` 的 host 只可能拿到 `nil`，改讀 `productCard` 即可；若原本就寫了 nil 分支，
  刪掉該欄位的引用即可編譯。
  **為什麼仍是 minor、不是 v5.0.0**：該欄位對應的 wire key 後端從未送過值，repo 內（含
  `LivebuyUI` / `LivebuyReferenceUI` / Example / RN / Flutter 橋接層）零消費端——沒有任何一個
  真實 host 讀過非 `nil` 的值。實務衝擊視為零，這是團隊已確認的判斷，非自動套用 SemVer 字面規則。

### Added

- **`LBWidgetResponse.productCard: String?`** —— `POST /sdk/widget` 回應 root 的 `product_card`
  raw passthrough。語意為 widget 輪播卡上「商品卡」的顯示模式，後端值域 `below`（卡片下方）/
  `inside`（卡內疊層）/ `hidden`（不顯示），後端預設 `inside`。**SDK 不解讀語意、不據此排版**。
  缺欄位（linetv 分支不送）→ `nil`，**SDK 刻意不補後端預設 `"inside"`**，讓 UI 層能區分
  「後端沒送」與「後端明確送 inside」。
- **`LivebuyWidgetCore.productCard: String?`** —— 同一個值的 host 可讀唯讀狀態，比照既有
  `widgetColor` / `widgetBgcolor`，於 carousel / grid 的 `loadFirstPage` / `requestLoadMore` 後更新。
  floating（`/sdk/widget/live`）不帶此欄，維持 `nil`。
- **Widget 輪播卡依 `product_card` 渲染三態**（`CarouselCardView`）——`inside`（維持既有縮圖內
  dark-glass 疊層，像素不變）/ `below`（商品卡移到縮圖外，落在**標題之下、卡片最底**；未綁商品時
  渲染等高透明佔位維持同列同格等高）/ `hidden`（完全不畫，不留佔位）。缺值或白名單外字串一律
  fallback 為 `inside`。
- **Widget 表面顏色接上 `widget_color` / `widget_bgcolor`**——`CarouselView` / `ScrollableCarouselView` /
  `VideoShopGridView` 三個 widget 表面依後台設定衍生文字與背景色：`widget_color == 2` 時文字轉
  `#FFFFFF`（`1` 不覆寫）；`widget_bgcolor` 為合法 hex 時覆寫背景（空字串 / 缺 key 視同不覆寫）。
  未設定時渲染與現況逐位元組相同。僅套用於這三個 widget 表面，不影響全域主題（player shell、
  product sheets 等維持既有 minimal palette）。
- **商品明細 / 快速購買 sheet 新增庫存文案開關** `LivebuyPlayerConfig.showStock`（DEFAULT `true`）——
  `false` 時「只剩庫存 N 組」整行不畫、不留佔位，既有「售完不顯示」閘不變（AND 關係）。
- **PlayerHeader 標題新增跑馬燈開關** `LivebuyPlayerConfig.titleScroll`（DEFAULT `true`）——是否
  捲動仍 100% 由內容是否覆蓋容器的量測決定，`titleScroll` 是疊加在量測之上的後端能力閘（AND
  關係），`false` 時維持既有單行省略顯示、行高不變。
- **浮動直播入口新增初始落點與延遲出現時機**（`LivebuyLiveEntryConfig`）——`position`（`nil` →
  右下，既有落點）/ `timing`（`nil` → 立即，既有時機）/ `delay`（DEFAULT `3` 秒）。`timing ==
  "delay"` 時延遲指定秒數才掛載並播進場動畫；`immediate` 維持現況、零行為變動。

### Fixed

- **`widget_color` 為 JSON 數字字串時不再被靜默吃掉。** 該欄宣告型別是 Int，但後端只在商城 base 值
  做整數轉型；widget-group override 那條路徑是逐字賦值、沒有轉型，故 wire 上可能是字串 `"2"`。
  舊解碼遇到字串會 fallback 成預設 `1`，**後台在 widget group 設定的「白色文字（2）」在 App 端
  無聲地變回黑色**。現在 Int 與數字字串皆正確解析；缺 key / `null` / 不可解析字串（如 `"abc"`）
  維持既有預設 `1` 且不拋錯。**API 面零變化**（`widgetColor` 仍是 `Int`）。
- **浮動直播入口關閉鈕改對齊現行設計稿。** 舊造型抄自一個已於 2026-06-09 移除的設計元件（框外
  24×24 深色玻璃 + 白描邊 + 自身陰影），現改為框內右上 20×20、`rgba(0,0,0,0.55)`、無描邊
  （對齊現行 `sdk-components.jsx:LBPFloatingWidget`）。卡片本身尺寸與位置不變，只有關閉鈕像素改變。

> **平台範圍**：iOS + Android 兩端本輪皆完整落地（parity change，見 Android CHANGELOG）。
> React Native / Flutter 對應能力已在主線，隨各自待發 `2.0.0` 出貨。

---

## [4.4.0] - 2026-07-31

> minor release，**無 API 破壞**（但有一條行為 BREAKING，見 `Changed`）、源碼相容，兩端 lockstep
> （iOS `v4.4.0` / Android `4.4.0`）。鎖點 `dcea410f`（本版最後一個碰 `ios/Sources/LivebuySDK/` 的
> commit）。自 v4.3.0 以來碰 `ios/Sources/LivebuySDK/`（binary target）共 **3 commit**（URL 開啟
> 策略與法務連結常數 `dcea410f`、暱稱驗證不再靜默成功 `12c894a4`、設定暱稱前先驗證是否被佔用
> `81a76425`）→ **binary MUST 重 build，checksum 為新值**（≠v4.3.0；由發版流程於 `v4.4.0` tag 產生
> 並 patch dist `Package.swift` / podspec）。`LivebuyUI`（view-model 層，source 出貨）本版另有一筆
> 把購買頁／客服連結接上 URL 開啟策略的**行為變更**（`5457c97e`，見下方 `Changed`）；
> `LivebuyReferenceUI`（source 出貨）本版有兩筆改動（中獎領獎 modal 頁尾連結可點擊 `55ef0e8d`、
> 暱稱被佔用時就地顯示錯誤 `fad82c7f`）。詳見
> [`docs/release/v4.4.0-tag-runbook.md`](../docs/release/v4.4.0-tag-runbook.md) 與
> [release notes](../docs/release-notes/v4.4.0.md)。

### Changed（⚠️ 行為變更 — 唯一「不改簽章但行為會變」的一條，請先讀）

- **⚠️ 外部連結（商品導購頁 `diversion == 1` / 客服連結，host 未攔截時）改依網址分流**
  （`5457c97e`，消費 core `dcea410f` 新增的 `LBURLOpenPolicy.decide(_:)`）。**規則**：
  `livebuy.tv`（含任意層子網域）→ 維持 in-app（`SFSafariViewController`）；其他可開網址
  （`http`/`https`/`mailto`/`tel`/`sms`）→ 系統瀏覽器；不在允許清單內（`javascript:` /
  `intent:` / `data:` / `file:` / 自訂 scheme 等）→ 安全 no-op（先前可能被原樣 present 進
  in-app browser）。**典型後果**：非 `livebuy.tv` 網域的商品導購頁與客服連結會從 in-app 瀏覽器
  改為 eject 到系統瀏覽器——這是刻意的行為變更，不是 regression。host 攔截順序（`PRODUCT_CLICK`
  / `performServiceLink()`）逐字不變，策略只在 host 未攔截時套用。「直播背景續播」的既有保證
  **只在 in-app 分支保留**，走系統瀏覽器分支後不再是無條件保證。**API 面零破壞**：呼叫點對 host
  不可見，無新參數、無新事件。

### Added（新公開面，皆 additive、源碼相容、無 breaking）

- **`LBURLOpenPolicy.decide(_:)` / `LBURLOpenTarget` / `LBLegalLinks.termsOfUse` /
  `.privacyPolicy`**（`dcea410f`）——純函式 URL 開啟目標裁決規則與法務連結網址事實來源。對 host
  而言是**可選用的新增 API**（不呼叫即無任何行為變化）；SDK 內部的消費點隨本版一起出貨，見上方
  `Changed`（view-model 層 `5457c97e`）與下方 `Fixed / drop-in behavior`（reference-ui 層
  `55ef0e8d`）。
- **`LivebuyPlayerViewController.setGuestNicknameVerified(_ name: String) async throws`**
  （`81a76425`）——設定留言暱稱前先對目前 video 呼叫既有 `checkName` 驗證，通過才持久化 + 廣播
  `AUTH_STATE_CHANGED`；被取走或其他錯誤一律不持久化、不廣播，拋出可分辨的 `LBError`
  （複用既有 `.guestNameTaken` / `.networkError` 等分類，不新增 case）。既有
  `setGuestNickname(_:)`（同步、無驗證）簽章與行為不變。
- **`setGuestNicknameVerified` 不再有靜默成功路徑**（`12c894a4`）——先前有兩道前置 guard（名稱
  trim 後為空、或 SDK 未 configure / 播放器未載入影片）會在完全沒有提交暱稱的情況下正常返回。
  現在一律 `throw`：SDK 未 configure → 既有 `.notConfigured`；名稱為空或無影片 → **新增**
  `LBError.nicknameSetPreconditionFailed`。public 簽章不變（本來就是 `async throws`），
  成功路徑與 `checkName` 失敗映射完全不變。

### Fixed / drop-in behavior（reference-ui，drop-in `LivebuyPlayer` 使用者自動生效）

- **中獎領獎 modal 底部使用條款／隱私政策改為可點擊**（`55ef0e8d`）——先前純版面佔位、不接連結；
  現在各自可點擊，經 `LBURLOpenPolicy.decide()` 裁決開啟方式，連結來源為 `LBLegalLinks`。既有
  82 張 snapshot baseline 逐位元組不變。
- **暱稱被佔用時就地顯示錯誤、不關閉 modal**（`fad82c7f`）——暱稱設定 modal 送出改走
  `setGuestNicknameVerified`，只有驗證成功才關閉；被取走或其他錯誤則就地顯示錯誤、留在 modal
  內讓使用者改名重試。`onSubmit` 簽章不變，既有呼叫端零改動。一併修掉一個併發世代缺失
  （送出→取消→重開會讓舊請求消費新一次呈現，加 `presentationGeneration` gate 堵住）。

### Notes

- **未新增 / 移除 / 改名任何既有 host-facing public 符號**、無參數型別變更、無 wire 破壞。本版
  唯一需要 host 留意的是上方 `Changed` 小節的外部連結開啟方式。
- **binary 重 build**：見上方鎖點說明，XCFramework MUST 重 build，checksum 為新值（≠v4.3.0）。
- **RN / Flutter 本輪不發**（停在待發 `2.0.0`）；本版全部主題於其主線皆已落地，隨各自 2.0.0 出貨。

## [4.3.0] - 2026-07-28

> minor release，**無源碼破壞**、源碼相容，兩端 lockstep（iOS `v4.3.0` / Android `4.3.0`）。鎖點
> `87149d07`（本版最後一個碰 `ios/Sources/LivebuySDK/` 的 commit）。自 v4.2.0 以來碰
> `ios/Sources/LivebuySDK/`（binary target）共 **6 commit**（`AWARD_CLAIM_RESULT` 10 key `a1be0fd2`、
> 其 codegen 描述 `a8adb6ad`、`AUTH_STATE_CHANGED.display_name` 語意收斂 `9a5bb811`、商品獎品自動加購
> `809741a7`、其 codegen 描述 `dd57ae54`、`LogConfigStore` 自我死鎖根治 `87149d07`）
> → **binary MUST 重 build，checksum 為新值**（≠v4.2.0；由發版
> 流程於 `v4.3.0` tag 產生並 patch dist `Package.swift` / podspec）。`LivebuyReferenceUI`（source 出貨）
> 本版另有兩筆 drop-in 改造（四階段領獎 sheet `62133e9c`、加入活動三層閘 `efcd06a1`），隨 source target
> 出貨。詳見 [`docs/release/v4.3.0-tag-runbook.md`](../docs/release/v4.3.0-tag-runbook.md)、
> [真機 e2e 檢查表](../docs/release/v4.3.0-e2e-checklist.md) 與
> [release notes](../docs/release-notes/v4.3.0.md)。

### Changed（⚠️ 行為變更 — 唯一「不改碼但行為會變」的一條，請先讀）

- **⚠️ `AUTH_STATE_CHANGED` 的 `display_name` 語意收斂為「使用者自己選定的名字；未選定時為空字串 `""`」**
  （`9a5bb811`，iOS + Android dual）。**iOS 側的實際變化**：登出（`clearUser()`）後由回填系統自動產生的
  預設名（例如 `"Guest_4F2A"`）**改為回傳 `""`**——除非訪客自己設過暱稱，那就回那個暱稱。
  `state == "logged_in"` 的既有行為**完全不變**。
  - **為什麼**：turnkey 的暱稱閘判定是「未登入且 `display_name` 為空 → 要求先設暱稱」。iOS 因為回填了
    非空的 `"Guest_4F2A"`，讓「登入過又登出」的訪客被判成「已設過名」，**連留言都不會被要求設暱稱，
    直接頂著機器產生的代號公開發言**。Android 原本行為（沒帶 key，解為 `""`）才是對的，本版往它對齊。
  - **非源碼破壞**：事件名稱、參數 key、參數型別、公開方法簽名**皆不變**，重新編譯不會壞——故仍走 minor。
  - **host 因應**：若你在登出 / 訪客狀態下拿 `display_name` 當「畫面上要顯示的名字」直接用，
    **MUST 自行 fallback**（值為空時改用你自己的訪客預設稱呼，或引導使用者取名）。只在 `logged_in` 時讀
    它、或本來就自己組訪客顯示名者，**完全不受影響**。
  - **明確不受影響：`resolvedDisplayName`** —— 聊天 wire 送出用的名字**仍保留 `Guest_XXXX` fallback，
    一字未改**。留言送出後顯示的名字不會變空白；變的只有 `AUTH_STATE_CHANGED` 帶給你的那個值。

### Added（新公開面，皆 additive、源碼相容、無 breaking）

- **`AWARD_CLAIM_RESULT` params 由 4 key 擴為 10 key**（`a1be0fd2`；codegen 描述 `a8adb6ad`）——新增
  `winner_id` / `event_title` / `award_name` / `award_expiration` / `award_image_url` / `award_stock`；
  既有 `status` / `award_type` / `event_id` / `award_code` 的語意與觸發時機**完全不變**（**純新增 key、
  向後相容**，既有 host 不讀新欄位不會壞）。欄位分兩類——**記憶體來源**（`status` / `award_type` /
  `winner_id` / `event_title`，成功失敗都可靠）與 **API 回應來源**（其餘六個，僅成功才有）；
  nil / 空字串的 key **整個省略**；失敗只帶記憶體來源欄位；`award_stock` 含 `0`（＝無庫存）；
  `award_code` / `award_expiration` 僅折扣型獎品。**SDK 領獎成功後不導頁、不渲染**，資訊交 host 處理。
- **`CART_ADD_REQUEST` 新增選填 `award_winner_id`**（`809741a7`；codegen 描述 `dd57ae54`）——本筆加購由
  獎品領獎觸發時才帶，值＝中獎票券 id（同 `AWARD_CLAIM_RESULT` 的 `winner_id`），供 host 識別「這筆是
  獎品」並串回領獎事件；非獎品觸發時**整個省略 key**。typed accessor `LBCartAddRequest.awardWinnerId`
  **刻意為 optional**（缺 key → `nil`，不退空字串）。
- **view-model 層新增帶 email 的領獎提交入口**（`f1bfb841`）—— 含 email 驗證純函式、`submitInFlight`
  送出中狀態、`dismissClaim()`。**舊 EMAIL-LESS 入口 deprecated 但保留、源碼相容。**

### Fixed / drop-in behavior（reference-ui + turnkey，drop-in `LivebuyPlayer` 使用者自動生效）

- **中獎領獎補 email 欄位 → turnkey 內建領獎 sheet 改為四階段流程**（`62133e9c`）—— 由「單頁通知型
  sheet」改為 `claim`（填 email）→ `confirmSubmit` / `confirmClose`（二次確認）→ `submitting`（送出中）
  → `done` / `fail`。**修好一整類「中獎領取失敗」**：core 領獎路徑 `email` **必填**，而舊 sheet 不收
  email，host 未攔截又沒有 email 時 SDK fail-fast、**連領獎請求都沒送出**，訪客沒有任何地方能填。
  關閉為**純 dismiss**（中獎票保留、徽章不變、可再次領取）；fail 卡顯示通用錯誤文案（後端不區分失敗原因）。
  email 為**純聯絡用、非識別鍵**（後端已確認）：填錯不構成領獎失敗、同一 email 可領多個獎、登入態可預填
  會員 email 但應保持可編輯。**訪客確實能參加、中獎、領獎**，訪客中獎後才登入**不會掉票**。
- **商品獎品領獎成功後自動加入購物車**（`809741a7`）—— `award_type == "product"` 的獎品領獎成功後
  SDK 自動加購，該筆領獎共派**兩個事件**：`AWARD_CLAIM_RESULT`（claim 成功即派）→ `CART_ADD_REQUEST`
  （addcart 成功後派）。**discount 型完全不受影響**（只有一個事件，行為一字未改）。加購失敗時獎品
  **仍算領到**（`status` 維持 `claimed`）且依既有契約**不派任何事件**——host 判斷方式＝收到
  `AWARD_CLAIM_RESULT(claimed, award_type=product)` 卻沒有配對的 `CART_ADD_REQUEST`；此情境下 host 只有
  獎品名稱與圖片、**沒有 host 側商品 id**，無法自行補進自家車（刻意的最小對外面積取捨）。獎品加購
  **豁免 30 秒防重複建單窗口**、且**不送**加購轉換埋點（0 元獎品不是加購轉換）。
- **加入活動 CTA 套用與留言一致的三層閘**（`efcd06a1`）—— 修好「**沒設暱稱卻能參加抽獎**」：參加活動
  本質上就是送一則帶 `event_id` 的口令留言，卻沒有任何閘。現在 drop-in 的加入活動 CTA 走
  ①登入閘（依 `sdkConfig` 訪客留言開關）→ ②暱稱閘（未登入且沒自選過暱稱）→ ③通過才送出，
  並在閘攔截後**續作**（pending-join，完成登入 / 設暱稱後自動接續原動作）。iOS 的閘位在 funnel **之前**
  return，被攔截的 tap **連 `EVENT_JOIN_INTENT` 都不會派**，因此 host 不會收到「假參加」訊號。
  （Android / RN / Flutter 另有一個 host join 觀察 callback，其「攔截時一併抑制」的收斂由各自平台的
  change 處理；iOS reference-ui 沒有該 callback，故無對應改動。）

### Fixed（core，iOS 獨有 — 既有缺陷，非本版引入）

- **`configure()` 之後 SDK 內部的一把鎖會被永久卡死**（`87149d07`）—— `LogConfigStore.refreshIfNeeded`
  在已持有內部 `NSLock` 的區段內呼叫了一個自己也會取同一把鎖的存取器。`NSLock` 不可重入，同執行緒
  二次取鎖**直接永久阻塞，且該鎖從此不再釋放**。這是確定性、無條件、不可恢復的（不是偶發競爭），
  而且**正式環境每次 `configure()` 都會觸發**。
  - **host 可觀察到的最嚴重後果**：同一 process 內**第二次以後的 `LivebuySDK.configure(...)` 永不返回**
    ——`await configure()` 一直不 resume，host 的 loading 狀態永遠不會結束。會踩到的典型情境是切換
    apiKey / shopId、或登入登出流程中重新 configure。**單次 configure 的 host 不受此影響。**
  - 其他後果：每次 configure 永久燒掉一條 Swift concurrency cooperative-pool 執行緒；SDK 內部事件
    批次上報排程在第一次 tick 後停擺。
  - **既有缺陷**：由 `1a00d32c`（2026-05-22）引入，已隨 v3.x / v4.0.0 / v4.1.0 / v4.2.0 出貨，
    **不是 v4.3.0 的 regression**。**iOS 獨有** —— Android 對應實作全檔無鎖，從不受影響。
  - **公開 API 零變動**，host 無需改碼。
  - ℹ️ **不要誤讀為「動態日誌降級配置開始生效」**：實測 `/sdk/log_config` 與 `/sdk/log` 在正式環境
    皆回 404（路由不存在），該功能修好後**仍不會生效**，只是從「死鎖」變成「乾淨地失敗並保留內建
    預設值」。批次大小 / 刷新間隔仍為內建預設，**行為與 v4.2.0 一致**。

### Notes

- **未新增 / 移除 / 改名任何既有 host-facing public 符號**、無參數型別變更、無 wire 破壞、無新增
  bundled 資源。本版唯一需要 host 留意的是上方 `Changed` 小節的 `display_name` 語意。
- **binary 重 build**：本版 core（`ios/Sources/LivebuySDK/`）被 6 顆 commit 動到，XCFramework MUST 重
  build、checksum 為新值（≠v4.2.0）——由發版流程於 `v4.3.0` tag 自動產生並 patch dist `Package.swift` /
  podspec。
- **RN / Flutter 本輪不發**（停在待發 `2.0.0`）；本版四個主題於其主線皆已落地，隨各自 2.0.0 出貨。

## [4.2.0] - 2026-07-22

> minor release，無 breaking，源碼相容，兩端 lockstep（iOS `v4.2.0` / Android `4.2.0`）。鎖點
> `5271eb03`（本版最後一個碰 `ios/Sources/` 的 commit）。自 v4.1.0 以來碰 `ios/Sources/LivebuySDK/`
> （binary target）共 **3 commit**（ACTIVE_EVENT 對外暴露 `5271eb03`、直播抽獎「參加」turnkey `40d57a02`、
> `WIN_RECEIVED` params KDoc 校正 `7f865a0b`）→ **binary 已重 build，checksum 為新值**（≠v4.1.0；由
> `release-ios.yml` 於 `v4.2.0` tag 產生）。`LivebuyReferenceUI`（source 出貨）本版另有多筆 drop-in 修復
> （商家 logo / 商品明細規格連動），一併隨 source target 出貨。詳見
> [`docs/release/v4.2.0-tag-runbook.md`](../docs/release/v4.2.0-tag-runbook.md) 與
> [release notes](../docs/release-notes/v4.2.0.md)。

### Added（新公開符號，皆 additive、源碼相容、無 breaking）

- **`ACTIVE_EVENT_STARTED` notification event (in-progress live event / live giveaway)** — the SDK
  dispatches this when `POST /sdk/video/goods` returns an `event[]` entry it has not notified before
  (**fire-once per event id**; the dedup set is cleared on video switch). Params (flat):
  `{ id, title, keyword?, duration, surplus, award }` — `keyword` (the "join event" passphrase) is
  omitted when empty, `surplus` is a seconds snapshot at dispatch time (the host counts down locally
  from `duration` + the wall-clock time it received the event), and `award` reuses the winner
  `[{type, name, code}]` shape. **Does not carry `stayTime`** (a turnkey-internal dwell threshold).
  Lets the host draw its own event countdown / prize teaser / join-event entry point.
- **`LBActiveEvent` public model** — `{ id, title, keyword, award, duration, surplus, stayTime }`,
  produced via the `Core/DTOs` → `Core/Mappers` route (not `Decodable`, consistent with the other
  mapped public models). `LBVideoGoodsResponse.event` is promoted from internal to **public** alongside it.
- **`activeEvents()` public accessor** — returns a snapshot of the in-progress events in the current
  goods cache, covering the late-subscriber blind spot where a host that attaches mid-stream would miss
  the fire-once `ACTIVE_EVENT_STARTED` event.

### Fixed / drop-in behavior（reference-ui + turnkey，drop-in `LivebuyPlayer` 使用者自動生效）

- **直播抽獎「參加」turnkey 化（drop-in `LivebuyPlayer`）** — host 未攔截 `EVENT_JOIN_INTENT` 時，drop-in
  容器自動送出加入活動的口令留言（帶 `event_id` + 純牆上時間 `stay_time`，背景照算 / 每支影片重置），host
  無須自接領獎流程。poll 每輪對進行中活動 fire-once `eventstay`。對齊 Android（本版兩端同步）。
- **商家 logo 改繪真實圖片（drop-in 播放器頂部主播列 + 商品資訊面板商家列）** — 兩處商家列改繪真實商家
  logo（漸層 monogram chip 降為底層佔位、永遠繪製，取代先前只有 monogram 的呈現）；並修好 iOS header
  **每次首開閃純白圓**（`RemoteStillImageView.load` 開頭無條件清空 image）與**全空白 logo 顯純白圓**
  （`URL(string:"   ")` 回非 nil 繞過 monogram fallback）兩個既有破口。對齊 Android / info panel。
- **商品明細 sheet 價格 / 主圖跟隨已選規格（drop-in ProductDetailSheet）** — 選規格後**售價 / 原價**與
  **主圖 / zoom 燈箱**同步切到該規格（先前價格停在商品層屬**誤導性 bug**、主圖不跟規格）；來源有效性與所繪
  項目採同一述詞。對齊 Android（本版兩端同步）。

### Notes

- **未新增 / 移除 / 改名任何既有 host-facing public 符號**（本版新增符號皆 additive）；無欄位型別變更、無
  新增 bundled 資源。ACTIVE_EVENT 新 API 供 headless host 消費；drop-in 修復對 `LivebuyPlayer` 使用者自動
  生效。
- **`WIN_RECEIVED` params KDoc 校正（無 wire / 行為變更）** — 事件登錄檔的 winner params 由從未填充的
  幽靈欄位 `name` 校正為實際 wire 的 `event_id` / `title`（emit 邏輯本就送 `event_id` / `title`，僅四端
  KDoc 據舊 source 生成錯誤）；**dispatch 的 params 無任何變化**，host 端無感。
- **binary 重 build**：本版 core（`ios/Sources/LivebuySDK/`）被動到（ACTIVE_EVENT 對外暴露 + turnkey 抽獎
  參加 + WIN_RECEIVED KDoc codegen），XCFramework 已重 build、checksum 為新值（≠v4.1.0）——由
  `release-ios.yml` 於 `v4.2.0` tag 自動產生並 patch dist `Package.swift` / podspec。

---

## [4.1.0] - 2026-07-17

> minor release，無 breaking，源碼相容，兩端 lockstep（iOS `v4.1.0` / Android `4.1.0`）。鎖點
> `35cd642e`（本版最後一個碰 `ios/Sources/` 的 commit）。自 v4.0.0 以來碰 `ios/Sources/` 共 **2 commit**
> （`94d4d89a` environment 擴張 + `35cd642e` 預錄直播 live-edge 修復），**皆動到 `ios/Sources/LivebuySDK/`
> （binary target）→ binary 已重 build，checksum 為新值**（≠v4.0.0；由 `release-ios.yml` 於 `v4.1.0` tag
> 產生）。詳見 [`docs/release/v4.1.0-tag-runbook.md`](../docs/release/v4.1.0-tag-runbook.md) 與
> [release notes](../docs/release-notes/v4.1.0.md)。

### Changed

- **`configure(environment:)` 現同時切換資料 API base URL（不再只切 `/stat`）** — `LBEnvironment.develop`
  由原本「只把 `/stat` 指向 `https://develop.livebuy.tv/stat`」擴張為連同**資料 API base URL** 一起切到
  `https://develop-admin.livebuy.tv/v1`；`.production`（或省略）維持 `https://api.livebuy.tv/v1`（**預設行為
  不變**）。切換經單一 chokepoint `APIClient.baseURL` 生效，涵蓋所有 `/sdk/*` 請求（config / video / widget /
  poll / comments / event upload / config refresh）。`/sdk/config` 本地快取 key 環境化（`.develop` 加
  `_develop` 後綴），杜絕 prod / dev 同 `shopId` 快取互污；`.production` 快取 key 維持 `lb_sdk_config_{shopId}`
  不變，既有正式用戶快取無縫升級。**只換 URL、不換憑證**（host 切 `.develop` 須自備 dev 憑證，SDK 不內建）；
  HMAC 簽章機制不變（只簽 `apiKey` + `timestamp`）。移除未使用的 `localBaseURL` dead code。**無新增 / 改名
  host-facing public 符號**（`LBEnvironment` case 未增未改，純既有參數行為擴張）。

### Fixed

- **預錄直播 live-edge 牆上時間錨點修復（一次修 3 個 bug，drop-in `LivebuyPlayer`）** — 預錄直播
  （`liveStatus == 1`、走 IVS 引擎）先前缺牆上時間錨點、到處誤把整片長 `duration` 當 live edge，導致三個
  症狀：(1) **App 退背景 / 真 PiP 後回前景，播放頭凍住、落後「現在」不追回 live**（唯一使用者可達路徑）；
  (2) **`isBehindLiveEdge` 全程誤判成回放**（LIVE 徽章消失、聊天鎖為回放態）；(3) **back-to-live 誤跳到
  片尾**（`performBackToLive` seek 到 `duration`）。本版建立牆上時間錨點模型：首次 begin-align 對齊時記錄
  錨點 `(錨點牆上時間, 錨點位置 = begin)`，純函式 `預期 live 位置 = 錨點位置 + max(0, 現在 − 錨點牆上時間)`
  （用牆上時間，背景 / 休眠仍前進）；回前景依錨點追回 live（落後 >5s 才 seek）、`isBehindLiveEdge` 改比對
  預期 live 位置、back-to-live 改 seek 到預期 live 位置（clamp 到 `duration`）。錨點持續整個 session，
  re-align **只在背景→前景觸發**（前景手動暫停不碰，避免與刻意 scrub-back 衝突）。此為既有模型缺陷修復
  （病根早於 v4.0.0，非改名 regression），對齊 Android `548bde9d`（本版兩端同步）。

### Notes

- **未新增 / 移除 / 改名任何 host-facing public 符號**（兩筆變更皆以 core 內部邏輯完成）；無欄位型別變更、
  無新增 bundled 資源。`.develop` 環境擴張、live-edge 修復皆 drop-in `LivebuyPlayer` 使用者自動生效。
- **binary 重 build**：本版 core（`ios/Sources/LivebuySDK/`）被動到（environment `APIClient.baseURL` +
  live-edge 錨點模型），XCFramework 已重 build、checksum 為新值（≠v4.0.0）——由 `release-ios.yml` 於
  `v4.1.0` tag 自動產生並 patch dist `Package.swift` / podspec。`LivebuyReferenceUI`（source 出貨）本版
  未動。
- **environment smoke 已驗**：develop 端 `POST /sdk/config` 回 HTTP 200 / inner code 200、body 為合法
  `SDKConfig`，坐實 base URL 正解 + 憑證有效 + 簽章正確。

---

## [4.0.0] - 2026-07-16

> **⚠ MAJOR — BREAKING（品牌大小寫識別字改名）。** 全庫程式識別字由 `LiveBuy*` → `Livebuy*`
> （`liveBuy*` → `livebuy*`），與品牌顯示形（`Livebuy`）一致。**乾淨改名、無 alias。**
> **SwiftPM/CocoaPods 模組名硬 break（無消費端別名機制）**——`import LiveBuySDK` / `LiveBuyUI` /
> `LiveBuyReferenceUI` 一律改成 `import LivebuySDK` / `LivebuyUI` / `LivebuyReferenceUI`。因核心模組
> 更名，binary XCFramework **重 build、checksum 更新**（由 `release-ios.yml` 於 `v4.0.0` tag 產生）。
> 詳見 [`docs/migration/brand-casing-livebuy-rename.md`](../docs/migration/brand-casing-livebuy-rename.md)。

### Changed

- **模組 / product / target 名**：`LiveBuySDK` → `LivebuySDK`、`LiveBuyUI` → `LivebuyUI`、
  `LiveBuyReferenceUI` → `LivebuyReferenceUI`（consumer `import` 必改；無 SwiftPM 別名）。
- **公開型別**：`LiveBuy` → `Livebuy`（class）、`LiveBuyEventListener` → `LivebuyEventListener`（protocol）、
  drop-in `LiveBuyPlayer` / `LiveBuyWidget` / `LiveBuyLiveEntry` + 各 `*Config`、`LiveBuyPlayerViewController`、
  `LiveBuyWidgetVisibility` 等一律 → `Livebuy*`。`@objc` 型別的 ObjC runtime 名同步改（無 `@objc(舊名)` 保留）。
- **public modifier**：`View.liveBuyPlayer(video:)` → `View.livebuyPlayer(video:)`（drop-in collapsible player）。

**不變**：`api.livebuy.tv` 網域、wire 行為、`LB*` model/event 型別（`LBError` / `LBProduct` / … 未改）。

---

## [3.2.2] - 2026-07-15

> PATCH release，無 breaking，源碼相容。版號與 Android SDK `3.2.2` **收斂同號**（兩端一起切 3.2.2，
> 延續 3.2.0 / 3.2.1 模式）——**同號、diff 各異**：兩端**共有** presenter 依相位驅動 widget-cover
> （iOS `5fcbc391` / Android `87702dcf`，實作互為 parity）＋ `LivebuyWidgetVisibility` KDoc 對齊
> （`a992bcfa`，四端同步）；**iOS 額外**多一筆 PiP 內暫停回前景續播（`e06cb761`），對 Android 為
> **N/A**（Android 無 PiP 暫停控制項 / 同 player 無縫延續，AVKit-restore 缺陷 iOS 特有）。同號 = 同
> parity 水位（如 3.2.1），各自獨立走各自通道（iOS SPM dist / Android Maven）。內容鎖點 `a992bcfa`
> （最後碰 `ios/Sources/` 的 commit）。自 v3.2.1（iOS 出貨鎖點內容 `8ebd9004`）以來碰 `ios/Sources/`
> 共 **3 commit**（3 reference-ui fix）；**`ios/Sources/LivebuySDK/`（binary target）零變更 → 不重
> build，checksum 沿用 v3.2.0/3.2.1 `a58952dd…`（同一顆 XCFramework 原封重傳）**。詳見
> [`docs/release/v3.2.2-readiness.md`](../docs/release/v3.2.2-readiness.md)。

### Fixed

- **首頁 widget 輪播預覽在被覆蓋 / 縮小後恢復（presenter 依相位驅動，drop-in collapsible player）** —
  用收合播放器（`.livebuyPlayer(video:)` presenter）時，影片開全螢幕覆蓋首頁 `LivebuyWidget` 輪播、或
  縮小成右下浮卡後，首頁輪播預覽先前會因硬體解碼器爭用卡住不播。本版讓 `LivebuyPlayerPresenter` 成為
  `setWidgetsCovered` 單一 owner（契約 `covered ⟺ 相位 .full`）：全螢幕 → 讓首頁預覽讓出解碼器；縮小 /
  關閉 / 移除 → 恢復。補齊 host-visibility-pause 的「host 從未呼叫」缺口。對齊 Android `87702dcf`。
  **host 不需改任何呼叫碼。**
- **真 PiP 內暫停回前景自動續播（定格幀修復，iOS-only）** — 影片真進系統 PiP、在 PiP 內手動暫停後回
  前景時，畫面先前會定格在暫停幀（AVKit restore 只還原畫面、不 un-pause 使用者在 PiP 內手動暫停的
  串流）。本版把回前景續播**延後到 PiP 結束**（`ForegroundResumeController` 新增 `resumeOnPiPExit`
  意圖 latch，待 `PIP_STATE_CHANGE` active→false 由 aux listener 觸發一次 `play()`）；fallback pause
  情境維持立即續播；背景前已暫停 / 背景關 PiP 皆不誤 resume。此筆對 Android 為 N/A。
- **`LivebuyWidgetVisibility` KDoc 對齊 presenter-owned 兩路徑** — 文件更新為「主路徑＝presenter 依相位
  自動驅動（host 免呼叫）；手動路徑＝僅裸 / 自管 host，且自製 floating 勿用 `presentedVideo != null`」，
  移除過時範例與 accepted over-pause 框架，使文件與 presenter 分流一致（四端同步、doc-comment only、
  無行為變更）。

### Notes

- **未新增 / 移除 / 改名任何 host-facing public 符號**（修復以容器內部邏輯 / presenter wiring 完成）；
  無欄位型別變更、無行為預設值翻轉、無新增 bundled 資源。三筆修復皆 drop-in `LivebuyPlayer` /
  collapsible presenter 使用者自動生效。
- **binary 沿用 v3.2.0/3.2.1**：本版無任何 core 變更，XCFramework 與 v3.2.0/3.2.1 逐 byte 相同——未重
  build、checksum 維持 `a58952dd…`，同一顆 `LivebuySDK.xcframework.zip` 原封重傳至 `v3.2.2` release。
  `LivebuyUI`（view-model）本版亦未動；三處變更都在 `LivebuyReferenceUI`（source 出貨）。

---

## [3.2.1] - 2026-07-14

> PATCH release，無 breaking，源碼相容，**iOS-only**（Android 留 `3.2.0`；本版是 iOS 追平 Android 既有
> lifecycle 行為，非兩端功能分歧）。鎖點 `8ebd9004`（本版唯一碰 `ios/Sources/` 的 commit）。自 v3.2.0
> （iOS 出貨鎖點內容 `7600fcd5`）以來碰 `ios/Sources/` 僅 **1 commit**（1 reference-ui fix）；
> **`ios/Sources/LivebuySDK/`（binary target）零變更 → 不重 build，checksum 沿用 v3.2.0 `a58952dd…`
> （同一顆 XCFramework 原封重傳）**。詳見 [`docs/release/v3.2.1-readiness.md`](../docs/release/v3.2.1-readiness.md)。

### Fixed

- **直播背景回前景「定格幀」修復（drop-in `LivebuyPlayer`）** — App 退背景後回前景時，直播（IVS 引擎）
  畫面先前會定格在暫停幀不續播：core 在系統 PiP 進不去時 fallback 暫停播放引擎，但 iOS 容器缺回前景
  續播的另一半。本版 reference-ui 容器補回與「進背景」成對的「回前景自動續播」，並在真正進入系統 PiP
  時交還 AVKit PiP restore（不雙重 resume）；回放 / VOD 情境同樣回前景可續播。對齊 Android
  `android-refui-player-lifecycle-pause` 的 `ON_STOP`/`ON_START` 行為。**core 零改、僅呼叫既有 public
  API；未新增 / 移除任何 host-facing public 符號、無新增 bundled 資源。**

---

## [3.2.0] - 2026-07-14

> minor release，無 breaking，源碼相容，兩端 lockstep（iOS `v3.2.0` / Android `3.2.0`）。鎖點
> `45fbf4f9`（iOS 出貨內容等價於最後一個碰 `ios/Sources/` 的 `7600fcd5`；其後 RN commit 零碰 iOS）。
> 自 v3.1.3（`60e2fa50`）以來碰 `ios/Sources/` 共 13 commit（8 core / 4 reference-ui / 1 template）；
> core 被動到，故 **binary 已重 build，checksum 為新值 `a58952dd…`**（≠v3.1.3 `6bea1e20…`）。
> 詳見 [`docs/release/v3.2.0-readiness.md`](../docs/release/v3.2.0-readiness.md)。

### ⚠️ 行為變更：`/stat` 統計埋點改「預設開」（opt-out）

`configure(...)` 的 `enableStatReporting` 預設值由 `false` 改為 `true`：**升級後不帶此參數，SDK 就會開始
送 `/stat`**（觀看 / 分享 / 加購 / 商品曝光等 10 型；端點 `https://livebuy.tv/stat`，unsigned、
form-urlencoded、fire-and-forget，wire body **無 PII / device id / ip**）。要維持關閉：顯式帶
`enableStatReporting: false`。只翻 stat、不動 `enableConversionAttribution`（涉 Meta 歸因 id，維持
opt-in / 預設關）。ATT / GDPR 同意仍是 host 責任。

### Added（新公開符號，皆 additive、無 breaking）

- `configure(...)` 新增三個帶預設值參數：`enableStatReporting: Bool = true`、
  `environment: LBEnvironment = .production`、`enablePowerProfileAdaptation: Bool = true`（既有呼叫碼不需改）。
- **`LBEnvironment`**（`.production` / `.develop`）— SDK 全域環境選擇器，目前用於 `/stat` 端點切換
  （`.develop` → `https://develop.livebuy.tv/stat`）；只選端點，不改是否送 stat / wire / no-HMAC 契約。
- **`LBEvent.powerProfileChanged`**（`POWER_PROFILE_CHANGED`）— 熱狀態感知的 power profile tier 改變時派發
  （param `profile` = `full` / `reduced` / `conservative` / `survival`），供 host / reference-ui 自適應。
- **`enablePowerProfileAdaptation`**（opt-out，預設 `true`）— 關掉即停用熱狀態感知的自動降載（畫質 cap /
  輪詢 backoff）。

### 功能亮點

**core**
- **`/stat` 埋點子系統（10 型）** — 原生送出觀看 / 分享 / 加購 / 商品曝光等統計，含 `person_time`
  （觀看時長）/ `person_duration`（前景停留）兩計時器。
- **直播發熱優化** — thermalState 感知自動降載（畫質上限 cap + 輪詢 backoff 隨溫度 tier）、直播兩條 5s
  輪詢合流到單一 scheduler tick（對齊 radio 喚醒省電）、螢幕感知畫質上限降低直播解碼發熱。

**reference-ui**
- **widget 預覽生命週期暫停** — widget live 預覽在 app 背景 / 離屏 / 被全螢幕 player 覆蓋時停止解碼，
  回前景 / 可見時續播，消除背景無謂解碼發熱。
- **連續裝飾動畫依 power profile 節流**。
- **onsale 商品開賣卡死碼移除**（reference-ui + template，無行為變更）。

**無 BREAKING。**（`/stat` 為預設值翻轉，非 API 破壞——見上方行為變更。）

---

## [3.1.3] - 2026-07-10

> patch release，無 breaking。鎖點 `60e2fa50`（iOS 出貨內容等價於最後一個碰 `ios/Sources/` 的
> commit `a905f3af`；其後 Android/RN/Flutter/docs commit 零碰 iOS）。自 v3.1.2（`e2c2fde0`）以來
> 碰 `ios/Sources/` 共 11 commit：6 fix / 4 feat / 1 pilot；其中 3 個 core commit 動到 binary
> 核心，故 **binary 已重 build，checksum 為新值 `6bea1e20…`**（≠v3.1.2 `a08e318c…`）。
> 詳見 [`docs/release/v3.1.3-readiness.md`](../docs/release/v3.1.3-readiness.md)。

### v3.1.3 — patch（總覽）

**Fixed**
- **LIVE 釘選商品卡「關閉」鈕誤開明細** — 關閉鈕接 dismiss，點 X 不再冒泡誤開商品明細；點卡片
  本體仍正常開明細。
- **EndScreen「換一批」誤開播放** — 直播結束畫面點「換一批」改在本地推薦視窗內輪播，不再意外
  開始播放某支影片。
- **合流聊天歷史上限 50→500** — 跳頁重進同一場直播，歷史聊天訊息不因舊的偏低上限而提前消失。
- **collapsible 播放器資源洩漏** — `LivebuyPlayer` 新增 `dismantleUIViewController` 保證性釋放，
  修復縮小浮卡播放器關閉時未 `unload()` 的資源洩漏。
- **Player `unload()` 冪等化（core）** — 多條關閉路徑不再疊加成重複結束事件。
- **系統 PiP 直播鎖定拖動（core）** — 進行中直播的 PiP 視窗停用拖動進度／快轉／快退（對齊
  Android IVS `controlsEnabled`）；暫停鍵無任何 Apple 公開 API 可控，記為永久平台限制。

**Added（新公開符號，皆 additive 或源碼相容的軟性 deprecate、無 breaking）**
- `LBChannel.begin: Int?`（core）— 預錄直播（`liveStatus == 1`、走 IVS 引擎）此刻所有觀眾共同
  播放到的秒數，供晚進場觀眾對齊播放進度；僅預錄直播情境有值，真．即時直播／預告／回放為 `nil`。
  public init 新增 `begin: Int? = nil` 參數（帶預設值，源碼相容）。
- `DefaultTemplateConstants.activityFeedChatRetain` / `.activityFeedActivityRetain`（view-model）
  — 合流 feed 聊天列/活動列各自獨立保留上限（500 / 200），聊天列不再被活動列擠出（iOS-only
  pilot；Android/RN/Flutter parity 為 follow-up）。既有 `activityFeedHistoryRetain` 加
  `@available(*, deprecated, ...)` 標記（值/型別不變，源碼相容，非強制遷移）。

**功能亮點（reference-ui 層）**
- **EndScreen 推薦影片卡封面圖** — 推薦影片卡補上 live-gated 封面圖與預覽動畫。
- **進行中直播隱藏商品分享入口** — LIVE 情境的 ProductDetailSheet 3-slot footer + 商品列分享
  icon 隱藏，對齊 design R12。
- **進行中直播禁止長按暫停** — 串流＋預錄直播禁止長按暫停手勢與提示；回放/VOD 維持可暫停。

**無 BREAKING。**

---

## [3.1.2] - 2026-07-08

> patch release，無 breaking。鎖點 `e2c2fde0`（iOS 出貨內容等價於 `200903fb`；其後 RN/Flutter
> 浮卡 parity commit 零碰 `ios/Sources/`）。修復 v3.1.1 發布後於 `ios/Example` 追修批次揭露的
> 兩個功能性 bug（直播結束不跳結束畫面 / 跳頁後直播歷史失效），並帶入 core/template 多觀察者
> 治本地基與浮卡縮圖同步自動接播。詳見 [`docs/release/v3.1.2-readiness.md`](../docs/release/v3.1.2-readiness.md)。

### v3.1.2 — patch（總覽）

**Fixed**
- **直播結束不跳結束畫面** — `live_end` wire 改容忍 Int 與數值字串（後端偶以字串回傳），
  直播結束時正確派發並跳 EndScreen（不再卡在播放中）。
- **跳頁後直播歷史失效** — 播放器 `deinit` 存歷史快照改用穩定 `lastKnownVideoId` 作 key，
  修復「跳頁後重進同一場直播看不到歷史留言」的破口。

**Added（新公開符號，皆 additive、屬內部接線 seam、無 breaking）**
- `LivebuyPlayerViewController.onDidAutoAdvance: ((LBNavItem) -> Void)?` — core 於 VOD 自動接播
  時 fire 的 instance seam（與 Android `LivebuyPlayerView` 同名 parity），供 reference-ui 浮卡
  同步縮圖；drop-in 容器自動接線，既有 host 呼叫碼零改動。
- `DefaultPlayerTemplate` / `DefaultWidgetTemplate` 的 `addObserver(_:) -> LBTemplateObserverToken`
  / `removeObserver(_:)` 與 `LBTemplateObserverToken` — view-model 層多觀察者註冊地基，
  reference-ui 內部消費（治本 onChange 串鏈脆弱）。

**功能亮點（純視覺，reference-ui 層）**
- **浮卡縮圖同步 VOD 自動接播** — VOD 自動接播下一支後，縮小的 `CollapsibleLivebuyPlayer`
  浮卡縮圖同步更新為新片、不再 stale（補上換片同步的第四條路徑）。
- **變體 chips flex-wrap** — 商品 sheet 規格 chips 選項多/字長時自然換行、看得到全文
  （iOS 16+ 自刻 `ChipFlowLayout`；iOS 14/15 fallback 每行三個）。

**內部重構（行為不變）**
- player / widget overlay model 從 onChange 串鏈遷移到多觀察者註冊，根除換片後 overlay
  凍在 stale 的脆弱模式。

**無 BREAKING。**

---

## [3.1.1] - 2026-07-05

> patch release，無 breaking。鎖點 `9bdbb1f6`。修復 v3.1.0 發布後密集浮現的 chat history 問題
> （關閉播放器重進同一場直播看不到歷史留言，經多輪修正收斂），另含兩個純視覺 reference-ui
> 呈現變更。詳見 [`docs/release/v3.1.1-readiness.md`](../docs/release/v3.1.1-readiness.md)。

### v3.1.1 — patch（總覽）

**Fixed**
- **chat history reentry** — 關閉播放器重進同一場直播，歷史留言不再消失；`PollManager` 改依
  per-instance `hasEverStarted` 旗標分流 `is_init`（不再誤判成「非首輪」）。
- **is_init 首輪歷史訊息批次 ingest** — 修正順序反轉假設方向錯誤，改為批次 ingest；修復後進場
  觀眾看得到歷史留言。
- **push id 去重** — 歷史訊息改依穩定 `id` 去重，避免 backlog 與 trickle 重疊重複顯示。
- **跨實例快取還原** — 歷史訊息快取升級為跨實例存活，關閉播放器重進同一場直播立即還原。
- **in-place 換片還原快取** — 切回已造訪影片時還原快取歷史，避免不必要重抓。
- **`LivebuyLiveEntry` 輪詢死鎖** — onAppear 掛在 EmptyView 分支導致輪詢無法啟動，已修復。

**功能亮點（純視覺，reference-ui 層）**
- **跑馬燈標題** — 直播標題實作真正的捲動動畫（LBPMarqueeText parity），不擠壓主播名稱版面。
- **炒氣氛提示改上方 toast** — 進場/選購/搶購/中獎不再混進聊天訊息列表，改由聊天室上方
  toast 顯示最新一則。

**無新增 host-facing public API。無 BREAKING。**

---

## [3.1.0] - 2026-07-03

> minor release，無 breaking。鎖點 `76a9baf4`。rc.1 真機煙囪（M1–M5）+ QA sign-off 皆過，
> binary 與 `v3.1.0-rc.1` 等價（沿用同一顆 checksum-pinned zip，未重 build）。詳見
> [`docs/release/v3.1.0-readiness.md`](../docs/release/v3.1.0-readiness.md)。

### v3.1.0 — minor（總覽）

**Added（新公開 API，皆 additive）**
- `LBAuthTriggerAction.subscribe` — 訂閱登入 gate 觸發類別；未登入點訂閱時 `AUTH_REQUIRED` 帶此
  trigger action，host 可精確分辨「因訂閱觸發的登入」。
- `CHAT_HISTORY_LOADED` — 新通知型事件（回放進場自動載入歷史留言後派發，交付 headless host 自繪聊天）。
- `POLL_RECEIVED` push row 透出穩定 `id`（headless host 去重用；欄位 omit-when-nil，舊 host 無感）。
- `onReplayChatRevealed` — 回放聊天 reveal 的 core seam。
- view-model 新欄位：`loadingCover` / `viewerCountVisible` / `isFinishedLiveReplay`。
- reference-ui host config：`showViewerCount`（可關閉直播人數徽章）。

**功能亮點**
- **訂閱一整套** — 未登入點訂閱跳登入 modal；訂閱方向改讀 live mirror（修回放/VOD 只能切一次）；
  在途連點 guard；登入/登出後 re-sync 徽章刷新。
- **分享預設 sheet** — 直播/回放底部 bar + VOD 側欄未接 `onShare` → 開系統分享 sheet（承 v3.0.0
  `performShare` 家族）。
- **回放一整套** — 套用 LIVE 版型、自動載入歷史留言、彈幕式時間軸同步（`time`=播放偏移秒數）、
  聊天室已關閉態。
- **聊天** — push 以穩定 `id` 去重；主播訊息完整顯示（不再截斷）；商品開賣（onsale）改走主播氣泡。
- **人數徽章** — honor 後端 `show_pv_num`；host 可用 `showViewerCount` 關閉。
- **播放器 fix** — 無可播串流不再卡 loading；規格選擇提示可重複觸發（re-arm）；loading 畫面顯示
  封面圖；加購 CTA 統一 accent 色。

**Fixed** — 47 個 fix（含四端 parity 修正）。**無 BREAKING。**

---

## [3.0.0] - 2026-07-01

> v2.0.0 從未發過正式版（只到 `v2.0.0-rc.5`）；其累積的 breaking（headless / token / rename）與
> 後續的 **Tier 2 統一加購** breaking 一次發為 v3.0.0。完整對外說明見
> [release notes](../docs/release-notes/v2.0.0.md)，升級照 [migration 總入口](../docs/migration/v2.0.0.md)。
> 未 tag 的 `[1.3.0]`（api-version）內容一併併入。checksum `21ba7ee…`（沿用 `v3.0.0-rc.3` 同顆
> binary，未重 build）。

### v3.0.0 — major / breaking（總覽）

**⚠ BREAKING — Tier 2 統一加購（`cart-add-tier2`）**
- **加購收斂為單一流程** — drop-in 播放器內加購由 SDK 自動 `addToCart` → 成功後派**通知型** `CART_ADD_REQUEST`（無 callback）交 host 加入自家購物車，取代舊「XOR 雙路線」。
- **`LBCartResultCallback` 退役** — `onEventTriggered` 的 `cartCallback` 恆 `nil`（保留簽章僅為 ABI 相容）；加購歸因改走 `reportCartTrack` + 訂單 webhook，不再經 callback。
- **`notifyCheckoutCompleted` deprecated** — 不再是歸因主路徑（成交歸因強制走 host 後端 order webhook，server-to-server）；下一 major 移除。
- **`CART_ADD_REQUEST` params 擴充** — 帶 `goods_no` / `specification_no`（= host 商品庫如 WooCommerce 的 product / variation id）、`buy_no`、`track`、`specification_id`、`sdk_track_code`，使 host 能對應自家目錄、寫入歸因欄位並呼叫 `reportCartTrack`。

**⚠ BREAKING — v2.0.0 累積（從未發正式版，併入 v3.0.0）**
- **Headless 化（`decouple-ui-from-logic`）** — 移除 Player / Widget / 9 sub-component 的所有像素渲染；class 簽章保留故能編譯但 view tree 空，UI callback 不攔為 no-op。改用 reference-ui drop-in 或自組 UI（**必聽 `dismissRequest`**）。
- **Token 模型（`session-token-migration`）** — per-video token 移除；`POST /sdk/video` 不回 token；改用 login session token。
- **裸 widget / player 改名 → `…Core`（`rename-bare-widget-to-core`）** — 黃金名 `LivebuyWidget` / `LivebuyPlayer` 讓給 reference-ui drop-in 容器；**iOS 因 module 分割不留 alias**。
- **音訊預設有聲** — 主播放 + 開場 intro 預設不靜音。
- （下方 widget-decode 區的 `LBVideoItem.goods?` / `LBWidgetResponse.widgetBgcolor?` BREAKING 一併入。）

**Added**
- **AWS IVS Player 直播低延遲引擎** — live `.m3u8` glass-to-glass ~15s → ~5s（iPhone 13 真機驗）；回放 `.m3u8` / intro MP4 / 非 `.m3u8` VOD 仍走 AVPlayer，引擎依 `selectPlaybackEngineKind(url, isLive)` 選。**散佈改變：SDK 含 binary（IVS XCFramework v1.52.0、checksum 鎖定）；改以三 product 出貨（binary `LivebuySDK` + source `LivebuyUI` / `LivebuyReferenceUI`）。**
- **reference-ui（新 product）** — drop-in 容器 `LivebuyPlayer` / `LivebuyWidget` + 可客製像素 source 層（對齊 `design/templates/minimal/*`）。
- **api-version-resilience**（原 `[1.3.0]`，100% 向後相容）、**sdk-widget API 串接**、widget / channel / video 解碼韌性硬化。

**Removed**
- SDK 內建 UI fallback / 預設 sheet；headless 後 snapshot 測試 + `compare-ui` CI（reference-ui 另有自己的 snapshot 體系）。

---

### Fixed — Widget 空清單 / error 碼解碼硬化 (`harden-widget-empty-and-error-decode`)

- **Widget 空清單不再 crash。** 後端於「過濾後無影片」時回 `code:200` 且 `data.videos.data`
  為 `null`（非 `[]`，後端 spec §Stage 3.5 / 場景 12）。`LBVideoListDTO` 現以手寫 `init(from:)`
  將 `videos.data` 的 `null` / 缺 key / 非陣列形態一律容忍為**空陣列**，整包回應解碼成功、不拋
  `DecodingError`。對齊 CLAUDE invariant「Required arrays default to `[]` on missing/null」。
  **對外 `LBVideoList.data` 維持非 optional 陣列（空時穩定為 `[]`），非 breaking。**
  Empty widget list (`videos.data: null`) no longer crashes; `LBVideoList.data` stays a
  non-optional array (stable `[]` when empty). Non-breaking.
- **iOS：`APIClient` schema-mapping POST 改為 code-first。** 先解輕量 `LBCodeEnvelope`
  （只含 `code`/`message`）gate 業務碼，僅 `code:200` 才將 `data` 解為 DTO。error 時 `data` 為
  非 widget 形狀（跨 agent `code:201` → `{}`、shop 不存在 `code:500` → `{"dbsc":""}`、
  guest_id/HMAC `code:401` → `[]`）不再拋 opaque `DecodingError`，而是穩定回
  `LBError.serverError(code:message:)`、保留 business code。426 / 429 派發時機不變。
  iOS: the schema-mapping POST is now code-first, so error business codes
  (201 cross-agent / 500 shop-not-found / 401) stably return `serverError` instead of an
  opaque `DecodingError`.

### Changed — Widget 回應解碼容錯對齊後端契約 (`align-widget-decode-robustness`)

- **⚠ BREAKING — `LBVideoItem.goods` 由 `LBFeaturedGood` 改為 `LBFeaturedGood?`。** 後端 `/sdk/widget`
  的 `goods` 為 `object|array|int|null` 四型態；影片無精選商品（`null`）或 count/array 型態時，`goods`
  現為 `nil`。Host app 讀取 `goods` 需處理 optional。
- **`LBWidgetResponse.widgetBgcolor` 由 `String` 改為 `String?`。** 後端未設定時整個 key 不出現，
  且值可能為 Int（1=透明）；SDK 改用 `decodeStringOrInt` raw passthrough（Int → `"1"`），未設定時為 `nil`。
- **新增 `LBWidgetResponse.showGoods: Int?`（商品卡位置 0/1/2）與 `otherUrl: String?`（91App 導購連結）**，raw passthrough。
- **解碼容錯**：`is_pv_exceed` 容忍 Int `0/1` 與 Bool（對齊「Bool 須容忍 Int 0/1」invariant）；
  `widget_color` 缺欄位時 default `1`；`source=linetv` 形態回應（無上述三欄位）也能成功解碼。

## [1.3.0] - 2026-05-26

> **發版剩餘步驟:** `git tag v1.3.0` + `git push origin v1.3.0` 觸發 distribution-repo workflow。本機已驗證:contract tests 全綠(MapperContractTests / LBRouteTests / ApiVersionConfigTests / DeprecationNoticeDispatcherTests / SdkUnsupportedOnceTests on iPhone 17 Pro / Xcode 26.5)、Example app 接 production backend smoke 過(`/sdk/widget` code:200,3 header 完整)。

### Added — API version resilience (`api-version-resilience`)

- **`LivebuySDK.configure(apiVersion:)`** — optional `Int` parameter, default `1`. Drives the
  `X-API-Version` request header and the internal mapper version dispatch. Invalid values
  (`0` / negative) fall back to `1` with a debug log.
- **3 automatic request headers on every API call** (附加於既有 `Authorization` header 之外,**不**影響 HMAC 簽名計算):
  - `X-SDK-Platform: ios`
  - `X-SDK-Version: <SemVer>` (讀自 `CFBundleShortVersionString`)
  - `X-API-Version: <integer>`
- **2 response-header signals parsed by SDK** (大小寫不敏感):
  - `X-API-Deprecation: true` → dispatch new `SDK_DEPRECATION_NOTICE` event (once per process).
  - `X-API-Sunset: <ISO 8601 date>` → carried as `sunset_date` in the event payload.
- **New event `LBEvent.sdkDeprecationNotice`** — notification class, payload schema
  `{ sunset_date: String?, sdk_version: String, recommended_action: "upgrade-sdk" }`.
- **New error `LBError.sdkVersionUnsupported`** — raised on every API response with inner
  `code: 426` (no dedup; host app gets a consistent error type in every `onError` branch).
- **`LBRoute` enum** — central registry for all 11 backend endpoints (`/sdk/video`,
  `/sdk/widget`, `/sdk/widget/live`, `/sdk/video/messages`, `/sdk/video/goods`,
  `/sdk/video/comments`, `/sdk/video/commentsub`, `/sdk/video/checkname`,
  `/sdk/video/subscribe`, `/sdk/video/like`, `/sdk/log`). All Player / Widget / Chat /
  Poll / EventUploader call sites go through `LBRoute.<case>.path`.
- **DTO + Mapper schema layer** — 12 public models (`LBChannel`, `LBProduct`, `LBSpec`,
  `LBVideoItem`, `LBShop`, `LBWidgetResponse`, `LBNavItem`, `LBHotItem`, `LBFeaturedGood`,
  `LBPushMsg`, `LBWinner`, `LBAward`) are now built by internal mappers from
  `Core/DTOs/`. Public field names / types unchanged. Mapper switches by `apiVersion`
  (default v1, unknown versions fall back to v1 with a debug log).
- **Internal escape hatch `APIClient.enableVersionHeaders`** — boolean, default `true`.
  Flip to `false` only if backend rejects unknown headers (emergency hotfix path).

### Changed

- 100% **向後相容**: host app integration code 不改一行就能升 SDK。
- Endpoint 字串不再散落於 source —— grep `"/sdk/"` 於 production source 應該無 match。
- `LBChannel` / `LBProduct` / 等 12 個 public struct 不再 conform `Decodable`(改由 mapper
  構造);host app 仍只透過 SDK callback 取得,公開 field 完全不變。

### Migration

詳見 [Migration Guide — API Version Resilience](../docs/migration/api-version-resilience.md)。
TL;DR — 不改 code 也行,但建議:
- listener 加 `SDK_DEPRECATION_NOTICE` case → 收 backend 軟性升級訊號。
- `onError` 加 `sdkVersionUnsupported` case → 收 inner code 426 強制升級訊號。
- 未來 backend 推 v2 時,在 `configure(...)` 傳 `apiVersion: 2`。

## [1.2.0-rc.2] - 2026-05-22

Hotfix on top of `1.2.0-rc.1`.

### Fixed

- **iOS Release build**: `LivebuySDK.swiftinterface` verification failed under
  `BUILD_LIBRARY_FOR_DISTRIBUTION=YES` because the public Swift interface
  referenced `import LivebuySDKObjC`, which is an internal SwiftPM target not
  listed in the package's public product list. Downstream consumers (Swift
  Package Index, XCFramework distribution) hit "no such module 'LivebuySDKObjC'".
  Switched the internal `EventDispatcher` import to
  `@_implementationOnly import LivebuySDKObjC` so the symbol no longer leaks
  into the public swiftinterface. No public API surface change.

## [1.2.0-rc.1] - 2026-05-22

First **release candidate** for v1.2.0. Internal-distribution build for integration
partners to smoke-test the unified event interceptor + reverse-notification APIs
before the final tag.

### Scope vs. v1.2.0 final

This RC ships the complete v1.2.0 feature set described below. The final v1.2.0 tag
will follow once:

- **Manual QA item B** (cart-attribution + auth-replay UI tap) is run on real device — currently relies on unit-test coverage (`AutoPiPTests`, `CheckoutCompletedTests`, `PendingAuthStoreTests`, `LBLocalizationReloadTest`/`SetLanguageTests` all green) plus the harness-driven AUTH_STATE_CHANGED chain in Android Tier 1.
- ms-MY / id-ID translations for the 3 new keys (`subscribe`, `activity_user_purchased`, `activity_user_joined`) reviewed by a native-speaker.
- First integration partner reports no blockers from `configure(autoPipOnIntercept: true)` default, `setLanguage(...)` live-reload, or `notifyCheckoutCompleted` dedupe.

Known limitations carried in 1.2.0 — see [v1.2.1 follow-ups](../docs/release/v1.2.1-followups.md):
1. Auto-PiP not real-device verified (iPhone 12 mini + Pixel 6 API 26 hardware not available)
2. Checkout `orderId` dedupe is in-memory only (does not survive process restart)
3. Android `flushPendingEvents` does not yet share an in-flight Future across concurrent callers
4. `flush_abuse` metric not yet emitted
5. `flushPendingEvents` 5-second timeout branch has no unit test
6. Backend merchant-facing attribution dashboard not yet built; SDK side ends at `POST /sdk/log` 200 OK

Subsequent rc.X tags will be cut for any partner-found regression.

## [1.2.0] - TBD

### Added — Unified event interceptor (`add-generic-event-interceptor`)

- `LivebuyEventListener` protocol — single entry point for every SDK event. Install with `Livebuy.setEventListener(_:)`.
- `LBEvent` constants — 16 event names (`VIDEO_OPEN`, `CART_ADD_REQUEST`, `AUTH_REQUIRED`, `PRODUCT_CLICK`, etc.). See the [Events chapter](README.md#events).
- Three dispatch semantics (notification / request-response / sync interceptor) with a 5-second hard timeout on `CART_ADD_REQUEST` and `try-catch` crash sandboxing around every listener invocation.
- Offline event queue + exponential backoff retry (2 s → 5 min, ≤ 5 attempts) + dynamic `/sdk/log_config` heartbeat sampling.
- Auto-Picture-in-Picture when a player-originated sync interceptor (`AUTH_REQUIRED`, `PRODUCT_CLICK`, `INFO_CUSTOMER_SERVICE`) is taken over by the listener. Opt out via `configure(autoPipOnIntercept: false)`.

> ⚠️ **Auto-PiP not real-device verified in 1.2.0.** Behaviour is covered by unit tests on both platforms (`AutoPiPTests`, all green) and verified against the Pixel 7 API 34 emulator. iPhone 12 mini and Pixel 6 API 26 real-device validation will land in **1.2.1**. If you observe unexpected PiP behaviour, opt out with `configure(autoPipOnIntercept: false)` and report via GitHub Issues — the safe fallback path is `player.pause()`, no playback or audio interruption beyond that.

### Added — Reverse-notification APIs

- `Livebuy.setUser(_:)` / `Livebuy.clearUser()` — host-app identity hand-over with 30-second auto-replay of actions blocked by `AUTH_REQUIRED`. Dispatches `AUTH_STATE_CHANGED`.
- `Livebuy.setLanguage(_:)` — mid-session language switch; overrides `configure(lang:)` and the API-returned lang. Dispatches `LANGUAGE_CHANGED`. **Visible Widget / Player UI text reloads immediately** (no view-reopen needed) via the `lbLocalizationChanged` notification path — see `fix-setlanguage-live-reload` in this release.
- `Livebuy.notifyCheckoutCompleted(orderId:sdkTrackCodes:items:)` — closes the SDK-assisted purchase funnel with `sdk_track_code` attribution. Dedupes same `orderId` within 24 h. Dispatches `CHECKOUT_COMPLETED`.
- `Livebuy.flushPendingEvents()` — async force-flush of the offline queue (5 s budget, returns `LBFlushResult`). Use before logout / app termination.
- New models: `LBCheckoutItem`, `LBFlushResult`, `LBSDKError.notConfigured`.

### Changed

- `Livebuy.configure(...)` gains an `autoPipOnIntercept: Bool = true` parameter. Existing call sites continue to work.

### Deprecated

- `LivebuyPlayerDelegate.didTapProduct(_:)` and the other per-event callbacks on `LivebuyPlayerDelegate` / `LivebuyWidgetDelegate`. The old callbacks still fire alongside the new event flow; they will be removed in **v2.0**. See [Migration Guide](../docs/migration/v1-event-interceptor.md).

### Migration

Existing integrations using delegate callbacks continue to work without code changes. To migrate:

1. Implement `LivebuyEventListener` (one object — not per Widget).
2. Call `Livebuy.setEventListener(myListener)` after `configure(...)`.
3. Dispatch by `eventName` (see the [Event catalogue](README.md#event-catalogue)).
4. Wire `Livebuy.setUser(...)` into your login completion callback so SDK-blocked actions auto-replay.

## [1.0.0] - TBD

### Added
- Initial public release
- `LivebuySDK.configure(apiKey:secret:lang:user:)` — SDK initialization
- `LivebuyPlayerViewController` — full-screen live / replay / VOD player with PiP and background audio
- `LivebuyWidget` — embeddable carousel, grid, and floating video list
- Localization support: `zh-TW`, `zh-CN`, `en`, `ms-MY`, `id-ID`
