import SafariServices
import UIKit
import LiveBuySDK

/// In-app browser opener (Task 2.1 / 2.5). Injectable so unit tests can verify
/// the diversion path with a fake opener without a live UIKit hierarchy.
typealias InAppBrowserOpener = (URL) -> Void

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

    /// 「請選規格」guard flag — set true when `addToCart()` is called with an
    /// incomplete spec selection (D5 guard); cleared when a valid add is attempted
    /// or a new product detail opens. Lets the host prompt the user.
    private(set) public var needsVariantSelection: Bool = false

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

    init(
        player: LiveBuyPlayerViewController,
        sdkConfig: SDKConfig,
        hostOptions: LBUIOptions?,
        openInAppBrowser: InAppBrowserOpener? = nil,
        guestNameEditRequester: (() -> Void)? = nil,
        setAwaitGoods: ((String, Bool) -> Void)? = nil,
        setNoticeGoods: ((String, Bool) -> Void)? = nil,
        addToCartRequester: ((LBCartRequest) async throws -> LBCartResult)? = nil
    ) {
        self.player = player
        self.effectiveConfig = EffectiveConfig(sdkConfig: sdkConfig, hostOptions: hostOptions)
        self.guestNameEditRequester = guestNameEditRequester
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
        // #3 — surface backend layout keys this template version doesn't recognise.
        DefaultLayoutKeys.logUnknown(scope: "player", incoming: sdkConfig.layout?.player)
        // Coalesce every feed / win-claim mutation into ONE host-facing onChange
        // (main thread). Each model fires onMutation exactly once per state
        // change, so onChange fires exactly once per change (no redraw storm).
        wireChangeNotification()
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
        guard let onChange = onChange else { return }
        if Thread.isMainThread {
            onChange()
        } else {
            DispatchQueue.main.async { onChange() }
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

    /// Feed the public `channel` into the top-bar chrome (D3), info-tab fields
    /// (D4) and side-rail conditional enablement (D2). Internal so unit tests can
    /// drive it with a fabricated `LBChannel` without a live load. Coalesced so a
    /// single channel ingest fires at most one onChange.
    func ingestChannel(_ ch: LBChannel) {
        coalescing {
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
            // Prev/next adjacent video targets (swipe-navigate-template) — read the
            // first item id of each nav array (LBNavItem.id). Diff-then-notify inside
            // this same coalescing batch, so a channel ingest still fires at most one
            // onChange.
            navigation.ingest(prevVideoId: ch.prev.first?.id, nextVideoId: ch.next.first?.id)
        }
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
                                   remain: s.autoNextRemainingSeconds)
            productOverlay.handleProducts(s.products, active: s.narratingProduct)
            header.handleHeader(isSubscribed: s.isSubscribed, viewerCount: s.viewerCount)
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
            // mini-cart fallback peek = the narrating product, ONLY when there is
            // no peek yet (a successful add wins — non-clobbering, D4). Keeps the
            // mini-cart populated with 講解中商品 before the first add.
            if let active = s.narratingProduct {
                miniCart.seedFallback(LBMiniCartPeek(productId: active.id, name: active.name,
                                                     priceShow: active.priceShow, soldOut: active.soldOut))
            }
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
    // triggers, it does NOT bump the tick (no double animation). System-UI for
    // share / serviceLink (share sheet / in-app browser) is presented by the host on
    // the not-intercepted `videoShareRequest` / `serviceLinkRequest` event (TK-4).

    /// Like (❤️) — forwards to the throttled core exit.
    public func performLike() { player?.performLike() }
    /// Share — forwards to core (emits interceptable `videoShareRequest`).
    public func performShare() { player?.performShare() }
    /// Toggle subtitles (CC) — forwards to the gated core exit.
    public func toggleSubtitle() { player?.performSubtitleToggle() }
    /// Open the shop service link — forwards to core (emits interceptable `serviceLinkRequest`).
    public func openServiceLink() { player?.performServiceLink() }
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
        // Reset the transient flags for this attempt.
        addToCartFailed = false
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
        let request = LBCartRequest(
            shopId: player?.channel?.shop.id ?? "",
            goodsId: detail.productId,
            num: qtyStepper.qty,
            specificationId: variantPicker.selectedSpecificationId)
        let peek = LBMiniCartPeek(productId: detail.productId, name: detail.name,
                                  priceShow: detail.priceShow, soldOut: detail.soldOut)
        // Capture the requester before the Task so the closure stays self-contained.
        let requester = addToCartRequester
        Task { [weak self] in
            do {
                _ = try await requester(request)
                await MainActor.run { [weak self] in self?.applyAddSuccess(peek: peek) }
            } catch {
                await MainActor.run { [weak self] in self?.applyAddFailure() }
            }
        }
    }

    /// Success branch (main thread): mini-cart peek + cart CTA count → ONE coalesced
    /// onChange (D6 — single add success = single notification).
    private func applyAddSuccess(peek: LBMiniCartPeek) {
        coalescing {
            miniCart.setPeek(peek)
            cartCTA.incrementOnAdd()
        }
    }

    /// Failure branch (main thread): expose the add-failed flag, count unchanged.
    private func applyAddFailure() {
        addToCartFailed = true
        notifyChange()
    }

    /// Host intent to re-zero the per-session cart count (OQ2 — on release /
    /// new-video). Exposed so the wiring / host can reset between videos.
    public func resetCartForSession() {
        cartCTA.resetForSession()
    }

    /// POLL_RECEIVED (Task 3.4) — headless; host provides poll UI
    func handlePollReceived(_ poll: LBPollResponse) {}

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
    /// activity rows are NOT written into the ChatView chat data source.
    func handleChat(text: String) {
        activityFeed.appendChat(text: text)
    }

    /// A poll `push[]` row → merged feed. A core event-BEGIN push
    /// (`push.isEventBegin`) is surfaced as an INDEPENDENT event-join item (host
    /// draws `LBEventJoinLine`); everything else — including event-END
    /// (`isEventEnd`) and ordinary pushes — stays a plain `.chat` row.
    func handlePush(_ push: LBPushMsg) {
        if push.isEventBegin {
            activityFeed.appendEventJoin(eid: push.eid ?? 0, keyword: push.ek ?? "", text: push.text)
        } else if push.color == DefaultTemplateConstants.productPushColor {
            // 商品推播 (`#66F796`, e.g.「商品開賣 / 開始介紹」) → the dedicated `intro` activity
            // row (喇叭 + accent 暈染). The `push[]` bucket has no stable id, so a backend re-send
            // on an adjacent poll would duplicate it — `appendIntro` routes through the same DE-DUPED
            // activity path so it shows once.
            activityFeed.appendIntro(text: push.text)
        } else if Self.isSystemNoticePush(push) {
            // Remaining system notice (event-end `eid>0` / promo `ct` / `p`) — DE-DUPED chat row so
            // a re-send shows once. Free user chat (below) stays un-deduped.
            activityFeed.appendSystemNotice(text: push.text)
        } else {
            activityFeed.appendChat(text: push.text)
        }
    }

    /// Whether a (non-event-begin, non-product-push) `push[]` row is a SYSTEM / 事件 / 促銷 notice
    /// rather than free user chat — used to route it through the DE-DUPED `appendSystemNotice` path.
    /// A notice is flagged by event metadata (`eid > 0`, e.g. event-end / event-tied) OR promo
    /// metadata (`ct` / `p`). NOTE: the product-push color (`productPushColor`, spec §PollManager
    /// fan-out) is handled BEFORE this check in `handlePush` (→ `intro` activity row), so it is NOT
    /// part of this predicate. Ordinary user chat carries none of these, so it stays un-deduped.
    /// Pure / testable.
    static func isSystemNoticePush(_ push: LBPushMsg) -> Bool {
        (push.eid ?? 0) > 0
            || !(push.ct ?? "").isEmpty
            || !(push.p ?? "").isEmpty
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

    /// `VIDEO_SWITCH` (notification) → reset the per-video-session family-2 overlay so
    /// the next video starts from a CLEAN feed / win entry. Clears the merged activity +
    /// chat feed AND the win-claim unclaimed entry / result state, symmetric with core's
    /// `resetPerSessionState()` (which clears `notifiedWinnerIds` etc.). Coalesced into a
    /// single host-facing `onChange`. core only dispatches `VIDEO_SWITCH` when the previous
    /// video id exists AND differs from the new one, so first-load and same-video retry /
    /// buffering NEVER reach here (no false clears). Headless — clears data only.
    func handleVideoSwitch() {
        coalescing {
            activityFeed.clear()
            winClaim.clear()
        }
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

    /// Dispatch `onChange` on the main thread. Already-main-thread calls run
    /// synchronously; off-main calls are marshalled. Purely additive — a nil
    /// `onChange` is a no-op.
    private func notifyChange() {
        guard let onChange = onChange else { return }
        if Thread.isMainThread {
            onChange()
        } else {
            DispatchQueue.main.async { onChange() }
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
