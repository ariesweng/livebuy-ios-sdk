# Changelog

All notable changes to the LiveBuy iOS SDK will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

_Nothing yet — next features accrue here toward the version after v3.2.1._

---

## [3.2.1] - 2026-07-14

> PATCH release，無 breaking，源碼相容，**iOS-only**（Android 留 `3.2.0`；本版是 iOS 追平 Android 既有
> lifecycle 行為，非兩端功能分歧）。鎖點 `8ebd9004`（本版唯一碰 `ios/Sources/` 的 commit）。自 v3.2.0
> （iOS 出貨鎖點內容 `7600fcd5`）以來碰 `ios/Sources/` 僅 **1 commit**（1 reference-ui fix）；
> **`ios/Sources/LiveBuySDK/`（binary target）零變更 → 不重 build，checksum 沿用 v3.2.0 `a58952dd…`
> （同一顆 XCFramework 原封重傳）**。詳見 [`docs/release/v3.2.1-readiness.md`](../docs/release/v3.2.1-readiness.md)。

### Fixed

- **直播背景回前景「定格幀」修復（drop-in `LiveBuyPlayer`）** — App 退背景後回前景時，直播（IVS 引擎）
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
- **collapsible 播放器資源洩漏** — `LiveBuyPlayer` 新增 `dismantleUIViewController` 保證性釋放，
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
- `LiveBuyPlayerViewController.onDidAutoAdvance: ((LBNavItem) -> Void)?` — core 於 VOD 自動接播
  時 fire 的 instance seam（與 Android `LiveBuyPlayerView` 同名 parity），供 reference-ui 浮卡
  同步縮圖；drop-in 容器自動接線，既有 host 呼叫碼零改動。
- `DefaultPlayerTemplate` / `DefaultWidgetTemplate` 的 `addObserver(_:) -> LBTemplateObserverToken`
  / `removeObserver(_:)` 與 `LBTemplateObserverToken` — view-model 層多觀察者註冊地基，
  reference-ui 內部消費（治本 onChange 串鏈脆弱）。

**功能亮點（純視覺，reference-ui 層）**
- **浮卡縮圖同步 VOD 自動接播** — VOD 自動接播下一支後，縮小的 `CollapsibleLiveBuyPlayer`
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
- **`LiveBuyLiveEntry` 輪詢死鎖** — onAppear 掛在 EmptyView 分支導致輪詢無法啟動，已修復。

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
- **裸 widget / player 改名 → `…Core`（`rename-bare-widget-to-core`）** — 黃金名 `LiveBuyWidget` / `LiveBuyPlayer` 讓給 reference-ui drop-in 容器；**iOS 因 module 分割不留 alias**。
- **音訊預設有聲** — 主播放 + 開場 intro 預設不靜音。
- （下方 widget-decode 區的 `LBVideoItem.goods?` / `LBWidgetResponse.widgetBgcolor?` BREAKING 一併入。）

**Added**
- **AWS IVS Player 直播低延遲引擎** — live `.m3u8` glass-to-glass ~15s → ~5s（iPhone 13 真機驗）；回放 `.m3u8` / intro MP4 / 非 `.m3u8` VOD 仍走 AVPlayer，引擎依 `selectPlaybackEngineKind(url, isLive)` 選。**散佈改變：SDK 含 binary（IVS XCFramework v1.52.0、checksum 鎖定）；改以三 product 出貨（binary `LiveBuySDK` + source `LiveBuyUI` / `LiveBuyReferenceUI`）。**
- **reference-ui（新 product）** — drop-in 容器 `LiveBuyPlayer` / `LiveBuyWidget` + 可客製像素 source 層（對齊 `design/templates/minimal/*`）。
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

- **`LiveBuySDK.configure(apiVersion:)`** — optional `Int` parameter, default `1`. Drives the
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

- **iOS Release build**: `LiveBuySDK.swiftinterface` verification failed under
  `BUILD_LIBRARY_FOR_DISTRIBUTION=YES` because the public Swift interface
  referenced `import LiveBuySDKObjC`, which is an internal SwiftPM target not
  listed in the package's public product list. Downstream consumers (Swift
  Package Index, XCFramework distribution) hit "no such module 'LiveBuySDKObjC'".
  Switched the internal `EventDispatcher` import to
  `@_implementationOnly import LiveBuySDKObjC` so the symbol no longer leaks
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

- `LiveBuyEventListener` protocol — single entry point for every SDK event. Install with `LiveBuy.setEventListener(_:)`.
- `LBEvent` constants — 16 event names (`VIDEO_OPEN`, `CART_ADD_REQUEST`, `AUTH_REQUIRED`, `PRODUCT_CLICK`, etc.). See the [Events chapter](README.md#events).
- Three dispatch semantics (notification / request-response / sync interceptor) with a 5-second hard timeout on `CART_ADD_REQUEST` and `try-catch` crash sandboxing around every listener invocation.
- Offline event queue + exponential backoff retry (2 s → 5 min, ≤ 5 attempts) + dynamic `/sdk/log_config` heartbeat sampling.
- Auto-Picture-in-Picture when a player-originated sync interceptor (`AUTH_REQUIRED`, `PRODUCT_CLICK`, `INFO_CUSTOMER_SERVICE`) is taken over by the listener. Opt out via `configure(autoPipOnIntercept: false)`.

> ⚠️ **Auto-PiP not real-device verified in 1.2.0.** Behaviour is covered by unit tests on both platforms (`AutoPiPTests`, all green) and verified against the Pixel 7 API 34 emulator. iPhone 12 mini and Pixel 6 API 26 real-device validation will land in **1.2.1**. If you observe unexpected PiP behaviour, opt out with `configure(autoPipOnIntercept: false)` and report via GitHub Issues — the safe fallback path is `player.pause()`, no playback or audio interruption beyond that.

### Added — Reverse-notification APIs

- `LiveBuy.setUser(_:)` / `LiveBuy.clearUser()` — host-app identity hand-over with 30-second auto-replay of actions blocked by `AUTH_REQUIRED`. Dispatches `AUTH_STATE_CHANGED`.
- `LiveBuy.setLanguage(_:)` — mid-session language switch; overrides `configure(lang:)` and the API-returned lang. Dispatches `LANGUAGE_CHANGED`. **Visible Widget / Player UI text reloads immediately** (no view-reopen needed) via the `lbLocalizationChanged` notification path — see `fix-setlanguage-live-reload` in this release.
- `LiveBuy.notifyCheckoutCompleted(orderId:sdkTrackCodes:items:)` — closes the SDK-assisted purchase funnel with `sdk_track_code` attribution. Dedupes same `orderId` within 24 h. Dispatches `CHECKOUT_COMPLETED`.
- `LiveBuy.flushPendingEvents()` — async force-flush of the offline queue (5 s budget, returns `LBFlushResult`). Use before logout / app termination.
- New models: `LBCheckoutItem`, `LBFlushResult`, `LBSDKError.notConfigured`.

### Changed

- `LiveBuy.configure(...)` gains an `autoPipOnIntercept: Bool = true` parameter. Existing call sites continue to work.

### Deprecated

- `LiveBuyPlayerDelegate.didTapProduct(_:)` and the other per-event callbacks on `LiveBuyPlayerDelegate` / `LiveBuyWidgetDelegate`. The old callbacks still fire alongside the new event flow; they will be removed in **v2.0**. See [Migration Guide](../docs/migration/v1-event-interceptor.md).

### Migration

Existing integrations using delegate callbacks continue to work without code changes. To migrate:

1. Implement `LiveBuyEventListener` (one object — not per Widget).
2. Call `LiveBuy.setEventListener(myListener)` after `configure(...)`.
3. Dispatch by `eventName` (see the [Event catalogue](README.md#event-catalogue)).
4. Wire `LiveBuy.setUser(...)` into your login completion callback so SDK-blocked actions auto-replay.

## [1.0.0] - TBD

### Added
- Initial public release
- `LiveBuySDK.configure(apiKey:secret:lang:user:)` — SDK initialization
- `LiveBuyPlayerViewController` — full-screen live / replay / VOD player with PiP and background audio
- `LiveBuyWidget` — embeddable carousel, grid, and floating video list
- Localization support: `zh-TW`, `zh-CN`, `en`, `ms-MY`, `id-ID`
