import SafariServices
import UIKit
import LiveBuySDK

/// In-app browser opener (Task 2.1 / 2.5). Injectable so unit tests can verify
/// the diversion path with a fake opener without a live UIKit hierarchy.
typealias InAppBrowserOpener = (URL) -> Void

/// Opaque, identity-equality handle returned by
/// `DefaultPlayerTemplate.addObserver(_:)`, used to `removeObserver(_:)` later
/// (ios-player-template-multi-observer-registry).
///
/// A `final class` so identity (`===`) is the sole notion of equality — each
/// registration yields a unique token the host holds; the host does NOT
/// construct one (no host-facing `init`). This is a TEMPLATE-layer type: it
/// MUST NOT depend on any core listener token (layer boundary — reference-ui →
/// template → core is one-way, so the template's public API never leaks a core
/// type). Same role as Android's `LBTemplateObserverToken`.
public final class LBTemplateObserverToken {
    /// Module-internal so the template mints tokens but hosts cannot fabricate
    /// arbitrary ones — they only hold what `addObserver` returns.
    init() {}
}

/// Default Player template event handler.
/// Holds a weak reference to the player VC and provides standard live-shopping
/// behaviour for interceptable SDK events.
///
/// Spec: `ui-template-foundation/spec.md`
///   § "Default Template 事件覆蓋範圍"
///   § "Default Template Host 取得實例介面（per-player accessor）"
///   § "Default Template Bindable State 變更通知"
///
/// The TYPE and its READ surface (`activityFeed` / `winClaim` host-bindable
/// state + the `onChange` notification) are `public` so a host can obtain this
/// instance via `LiveBuyUI.playerTemplate(for:)` and bind/observe its state.
/// The INTERNAL wiring — `init` and the `handle*` event methods — stays
/// `internal` (the host consumes state; it does NOT construct the instance or
/// feed events directly).
public final class DefaultPlayerTemplate {

    private weak var player: LiveBuyPlayerViewController?
    private let effectiveConfig: EffectiveConfig
    private let openInAppBrowser: InAppBrowserOpener

    /// Guest rename-intent forwarder (auth-gate-template-state §Guest 改名意圖
    /// passthrough). Injected so the wiring hands the template a closure that
    /// reaches the core's guest-name-edit exit (emit `GUEST_NAME_EDIT_REQUEST` —
    /// passthrough, non-navigation, no auto-PiP). nil → `requestGuestNameEdit()`
    /// is an inert no-op (headless-safe). EXACT parity with Android's
    /// `GuestNameEditRequester` / Flutter's typedef / RN's `requestGuestNameEdit`.
    private let guestNameEditRequester: (() -> Void)?

    /// 查看購物車 intent forwarder (ui-template-foundation §查看購物車意圖 passthrough).
    /// Injected so the wiring hands the template a closure that reaches the core's
    /// `Player.requestViewCart(productId:)` exit (emit `VIEW_CART` — notification,
    /// non-navigation, no auto-PiP). `productId` is the current product detail's id
    /// (detail CTA) or nil (list-bottom CTA). nil requester → `openCart` is an inert
    /// no-op (headless-safe). EXACT parity with the `guestNameEditRequester` model.
    private let viewCartRequester: ((String?) -> Void)?

    // MARK: - Host-bindable behaviour view-models (reconcile-activity-notification-contract-template)

    /// §1 — merged activity + chat feed (data-layer merge; host draws the rows).
    public let activityFeed: DefaultActivityFeed

    /// §2–§4 — win unclaimed set + claim submit + result-state feedback.
    /// `requester` is the player itself (it conforms to `AwardClaimRequesting`).
    public let winClaim: DefaultWinClaim

    /// Player error-state (livebuy-ui-event-join-and-error-state-template) —
    /// `error(LBError)` + `stateChange(error)` → host-bindable `{kind, phase}`
    /// for `LBPErrorScreen`. Cleared when the player leaves `error`.
    public let errorState: DefaultErrorState

    // MARK: - Player moment view-models (expose-player-moment-state-template)

    /// StartScreen splash phase (loading / splash / buffering / done) — mapped
    /// from the player state + `channel.start` presence.
    public let startScreen: DefaultStartScreenState

    /// Upcoming（直播預告）等待開播 view-model（`active` + `scheduledStartAt`），由
    /// canonical state `"awaitingLive"` + `channel.publishAt` 推導。reference-ui 綁此渲染倒數。
    public let upcoming = DefaultUpcomingState()

    /// EndScreen `next` / `hot` + optional auto-next `countdown { remain, total }`.
    public let endScreen: DefaultEndScreenState

    /// ProductOverlay `products` snapshot + single `narrate_status==2` activeProduct.
    public let productOverlay: DefaultProductOverlayState

    /// PlayerHeader `{ isSubscribed, viewerCount, muted }` for `LBPHostBadge`.
    public let header: DefaultPlayerHeaderState

    /// Prev/next adjacent video targets `{ prevVideoId, nextVideoId }` derived from the
    /// public core `channel.prev`/`next` (swipe-navigate-template). Drives the reference-ui
    /// vertical-swipe-to-switch-video gesture + the `navigateToPrev()`/`navigateToNext()`
    /// forwarders below.
    public let navigation: DefaultPlayerNavigation

    /// VOD playback progress `{ position, duration, isPlaying, isReplay }` (VOD-2),
    /// fed from the core's dedicated `onPlaybackProgressChange`. Drives the VOD chrome.
    public let playbackProgress = DefaultPlaybackProgressState()

    /// ALL products currently being introduced in a VOD (multiple products can be introduced
    /// at the same playhead — overlapping `[beginTime, endTime)` windows), derived from the
    /// playhead vs each product's time window (seconds; backend `begin_time`/`end_time`).
    /// Ordered by `beginTime` ASCENDING (earliest-introduced first); products missing
    /// begin/end are excluded; empty when none contains the playhead. Pure computed (no second
    /// state). Feeds the reference-ui now-introducing carousel (問題 10,
    /// vod-now-introducing-multi-image-template). Does NOT alter the LIVE
    /// `productOverlay.activeProduct` path.
    public var vodActiveProducts: [LBProduct] {
        let pos = playbackProgress.position
        return productOverlay.products
            .filter { p in
                guard let b = p.beginTime, let e = p.endTime else { return false }
                return Double(b) <= pos && pos < Double(e)
            }
            .sorted { ($0.beginTime ?? 0) < ($1.beginTime ?? 0) }
    }

    /// The single product currently being introduced in a VOD — the VOD analogue of
    /// `productOverlay.activeProduct`. Equals `vodActiveProducts.last` (the latest `beginTime`
    /// = most-recently-introduced; equivalent to the prior `.max(by: beginTime)`), `nil` when
    /// none contains the playhead. Kept for back-compat; the carousel reads `vodActiveProducts`.
    public var vodActiveProduct: LBProduct? { vodActiveProducts.last }

    /// ALL products currently being introduced in a LIVE — every product with `narrate_status == 2`
    /// in the current `productOverlay.products` snapshot. The backend MAY narrate MULTIPLE products
    /// simultaneously (component-contracts updated: `narratingProduct` / `activeProduct` take the
    /// first; this exposes the FULL set). Order follows `products` (the data-layer order; template
    /// MUST NOT re-sort); empty when none. Pure computed (no second state). Feeds the reference-ui
    /// LIVE now-introducing carousel (問題 7, live-now-introducing-multi-product-template). Does NOT
    /// alter the single `productOverlay.activeProduct` (`narrate_status == 2` first) / `pinnedProduct`
    /// path (back-compat). The LIVE analogue of `vodActiveProducts`.
    public var liveActiveProducts: [LBProduct] {
        productOverlay.products.filter { $0.narrateStatus == 2 }
    }

    /// SubtitleTrack `{ available, enabled }`.
    public let subtitle: DefaultSubtitleState

    // MARK: - Auth host-bindable view-models (auth-gate-template-state)

    /// Un-intercepted `AUTH_REQUIRED` →「請先登入」host-bindable state
    /// `{ triggerAction, productId?, videoId? }`. Cleared on `logged_in`.
    public let authGate: DefaultAuthGate

    /// `AUTH_STATE_CHANGED` → identity-label `{ displayName, isLoggedIn }` for
    /// `PlayerHeader` / `ChatView`. nil until the first event (no configure seed).
    public let identityLabel: DefaultIdentityLabel

    // MARK: - Goods-tracking + notice-tab view-models (await-toggle-and-notice-tab-template-state)

    /// Per-product 到貨追蹤 (await, type=1) + 補貨通知 (notice, type=2) dual switch.
    /// Two INDEPENDENT (non-mutually-exclusive) flags per `goodsGpn`; seeded from
    /// products, optimistic on toggle, corrected by `AWAIT/NOTICE_GOODS_CHANGED`.
    public let goodsTracking: DefaultGoodsTracking

    /// VideoInfoPanel 公告分頁 open-state `{ canOpen, isOpen, systemNotice, notice }`.
    /// `canOpen` derived (either text non-empty); texts injected from `channel`.
    public let noticeTab: DefaultNoticeTab

    // MARK: - Player chrome view-models (player-chrome-template)

    /// OperationPanel side-rail `{ items[{kind,enabled}], bagCount, heartBurstTick,
    /// muted }` for `LBLiveBottomBar` / `LBPSideRail`. Actions go through the core's
    /// existing `simulate*`; this model is presentation state only.
    public let operationRail: DefaultOperationRail

    /// VideoInfoPanel info-tab `{ title, publishAt, shopName, shopIntro, shopLogo,
    /// isSubscribed }` + two-tab switching `{ activeTab }`. `isSubscribed` mirrors
    /// the SAME truth as `header.isSubscribed`; `notice` tab selectability mirrors
    /// `noticeTab.canOpen`.
    public let infoTab: DefaultInfoTab

    // MARK: - Product sheet-stack view-models (product-sheet-stack-template)

    /// product-detail sheet `{ productId, name, priceShow, …, specifications,
    /// specOptions }` for `LBPBottomSheet` + `LBPProductRow`. Set on a
    /// `diversion == 0` `productTap`; `diversion == 1` keeps the in-app browser.
    public let productSheet: DefaultProductSheet

    /// variant-picker `groups` (from `specOptions`) + `selection` + resolved
    /// `selectedSpec` / `selectedSpecificationId` (from `specifications`).
    public let variantPicker: DefaultVariantPicker

    /// qty-stepper `{ qty, min, max }` — `max` from the chosen spec / product stock.
    public let qtyStepper: DefaultQtyStepper

    /// mini-cart peek `{ productId, name, priceShow, soldOut }` for `LBPMiniCart`.
    public let miniCart: DefaultMiniCart

    /// cart CTA `{ count }` (per-session successful adds) + `openCart` passthrough.
    public let cartCTA: DefaultCartCTA

    /// Add-to-cart failure flag (route-B `addToCart` threw) so the host can show an
    /// error toast. Set true on a failed delegation; cleared on the next add
    /// attempt. Purely additive (false by default).
    private(set) public var addToCartFailed: Bool = false

    /// Add-to-cart「需登入」flag, orthogonal to `addToCartFailed`. Set true when the
    /// route-B `addToCart` threw the core「needs login」signal
    /// (`LBError.serverError(code: 401, ...)` raised for an empty `buy_no`) so the
    /// reference-ui can present a login gate (host `config.onLogin`) instead of the
    /// 「加入購物車失敗」retry banner. Reset alongside `addToCartFailed` on every new
    /// attempt / sheet (re-)open. Purely additive (false by default).
    private(set) public var addToCartNeedsLogin: Bool = false

    /// Add-to-cart「請求進行中」flag (cart-add-loading-state). Set true the moment
    /// `addToCart()` actually fires an addcart request (after all guards), false on ANY
    /// outcome (success / dedupe / failure / needs-login). Orthogonal to `addToCartFailed`
    /// / `addToCartNeedsLogin`. Lets a host / reference-ui disable the add-to-cart CTA for
    /// the request lifecycle (`cart-checkout`「加購按鈕 loading 綁請求生命週期」). Pixels are
    /// reference-ui's (another change); this is the zero-pixel data layer.
    private(set) public var addToCartInFlight: Bool = false

    /// 置頂留言（chat-message-kind ⑤，messages `data.top`）。由 `handlePollReceived` 從
    /// `poll.top` 設定，供 reference-ui 渲染。冪等：每輪以當前釘選狀態覆蓋，取消釘選 → nil。
    /// 預設 nil（無置頂）。
    private(set) public var pinnedMessage: LBPinnedMessage?

    /// 會員等級限定旗標（restriction-gate ②），由 `ingestChannel` 從 `LBChannel.isRestriction`
    /// 衍生（`== 1`）。**軟性顯示閘門**：core 不擋播放，reference-ui 讀此旗標在播放畫面上疊
    /// 升級遮罩。預設 false（未受限）。
    private(set) public var isRestricted: Bool = false

    /// 「請選規格」guard flag — set true when `addToCart()` is called with an
    /// incomplete spec selection (D5 guard); cleared when a valid add is attempted
    /// or a new product detail opens. Lets the host prompt the user.
    private(set) public var needsVariantSelection: Bool = false

    /// Current video id, tracked from `ingestChannel` (cart-add-tier2). Threaded
    /// into `addToCart` → `LBCartRequest.videoId` so the core `CART_ADD_REQUEST`
    /// carries the correct `video_id`. nil until a channel is ingested.
    private(set) public var currentVideoId: String?

    /// 「本實例目前所知的、穩定的 videoId」——`deinit` 存快照的 save key 用它，避免依賴 teardown /
    /// ARC 當下才去讀 `currentVideoId` / `player?.channel?.id`（那時可能都已為 nil：channel 尚未
    /// `ingestChannel`、或只經 `handleVideoSwitch(to:)` 抵達新場而其 channel 未 ingest、或 player 已先
    /// 釋放）。在生命週期中**盡早**、從任何學到 videoId 的時刻捕捉（見 `rememberVideoId`），且**只前進
    /// 不退回 nil**，使 `deinit` 一定拿得到一個穩定 key 存進 `feedSnapshotCache`（否則下一個新實例
    /// cache-miss → `clear()` → 歷史消失，即「跳到其他頁面直播歷史訊息快取失效」的破口）。
    private var lastKnownVideoId: String?

    /// 盡早捕捉一個穩定的 videoId 進 `lastKnownVideoId`。**只前進不退回**：傳入 `nil` / 空字串一律
    /// no-op（never 把已學到的 id 抹回 nil）；傳入非空且不同時更新為最新（換片後反映新場，使 `deinit`
    /// 存到正確的 video）。純函式風格（只寫一個 var），供 `ingestChannel` / `handleVideoSwitch` /
    /// `handlePollReceived` 三處呼叫。
    private func rememberVideoId(_ id: String?) {
        guard let id = id, !id.isEmpty else { return }
        lastKnownVideoId = id
    }

    /// General (NOT upcoming-scoped) 封面圖 URL for the player **loading** surface
    /// (`player-loading-cover-background-template`). Channel-derived (`channel.cover`),
    /// fed by `ingestChannel` via `applyLoadingCover(_:)` — so a normal live / VOD
    /// video (not just an `awaitingLive` upcoming) can supply a cover to the loading
    /// screen. Zero-pixel passthrough: the template MUST NOT load the image; a
    /// follow-up reference-ui change renders the cover + mask background. Empty (`""`)
    /// until a channel with a non-empty `cover` is ingested. DISTINCT from the
    /// upcoming-scoped `upcoming.cover` (`DefaultUpcomingState.cover`, direct-only) —
    /// both coexist and neither alters the other. Default `""` (pre-channel / no cover).
    private(set) public var loadingCover: String = ""

    /// Injected route-B add-to-cart requester (default throwing stub for headless
    /// unit tests, mirroring `DefaultGoodsTracking`'s `setAwait`/`setNotice`
    /// closures). The wiring fills it with `LiveBuy.addToCart(...)`. The template
    /// NEVER builds an HTTP request itself. Returns the `LBCartResult` on success.
    private let addToCartRequester: (LBCartRequest) async throws -> LBCartResult

    // MARK: - Change notification (expose-default-template-bindable-state)

    /// Coalesced "host-bindable state changed" notification. Fires EXACTLY ONCE
    /// per single state change (merged-feed append / unclaimed `recordWin` /
    /// claimed removal / award-claim result update / `clear`), dispatched on the
    /// main thread, after the state has been updated (the host re-reads
    /// `activityFeed` / `winClaim` — the callback carries no diff payload).
    /// Purely additive: nil by default; when unset the template behaves exactly
    /// as before.
    public var onChange: (() -> Void)?

    // MARK: - Multi-observer registry (ios-player-template-multi-observer-registry)

    /// One registered change observer paired with its removal token. Stored in an
    /// ORDERED array (not a dictionary — Swift closures aren't `Equatable`) so the
    /// fire order equals registration order; removal is by token identity (`===`).
    private struct ObserverEntry {
        let token: LBTemplateObserverToken
        let observer: () -> Void
    }

    /// Ordered observer registrations. Coexists with the legacy `onChange`: a
    /// single state change dispatches to BOTH (legacy first, then observers in
    /// registration order — see `dispatchOnChange`). Empty by default (purely
    /// additive; a template with no observer behaves exactly as before).
    private var observers: [ObserverEntry] = []

    /// Register a change observer that fires on the SAME coalesced "state changed"
    /// notification as `onChange`, and return an opaque token to remove it later.
    /// Multiple observers each keep an independent subscription — registering one
    /// NEVER clobbers another (the whole point vs. the single-`onChange`-var chain).
    /// Fires alongside (and after) the legacy `onChange` on every dispatch.
    ///
    /// Main-thread contract: call from the main thread (same assumption as
    /// assigning `onChange`; reference-ui overlays register/unregister on their
    /// SwiftUI/UIKit attach/detach, which is main-thread).
    public func addObserver(_ observer: @escaping () -> Void) -> LBTemplateObserverToken {
        let token = LBTemplateObserverToken()
        observers.append(ObserverEntry(token: token, observer: observer))
        return token
    }

    /// Remove a previously registered observer by its token (identity match). An
    /// unknown / already-removed token is a no-op. Main-thread contract mirrors
    /// `addObserver`.
    public func removeObserver(_ token: LBTemplateObserverToken) {
        observers.removeAll { $0.token === token }
    }

    init(
        player: LiveBuyPlayerViewController,
        sdkConfig: SDKConfig,
        hostOptions: LBUIOptions?,
        openInAppBrowser: InAppBrowserOpener? = nil,
        guestNameEditRequester: (() -> Void)? = nil,
        viewCartRequester: ((String?) -> Void)? = nil,
        setAwaitGoods: ((String, Bool) -> Void)? = nil,
        setNoticeGoods: ((String, Bool) -> Void)? = nil,
        addToCartRequester: ((LBCartRequest) async throws -> LBCartResult)? = nil,
        feedSnapshotCache: VideoFeedSnapshotCache = .shared
    ) {
        self.player = player
        self.feedSnapshotCache = feedSnapshotCache
        self.effectiveConfig = EffectiveConfig(sdkConfig: sdkConfig, hostOptions: hostOptions)
        self.guestNameEditRequester = guestNameEditRequester
        self.viewCartRequester = viewCartRequester
        // Default: a throwing stub so a headless unit test that does NOT inject a
        // requester sees `addToCart()` fail cleanly (no HTTP, no count change),
        // mirroring DefaultGoodsTracking's no-op closures.
        self.addToCartRequester = addToCartRequester ?? { _ in
            throw LBProductSheetError.noRequester
        }
        self.activityFeed = DefaultActivityFeed()
        self.winClaim = DefaultWinClaim(requester: player)
        self.errorState = DefaultErrorState()
        self.startScreen = DefaultStartScreenState()
        self.endScreen = DefaultEndScreenState()
        self.productOverlay = DefaultProductOverlayState()
        self.header = DefaultPlayerHeaderState()
        self.navigation = DefaultPlayerNavigation()
        self.subtitle = DefaultSubtitleState()
        self.authGate = DefaultAuthGate()
        self.identityLabel = DefaultIdentityLabel()
        self.goodsTracking = DefaultGoodsTracking(
            setAwait: setAwaitGoods ?? { _, _ in },
            setNotice: setNoticeGoods ?? { _, _ in })
        self.noticeTab = DefaultNoticeTab()
        self.operationRail = DefaultOperationRail()
        self.infoTab = DefaultInfoTab()
        self.productSheet = DefaultProductSheet()
        self.variantPicker = DefaultVariantPicker()
        self.qtyStepper = DefaultQtyStepper()
        self.miniCart = DefaultMiniCart()
        self.cartCTA = DefaultCartCTA()
        // info-tab `isSubscribed` mirrors the SAME truth as the PlayerHeader
        // (read at snapshot time — never a stored second copy, R2); the notice tab
        // is selectable iff the notice-tab `canOpen` (R4). Capture the two models
        // (already initialised above) by reference.
        infoTab.isSubscribedProvider = { [header] in header.isSubscribed }
        infoTab.canOpenNoticeProvider = { [noticeTab] in noticeTab.canOpen }
        // Default presents SFSafariViewController over the player VC so the user
        // stays in-app (the live keeps playing behind it; the user can swipe back).
        self.openInAppBrowser = openInAppBrowser ?? { [weak player] url in
            player?.present(SFSafariViewController(url: url), animated: true)
        }
        // mini-cart「open detail」re-opens the peeked product's detail sheet using
        // the latest known products snapshot (productOverlay). cart CTA「openCart」
        // is a host passthrough — the template owns NO checkout page (D4). Wired
        // after all stored properties are initialised so `self` is fully formed.
        miniCart.openDetailForwarder = { [weak self] productId in
            guard let self = self,
                  let product = self.productOverlay.products.first(where: { $0.id == productId })
            else { return }
            self.openProductDetail(product)
        }
        // cart CTA「openCart」→ core seam `Player.requestViewCart(productId:)` via the
        // injected `viewCartRequester` (ui-template-foundation §查看購物車意圖 passthrough).
        // productId = current detail's id (detail CTA) or nil (list-bottom CTA → seam
        // omits `product_id`). nil requester → inert no-op (demo / headless-safe).
        cartCTA.openCartForwarder = { [weak self] in
            guard let self = self else { return }
            self.viewCartRequester?(self.productSheet.detail?.productId)
        }
        // #3 — surface backend layout keys this template version doesn't recognise.
        DefaultLayoutKeys.logUnknown(scope: "player", incoming: sdkConfig.layout?.player)
        // Coalesce every feed / win-claim mutation into ONE host-facing onChange
        // (main thread). Each model fires onMutation exactly once per state
        // change, so onChange fires exactly once per change (no redraw storm).
        wireChangeNotification()
    }

    /// Save THIS instance's current video's chat/activity feed into `feedSnapshotCache` before
    /// deallocation (chat-history-video-switch-cache-cross-instance, fixing 「直播縮小關閉再進入
    /// 也要保留」). `handleVideoSwitch`'s `from` save only covers an in-place SWITCH to a
    /// DIFFERENT video — core never dispatches `VIDEO_SWITCH` on a plain dismiss/close (the whole
    /// VC/template is torn down, not switched), so without this hook a closed-and-reopened video
    /// would never populate the cache for its own next (brand-new) instance to restore from.
    /// Guarded exactly like `VideoFeedSnapshotCache.save` itself (empty history → no-op) so a
    /// video that never accumulated chat doesn't occupy a cache slot for nothing.
    ///
    /// Save key SHALL be `lastKnownVideoId ?? currentVideoId` — NOT `currentVideoId` alone. Under
    /// teardown / ARC ordering `currentVideoId` can still be `nil` here (channel not yet
    /// `ingestChannel`'d, or the instance only ever `handleVideoSwitch(to:)`'d to a video whose
    /// channel never ingested) even though `activityFeed` already holds that video's accumulated
    /// history — and reaching into `player?.channel?.id` at deinit is unreliable too (the player may
    /// already be released). `lastKnownVideoId` is captured EAGERLY during the instance's lifetime
    /// (see `rememberVideoId`) and only ever advances, so it survives to deinit and yields the
    /// correct key. Without it, a nil `currentVideoId` → no save → the next fresh instance's
    /// `arriveAt` cache-misses → `clear()` → the history vanishes (the reported「跳到其他頁面直播歷史
    /// 訊息快取失效」break).
    deinit {
        if let videoId = lastKnownVideoId ?? currentVideoId, !activityFeed.history.isEmpty {
            feedSnapshotCache.save(videoId: videoId, history: activityFeed.history, seenPushIds: seenPushIds)
        }
    }

    /// Fan the two view-models' internal `onMutation` hooks into the single
    /// host-facing `onChange`, always on the main thread.
    private func wireChangeNotification() {
        activityFeed.onMutation = { [weak self] in self?.notifyChange() }
        winClaim.onMutation = { [weak self] in self?.notifyChange() }
        errorState.onMutation = { [weak self] in self?.notifyChange() }
        // Fan each moment view-model's mutation into the SAME single onChange.
        startScreen.onMutation = { [weak self] in self?.notifyChange() }
        upcoming.onMutation = { [weak self] in self?.notifyChange() }
        endScreen.onMutation = { [weak self] in self?.notifyChange() }
        productOverlay.onMutation = { [weak self] in self?.notifyChange() }
        header.onMutation = { [weak self] in self?.notifyChange() }
        navigation.onMutation = { [weak self] in self?.notifyChange() }
        playbackProgress.onMutation = { [weak self] in self?.notifyChange() }
        subtitle.onMutation = { [weak self] in self?.notifyChange() }
        // Auth-gate set/clear + identity-label update fan into the SAME onChange.
        authGate.onMutation = { [weak self] in self?.notifyChange() }
        identityLabel.onMutation = { [weak self] in self?.notifyChange() }
        // Goods-tracking flag flips/corrections + notice-tab open/close fan in too.
        goodsTracking.onMutation = { [weak self] in self?.notifyChange() }
        noticeTab.onMutation = { [weak self] in self?.notifyChange() }
        // Player chrome — side-rail enablement / bagCount / heart-burst / muted +
        // info-tab fields / tab switch fan into the SAME single onChange.
        operationRail.onMutation = { [weak self] in self?.notifyChange() }
        infoTab.onMutation = { [weak self] in self?.notifyChange() }
        // Product sheet-stack — detail open / variant selection / qty change /
        // mini-cart peek / cart CTA count all fan into the SAME single onChange. A
        // single add-to-cart success animates mini-cart + cartCTA inside ONE
        // coalescing batch → exactly one onChange (D6).
        productSheet.onMutation = { [weak self] in self?.notifyChange() }
        variantPicker.onMutation = { [weak self] in self?.notifyChange() }
        qtyStepper.onMutation = { [weak self] in self?.notifyChange() }
        miniCart.onMutation = { [weak self] in self?.notifyChange() }
        cartCTA.onMutation = { [weak self] in self?.notifyChange() }
    }

    /// Re-entrancy depth of an in-flight `coalescing` batch. While > 0, model
    /// mutations only flag `pendingNotify` instead of dispatching; the outermost
    /// batch fires a SINGLE `onChange` if anything changed. 0 = no batch (each
    /// mutation dispatches immediately, as before).
    private var coalesceDepth = 0
    private var pendingNotify = false

    /// Run `body` as ONE coalesced notification: any number of model mutations
    /// inside it collapse to a single host-facing `onChange` (D6 — one snapshot
    /// push → one notification). Used by `handleMomentState`, which fans into
    /// four view-models at once.
    private func coalescing(_ body: () -> Void) {
        coalesceDepth += 1
        body()
        coalesceDepth -= 1
        if coalesceDepth == 0 && pendingNotify {
            pendingNotify = false
            dispatchOnChange()
        }
    }

    /// Dispatch `onChange` on the main thread. Already-main-thread calls run
    /// synchronously (no needless hop); off-main calls are marshalled.
    private func notifyChange() {
        // Inside a coalescing batch, just record that a change happened — the
        // outermost batch fires exactly once.
        if coalesceDepth > 0 { pendingNotify = true; return }
        dispatchOnChange()
    }

    private func dispatchOnChange() {
        // Capture the legacy callback and a SNAPSHOT copy of the observer list at
        // notify time. A callback that adds/removes an observer therefore affects
        // only the NEXT dispatch — never this one (no mutation-during-iteration
        // crash; matches the legacy `onChange`-captured-at-notify semantics).
        let legacy = onChange
        let observerSnapshot = observers.map { $0.observer }
        // Gate: skip the dispatcher entirely ONLY when there is nothing to notify
        // (no legacy onChange AND no registered observer). This preserves the prior
        // "onChange nil → don't touch the dispatcher" behaviour for the pure
        // no-observer case, while an observer-only registration still dispatches.
        guard legacy != nil || !observerSnapshot.isEmpty else { return }
        let fire = {
            legacy?()                                     // legacy first (fixed order)
            for observer in observerSnapshot { observer() } // then observers, in registration order
        }
        if Thread.isMainThread {
            fire()
        } else {
            DispatchQueue.main.async(execute: fire)
        }
    }

    // MARK: - Event handlers (Tasks 3.1–3.4)

    /// VIDEO_STATE_CHANGE — loading / error UI (Task 3.1).
    /// SDK is headless; host provides overlay UI. Drives error-state clearing:
    /// when the player LEAVES `error` (host re-`load`ed), the error-state is
    /// cleared so the host dismisses `LBPErrorScreen`.
    func handlePlayerStateChange(state: String) {
        lbuiDebugLog("[DefaultTemplate] playerState: \(state)")
        errorState.handleStateChange(state)
        // StartScreen splash phase derives from the player state + `channel.start`
        // presence (D2). `startScreenPlaying` → splash ONLY when start is non-empty.
        // Read `channel.start` (loaded before this state) rather than `momentState.startUrl`,
        // which is built on a separate cadence and can still be empty when this fires (it
        // left the splash/intro chrome off for upcoming intros).
        let hasStart = !(player?.channel?.start ?? "").isEmpty
        startScreen.handlePhase(canonicalState: state, hasStart: hasStart)
        // Upcoming（直播預告）：active when awaiting a not-yet-started live; introPlaying
        // when the upcoming video's opening video (intro MP4) is playing. The start time
        // is the channel's publish_at (channel is loaded before the awaitingLive / intro
        // state, so it is reliable here). reference-ui renders the countdown (active) and
        // switches to the LIVE chrome during the upcoming intro (introPlaying); a VOD's
        // intro keeps introPlaying == false (→ VOD chrome).
        // upcoming = a scheduled LIVE (type == 2) not yet started (liveStatus == 0) — time-
        // independent (upcoming-intro-persist-after-schedule), so the intro keeps introPlaying
        // even after the scheduled publishAt passes. A regular VOD (type == 1) → false → VOD chrome.
        let isUpcomingChannel = Self.isUpcomingChannel(
            liveStatus: player?.channel?.liveStatus ?? -1,
            type: player?.channel?.type ?? -1)
        upcoming.handle(active: state == "awaitingLive",
                        introPlaying: state == "startScreenPlaying" && hasStart && isUpcomingChannel,
                        scheduledStartAt: player?.channel?.publishAt ?? "",
                        cover: player?.channel?.cover ?? "")
        // Inject the latest notice texts from the channel (available once loaded).
        // injectNotices is idempotent — it only notifies when a text actually
        // changes, so calling it on every state change is cheap.
        handleChannelNotices(systemNotice: player?.channel?.sysNotice ?? "",
                             notice: player?.channel?.notice ?? "")
        // Read the public `channel` to feed the top-bar chrome / info-tab fields /
        // side-rail enablement (player-chrome-template; same legitimate path the
        // notice-tab already uses). All feeds are idempotent (diff-then-notify).
        if let ch = player?.channel { ingestChannel(ch) }
    }

    /// Whether the loaded channel is an UPCOMING (尚未開播的直播) video — a scheduled LIVE
    /// (`type == 2`，直播) that has not started yet (`liveStatus == 0`). Pure + time-independent
    /// (no `Date()`). Used to classify the channel for `upcoming.introPlaying`, so an upcoming
    /// live's intro keeps `introPlaying == true` even AFTER its scheduled `publishAt` time
    /// passes (host running late), while a regular VOD's intro (`type == 1`) stays VOD chrome.
    ///
    /// Replaces the prior future-`publishAt` heuristic (upcoming-intro-persist-after-schedule):
    /// `liveStatus == 0` is shared by BOTH a regular VOD (`type == 1`) and a scheduled live
    /// (`type == 2`), so the future-`publishAt` proxy flipped an upcoming intro to VOD the moment
    /// its scheduled time passed. `type == 2` is the proper, time-independent signal.
    static func isUpcomingChannel(liveStatus: Int, type: Int) -> Bool {
        liveStatus == 0 && type == 2
    }

    /// Whether the loaded channel is a 回放 (一場**已結束的直播**). Pure + time-independent
    /// (no `Date()`). 型別語意（實測校正，影片 `W4pqqM` 為 `type == 3` / `liveStatus == 3`）：
    /// **`type == 3` = 回放（已結束直播）**、`type == 2` = 直播（預告 + 進行中）、`type == 1` = 點播 VOD。
    /// `liveStatus` 權威定義：`openspec/specs/backend/videos.md`（0=未直播 / 1=直播中 / 3=已結束/回放）。
    ///
    /// 回放為 **`type == 3`**（回放型別，與 `liveStatus` 無關）**或** `type == 2 && liveStatus == 3`
    /// （剛結束、仍標記為直播型別的邊界）。`false` for: 直播中 (`liveStatus == 1`), 直播預告
    /// (`type == 2 && liveStatus == 0`), 純 VOD 點播 (`type == 1`, any `liveStatus`). 與 `isLive`
    /// (`liveStatus == 1`) 互斥。下游 reference-ui 讀此把 回放 渲染成與直播相同的 LIVE chrome
    /// (replay-live-chrome-flag)。先前僅認 `type == 2 && liveStatus == 3` 會漏掉 `type == 3` 的真實回放。
    static func isFinishedLiveReplay(type: Int, liveStatus: Int) -> Bool {
        type == 3 || (type == 2 && liveStatus == 3)
    }

    /// Feed the public `channel` into the top-bar chrome (D3), info-tab fields
    /// (D4) and side-rail conditional enablement (D2). Internal so unit tests can
    /// drive it with a fabricated `LBChannel` without a live load. Coalesced so a
    /// single channel ingest fires at most one onChange.
    ///
    /// `ingestChannel` is ALSO this instance's earliest signal of its very FIRST video
    /// (`currentVideoId == nil` before this call — subsequent calls for the SAME video, e.g.
    /// `onChannelRefresh`'s mid-stream re-ingest, see `currentVideoId` already set and skip the
    /// arrival check). On that first call, `arriveAt(videoId:)` restores `ch.id`'s chat/activity
    /// history from `feedSnapshotCache` if ANY earlier instance this process already visited it
    /// — e.g. closing the player and re-entering the same still-live video
    /// (chat-history-video-switch-cache-cross-instance, fixing 「直播縮小關閉再進入也要保留」歷史
    /// 訊息快取). `PollManager` still forces `is_init` on a brand-new instance regardless (
    /// `chat-history-reentry-instance-scoped-cursor-core`, unchanged) — the incoming backlog
    /// merges harmlessly against the restored snapshot via `seenPushIds` (no core changes here).
    func ingestChannel(_ ch: LBChannel) {
        let isFirstChannelThisInstance = currentVideoId == nil
        // cart-add-tier2: track the current video id from the channel-injection path
        // so addToCart can thread it as CART_ADD_REQUEST.video_id (the template's
        // view-model truth; mirrors player.channel without reaching into player state).
        currentVideoId = ch.id
        // Remember a stable videoId for the deinit save-key (only advances, never nils out).
        rememberVideoId(ch.id)
        coalescing {
            if isFirstChannelThisInstance {
                arriveAt(videoId: ch.id)
            }
            handleHeaderChrome(title: ch.title, hostName: ch.shop.name,
                               shopLogo: ch.shop.logo, shareUrl: ch.shareUrl)
            handleInfo(title: ch.title, publishAt: ch.publishAt, shopName: ch.shop.name,
                       shopIntro: ch.shop.intro, shopLogo: ch.shop.logo)
            handleRailEnablement(
                // chat: live + comments not gated to login-only (channel-only
                // derivation — `guest_comment==1` means comments are open to all).
                chatEnabled: ch.liveStatus == 1 && ch.guestComment == 1,
                // serviceLink: available whenever the shop configured a contact link. The
                // live/VOD choice is handled by the shell layout (the side rail only renders
                // in the non-live layout), so this derivation no longer gates on live_status
                // — the prior `&& live_status==0` over-restricted it to upcoming videos only,
                // hiding 聯繫商家 on the VOD/replay rail where it should appear (aligns with
                // design `LBPSideRail`, which draws contact unconditionally).
                serviceLinkAvailable: !ch.shop.serviceLink.isEmpty,
                // guest-edit: comments open (guest may rename) AND a live session.
                guestEditAvailable: ch.guestComment == 1)
            // LIVE/VOD flag for the top-bar chrome branch (host reads header.isLive).
            handleLive(ch.liveStatus == 1)
            // 回放旗標（replay-live-chrome-flag）：一場已結束的直播（type==2 && liveStatus==3）。
            // 與 isLive 並列、語意分離、互斥。下游 reference-ui 讀此把回放渲染成 LIVE 版型。
            // 純 VOD 點播（type==1）兩旗標皆 false → 維持 VOD 版型。
            header.handleFinishedLiveReplay(
                Self.isFinishedLiveReplay(type: ch.type, liveStatus: ch.liveStatus))
            // 會員等級限定軟閘門（restriction-gate ②）：衍生 isRestricted 供 reference-ui 疊遮罩。
            applyRestriction(ch.isRestriction == 1)
            // 通用 loading 封面（player-loading-cover-background-template）：衍生 loadingCover =
            // channel.cover 供 loading 畫面（不限 upcoming）繪封面圖背景。zero-pixel passthrough，
            // diff-then-notify 折進本批次（單次 ingest 至多一次 onChange）。不動 upcoming.cover。
            applyLoadingCover(ch.cover)
            // Prev/next adjacent video targets (swipe-navigate-template) — read the
            // first item id of each nav array (LBNavItem.id). Diff-then-notify inside
            // this same coalescing batch, so a channel ingest still fires at most one
            // onChange.
            navigation.ingest(prevVideoId: ch.prev.first?.id, nextVideoId: ch.next.first?.id)
            // 公告也是 channel 資料：跟 header / rail / nav 同路徑注入，使 LIVE 進行中 core 的
            // live channel refresh（20s 重抓 /sdk/video，`onChannelRefresh` → `ingestChannel`）帶回
            // 的 mid-stream 後台公告變更**即時反映**到 notice-tab，無需使用者重進播放器（問題 5,
            // live-notice-channel-refresh-template）。`handleChannelNotices` 為 idempotent
            // diff-then-notify，且其內層 coalescing 由計數式 depth 折進本批次（仍只發一次 onChange）。
            handleChannelNotices(systemNotice: ch.sysNotice, notice: ch.notice)
        }
    }

    /// Diff-then-notify the member-restriction soft-gate flag (restriction-gate ②).
    /// Called inside `ingestChannel`'s coalescing batch, so a change here folds into
    /// the single channel-ingest onChange.
    private func applyRestriction(_ restricted: Bool) {
        guard isRestricted != restricted else { return }
        isRestricted = restricted
        notifyChange()
    }

    /// Diff-then-notify the general (not upcoming-scoped) loading cover
    /// (`player-loading-cover-background-template`). Called inside `ingestChannel`'s
    /// coalescing batch, so a cover change folds into the single channel-ingest
    /// onChange. Exact shape of `applyRestriction` (channel-derived, guard-then-set).
    private func applyLoadingCover(_ cover: String) {
        guard loadingCover != cover else { return }
        loadingCover = cover
        notifyChange()
    }

    /// Feed the VideoInfoPanel notice-tab the latest `sys_notice` / `notice` from
    /// the channel. Internal so unit tests can drive it without a loaded channel.
    /// Coalesced: after the notice texts settle, the info-tab reconciles its active
    /// tab (公告轉空 while sitting on `notice` → auto-fall-back to `info`, D4 / R4),
    /// so one notice injection fires at most one onChange.
    func handleChannelNotices(systemNotice: String, notice: String) {
        coalescing {
            noticeTab.injectNotices(systemNotice: systemNotice, notice: notice)
            infoTab.reconcileActiveTab()
        }
    }

    // MARK: - Goods-tracking broadcast handlers (await-toggle-and-notice-tab-template-state)

    /// `AWAIT_GOODS_CHANGED` (notify) → correct the await flag for `goodsGpn` from
    /// the authoritative broadcast (touches only that flag — non-mutual-exclusion).
    func handleAwaitGoodsChanged(goodsGpn: String, enabled: Bool) {
        goodsTracking.applyAwaitBroadcast(goodsGpn: goodsGpn, enabled: enabled)
    }

    /// `NOTICE_GOODS_CHANGED` (notify) → correct the notice flag for `goodsGpn`.
    func handleNoticeGoodsChanged(goodsGpn: String, enabled: Bool) {
        goodsTracking.applyNoticeBroadcast(goodsGpn: goodsGpn, enabled: enabled)
    }

    // MARK: - Player moment-state ingestion (expose-player-moment-state-template)

    /// Fan one core `LBPlayerMomentState` snapshot into the EndScreen / Product-
    /// Overlay / PlayerHeader / SubtitleTrack view-models. Each model diffs and
    /// notifies at most once, so one snapshot push coalesces into one onChange.
    /// `muted` is NOT in the snapshot (sourced via `handleMuted`).
    func handleMomentState(_ s: LBPlayerMomentState) {
        coalescing {
            endScreen.handleMoment(next: [s.nextItem].compactMap { $0 },
                                   hot: s.hotItems,
                                   countdownActive: s.autoNextCountdownActive,
                                   remain: s.autoNextRemainingSeconds,
                                   endScreenShown: s.endScreenShown)
            productOverlay.handleProducts(s.products, active: s.narratingProduct)
            header.handleHeader(isSubscribed: s.isSubscribed, viewerCount: s.viewerCount,
                                viewerCountVisible: s.viewerCountVisible)
            subtitle.handle(available: s.subtitleAvailable, enabled: s.subtitleEnabled)
            // Side-rail bag-count = products.count (derived — NO second copy, D2)
            // and the subtitle-enabled item flag reuse `subtitleAvailable`.
            operationRail.handleBagCount(s.products.count)
            operationRail.handleEnablement(
                chatEnabled: railChatEnabled,
                subtitleAvailable: s.subtitleAvailable,
                serviceLinkAvailable: railServiceLinkAvailable,
                guestEditAvailable: railGuestEditAvailable)
            // Seed goods-tracking initial flags from the products this snapshot
            // carries (non-clobbering — a toggled / broadcast-corrected key wins).
            for p in s.products {
                goodsTracking.seed(goodsGpn: p.goodsGpn, isAwait: p.isAwait, isAwaitNotice: p.isAwaitNotice)
            }
            // mini-cart peek is populated ONLY by a successful add (route-B), NOT by the
            // narrating product (tmpl-ios-remove-minicart-peek-fallback): the 講解中商品 is
            // already shown by the pinned card (LIVE) / now-introducing card (VOD), so seeding
            // the mini-cart peek with it duplicated that surface (same `MiniCartView` component)
            // and leaked the VOD-only peek into LIVE. The prior `miniCart.seedFallback(narrating)`
            // is removed.
        }
    }

    /// Player mute flag → PlayerHeader AND side-rail (mirror the SAME source, D2 —
    /// no second truth). Seeded `true` at attach (auto-muted on start); the host /
    /// wiring drives subsequent flips. Coalesced so one mute flip = one onChange.
    /// PRESENTATION-ONLY — use `setMuted(_:)` to also drive the core engine.
    func handleMuted(_ muted: Bool) {
        coalescing {
            header.handleMuted(muted)
            operationRail.handleMuted(muted)
        }
    }

    /// Host-callable mute that closes the iOS mute-wiring gap: it forwards the intent
    /// to the core player (`setMuted` → active engine, AVPlayer or IVS — the audio
    /// path that actually un/mutes the stream) AND mirrors the presentation `muted`
    /// flag (`handleMuted`) from the SAME call, so the header / side-rail never
    /// diverge from the engine. The auto-muted seed (`handleMuted(true)` at attach)
    /// is unchanged; this is the exit the tap-to-unmute gesture + the host drive so
    /// the player actually produces sound.
    public func setMuted(_ muted: Bool) {
        player?.setMuted(muted)   // core: routes to activeEngine (AVPlayer / IVS)
        handleMuted(muted)        // presentation: PlayerHeader + side-rail mirror
    }

    /// Toggle mute relative to the current presentation truth (`header.muted`).
    /// Convenience for the tap-to-unmute gesture / a mute button.
    public func toggleMute() {
        setMuted(!header.muted)
    }

    // MARK: - Turnkey perform-methods (forward to core public action exits, TK-1)
    //
    // Pure forwarders to the player's public `perform*` exits so reference-ui can
    // forward a tap to the template (the selectInfoTab / addToCart pattern) and the
    // design default flow runs when the host does NOT intercept. NO gating/throttle
    // here (lives in core); a host sync-interceptor still wins. Heart-burst stays
    // driven by the reactive `handleLikePerformed` (VIDEO_LIKE) — `performLike` only
    // triggers, it does NOT bump the tick (no double animation). System-UI for share
    // (share sheet) is presented by the host on the not-intercepted `videoShareRequest`
    // event (TK-4). serviceLink is the ONE exception: when neither `INFO_CUSTOMER_SERVICE`
    // nor `SERVICE_LINK_REQUEST` is intercepted, the template itself opens a default
    // in-app browser via the existing `openInAppBrowser` seam (dropin-service-link-
    // default-browser) — there is no reference-ui container config seam for it (unlike
    // `onShare`), so the default lives here instead.

    /// Like (❤️) — forwards to the throttled core exit.
    public func performLike() { player?.performLike() }
    /// Share — forwards to core (emits interceptable `videoShareRequest`).
    public func performShare() { player?.performShare() }
    /// Toggle subtitles (CC) — forwards to the gated core exit.
    public func toggleSubtitle() { player?.performSubtitleToggle() }
    /// Open the shop service link — forwards to core (emits interceptable `INFO_CUSTOMER_SERVICE` /
    /// `SERVICE_LINK_REQUEST`). If NEITHER event was intercepted by the host AND
    /// `channel.shop.serviceLink` is a non-empty, parseable URL, opens it via the existing
    /// `openInAppBrowser` seam (dropin-service-link-default-browser) — mirrors the `diversionUrl`
    /// precedent. Empty / unparseable url → safe no-op (does NOT present an empty browser).
    public func openServiceLink() {
        let intercepted = player?.performServiceLink() ?? false
        guard !intercepted,
              let urlString = player?.channel?.shop.serviceLink, !urlString.isEmpty,
              let url = URL(string: urlString)
        else { return }
        openInAppBrowser(url)
    }
    /// Subscribe / unsubscribe — forwards to core.
    public func toggleSubscribe() { player?.performSubscribe() }
    /// Tap a product → core default flow (not-intercepted → reactive `handleProductTap`
    /// builds the detail-sheet state the family-3 overlay binds).
    public func performProductTap(_ product: LBProduct) { player?.performProductTap(product) }

    /// Request the next page of chat history.
    public func loadChatHistory() { player?.performLoadChatHistory() }
    /// Send a chat message — wraps the already-public async core `sendChat`.
    public func sendChat(_ text: String, eventId: Int? = nil) {
        Task { try? await player?.sendChat(message: text, eventId: eventId) }
    }
    /// Telemetry-only: emit the product-panel toggle event (list visibility host-owned).
    public func performGoodsTap() { player?.performGoodsTap() }
    /// Telemetry-only: emit the chat toggle event (chat visibility host-owned).
    public func performChatToggle() { player?.performChatToggle() }

    // MARK: - VOD playback (VOD-2)

    /// Ingest the core's dedicated playback-progress channel into the read-only
    /// `playbackProgress` view-model (diff-then-notify → one onChange per real change).
    func handlePlaybackProgress(_ p: LBPlaybackProgress) {
        playbackProgress.handle(position: p.position, duration: p.duration,
                                isPlaying: p.isPlaying, isReplay: p.isReplay)
    }

    /// VOD play/pause toggle — forward to core.
    public func togglePlayPause() { player?.togglePlayPause() }
    /// VOD absolute seek — forward to core (gated to non-live).
    public func seek(to seconds: Double) { player?.seek(seconds: seconds) }
    /// VOD relative seek — forward to core (clamped).
    public func seekBy(_ delta: Double) { player?.seekBy(delta) }

    // MARK: - Prev/next video navigation forwarders (swipe-navigate-template)

    /// Switch to the previous adjacent video (`navigation.prevVideoId`) by driving the
    /// core `load(videoId:)`. No-op when there is no previous video (id nil).
    public func navigateToPrev() {
        guard let id = navigation.prevVideoId else { return }
        player?.load(videoId: id)
    }

    /// Switch to the next adjacent video (`navigation.nextVideoId`) by driving the core
    /// `load(videoId:)`. No-op when there is no next video (id nil).
    public func navigateToNext() {
        guard let id = navigation.nextVideoId else { return }
        player?.load(videoId: id)
    }

    // MARK: - Player chrome feed (player-chrome-template)

    /// Top-bar chrome from the public `channel` → PlayerHeader (D3). Read once the
    /// channel is loaded; idempotent (diff-then-notify inside the model).
    func handleHeaderChrome(title: String, hostName: String, shopLogo: String, shareUrl: String) {
        header.handleHeaderChrome(title: title, hostName: hostName,
                                  shopLogo: shopLogo, shareUrl: shareUrl)
    }

    /// LIVE/VOD flag from the public `channel` (`liveStatus == 1`) → PlayerHeader.
    /// Idempotent (diff-then-notify inside the model). Called inside `ingestChannel`'s
    /// coalescing batch so a single channel ingest fires at most one onChange.
    func handleLive(_ isLive: Bool) {
        header.handleLive(isLive)
    }

    /// Info-tab fields from the public `channel` → VideoInfoPanel info-tab (D4).
    func handleInfo(title: String, publishAt: String, shopName: String,
                    shopIntro: String, shopLogo: String) {
        infoTab.handleInfo(title: title, publishAt: publishAt, shopName: shopName,
                           shopIntro: shopIntro, shopLogo: shopLogo)
    }

    /// Side-rail conditional enablement from the public `channel` (D2). Persists
    /// the channel-derived inputs so a later momentState push (subtitle) keeps them.
    func handleRailEnablement(chatEnabled: Bool, serviceLinkAvailable: Bool,
                              guestEditAvailable: Bool) {
        railChatEnabled = chatEnabled
        railServiceLinkAvailable = serviceLinkAvailable
        railGuestEditAvailable = guestEditAvailable
        operationRail.handleEnablement(
            chatEnabled: chatEnabled,
            subtitleAvailable: subtitle.available,
            serviceLinkAvailable: serviceLinkAvailable,
            guestEditAvailable: guestEditAvailable)
    }

    /// A core `VIDEO_LIKE` (like API success) → bump the heart-burst tick (D2 / R5).
    func handleLikePerformed() {
        operationRail.handleLikePerformed()
    }

    /// Host-triggered info-tab tab switch (D4). `notice` honoured only when the
    /// notice-tab `canOpen` (no-op otherwise); `info` always selectable.
    public func selectInfoTab(_ tab: LBInfoPanelTab) {
        infoTab.selectTab(tab)
    }

    /// Channel-derived side-rail enablement inputs, persisted across feeds so a
    /// momentState push (which only knows subtitle) does not reset chat / service-
    /// link / guest-edit. Default false until the channel loads.
    private var railChatEnabled = false
    private var railServiceLinkAvailable = false
    private var railGuestEditAvailable = false

    /// VIDEO_ERROR — core `error(LBError)` → host-bindable error-state `{kind,
    /// phase: .failed}` for `LBPErrorScreen`. core stays headless; the template
    /// only maps + exposes (no rendering).
    func handleError(_ error: LBError) {
        errorState.recordError(error)
    }

    // MARK: - Auth-gate + identity-label handlers (auth-gate-template-state)

    /// `AUTH_REQUIRED` — un-intercepted「請先登入」→ host-bindable auth-gate state.
    /// `hostIntercepted` is hard-wired `false` at the route-B call site: the core's
    /// primary-before-aux short-circuit means the aux listener only ever sees this
    /// event when the host's primary did NOT intercept (host-takeover exclusion is
    /// the dispatcher gate, NOT re-judged here). When `true` the model leaves its
    /// state untouched and fires no `onMutation` → no notification.
    func handleAuthRequired(params: [String: Any], hostIntercepted: Bool) {
        authGate.recordRequired(params: params, hostIntercepted: hostIntercepted)
    }

    /// `AUTH_STATE_CHANGED` — update identity-label and, on `logged_in`, clear the
    /// auth-gate prompt. ONE event = AT MOST ONE notification (D5): the two model
    /// mutations are coalesced so a single login-success fires `onChange` exactly
    /// once. `resumed_action` is NOT reflected in identity-label (Non-Goal).
    func handleAuthStateChanged(params: [String: Any]) {
        coalescing {
            let state = params["state"] as? String ?? ""
            identityLabel.update(state: state, displayName: params["display_name"] as? String)
            if state == "logged_in" { authGate.clearOnLogin() }
        }
    }

    /// Host-triggered「請求改名」intent (guest 態) → injected core exit
    /// (`Player.guestNameEditRequest()`-equivalent, emit `GUEST_NAME_EDIT_REQUEST`,
    /// passthrough / non-navigation / no auto-PiP). Inert no-op when no requester
    /// was injected. The template draws NO rename UI and changes NO event semantics
    /// — host fulfils the rename via `LiveBuySDK.setUser`.
    public func requestGuestNameEdit() {
        guestNameEditRequester?()
    }

    /// DISMISS_REQUEST — platform-native dismiss (Task 3.2)
    func handleDismissRequest() {
        player?.presentingViewController?.dismiss(animated: true)
    }

    /// PRODUCT_TAP — diversion=1 opens the purchase page in an in-app browser
    /// (Task 2.1 / D3); diversion=0 opens the in-app product-detail sheet state
    /// (product-sheet-stack-template D1 — host renders the sheet from the exposed
    /// product-detail / variant / qty view-models). Only reached when the host did
    /// NOT intercept `productTap` (route-A typed callback = core's not-intercepted
    /// default behaviour → host-takeover exclusion is the dispatcher gate, NOT
    /// re-judged here; a host that takes over `productTap` never reaches this).
    /// MUST NOT eject the user to the system browser.
    func handleProductTap(product: LBProduct, diversion: Int) {
        if diversion == 1 {
            guard !product.diversionUrl.isEmpty, let url = URL(string: product.diversionUrl) else { return }
            openInAppBrowser(url)
            return
        }
        // diversion == 0 →站內面板: feed the product-detail sheet state.
        openProductDetail(product)
    }

    /// Open the product-detail sheet state for `product` (diversion==0 tap, or a
    /// mini-cart「open detail」re-open). Resets variant selection + recomputes the
    /// qty bounds for the new product (D1 / D2 / D3) inside ONE coalesced
    /// notification, and clears the「請選規格」/ add-failed flags.
    func openProductDetail(_ product: LBProduct) {
        coalescing {
            needsVariantSelection = false
            addToCartFailed = false
            addToCartNeedsLogin = false
            addToCartInFlight = false
            productSheet.openDetail(product)
            guard let detail = productSheet.detail else { return }
            variantPicker.reset(for: detail)
            // qty bounds: chosen spec stock if a spec is implicitly selected
            // (no-spec product), else product stock. soldOut forces 0.
            let stock = variantPicker.selectedSpec?.stock ?? detail.stock
            qtyStepper.recomputeBounds(stock: stock, soldOut: detail.soldOut)
        }
    }

    /// Host「關閉商品明細 sheet」intent — clears the product-detail state (`productSheet.detail
    /// → nil`) in one coalesced notification. The reference-ui sheet's dismiss wires here so the
    /// template's `detail` returns to nil; otherwise `openDetail` is diff-then-notify (re-opening
    /// the SAME product is a no-op), so a closed sheet could not be re-opened by tapping the same
    /// product again until a DIFFERENT product changed `detail`. No-op when already nil.
    /// (expose-close-product-detail-template)
    public func closeProductDetail() {
        coalescing {
            productSheet.clearDetail()
        }
    }

    /// Host chip tap → update variant selection and re-clamp qty to the newly
    /// chosen spec's stock (D2 / D3). Coalesced so one selection = one onChange.
    public func selectVariant(groupIndex: Int, optionIndex: Int) {
        coalescing {
            variantPicker.selectVariant(groupIndex: groupIndex, optionIndex: optionIndex)
            // A complete selection now has a `selectedSpec` → re-derive qty bounds
            // from its stock; clears「請選規格」prompt once a spec resolves.
            if variantPicker.selectedSpec != nil {
                needsVariantSelection = false
            }
            let stock = variantPicker.selectedSpec?.stock ?? productSheet.detail?.stock ?? 0
            let soldOut = productSheet.detail?.soldOut ?? 0
            qtyStepper.recomputeBounds(stock: stock, soldOut: soldOut)
        }
    }

    /// Host qty-stepper intents (clamped to `[min, max]` inside the model).
    public func setQty(_ value: Int) { qtyStepper.setQty(value) }
    public func incQty() { qtyStepper.incQty() }
    public func decQty() { qtyStepper.decQty() }

    /// Host「加入購物車」intent (product-sheet-stack-template D5, route-B). Guards:
    ///   - sold-out / out of stock (`qty.max == 0`) → MUST NOT delegate.
    ///   - product HAS spec groups but selection incomplete (`selectedSpec == nil`)
    ///     → MUST NOT delegate; set `needsVariantSelection` for the host prompt.
    /// On a valid request: assemble `LBCartRequest` and delegate to the injected
    /// core requester (route-B `LiveBuy.addToCart`). Success → mini-cart peek +
    /// cart CTA count++ in ONE coalesced onChange; failure → `addToCartFailed`,
    /// count unchanged. The template builds NO HTTP. Host-takeover (route A) is
    /// excluded upstream (this handler is only reached on the not-intercepted
    /// route — a host that takes over `productTap`/加購 never opens this sheet).
    public func addToCart() {
        guard let detail = productSheet.detail else { return }
        // Reset the transient flags for this attempt (both orthogonal flags together).
        addToCartFailed = false
        addToCartNeedsLogin = false
        // Guard 1 — sold-out / no stock.
        guard qtyStepper.max > 0 else { return }
        // Guard 2 — has spec groups but selection incomplete.
        let hasGroups = !variantPicker.groups.isEmpty
        if hasGroups && variantPicker.selectedSpec == nil {
            if !needsVariantSelection {
                needsVariantSelection = true
                notifyChange()
            }
            return
        }
        needsVariantSelection = false
        // cart-add-loading-state: a request is about to fire → enter in-flight and notify so
        // the host / reference-ui can disable the CTA for the request lifecycle. (Guards above
        // return early without firing, so they never enter in-flight.)
        addToCartInFlight = true
        notifyChange()
        let request = LBCartRequest(
            shopId: player?.channel?.shop.id ?? "",
            goodsId: detail.productId,
            num: qtyStepper.qty,
            specificationId: variantPicker.selectedSpecificationId,
            videoId: currentVideoId ?? player?.channel?.id)
        let peek = LBMiniCartPeek(productId: detail.productId, name: detail.name,
                                  priceShow: detail.priceShow, soldOut: detail.soldOut)
        // Capture the requester before the Task so the closure stays self-contained.
        let requester = addToCartRequester
        Task { [weak self] in
            do {
                _ = try await requester(request)
                await MainActor.run { [weak self] in self?.applyAddSuccess(peek: peek) }
            } catch {
                // Branch the thrown error (cart-add-tier2): dedupe-hit
                // (`LBError.cartAddDeduplicated`, 30s 重複加購) → 已加入 UX;
                // 「needs login」(`serverError(code:401)` for an empty `buy_no`) →
                // needs-login; any other error → genuine failure.
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    if case LBError.cartAddDeduplicated = error {
                        self.applyAddDeduplicated(peek: peek)
                    } else if Self.isAddToCartAuthRequired(error) {
                        self.applyAddNeedsLogin()
                    } else {
                        self.applyAddFailure()
                    }
                }
            }
        }
    }

    /// Success branch (main thread): mini-cart peek + cart CTA count → ONE coalesced
    /// onChange (D6 — single add success = single notification).
    private func applyAddSuccess(peek: LBMiniCartPeek) {
        coalescing {
            addToCartInFlight = false
            miniCart.setPeek(peek)
            cartCTA.incrementOnAdd()
        }
    }

    /// Dedupe-hit branch (main thread, cart-add-tier2): the same product was added
    /// within the 30s window so core skipped a duplicate addcart. Treat as「已加入
    /// 購物車」— refresh the mini-cart peek, but DO NOT increment the CTA count
    /// (the count was already bumped on the original add) and DO NOT set the
    /// add-failed flag.
    private func applyAddDeduplicated(peek: LBMiniCartPeek) {
        // Coalesce so the peek refresh is ONE onChange (mirrors applyAddSuccess; the
        // mini-cart sub-state notifies on its own, so an extra notifyChange would
        // double-fire).
        coalescing {
            addToCartInFlight = false
            miniCart.setPeek(peek)
        }
    }

    /// Failure branch (main thread): expose the add-failed flag, count unchanged.
    private func applyAddFailure() {
        addToCartInFlight = false
        addToCartFailed = true
        notifyChange()
    }

    /// Needs-login branch (main thread): expose the needs-login flag (orthogonal to
    /// `addToCartFailed`), count unchanged. The reference-ui presents a login gate
    /// (host `config.onLogin`) instead of the「加入購物車失敗」retry banner.
    private func applyAddNeedsLogin() {
        addToCartInFlight = false
        addToCartNeedsLogin = true
        notifyChange()
    }

    /// Pure classifier: `true` only for the core「needs login」signal
    /// (`LBError.serverError(code: 401, ...)` raised for an empty `buy_no`), `false`
    /// for every other error (other `serverError` codes, `networkError`, framework
    /// errors, …). Extracted so the add-to-cart error branching is unit-testable in
    /// isolation.
    static func isAddToCartAuthRequired(_ error: Error) -> Bool {
        if case LBError.serverError(let code, _) = error { return code == 401 }
        return false
    }

    /// Host intent to re-zero the per-session cart count (OQ2 — on release /
    /// new-video). Exposed so the wiring / host can reset between videos.
    public func resetCartForSession() {
        cartCTA.resetForSession()
    }

    /// POLL_RECEIVED (Task 3.4) — headless; host provides poll UI.
    /// chat-message-kind ⑤：消費 `poll.top` 暴露置頂留言 view-model（冪等：取消釘選 → nil）。
    /// 值未變時不觸發多餘變更通知。
    func handlePollReceived(_ poll: LBPollResponse) {
        // Lazy fallback capture of a stable videoId for the deinit save-key: this per-poll handler
        // runs on EVERY poll and BEFORE any feed ingestion (`handlePush`/`handleJoin`/`handlePurchase`
        // /`ingestBacklog`) in the same `onPollReceived` cycle, so it covers the edge where poll
        // messages start accumulating history before the channel is ever `ingestChannel`'d
        // (`currentVideoId` still nil). Only attempt while unknown; a nil `player?.channel?.id` is a
        // harmless no-op (rememberVideoId never nils out).
        if lastKnownVideoId == nil { rememberVideoId(player?.channel?.id) }
        if pinnedMessage != poll.top {
            pinnedMessage = poll.top
            notifyChange()
        }
    }

    /// Activity notification (Task 3.4) — headless; host provides notification UI.
    /// Retained for source compatibility; join / purchase / win now route through
    /// the typed `handleJoin` / `handlePurchase` / `handleWin` below so the merged
    /// feed can mark each item's visual tier.
    func handleActivityNotice(text: String) {}

    // MARK: - Activity → merged feed (§1) + win claim (§2)

    /// `showJoin` (user[]) → feed activity row, tier = join (lowest emphasis).
    func handleJoin(text: String) {
        activityFeed.appendJoin(text: text)
    }

    /// `showPurchase` (rush[]) → feed activity row, tier = purchase.
    func handlePurchase(text: String) {
        activityFeed.appendPurchase(text: text)
    }

    /// `showWin` (winner[]) → feed activity row (tier = win) AND the INDEPENDENT
    /// unclaimed entry set (feed = 「中獎發生」, entry = 「尚有 N 筆可領」).
    func handleWin(text: String, winner: LBWinner) {
        activityFeed.appendWin(text: text, winner: winner)
        winClaim.recordWin(winner)
    }

    /// Chat row (push / comment) → feed chat row. The feed is a SEPARATE model;
    /// activity rows are NOT written into the ChatView chat data source. `name` is
    /// the author nickname (chat-nickname-display); nil → text-only row.
    func handleChat(text: String, name: String? = nil) {
        activityFeed.appendChat(text: text, name: name)
    }

    // MARK: - 回放聊天 bridge（replay-chat-feed-bridge-template，Depends On -core）

    /// 已 append 進 `activityFeed` 的回放已揭露前綴長度（單調游標）。core 的通知型 seam
    /// `onReplayChatRevealed` 一律送「同一條依 `time` 升序串的前綴」，故此值即上次 reveal 已
    /// reconcile 的長度，用來判定「前進只 append 新尾段」或「倒退 / 清空 / 換片重建」。換片
    /// （core 送 `[]` 或 `handleVideoSwitch`）時歸 0。
    private var replayChatAppendedCount: Int = 0

    /// 回放已揭露前綴 reconcile 進 `activityFeed` 的**純決策**（遵 docs/unit-test-discipline.md）。
    /// 前綴單調（core 一律送同一升序串的前綴）：
    /// - `incomingCount >= appendedCount`（播放前進 / 不變）→ `.appendDelta`：只 append 尾段索引
    ///   區間 `[appendedCount, incomingCount)`（`incomingCount == appendedCount` 為空區間 = no-op，
    ///   前進時**不重建、不閃爍**）。
    /// - `incomingCount < appendedCount`（seek 倒退 / 收到 `[]` 清空 / 換片）→ `.rebuild`：先 clear
    ///   再重建全部 `[0, incomingCount)`（可能為空）。
    enum ReplayChatReconcile: Equatable {
        /// 只 append 索引區間 `[from, to)` 的新尾段（`to == from` 時為 no-op）。
        case appendDelta(from: Int, to: Int)
        /// 先 `clear` 再重建索引區間 `[0, to)` 全部（倒退 / 清空 / 換片）。
        case rebuild(to: Int)
    }

    /// Pure → 可單測（回傳 Equatable enum、complexity 低、無副作用）。唯一決策點。
    static func replayChatReconcile(incomingCount: Int, appendedCount: Int) -> ReplayChatReconcile {
        incomingCount >= appendedCount
            ? .appendDelta(from: appendedCount, to: incomingCount)
            : .rebuild(to: incomingCount)
    }

    /// 把回放歷史 `LBComment` 映射成 chat feed row 的角色 metadata。歷史端（`/sdk/video/comments`）
    /// 僅三型：`.comment`（觀眾留言）/ `.host`（主播留言）/ `.hostReply`（主播回覆，帶引用 `reply`）。
    /// AI 回覆（`.aiReply`）為直播 push 限定、回放歷史不會出現 → `isAI` 一律 false。`color` /
    /// `replyColor` 不入 feed 模型（reference-ui 以**版型**而非顏色區分主播 / 回覆），故只搬
    /// `text` / `name` / `reply`（經 `isHost` / `replyText`）。Pure / testable。
    static func replayChatRow(for comment: LBComment) -> (isHost: Bool, replyText: String?) {
        switch comment.kind {
        case .hostReply:
            return (isHost: true, replyText: comment.reply.isEmpty ? nil : comment.reply)
        case .host:
            return (isHost: true, replyText: nil)
        default:
            return (isHost: false, replyText: nil)
        }
    }

    private func appendReplayComment(_ comment: LBComment) {
        let row = Self.replayChatRow(for: comment)
        activityFeed.appendChat(text: comment.text, name: comment.name,
                                isHost: row.isHost, replyText: row.replyText)
    }

    /// 回放聊天 bridge：訂閱 core 通知型 seam `onReplayChatRevealed`，把「回放當前已揭露前綴」
    /// reconcile 進 `activityFeed`，使 reference-ui 的 `ChatFeedView`（只讀 view-model 的
    /// activity feed、不讀 core `chatView`）在回放也隨播放進度顯示歷史留言（與直播走相同的
    /// `activityFeed` → `onChange` 管線）。前進只 append 新尾段（不閃爍）、倒退 / `[]` / 換片
    /// 重建。一筆 reveal = 一次 coalesced `onChange`（D6）。直播絕不進來（core 非回放期不 fire）。
    func handleReplayChatRevealed(_ comments: [LBComment]) {
        let decision = Self.replayChatReconcile(incomingCount: comments.count,
                                                appendedCount: replayChatAppendedCount)
        coalescing {
            switch decision {
            case .appendDelta(let from, let to):
                for comment in comments[from..<to] { appendReplayComment(comment) }
            case .rebuild(let to):
                activityFeed.clear()
                for comment in comments[0..<to] { appendReplayComment(comment) }
            }
        }
        replayChatAppendedCount = comments.count
    }

    /// A poll `push[]` row → merged feed. A core event-BEGIN push
    /// (`push.isEventBegin`) is surfaced as an INDEPENDENT event-join item (host
    /// draws `LBEventJoinLine`); everything else — including event-END
    /// (`isEventEnd`) and ordinary pushes — stays a plain `.chat` row.
    /// 活動「加入 CTA」keyword 來源 = messages `push.ek`（後端「`ek` isset 才顯示 CTA」契約）。
    /// 與 goods `event[]` / `activeEventKeyword(eid:)` 解耦——`ek` 與 push 同一筆同步到達，無時序競態。
    /// `ek` unset（nil）→ `""` → 純活動公告（無 CTA）。Pure / testable（`@testable` internal）。
    static func eventJoinKeyword(for push: LBPushMsg) -> String {
        push.ek ?? ""
    }

    func handlePush(_ push: LBPushMsg) {
        // chat-push-id-dedupe-template：身分（identity）去重——同一 session 內同一非 nil `id` 只
        // append 一次，drop 在到達任何 `activityFeed.appendXXX` 之前（不 append、不觸發
        // `onMutation`）。`id == nil` 一律照原行為放行、NOT 被擋、NOT 拿去做內容比對。這與
        // `dedupeSignature(for:)` 的「MUST NOT 比對任何訊息內容」正交、不衝突：本 guard 只比對
        // `id`，後台刻意重送的真實通知（相同文字、新 id）不受影響仍會顯示。同時涵蓋批次
        // `ingestBacklog` 與即時 trickle 兩條路徑（皆呼叫本函式）及兩者交錯的情境。
        guard Self.shouldIngestPush(id: push.id, seen: &seenPushIds) else { return }
        // chat-message-kind ⑤：依 `push.kind` 判型路由，**停止以 `color` 反推**。
        // event-join-cta-isset-ek-template：`kind=event` 活動公告（與其他 kind 正交）仍**最先**判定 →
        // 獨立 event-join 項（套用 `LBEventJoinLine` 樣式）。判定用 `kind == .event` + `eid > 0`。
        // 「加入活動」CTA 的 keyword 來源 = **messages `push.ek`**（後端「`ek` isset 才顯示 CTA」契約：
        // 進行中帶 `ek="168"`、結束後不帶）——`ek` 與 push 同一筆同步到達，**MUST NOT** 改用 goods
        // `event[]` / `activeEventKeyword(eid:)`（獨立 poll，時序競態 + 去重鎖死會使 CTA 永久消失）。
        // begin/end 由 `push.ek` isset 與否自然分流：isset → keyword 非空 → CTA；unset → `""` → 純公告。
        if push.kind == .event, let eid = push.eid, eid > 0 {
            let keyword = Self.eventJoinKeyword(for: push)
            activityFeed.appendEventJoin(eid: eid, keyword: keyword, text: push.text)
            return
        }
        switch push.kind {
        case .narrate:
            // 觀眾選購（`#66F796`, ty=ds）= 社會認同廣播（「{觀眾名} 正在選購商品～」），
            // **性質同 join / purchase、非主播訊息、非介紹中**。→ 社會認同 activity row。
            // （舊版誤把 `#66F796` 當「商品介紹中」走 appendIntro，本批次語意校正。）
            activityFeed.appendNarrate(text: push.text)
        case .onsale:
            // onsale 商品開賣改用「主播訊息」UI（主播氣泡：主播標＋暱稱＋accent 氣泡），不再走特製商品開賣卡。
            // text 直顯後端組裝好的完整文案；name = push.name（主播名）；isHost = true。
            // 空 text → 不 append（避免空氣泡；取代舊「退回系統通知」分支）。
            guard !push.text.isEmpty else { break }
            activityFeed.appendChat(text: push.text, name: push.name, isHost: true)
        case .comment:
            // 一般用戶 / 訪客留言 → chat row 帶暱稱（chat-nickname-display），isHost=false，不去重。
            activityFeed.appendChat(text: push.text, name: push.name)
        case .host, .hostReply, .aiReply:
            // 主播訊息：帶 promo metadata（`ct` / `p`，或 `eid>0` 的 promo-tied）→ DE-DUPED 系統通知；
            // 其餘主播留言 → chat row 帶暱稱 + 角色 metadata。維持既有去重語意。
            // （`.event` 已在最前面以 `kind == .event` 攔截為 event-join 活動公告，不再落此分支。）
            if Self.isSystemNoticePush(push) {
                activityFeed.appendSystemNotice(text: push.text)
            } else {
                // 群組① 真正的聊天（chat-message-taxonomy ⑤）：thread 角色 metadata 供
                // reference-ui 依**版型**區分主播留言（主播標 + accent 氣泡）/ 主播回覆（引用框）/
                // AI 回覆（AI 標）。
                let isAI = (push.kind == .aiReply)
                let isReply = (push.kind == .hostReply || push.kind == .aiReply)
                activityFeed.appendChat(
                    text: push.text, name: push.name,
                    isHost: true,
                    replyText: (isReply && !push.reply.isEmpty) ? push.reply : nil,
                    isAI: isAI)
            }
        default:
            // .join / .purchase / .win 不會落 push 桶；.unknown → 保守當 chat。
            activityFeed.appendChat(text: push.text, name: push.name)
        }
    }

    /// Whether a host / event `push[]` row (kind `.host` / `.hostReply` / `.aiReply` / `.event`)
    /// is a SYSTEM / 事件 / 促銷 notice rather than free主播 chat — used (within the `kind`-based
    /// `handlePush` routing) to send it through the DE-DUPED `appendSystemNotice` path. A notice is
    /// flagged by event metadata (`eid > 0`, e.g. event-end / event-tied) OR promo metadata (`ct` /
    /// `p`). `.narrate` / `.onsale` / `.comment` are routed by kind BEFORE this check, so they are
    /// NOT part of this predicate. Ordinary主播 chat carries none of these, so it stays un-deduped.
    /// Pure / testable.
    static func isSystemNoticePush(_ push: LBPushMsg) -> Bool {
        (push.eid ?? 0) > 0
            || !(push.ct ?? "").isEmpty
            || !(push.p ?? "").isEmpty
    }

    // MARK: - messages is_init backlog batch ingest (live-chat-backlog-batch-ingest-template,
    // ordering corrected by live-chat-backlog-ingest-order-fix-template)

    /// Pure: identity pass-through for one `is_init` backlog bucket (`push[]` / `user[]` /
    /// `rush[]`) before batch ingestion — the bucket is appended in the ORDER it arrives.
    ///
    /// **History**: the original `live-chat-backlog-batch-ingest-template` change (2026-07-03,
    /// archived) had this function REVERSE the bucket, under an explicitly documented-as-unproven
    /// assumption (its design.md D2) that each bucket is delivered **newest-first**. A live
    /// regression report (`歷史訊息的順序顛倒了, 新的要在舊的訊息下面` — history order reversed,
    /// newest should render BELOW oldest) proved that assumption backwards: `DefaultActivityFeed`
    /// stores newest-at-the-tail, and `ChatFeedView` renders `history` verbatim (oldest → newest,
    /// top → bottom, no reordering at render time) — so reversing an already-oldest-first bucket
    /// put the newest message at the HEAD (rendered at the top) and the oldest at the TAIL
    /// (rendered at the bottom), exactly backwards. It also made the end-of-batch trim keep the
    /// WRONG (oldest) subset whenever a backlog round exceeds the retain cap, silently un-fixing
    /// the original `後面進入直播的人看不到歷史訊息` bug.
    ///
    /// **Documented assumption** (`live-chat-backlog-ingest-order-fix-template/design.md` D2):
    /// none of `LBPushMsg` / `LBUserMsg` / `LBRushMsg` carry a timestamp or sequence field, and no
    /// spec documents this round's array direction — so this function now assumes each bucket is
    /// delivered **oldest-first** (index 0 = oldest), the ordinary convention for a "history"
    /// endpoint and the direction the live regression supports, and therefore does NOT reorder it.
    /// This does NOT reorder ACROSS buckets — push/user/rush relative sequencing is untouched (no
    /// evidence either way for that dimension). If backend confirmation ever shows a bucket is
    /// actually newest-first, reinstate `Array(bucket.reversed())` here (isolated to this one
    /// function) rather than touching the batching/notify plumbing.
    static func backlogIngestOrder<T>(_ bucket: [T]) -> [T] {
        bucket
    }

    /// Batch-ingest the messages `is_init` backlog round (≤500 筆一次性歷史per bucket) as ONE
    /// atomic operation, instead of feeding it through the live per-item path.
    ///
    /// **Why**: `DefaultActivityFeed`'s `history` buffer is trimmed by SEPARATE per-type caps
    /// (chat rows at `chatRetain`, activity-bucket rows at `activityRetain` — chat-activity-
    /// separate-retention-ios-template). The live trickle path (`handlePush` / `handleJoin` /
    /// `handlePurchase`, called once per item as messages arrive a few seconds apart) trims on
    /// every append — correct and cheap for that cadence. But the `is_init` round can deliver up
    /// to 500 items in ONE poll response; naively forwarding that array in FORWARD order through
    /// the same per-item path assumes it is oldest-first (§`backlogIngestOrder` doc) — the
    /// direction this codebase now assumes it actually is, so forward-order (unreversed) ingestion
    /// is correct: appending oldest-first means the LAST-appended item (the newest message) lands
    /// at `history`'s tail, matching `DefaultActivityFeed`'s "newest at the tail" invariant, and
    /// the single end-of-batch per-type trim correctly keeps the chronologically newest rows of
    /// each type — fixing the reported symptom (後面進入直播的人看不到歷史訊息: a late joiner must
    /// see the messages right before they joined, not stale ones).
    ///
    /// This method feeds each bucket through `backlogIngestOrder` (now an identity pass-through)
    /// and reuses the EXISTING, UNMODIFIED `handlePush` / `handleJoin` / `handlePurchase`
    /// classification methods — called inside `activityFeed.batchIngest { ... }` so the
    /// per-type trim and the host-facing notification each fire EXACTLY ONCE for the whole
    /// round (was: up to 500 times). The live one-at-a-time trickle path is untouched — this
    /// method is only invoked when `response.isBacklogReplay == true` (see
    /// `TemplateAttachment.onPollReceived`).
    func ingestBacklog(push: [LBPushMsg], user: [LBUserMsg], rush: [LBRushMsg]) {
        activityFeed.batchIngest {
            for item in Self.backlogIngestOrder(push) { handlePush(item) }
            for item in Self.backlogIngestOrder(user) { handleJoin(text: item.text) }
            for item in Self.backlogIngestOrder(rush) { handlePurchase(text: item.text) }
        }
    }

    /// Host-triggered「加入活動」intent for an event-join feed item. Calls the
    /// core's interceptable `requestEventJoin` (emits `eventJoinIntent`; if the
    /// host intercepts it, the host fulfils the join) and OPTIMISTICALLY marks
    /// the item `joined` (core has no "join succeeded" callback). MUST NOT
    /// auto-`sendChat` (avoids double submission).
    public func joinEvent(eid: Int, keyword: String) {
        player?.requestEventJoin(eid: eid, keyword: keyword)
        activityFeed.markJoined(eid: eid)
    }

    /// AWARD_CLAIM_RESULT (notify) → win-claim result-state model (§4).
    func handleAwardClaimResult(status: LBAwardClaimStatus,
                                awardType: String,
                                awardCode: String?) {
        winClaim.consumeResult(status: status, awardType: awardType, awardCode: awardCode)
    }

    /// Live end (Task 3.4) — headless; host provides end screen
    func handleLiveEnd() {}

    /// `VIDEO_SWITCH` (notification) → reset the per-video-session family-2 overlay so the next
    /// video starts from a CLEAN feed / win entry — UNLESS the destination video (`to`) is one
    /// ANY `DefaultPlayerTemplate` instance this process already visited (now that
    /// `feedSnapshotCache` is `.shared`/process-level, chat-history-video-switch-cache-cross
    /// -instance), in which case its chat/activity history is RESTORED via `arriveAt(videoId:)`
    /// instead of being left empty (`chat-history-video-switch-cache-template`, fixing
    /// 「切換影片再回來又看不到歷史訊息」). `winClaim` / `replayChatAppendedCount` are unaffected by
    /// this cache — still cleared / reset unconditionally (separate concerns from the reported
    /// bug: unclaimed award entries, VOD/replay reveal cursor).
    ///
    /// `from` / `to` are the core-supplied `VIDEO_SWITCH` params (`from_video_id` / `to_video_id`,
    /// already sent by `LiveBuyPlayerViewController.load(videoId:)`, now threaded through by
    /// `TemplateAttachment`). Both default to `nil` so existing no-arg call sites (tests exercising
    /// OTHER, orthogonal behaviors) keep compiling and exercise exactly today's clear+reset path —
    /// a missing `from` just means "nothing to save", a missing/uncached `to` means "no snapshot to
    /// restore", both degrading safely to the pre-existing behavior. Coalesced into a single
    /// host-facing `onChange`. core only dispatches `VIDEO_SWITCH` when the previous video id
    /// exists AND differs from the new one, so first-load and same-video retry / buffering NEVER
    /// reach here (no false clears/restores) — this instance's OWN first video load is instead
    /// covered by `ingestChannel`'s `arriveAt` call (see there). Headless — clears/restores data
    /// only.
    func handleVideoSwitch(from: String? = nil, to: String? = nil) {
        coalescing {
            // 離開前先把「這支影片目前的 feed + push id 去重集合」存進快取（history 空則 save 內部
            // 自行略過，見 VideoFeedSnapshotCache.save）——chat-history-video-switch-cache-template。
            if let from = from {
                feedSnapshotCache.save(videoId: from, history: activityFeed.history, seenPushIds: seenPushIds)
            }
            winClaim.clear()
            // 回放聊天游標同步歸 0（feed 即將 clear 或 restore，否則下一場前綴會誤判前進/倒退）—
            // replay-chat-feed-bridge-template。core 也會在 resetPerSessionState 送 `[]`，兩路皆安全。
            replayChatAppendedCount = 0
            // 換片抵達端也記住新場 videoId：`handleVideoSwitch` 本身不設 `currentVideoId`，若這支影片的
            // channel 之後才（或未）`ingestChannel`，deinit 仍能靠 `lastKnownVideoId` 存到正確的新場快照。
            rememberVideoId(to)
            arriveAt(videoId: to)
        }
    }

    /// Shared arrival-side logic for BOTH `handleVideoSwitch(to:)` and this instance's very
    /// FIRST video load (`ingestChannel`, chat-history-video-switch-cache-cross-instance) —
    /// restore `activityFeed`/`seenPushIds`/`hasIngestedBacklog` from `feedSnapshotCache` if
    /// `videoId` was already visited (by ANY template instance this process, now that the cache
    /// is `.shared`/process-level), else fall through to today's clear+reset so the normal
    /// `is_init`/backlog-fetch path populates it from the network. Caller MUST already be inside
    /// a `coalescing { }` block (this does not fire its own `onChange`).
    private func arriveAt(videoId: String?) {
        if let videoId = videoId, let cached = feedSnapshotCache.snapshot(for: videoId) {
            // 已造訪過 `videoId`——還原快照而非清空。連帶還原 seenPushIds（同一原子單位，
            // chat-history-video-switch-cache-template design.md D1）；強制 hasIngestedBacklog =
            // true 補上 user[]/rush[] 無 id 桶的防線（design.md D3）：即使罕見地又收到一輪 stray
            // 整批 backlog，也整批 skip，不在還原的快照上重複疊加。
            activityFeed.restore(cached.history)
            seenPushIds = cached.seenPushIds
            hasIngestedBacklog = true
        } else {
            // `videoId` 缺省，或本 process 內第一次出現——維持既有行為：clear + 重置旗標，交給
            // 正常的 is_init / backlog-fetch 從網路取得歷史。
            activityFeed.clear()
            // 換片後新場的第一批 backlog 應能正常 ingest（feed 已 clear、旗標 reset → 乾淨）
            // — chat-history-dedupe-template。
            hasIngestedBacklog = false
            // 換片後新場的 id 不應與前一場撞名——chat-push-id-dedupe-template。
            seenPushIds.removeAll()
        }
    }

    /// 有界（bounded）的「videoId → 上次離開時的 feed 快照」快取，讓 in-place 換片切回本 session
    /// 已造訪過的影片、以及**關閉播放器重進同一場**（全新實例的第一支影片）時都能還原歷史，不需要
    /// （也不應該）等待後端重新回傳整批 backlog（`PollManager` 既有的 cursor / `is_init` 判斷本身
    /// 正確，缺的只是消費端的記憶）。預設 `.shared`（process-level singleton，隨 app 存活，NOT
    /// 隨本 template 實例生滅——chat-history-video-switch-cache-cross-instance）；ctor-injectable
    /// 供測試傳入獨立實例，避免跨測試汙染（docs/unit-test-discipline.md）。
    private let feedSnapshotCache: VideoFeedSnapshotCache

    // MARK: - 聊天歷史 backlog 分流（cursor-based，chat-history-dedupe-template）

    /// per-session 旗標：該場是否已 ingest 過第一批「首輪 backlog 重放」（`isBacklogReplay == true`）。
    /// 由 `arriveAt(videoId:)` 分流（換片 / 本實例第一支影片皆經此）：重置為 `false`——除非命中
    /// `feedSnapshotCache`（本 session 換回，或跨實例的關閉重進），此時強制設為 `true`（見
    /// `arriveAt` 文件，chat-history-video-switch-cache-template design.md D3）。
    private var hasIngestedBacklog = false

    /// 純函式：是否 ingest 這一輪 poll 進 feed。**只依 cursor 訊號 + per-session 旗標，NOT 內容**
    /// （禁內容指紋去重——後台「推廣活動」會刻意重送相同內容真實通知，內容去重會誤殺）：
    /// - 後續輪（`isBacklogReplay == false`）→ 一律 ingest（真實新訊息，含後台刻意重送，照顯示）。
    /// - 首輪 backlog 首次（旗標 false）→ ingest 當該場歷史首屏，置旗標 true。
    /// - 首輪 backlog 已 ingest 過（旗標 true）→ 整批 skip（換片漏 clear / 同場重入疊加時不重灌歷史）。
    static func shouldIngestPoll(isBacklogReplay: Bool, alreadyIngestedBacklog: inout Bool) -> Bool {
        if !isBacklogReplay { return true }
        if alreadyIngestedBacklog { return false }
        alreadyIngestedBacklog = true
        return true
    }

    /// Instance wrapper：操作 per-session `hasIngestedBacklog`（chat-history-dedupe-template）。
    func shouldIngestPoll(_ isBacklogReplay: Bool) -> Bool {
        Self.shouldIngestPoll(isBacklogReplay: isBacklogReplay, alreadyIngestedBacklog: &hasIngestedBacklog)
    }

    // MARK: - push id 身分去重（chat-push-id-dedupe-template）

    /// per-session 已見 push id 集合。**只 push 桶適用**——`LBUserMsg`（進場）／`LBRushMsg`
    /// （搶購）不帶任何 id 欄位（只活在直播當下的即時氣氛糖，從不進歷史），故不受此集合影響。
    /// 由 `arriveAt(videoId:)` 分流（換片 / 本實例第一支影片皆經此）：重置為空集合，避免新場的
    /// id 與前一場撞名——除非命中 `feedSnapshotCache`（本 session 換回，或跨實例的關閉重進），此時
    /// 改為還原該影片離開當下的 id 集合（與其 `history` 為同一原子單位一併還原，
    /// chat-history-video-switch-cache-template design.md D1）。
    private var seenPushIds: Set<String> = []

    /// 純函式：template 層 push id 身分去重（port 自 core 的 `LiveBuyPlayerViewController
    /// .shouldAppendPush(id:seen:)`，`chat-push-id-dedupe-core`——同構、非共用，因
    /// `LiveBuyUI` 不得依賴 `LiveBuySDK` internal 實作，只依賴其 public `LBPushMsg.id`）。
    ///
    /// 這是**身分（identity）判定**，只比對 `id` 本身，NEVER 讀取或比較 `text`／`name` 等內容欄
    /// 位——與 `DefaultActivityFeed.dedupeSignature(for:)`「MUST NOT 比對任何訊息內容」的
    /// Requirement 正交、不衝突：後者防的是「以內容誤殺後台刻意重送的真實通知」（resend 依
    /// 2026-07-01 後端定案一律換新 id，故不受本函式影響、仍會顯示）；本函式只擋「完全相同 id」
    /// 的重複。`id == nil`（缺省 / 舊後端）一律回傳 true 且不記錄（fallback，不去重）。Pure /
    /// testable（no I/O，操作傳入的 `inout Set`）。
    static func shouldIngestPush(id: String?, seen: inout Set<String>) -> Bool {
        guard let id = id else { return true }
        return seen.insert(id).inserted
    }

    // MARK: - Layout well-known keys (Task 3.7)

    var productOverlayPosition: String {
        effectiveConfig.layoutValue(key: "productOverlay_position", default: "bottom") as? String ?? "bottom"
    }

    var productOverlayStyle: String {
        effectiveConfig.layoutValue(key: "productOverlay_style", default: "sheet") as? String ?? "sheet"
    }
}

// MARK: - DefaultOperationPanel (Task 3.5)

/// Cascade: visibility.chat/productOverlay/videoInfoPanel → hide corresponding buttons.
struct DefaultOperationPanel {

    let chatVisible: Bool
    let productVisible: Bool
    let announcementVisible: Bool

    init(sdkConfig: SDKConfig, hostOptions: LBUIOptions?) {
        chatVisible = ConfigMerger.effectiveVisibility(
            sdkValue: sdkConfig.visibility?.chat,
            hostValue: hostOptions?.visibility?.chat,
            templateDefault: true
        )
        productVisible = ConfigMerger.effectiveVisibility(
            sdkValue: sdkConfig.visibility?.productOverlay,
            hostValue: hostOptions?.visibility?.productOverlay,
            templateDefault: true
        )
        announcementVisible = ConfigMerger.effectiveVisibility(
            sdkValue: sdkConfig.visibility?.videoInfoPanel,
            hostValue: hostOptions?.visibility?.videoInfoPanel,
            templateDefault: true
        )
    }
}

// MARK: - DefaultWidgetTemplate (Task 3.6 + widget-content-template)

/// Default Widget template event handler.
///
/// Spec: `ui-template-foundation/spec.md`
///   § "Default Template Widget 內容 view-model 暴露"
///   § "Default Template Host 取得 widget template 實例介面"
///   § "Default Template Bindable State 變更通知" (widget content folded in)
///
/// The TYPE and its READ surface (`content` host-bindable widget-content state +
/// the `onChange` notification) are `public` so a host can obtain this instance
/// via `LiveBuyUI.widgetTemplate(for:)` and bind/observe its state. The INTERNAL
/// wiring — `init`, `handleVideoTap`, and `refreshContent()` — stays `internal`
/// (the host consumes state; it does NOT construct the instance or feed it data).
/// Existing `handleVideoTap` + the three layout-key getters are UNCHANGED (purely
/// additive, widget-content-template D5).
public final class DefaultWidgetTemplate {

    private weak var widget: LiveBuyWidgetCore?
    private let effectiveConfig: EffectiveConfig

    // MARK: - Host-bindable widget content view-model (widget-content-template)

    /// Widget content (videos / mode / pagination / liveVideo / colors) mirrored
    /// from core `LiveBuyWidgetCore` (colors from `widget-bridge-color-core`). The
    /// host draws `widgets.jsx` from this; the template renders nothing (D1).
    public let content: DefaultWidgetContent

    // MARK: - Change notification (expose-default-template-bindable-state)

    /// Coalesced "host-bindable state changed" notification. Fires EXACTLY ONCE
    /// per single widget-content change (videos update / mode change / page
    /// advance / liveVideo update / color update), dispatched on the main thread,
    /// after the state has been updated (the host re-reads `content.current` — the
    /// callback carries no diff payload). Purely additive: nil by default; when
    /// unset the template behaves exactly as before.
    public var onChange: (() -> Void)?

    // MARK: - Multi-observer registry (ios-widget-template-multi-observer-registry)

    /// One registered widget-content-change observer paired with its removal token.
    /// Stored in an ORDERED array (not a dictionary — Swift closures aren't
    /// `Equatable`) so the fire order equals registration order; removal is by token
    /// identity (`===`). Named `WidgetObserverEntry` (not the player's `ObserverEntry`)
    /// so the two same-file registries stay unambiguous.
    private struct WidgetObserverEntry {
        let token: LBTemplateObserverToken
        let observer: () -> Void
    }

    /// Ordered observer registrations. Coexists with the legacy `onChange`: a single
    /// widget-content change dispatches to BOTH (legacy first, then observers in
    /// registration order — see `notifyChange`). Empty by default (purely additive;
    /// a template with no observer behaves exactly as before). REUSES the same
    /// top-level `LBTemplateObserverToken` the player registry introduced (no second
    /// token type; the template contract never leaks a core listener token — layer
    /// boundary reference-ui → template → core is one-way).
    private var observers: [WidgetObserverEntry] = []

    /// Register a change observer that fires on the SAME coalesced "widget content
    /// changed" notification as `onChange`, and return an opaque token to remove it
    /// later. Multiple observers each keep an independent subscription — registering
    /// one NEVER clobbers another (the whole point vs. the single-`onChange`-var
    /// chain reference-ui widget overlays used to share). Fires alongside (and after)
    /// the legacy `onChange` on every dispatch.
    ///
    /// Main-thread contract: call from the main thread (same assumption as assigning
    /// `onChange`; reference-ui widget overlays register/unregister on their
    /// SwiftUI/UIKit attach/detach, which is main-thread).
    public func addObserver(_ observer: @escaping () -> Void) -> LBTemplateObserverToken {
        let token = LBTemplateObserverToken()
        observers.append(WidgetObserverEntry(token: token, observer: observer))
        return token
    }

    /// Remove a previously registered observer by its token (identity match). An
    /// unknown / already-removed token is a no-op. Main-thread contract mirrors
    /// `addObserver`.
    public func removeObserver(_ token: LBTemplateObserverToken) {
        observers.removeAll { $0.token === token }
    }

    init(widget: LiveBuyWidgetCore, sdkConfig: SDKConfig, hostOptions: LBUIOptions?) {
        self.widget = widget
        self.effectiveConfig = EffectiveConfig(sdkConfig: sdkConfig, hostOptions: hostOptions)
        self.content = DefaultWidgetContent(mode: widget.mode)
        // Fan the content view-model's internal `onMutation` into the single
        // host-facing `onChange` (main thread). Each refresh diffs and notifies at
        // most once, so onChange fires at most once per change (no redraw storm).
        content.onMutation = { [weak self] in self?.notifyChange() }
        // #3 — surface backend widget layout keys this template version doesn't recognise.
        DefaultLayoutKeys.logUnknown(scope: "widget", incoming: sdkConfig.layout?.widget)
        // Seed the snapshot from the widget's current state (carousel/grid start
        // empty; floating may already carry a live card). Idempotent — refresh
        // only mutates / notifies if the snapshot actually differs.
        refreshContent()
    }

    /// VIDEO_TAP — open Player fullscreen (Task 3.6)
    /// Creates a LiveBuyPlayerViewController and routes it through playerPresenter.
    func handleVideoTap(video: LBVideoItem) {
        guard let widget = widget else { return }
        let vc = LiveBuyPlayerViewController()
        vc.load(videoId: video.id)
        widget.playerPresenter?(vc)
    }

    /// Re-read the core `LiveBuyWidgetCore`'s current public state into the
    /// host-bindable content snapshot (INTERNAL data-feed — host does NOT call
    /// this; it stays internal per the spec's "內部接線不對 host 公開"). Driven by
    /// the attach wiring whenever core loadMore / floating-close / error settles
    /// widget state, and by the public `reload` / `requestLoadMore` intents below.
    /// Diffs internally, so repeated calls without a state change fire no onChange.
    func refreshContent() {
        guard let widget = widget else { return }
        content.refresh(from: widget)
    }

    /// Host intent: load the widget's first page (carousel / grid) through the
    /// core `LiveBuyWidgetCore.loadFirstPage()`, then mirror the result into the
    /// content snapshot. core `loadFirstPage` has NO completion callback, so this
    /// public intent is the host's hook to refresh `content` AFTER the first load
    /// completes (widget-content-template D2 / D7 — the template only consumes
    /// core; it never builds an HTTP request itself). A single first-load fires at
    /// most one onChange (diff-then-notify inside the snapshot). No-op (snapshot
    /// only refreshed) once the widget is gone.
    @MainActor
    public func reload() async {
        guard let widget = widget else { return }
        await widget.loadFirstPage()
        refreshContent()
    }

    /// Host intent: request the next page (grid only) through the core
    /// `LiveBuyWidgetCore.requestLoadMore()`, then mirror the result. core also fires
    /// `onLoadMore` on success (chained to `refreshContent` in the attach wiring),
    /// so the snapshot is up to date either way; this public passthrough lets a
    /// host trigger pagination from the content view-model (OQ1). No-op past the
    /// last page (core guards) and once the widget is gone.
    @MainActor
    public func requestLoadMore() async {
        guard let widget = widget else { return }
        await widget.requestLoadMore()
        refreshContent()
    }

    /// Dispatch the "widget content changed" notification on the main thread.
    /// Already-main-thread calls run synchronously; off-main calls are marshalled.
    ///
    /// Fires the legacy `onChange` (if set) FIRST, then every registered observer in
    /// registration order — all inside ONE main-thread hop (multi-observer registry,
    /// ios-widget-template-multi-observer-registry). Widget has NO coalescing batch
    /// (that `coalesceDepth` / `dispatchOnChange` split is player-only); the content
    /// view-model already diffs-then-notifies so each real change dispatches once.
    private func notifyChange() {
        // Capture the legacy callback and a SNAPSHOT copy of the observer list at
        // notify time. A callback that adds/removes an observer therefore affects
        // only the NEXT dispatch — never this one (no mutation-during-iteration
        // crash; matches the legacy `onChange`-captured-at-notify semantics).
        let legacy = onChange
        let observerSnapshot = observers.map { $0.observer }
        // Gate: skip the dispatcher entirely ONLY when there is nothing to notify
        // (no legacy onChange AND no registered observer). This preserves the prior
        // "onChange nil → don't touch the dispatcher" behaviour for the pure
        // no-observer case, while an observer-only registration still dispatches.
        guard legacy != nil || !observerSnapshot.isEmpty else { return }
        let fire = {
            legacy?()                                       // legacy first (fixed order)
            for observer in observerSnapshot { observer() } // then observers, in registration order
        }
        if Thread.isMainThread {
            fire()
        } else {
            DispatchQueue.main.async(execute: fire)
        }
    }

    // MARK: - Widget layout well-known keys (Task 3.8) — UNCHANGED (additive)

    var carouselEffect: String {
        effectiveConfig.widgetLayoutValue(key: "carousel_effect", default: "slide") as? String ?? "slide"
    }

    var carouselAutoPlay: Bool {
        effectiveConfig.widgetLayoutValue(key: "carousel_autoPlay", default: false) as? Bool ?? false
    }

    var gridColumns: Int {
        effectiveConfig.widgetLayoutValue(key: "grid_columns", default: 2) as? Int ?? 2
    }
}

// MARK: - EffectiveConfig snapshot (D6: read once at instantiate time)

struct EffectiveConfig {

    private let sdkConfig: SDKConfig
    private let hostOptions: LBUIOptions?

    init(sdkConfig: SDKConfig, hostOptions: LBUIOptions?) {
        self.sdkConfig = sdkConfig
        self.hostOptions = hostOptions
    }

    func layoutValue(key: String, default defaultValue: Any) -> Any {
        // templateDefaults always contains `key`, so the merge never returns nil
        // for a well-known key — the old `result == nil` log was dead code (D7).
        // Unknown-key detection now happens once at instantiate time via
        // DefaultLayoutKeys.logUnknown() in the template initializers.
        let result = ConfigMerger.effectiveLayoutValue(
            key: key,
            sdkMap: sdkConfig.layout?.player?.mapValues { $0.value },
            hostMap: hostOptions?.layoutPlayer,
            templateDefaults: [key: defaultValue]
        )
        return result ?? defaultValue
    }

    func widgetLayoutValue(key: String, default defaultValue: Any) -> Any {
        let result = ConfigMerger.effectiveLayoutValue(
            key: key,
            sdkMap: sdkConfig.layout?.widget?.mapValues { $0.value },
            hostMap: hostOptions?.layoutWidget,
            templateDefaults: [key: defaultValue]
        )
        return result ?? defaultValue
    }
}

// MARK: - Well-known layout keys (Task 3.1 / D7)

/// The layout keys each Default template understands. Keys the backend
/// (`sdkConfig.layout`) sends that are not in these sets are silently ignored
/// (no crash, other keys unaffected) but surfaced via a debug log as a hint.
enum DefaultLayoutKeys {
    static let player: Set<String> = ["productOverlay_position", "productOverlay_style"]
    static let widget: Set<String> = ["carousel_effect", "carousel_autoPlay", "grid_columns"]

    /// Diff the backend-sent layout map against the well-known set for `scope`
    /// and debug-log any unrecognised key. Silent ignore is preserved.
    static func logUnknown(scope: String, incoming: [String: AnyEquatable]?) {
        guard let incoming = incoming else { return }
        let known = scope == "widget" ? widget : player
        for key in incoming.keys where !known.contains(key) {
            lbuiDebugLog("[DefaultTemplate] unrecognized \(scope) layout key: \(key)")
        }
    }
}

// MARK: - Internal debug log

@inline(__always)
private func lbuiDebugLog(_ message: @autoclosure () -> String) {
#if DEBUG
    print(message())
#endif
}
