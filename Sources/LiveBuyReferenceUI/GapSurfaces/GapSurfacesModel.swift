import SwiftUI
import Combine
import LiveBuySDK
import LiveBuyUI

// MARK: - GapSurfacesModel — family-6 gap-surfaces observable snapshot bridge
//
// Spec: `reference-ui-rendering/spec.md` (family-6 gap-surfaces — the LAST iOS
//        Phase-1 family closing out the four "gap" surfaces).
// Design: rb-ios-gap-surfaces design.md §"容器與 view-model 橋接" + §"守住的不變式".
//
// This is the SKELETON for rb-ios-gap-surfaces. It bridges the headless template
// view-models exposed by `DefaultPlayerTemplate` (obtained via
// `LiveBuyUI.playerTemplate(for:)`) into a SwiftUI-observable snapshot that the
// four family-6 gap-surface sub-views read. It is a read-only mirror — IDENTICAL
// pattern to `PlayerShellModel` (family-1) / `FeedWinModel` (family-2) /
// `ProductSheetsModel` (family-3) / `MomentsModel` (family-4):
//
//   - It holds NO second copy of authoritative state. Unlike the prior families,
//     which republish into `@Published` mirrors, the family-6 surfaces are driven
//     by COMPUTED GETTERS that READ the bound template each time (so a single
//     coalesced `onChange` → `objectWillChange.send()` repaints the container and
//     the getters re-read fresh values). This keeps the auth-gate / identity-label /
//     goods-tracking / notice-tab state's SINGLE SOURCE OF TRUTH inside the template
//     (design §"守住的不變式": 只讀呈現, 不持第二份 state).
//   - It does NOT add pixels and it does NOT add any accessor to `LiveBuyUI`
//     (that would be a template-layer concern, out of scope here).
//   - It does NOT subscribe to each model's internal `onMutation` (that is a
//     template-internal hook); it observes ONLY the template's single public
//     `onChange` (design §"容器與 view-model 橋接").
//   - The mutating interactions this layer drives are thin forwarders to the
//     EXISTING public template exits — they live on the CONTAINER
//     (`GapSurfacesOverlayView`), which reaches the template via these getters /
//     the bound template (`authGate.clear()` / `goodsTracking.toggleAwait` /
//     `goodsTracking.toggleNotice` / `noticeTab.openNoticeTab` /
//     `noticeTab.closeNoticeTab` / `requestGuestNameEdit()`). reference-ui NEVER
//     calls core directly — every write routes through an existing public template
//     exit.
//
// iOS-14-safe: `ObservableObject` + `objectWillChange` are available from iOS 13,
// so no `@available` guard is needed here.

/// Observable read-only bridge over the family-6 gap-surface state, backed by a
/// live `DefaultPlayerTemplate`. Holds NO copy of state — every getter reads the
/// bound template each call; the container repaints when the template fires its
/// single coalesced `onChange`. A demo instance (no bound template) returns the
/// freshly-constructed template defaults (auth-gate nil / identity nil / notice
/// closed / no goods flags) so previews and snapshot tests stay deterministic.
public final class GapSurfacesModel: ObservableObject {

    // MARK: - Live binding

    /// The bound template, when constructed from a live player. nil for demo /
    /// snapshot instances. Held weakly so this model never retains the template
    /// (the player VC owns it; dependency stays one-way UI → core).
    private weak var template: DefaultPlayerTemplate?

    /// The independent observer registration token this model holds. Removed on
    /// deinit so this model unsubscribes ONLY itself — never clobbers another
    /// model's subscription (multi-observer registry, same as the family-1/2/3/4 models).
    private var observerToken: LBTemplateObserverToken?

    // MARK: - Live initializer (design §"容器與 view-model 橋接")

    /// Bridge a live `DefaultPlayerTemplate`: register an observer on its single
    /// coalesced change notification so every auth-gate set/clear, identity-label
    /// update, goods-tracking flag flip / broadcast correction, or notice-tab
    /// open/close triggers an `objectWillChange.send()` — the SwiftUI container then
    /// re-reads the computed getters (which read the template directly). No snapshot
    /// is stored.
    ///
    /// The host obtains the template via `LiveBuyUI.playerTemplate(for:)` and
    /// passes it here. This registers an INDEPENDENT observer via `addObserver`; it
    /// does NOT chain or replace the template's legacy `onChange`.
    public init(template: DefaultPlayerTemplate) {
        self.template = template
        self.observerToken = template.addObserver { [weak self] in
            // Read-only bridge: there is no stored mirror to refresh — just tell
            // SwiftUI to re-render so the computed getters re-read the template.
            self?.objectWillChange.send()
        }
    }

    /// Construct a deterministic instance WITHOUT a live player — for the gap-surface
    /// sub-views' previews and the per-surface snapshot tests. With no bound template
    /// every getter returns the freshly-constructed template default (auth-gate nil,
    /// identity nil → not logged in / empty name, notice closed / un-openable, all
    /// goods flags off), so a zero-argument call yields a stable baseline.
    public init() {
        self.template = nil
    }

    deinit {
        // Remove ONLY this model's own observer so a re-bound template is not left
        // with a dangling closure capturing this (now gone) model — other models'
        // subscriptions are untouched (no chain to restore, no clobber).
        if let token = observerToken { template?.removeObserver(token) }
    }

    // MARK: - Surface 1: AuthGateModalView ←「請先登入」auth-gate (auth-gate-template-state)
    //
    // The auth-gate modal is shown ONLY when there is a pending un-intercepted
    // `AUTH_REQUIRED` AND the user is NOT already logged in (a late `logged_in`
    // clears the prompt via the template; this guard is belt-and-braces). The modal
    // copy is chosen per `triggerAction` (cartAdd / commentSend / couponClaim /
    // other) — the surface picks the copy, this layer only surfaces the category.

    /// The trigger category behind the pending「請先登入」prompt, or nil when none.
    /// Reads `template.authGate.current?.triggerAction` each call (no stored copy).
    public var authGateTriggerAction: LBAuthTriggerAction? {
        template?.authGate.current?.triggerAction
    }

    /// Whether the auth-gate modal should be presented: a pending un-intercepted
    /// `AUTH_REQUIRED` exists AND the user is not already logged in.
    public var authGateVisible: Bool {
        guard let template = template, template.authGate.current != nil else { return false }
        return !(template.identityLabel.current?.isLoggedIn ?? false)
    }

    // MARK: - Surface 4: GuestNameEditModalView ← identity-label (auth-gate-template-state)
    //
    // The guest-name-edit surface reads the identity label to show the current
    // display name + whether the user is logged in (a logged-in user does not need
    // the guest rename affordance). The actual rename happens via the host /
    // `LiveBuySDK.setUser`; this layer only forwards the「請求改名」intent through
    // the template's `requestGuestNameEdit()` exit.

    /// Current display name (`template.identityLabel.current?.displayName`),
    /// "" until the first `AUTH_STATE_CHANGED` or for demo instances.
    public var displayName: String {
        template?.identityLabel.current?.displayName ?? ""
    }

    /// Whether the user is logged in (`template.identityLabel.current?.isLoggedIn`),
    /// false until the first `AUTH_STATE_CHANGED` or for demo instances.
    public var isLoggedIn: Bool {
        template?.identityLabel.current?.isLoggedIn ?? false
    }

    // MARK: - Retained notice-tab bridge (read-only)
    //
    // POST-RECONCILE (design 2026-06-06): the standalone family-6 notice panel was
    // removed; 公告 content is now rendered by the family-1 VideoInfoPanel 公告 tab
    // (via PlayerShellModel). These read-only mirrors of the template's `noticeTab`
    // open-state are retained for host use; no family-6 view consumes them now.
    // `canOpen` is template-derived (either text non-empty); `isOpen` host-toggled
    // via `openNoticeTab` / `closeNoticeTab`; texts come from the channel via the
    // template — this layer reads them, never injects.

    /// Whether the notice panel may open at all — `template.noticeTab.canOpen`
    /// (derived: either text non-empty). false for demo instances.
    public var noticeCanOpen: Bool {
        template?.noticeTab.canOpen ?? false
    }

    /// Whether the notice panel is currently expanded — `template.noticeTab.isOpen`.
    /// false for demo instances.
    public var noticeIsOpen: Bool {
        template?.noticeTab.isOpen ?? false
    }

    /// System notice text (`sys_notice`) — `template.noticeTab.systemNotice`.
    /// "" for demo instances.
    public var systemNotice: String {
        template?.noticeTab.systemNotice ?? ""
    }

    /// Shop / video notice text (`notice`) — `template.noticeTab.notice`.
    /// "" for demo instances.
    public var notice: String {
        template?.noticeTab.notice ?? ""
    }

    // MARK: - Retained goods-tracking bridge (read-only)
    //
    // POST-RECONCILE (design 2026-06-06): the standalone family-6 dual-switch sheet
    // was removed; 到貨追蹤 (await type=1) is now the family-3 商品明細 收藏 toggle and
    // 補貨通知 (notice type=2) the family-3 售完補貨通知 sheet. These read-only mirrors
    // of `template.goodsTracking` (both flags INDEPENDENT, keyed by `goodsGpn`) are
    // retained for host use; no family-6 view consumes them now.

    /// Read the 到貨追蹤 (await, type=1) flag for `goodsGpn` — delegates to
    /// `template.goodsTracking.awaitEnabled(for:)`. false for demo instances.
    public func awaitEnabled(for goodsGpn: String) -> Bool {
        template?.goodsTracking.awaitEnabled(for: goodsGpn) ?? false
    }

    /// Read the 補貨通知 (notice, type=2) flag for `goodsGpn` — delegates to
    /// `template.goodsTracking.noticeEnabled(for:)`. false for demo instances.
    public func noticeEnabled(for goodsGpn: String) -> Bool {
        template?.goodsTracking.noticeEnabled(for: goodsGpn) ?? false
    }

    // MARK: - Read-only host intents (pass-through to the bound template)
    //
    // Thin forwarders for the template-owned gap-surface intents the family-6
    // surfaces drive. Each is a no-op for demo instances (no bound template). Each
    // routes through an EXISTING public template / model exit (design §範圍與不變式) —
    // reference-ui NEVER calls core directly:
    //
    //   • dismissAuthGate → `DefaultAuthGate.clear()`
    //   • toggleAwait / toggleNotice → `DefaultGoodsTracking.toggleAwait/toggleNotice`
    //   • openNoticeTab / closeNoticeTab → `DefaultNoticeTab.openNoticeTab/closeNoticeTab`
    //   • requestGuestNameEdit → `DefaultPlayerTemplate.requestGuestNameEdit()`
    //
    // NOTE — the auth-gate「登入」CTA is NOT a template forwarder. Performing the
    // login is the HOST's job (host wires its own login flow + calls
    // `LiveBuySDK.setUser`); the surface funnels「登入」to a host-wired closure on the
    // CONTAINER (`GapSurfacesOverlayView.onRequestLogin`), never through this model
    // (mirrors family-3 `ProductListView`'s host-wired product-tap exit). Likewise
    // the guest-name SUBMIT (the actual new name) is host-fulfilled via
    // `LiveBuySDK.setUser` on a CONTAINER closure; this model only forwards the
    // passthrough「請求改名」intent.

    /// Forward an auth-gate dismiss → `DefaultAuthGate.clear()`. No-op for demo.
    public func dismissAuthGate() {
        template?.authGate.clear()
    }

    /// Forward a 到貨追蹤 toggle → `DefaultGoodsTracking.toggleAwait(_:)` (optimistic
    /// flip of ONLY the await flag → core `setAwaitGoods` type=1; corrected by
    /// `AWAIT_GOODS_CHANGED`). No-op for demo instances.
    public func toggleAwait(_ goodsGpn: String) {
        template?.goodsTracking.toggleAwait(goodsGpn)
    }

    /// Forward a 補貨通知 toggle → `DefaultGoodsTracking.toggleNotice(_:)` (optimistic
    /// flip of ONLY the notice flag → core `setNoticeGoods` type=2; corrected by
    /// `NOTICE_GOODS_CHANGED`). No-op for demo instances.
    public func toggleNotice(_ goodsGpn: String) {
        template?.goodsTracking.toggleNotice(goodsGpn)
    }

    /// Forward a notice-tab open → `DefaultNoticeTab.openNoticeTab()` (honoured only
    /// when `canOpen`; un-openable → no-op inside the model). No-op for demo.
    public func openNoticeTab() {
        template?.noticeTab.openNoticeTab()
    }

    /// Forward a notice-tab close → `DefaultNoticeTab.closeNoticeTab()`. No-op for demo.
    public func closeNoticeTab() {
        template?.noticeTab.closeNoticeTab()
    }

    /// Forward the「請求改名」intent (guest 態) → `DefaultPlayerTemplate.requestGuestNameEdit()`
    /// (emits `GUEST_NAME_EDIT_REQUEST` — passthrough, non-navigation, no auto-PiP).
    /// The actual rename is host-fulfilled via `LiveBuySDK.setUser`; this only
    /// forwards the intent. No-op for demo instances.
    public func requestGuestNameEdit() {
        template?.requestGuestNameEdit()
    }

    // MARK: - Deterministic demo seeds (previews + snapshot tests)
    //
    // Plain literals only — the family-6 surfaces are self-contained with their own
    // `demo(theme:)` constructors, so these are minimal helpers a preview / snapshot
    // fixture MAY reuse for stable copy. They construct NO view-model objects (the
    // template's view-model inits — e.g. `LBAuthGateState` — are reachable, but the
    // surfaces take the snapshot values directly, so we keep this layer to plain
    // literals per the design's "do NOT construct view-model objects you cannot
    // drive" guidance). The auth trigger enum IS public + reference-ui-reachable, so
    // a demo trigger action is provided for the auth-gate surface fixture.

    /// A deterministic demo auth trigger action (加入購物車 gate) for the auth-gate
    /// surface fixture. `LBAuthTriggerAction` is public + reference-ui-reachable.
    public static let demoAuthTriggerAction: LBAuthTriggerAction = .cartAdd

    /// A deterministic demo product name for the goods-tracking dual-switch sheet.
    public static let demoProductName = "Aurora 霧面唇釉 #03 珊瑚橘"

    /// A deterministic demo system-notice text for the notice-tab panel.
    public static let demoSystemNotice = "本場直播限時 9 折,結帳自動折抵。"

    /// A deterministic demo shop-notice text for the notice-tab panel.
    public static let demoNotice = "下單後 3 個工作天內出貨,離島地區另計運費。"

    /// A deterministic demo guest display name for the guest-name-edit modal.
    public static let demoGuestDisplayName = "Guest_8F3A"
}
