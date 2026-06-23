# Changelog

All notable changes to the LiveBuy iOS SDK will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

> 🚀 **下一個發版 = v3.0.0（major / breaking）。** v2.0.0 從未發過正式版（只到 `v2.0.0-rc.5`）；
> 其累積的 breaking（headless / token / rename）與後續的 **Tier 2 統一加購** breaking 一次發為 v3.0.0。
> 完整對外說明見 [release notes](../docs/release-notes/v2.0.0.md)，升級照
> [migration 總入口](../docs/migration/v2.0.0.md)。**發版時本 `[Unreleased]` → `[3.0.0] - <date>`**；
> 未 tag 的 `[1.3.0]`（api-version）內容一併併入。

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
