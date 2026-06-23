import ObjectiveC.runtime
import LiveBuySDK

// MARK: - livebuy-ui-event-wiring-template — iOS attach wiring
//
// This file turns `LiveBuyUI.install()` into a live wiring: when the core
// fires its template-agnostic `onInstantiate` hook for a Player / Widget, we
// instantiate the matching Default template handler and connect the SDK's
// events to it via **two routes** (design D1):
//
//   路 A — deprecated typed callbacks (full typed objects). `onProductTap` /
//          `onPollReceived` / `onStateChange` (Player) and `onVideoTap`
//          (Widget) carry the complete `LBProduct` / `LBPollResponse` /
//          `LBPlayerState` / `LBVideoItem` that the unified listener params
//          are too light to surface. These callbacks are the core's
//          "not-intercepted default behaviour" — using them does NOT shadow
//          the host's primary `setEventListener`.
//
//   路 B — `addEventListener` auxiliary listener (unified-listener-only
//          events). `DISMISS_REQUEST` / `WIN_RECEIVED` have no typed callback;
//          a `TemplateAuxListener` is attached via the core's auxiliary
//          listener API (event-dispatcher-multi-listener-core) so the template
//          receives them WITHOUT overwriting the host's primary listener.
//
// The same interaction MUST NOT be processed by both routes (productTap goes
// route A only; the aux listener ignores `PRODUCT_CLICK`).
//
// Lifecycle (design D2 / D5): the attachment + aux listener + removal token are
// held by a `TemplateAttachment` box bound to the instance via an associated
// object (OBJC_ASSOCIATION_RETAIN_NONATOMIC). When the instance deallocs, the
// associated object — and therefore the attachment — is released. The core
// hook closure weak-captures the instance and never retains the attachment, so
// there is no retain cycle.

// MARK: - Aux listener adapter (路 B)

/// Bridges the core's unified `LiveBuyEventListener` protocol to the Default
/// Player template's handlers for the unified-listener-only events
/// (`DISMISS_REQUEST` / `WIN_RECEIVED` / `AWARD_CLAIM_RESULT` / `AUTH_REQUIRED` /
/// `AUTH_STATE_CHANGED` / `AWAIT_GOODS_CHANGED` / `NOTICE_GOODS_CHANGED` /
/// `VIDEO_LIKE`). Held strongly by `TemplateAttachment`;
/// references the template weakly so it never extends the template's lifetime.
final class TemplateAuxListener: NSObject, LiveBuyEventListener {

    private weak var template: DefaultPlayerTemplate?

    /// Test-visible counter: how many `WIN_RECEIVED` events this aux listener
    /// has observed. WIN_RECEIVED UI behaviour belongs to a later change (§5.1);
    /// this pilot only proves the aux route delivers the event.
    private(set) var winReceivedCount: Int = 0

    init(template: DefaultPlayerTemplate) {
        self.template = template
    }

    func onEventTriggered(
        eventName: String,
        params: [String: Any],
        cartCallback: LBCartResultCallback?,
        shareContext: LBShareContext?
    ) -> Bool {
        switch eventName {
        case LBEvent.dismissRequest:
            // Template performs the platform-native dismiss. The aux listener is
            // a NON-primary listener; returning false keeps the core's default
            // dismiss semantics intact (the template already executed dismiss).
            template?.handleDismissRequest()
            return false
        case LBEvent.winReceived:
            // Reconstruct the winner from the 6-field payload → merged feed (tier
            // = win) + INDEPENDENT unclaimed entry set (§1 / §2). Non-primary:
            // returns false so the host's primary listener still sees the event.
            winReceivedCount += 1
            if let winner = Self.winner(from: params) {
                template?.handleWin(text: winner.title, winner: winner)
            }
            return false
        case LBEvent.awardClaimResult:
            // Notify event → win-claim result-state model (§4). `.claimed`
            // decrements the unclaimed count for the in-flight winner.
            template?.handleAwardClaimResult(
                status: Self.claimStatus(from: params),
                awardType: params["award_type"] as? String ?? "",
                awardCode: params["award_code"] as? String)
            return false
        case LBEvent.authRequired:
            // SYNC_INTERCEPTOR: the core's EventDispatcher calls the host's PRIMARY
            // listener FIRST and only iterates aux listeners when it was NOT
            // intercepted. So merely RECEIVING AUTH_REQUIRED here PROVES the host's
            // primary did NOT intercept (host-takeover exclusion is the dispatcher
            // gate, not re-judged in the template). Pass hostIntercepted = false;
            // returning false below keeps core interception / PendingAuthStore /
            // 30s replay / auto-PiP untouched (the aux listener is NON-primary).
            template?.handleAuthRequired(params: params, hostIntercepted: false)
            return false
        case LBEvent.authStateChanged:
            // Notification event → update identity-label and clear auth-gate on
            // logged_in. Non-primary: return false (the value is ignored for
            // notification dispatch; the host's primary still sees the event).
            template?.handleAuthStateChanged(params: params)
            return false
        case LBEvent.awaitGoodsChanged:
            // Authoritative 到貨追蹤 broadcast → correct the await flag for the
            // product. Non-primary: return false (the host's primary still sees it).
            if let gpn = params["goods_gpn"] as? String {
                template?.handleAwaitGoodsChanged(goodsGpn: gpn, enabled: params["enabled"] as? Bool ?? false)
            }
            return false
        case LBEvent.noticeGoodsChanged:
            // Authoritative 補貨通知 broadcast → correct the notice flag.
            if let gpn = params["goods_gpn"] as? String {
                template?.handleNoticeGoodsChanged(goodsGpn: gpn, enabled: params["enabled"] as? Bool ?? false)
            }
            return false
        case LBEvent.videoLike:
            // VIDEO_LIKE — the like API actually SUCCEEDED (core dispatches this
            // notification only on success, with snake_case `video_id`; no typed
            // `onLikePerformed` callback exists, so route-B is the heart-burst
            // source per player-chrome-template D6 / R5). Bump the monotonic burst
            // tick → host plays the heart-burst animation. Non-primary: returns
            // false so the host's primary listener still sees the event.
            template?.handleLikePerformed()
            return false
        case LBEvent.videoSwitch:
            // VIDEO_SWITCH — core dispatched a real video change (only fired when the
            // previous video id existed AND differs from the new one; first-load /
            // same-video retry never reach here). Reset the per-video-session family-2
            // overlay so the next video starts CLEAN: clear the merged activity + chat
            // feed AND the win-claim entry. VIDEO_SWITCH is a NOTIFICATION event, so the
            // dispatcher fires it to the primary listener AND every aux listener — the
            // reset is guaranteed regardless of host interception. Non-primary: returns
            // false so the host's primary listener still sees the switch.
            template?.handleVideoSwitch()
            return false
        default:
            // PRODUCT_CLICK and every other event are handled by route A or by
            // the host's primary listener — never double-process here.
            return false
        }
    }

    // MARK: - Param decoding helpers (pure)

    /// Rebuild an `LBWinner` from the WIN_RECEIVED 5-field payload
    /// (`id` / `event_id` / `title` / `award_type` / `award_name` / `award_code`).
    /// Returns nil when `id` is missing (defensive; the core always sends it).
    static func winner(from params: [String: Any]) -> LBWinner? {
        guard let id = params["id"] as? String else { return nil }
        let award = LBAward(
            type: params["award_type"] as? String ?? "product",
            code: params["award_code"] as? String ?? "",
            name: params["award_name"] as? String ?? "")
        return LBWinner(id: id,
                        eventId: params["event_id"] as? Int ?? 0,
                        title: params["title"] as? String ?? "",
                        award: award)
    }

    /// Map the AWARD_CLAIM_RESULT `status` wire string back to `LBAwardClaimStatus`
    /// (`"claimed"` / `"failed"` / `"unknown_<code>"`). Unknown / unparseable
    /// strings fall back to `.failed` (treated as failure per spec).
    static func claimStatus(from params: [String: Any]) -> LBAwardClaimStatus {
        switch params["status"] as? String {
        case "claimed": return .claimed
        case "failed":  return .failed
        case let s?:
            let code = Int(s.replacingOccurrences(of: "unknown_", with: ""))
            return code.map { .unknown($0) } ?? .failed
        default:        return .failed
        }
    }
}

// MARK: - Attachment box (lifecycle holder)

/// Strong holder for one attached instance's template + aux listener + removal
/// token. Bound to the instance via an associated object so its lifetime tracks
/// the instance's.
final class TemplateAttachment {

    let playerTemplate: DefaultPlayerTemplate?
    let widgetTemplate: DefaultWidgetTemplate?
    let auxListener: TemplateAuxListener?
    private let token: LBListenerToken?
    private weak var dispatcherOwnerPlayer: LiveBuyPlayerViewController?

    init(playerTemplate: DefaultPlayerTemplate,
         auxListener: TemplateAuxListener,
         token: LBListenerToken,
         player: LiveBuyPlayerViewController) {
        self.playerTemplate = playerTemplate
        self.widgetTemplate = nil
        self.auxListener = auxListener
        self.token = token
        self.dispatcherOwnerPlayer = player
    }

    init(widgetTemplate: DefaultWidgetTemplate) {
        self.playerTemplate = nil
        self.widgetTemplate = widgetTemplate
        self.auxListener = nil
        self.token = nil
        self.dispatcherOwnerPlayer = nil
    }

    deinit {
        // Detach the aux listener so the (process-level) dispatcher registry
        // does not keep a dead weak box around. The core holds the listener
        // weakly, but removing the token is the tidy, explicit teardown.
        if let token = token {
            dispatcherOwnerPlayer?.removeEventListener(token)
        }
    }
}

// MARK: - Associated-object binding

private enum AssociatedKeys {
    static var attachment: UInt8 = 0
}

extension TemplateAttachment {

    /// Bind this attachment to `instance` so it lives exactly as long as the
    /// instance (design D2). RETAIN_NONATOMIC: the instance strongly holds the
    /// attachment; the attachment only weak/aux-references back.
    static func bind(_ attachment: TemplateAttachment, to instance: AnyObject) {
        objc_setAssociatedObject(instance, &AssociatedKeys.attachment,
                                 attachment, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    /// Read the attachment bound to `instance`, if any. Used by tests to assert
    /// attach happened (and to assert it did NOT after `uninstall()`).
    static func bound(to instance: AnyObject) -> TemplateAttachment? {
        objc_getAssociatedObject(instance, &AssociatedKeys.attachment) as? TemplateAttachment
    }
}

// MARK: - Attach entry points (called from LiveBuyUI.install's hook)

enum TemplateWiring {

    /// Resolve the effective SDKConfig once at attach time (ui-template-config-merge).
    /// Falls back to an all-nil `SDKConfig()` when the SDK is not yet configured
    /// (e.g. unit tests that create a bare instance) so attach never crashes.
    private static func effectiveSDKConfig() -> SDKConfig {
        (try? LiveBuy.sdkConfig()) ?? SDKConfig()
    }

    /// Attach a Default Player template to `vc` and wire both routes.
    static func attachPlayer(_ vc: LiveBuyPlayerViewController) {
        // guestNameEditRequester forwards the template's `requestGuestNameEdit()`
        // to the core public `Player.requestGuestNameEdit()` exit (emit
        // `GUEST_NAME_EDIT_REQUEST`, passthrough / non-navigation / no auto-PiP).
        let template = DefaultPlayerTemplate(
            player: vc,
            sdkConfig: effectiveSDKConfig(),
            hostOptions: LiveBuyUI.hostOptions,
            // Forward to the core public guest-name-edit exit (weak-capture vc,
            // parity with onProductTap/onError below — no retain cycle).
            guestNameEditRequester: { [weak vc] in vc?.requestGuestNameEdit() },
            // Forward the cart CTA「openCart」to the core public `requestViewCart`
            // exit (emit `VIEW_CART`, notification / non-navigation / no auto-PiP).
            // productId carried from the template's current product detail.
            viewCartRequester: { [weak vc] productId in vc?.requestViewCart(productId: productId) },
            // goods-tracking toggles delegate to the core public async endpoints
            // (headless: the template never builds an HTTP request itself). The
            // authoritative `AWAIT/NOTICE_GOODS_CHANGED` broadcasts correct the
            // optimistic flags via the aux listener above.
            setAwaitGoods: { gpn, enabled in
                Task { try? await LiveBuy.setAwaitGoods(goodsGpn: gpn, enabled: enabled) }
            },
            setNoticeGoods: { gpn, enabled in
                Task { try? await LiveBuy.setNoticeGoods(goodsGpn: gpn, enabled: enabled) }
            },
            // add-to-cart (product-sheet-stack-template, route-B) delegates to the
            // core public async `LiveBuy.addToCart(...)` — the template never builds
            // an HTTP request itself (headless write contract, same pattern as the
            // goods-tracking toggles above). `shop_id` / `guest_id` / login token /
            // `lang` are injected by core; `source` is overridden server-side. The
            // template only assembles goods_id / num / specification_id from the
            // current product-detail + variant + qty selection. Host-takeover (route
            // A) is excluded upstream — this requester is only invoked from the
            // not-intercepted `productTap` → detail-sheet path.
            addToCartRequester: { request in
                try await LiveBuy.addToCart(
                    shopId: request.shopId,
                    goodsId: Int(request.goodsId),
                    num: request.num,
                    specificationId: request.specificationId.flatMap { Int($0) },
                    videoId: request.videoId)
            }
        )

        // 路 A — full typed objects via deprecated typed callbacks. These are
        // the core's "not intercepted" default behaviour; they do NOT shadow
        // the host's unified listener. weak-capture both sides (D2).
        vc.onProductTap = { [weak template, weak vc] product in
            template?.handleProductTap(product: product,
                                       diversion: vc?.channel?.diversion ?? 0)
        }
        vc.onPollReceived = { [weak template] response in
            guard let template = template else { return }
            template.handlePollReceived(response)
            // Derive the merged feed (§1) + live-end from the full response —
            // these are NOT separate typed callbacks. join = user[], purchase =
            // rush[], chat/event-join = push[]. Win (with award detail) arrives
            // via route-B WIN_RECEIVED, not here (`win[]` is the broadcast bucket).
            // `handlePush` splits event-begin pushes into event-join feed items.
            //
            // backlog gate（chat-history-dedupe-template）：以 core 的 `isBacklogReplay` cursor 訊號
            // + per-session 旗標分流 feed ingestion——後續輪真實新訊息（含後台刻意重送）一律灌、首輪
            // backlog 首次灌當歷史首屏、已 ingest 過的 backlog 重放整批 skip（換片漏 clear / 重入疊加）。
            // `handlePollReceived`（header / pinned 等）維持每輪呼叫（冪等，不受 gate 影響）。
            if template.shouldIngestPoll(response.isBacklogReplay) {
                for push in response.push { template.handlePush(push) }
                for user in response.user { template.handleJoin(text: user.text) }
                for rush in response.rush { template.handlePurchase(text: rush.text) }
            }
            if response.liveEnd == 1 { template.handleLiveEnd() }
        }
        vc.onStateChange = { [weak template] state in
            // Align to the canonical VIDEO_STATE_CHANGE `state` naming. Also
            // drives error-state clearing when the player leaves `error`.
            template?.handlePlayerStateChange(state: state.canonicalName)
        }
        vc.onError = { [weak template] error in
            // core `error(LBError)` → host-bindable error-state for LBPErrorScreen.
            template?.handleError(error)
        }
        // NEW moment-state surface (expose-player-moment-state-core) → the five
        // moment view-models (EndScreen / ProductOverlay / PlayerHeader /
        // SubtitleTrack). StartScreen phase is driven by onStateChange above.
        // weak-capture (no retain cycle, parity with onError/onStateChange).
        vc.onMomentStateChange = { [weak template] state in
            template?.handleMomentState(state)
        }
        // VOD playback progress (dedicated channel, VOD-2) → the progress view-model
        // that drives the VOD chrome. weak-capture (parity with onMomentStateChange).
        vc.onPlaybackProgressChange = { [weak template] progress in
            template?.handlePlaybackProgress(progress)
        }
        // Live channel-settings refresh (core-live-guest-comment-refresh) → re-ingest the
        // freshly-fetched channel so mid-stream `guest_comment` (chatEnabled) changes apply
        // WITHOUT the user re-entering the player. `ingestChannel` is a pure view-model
        // re-derivation (header / rail enablement / nav) — it does NOT restart playback.
        // weak-capture (parity with onPlaybackProgressChange).
        vc.onChannelRefresh = { [weak template] channel in
            template?.ingestChannel(channel)
        }
        // Seed the PlayerHeader mute flag = false (unmuted by default / sound on,
        // matching the core engines' default-unmuted main playback). momentState
        // carries no `muted`; the tap-to-unmute gesture / host toggle subsequent
        // flips via setMuted/toggleMute.
        template.handleMuted(false)

        // 路 B — unified-listener-only events via an auxiliary listener that
        // COEXISTS with the host's primary `setEventListener` (does not shadow).
        let auxListener = TemplateAuxListener(template: template)
        let token = vc.addEventListener(auxListener)

        let attachment = TemplateAttachment(
            playerTemplate: template,
            auxListener: auxListener,
            token: token,
            player: vc
        )
        TemplateAttachment.bind(attachment, to: vc)
    }

    /// Attach a Default Widget template to `widget` (路 A only — Widget's
    /// unified-listener-only events are out of scope for this pilot).
    ///
    /// widget-content-template: the template's `content` view-model MIRRORS core
    /// `LiveBuyWidgetCore`'s existing public read-only state. core load completion has
    /// no callback, but `onLoadMore` / `onError` fire after a fetch settles and
    /// `onClose` after a floating close, so each core callback re-reads core into
    /// the snapshot (`refreshContent`). The first `refresh` happens inside the
    /// template's init (seed). All closures weak-capture the template (no retain
    /// cycle, parity with `vcOnVideoTap`).
    static func attachWidget(_ widget: LiveBuyWidgetCore) {
        let template = DefaultWidgetTemplate(
            widget: widget,
            sdkConfig: effectiveSDKConfig(),
            hostOptions: LiveBuyUI.hostOptions
        )
        vcOnVideoTap(widget, template)
        wireWidgetContentRefresh(widget, template)
        let attachment = TemplateAttachment(widgetTemplate: template)
        TemplateAttachment.bind(attachment, to: widget)
    }

    private static func vcOnVideoTap(_ widget: LiveBuyWidgetCore,
                                     _ template: DefaultWidgetTemplate) {
        widget.onVideoTap = { [weak template] video in
            template?.handleVideoTap(video: video)
        }
    }

    /// Chain the existing core callbacks so each state-settling event re-reads
    /// core into the content snapshot (widget-content-template D2 / D7 native
    /// wiring). PRESERVES any host-set callback by invoking it first, then
    /// refreshing (host callbacks remain functional — additive). `onLoadMore`
    /// fires after a successful grid loadMore (page advance + videos appended);
    /// `onError` after a failed fetch (state may be unchanged → diff no-ops);
    /// `onClose` after a floating close (`isClosed == true` → `minimized`).
    private static func wireWidgetContentRefresh(_ widget: LiveBuyWidgetCore,
                                                 _ template: DefaultWidgetTemplate) {
        let priorLoadMore = widget.onLoadMore
        widget.onLoadMore = { [weak template] page in
            priorLoadMore?(page)
            template?.refreshContent()
        }
        let priorError = widget.onError
        widget.onError = { [weak template] error in
            priorError?(error)
            template?.refreshContent()
        }
        let priorClose = widget.onClose
        widget.onClose = { [weak template] in
            priorClose?()
            template?.refreshContent()
        }
    }
}
