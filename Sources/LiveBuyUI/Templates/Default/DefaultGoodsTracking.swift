import LivebuySDK

// MARK: - DefaultGoodsTracking — per-product await + notice dual-switch state
//
// Spec: `ui-template-foundation/spec.md`
//   § "Default Template 到貨追蹤與補貨通知雙開關狀態行為"
// Design: design.md D1 / D2 / D3.
//
// Behaviour / view-model layer ONLY (no pixels). core stays headless: it owns the
// two independent endpoints (`setAwaitGoods` type=1 / `setNoticeGoods` type=2),
// the `LBProduct.isAwait` / `isAwaitNotice` source flags, and the authoritative
// `AWAIT_GOODS_CHANGED` / `NOTICE_GOODS_CHANGED` broadcasts. This model maps them
// into a per-`goodsGpn` host-bindable pair of INDEPENDENT (non-mutually-exclusive)
// flags so the host can draw two product-detail switches.

/// One host-bindable per-product flag pair. The two flags are INDEPENDENT — the
/// backend keeps two separate rows; toggling one MUST NOT move the other.
public struct LBGoodsTrackingFlags: Equatable {
    /// 到貨追蹤 (await, type=1) — mirrors `LBProduct.isAwait`.
    public let awaitEnabled: Bool
    /// 補貨通知 (notice, type=2) — mirrors `LBProduct.isAwaitNotice`.
    public let noticeEnabled: Bool

    public init(awaitEnabled: Bool, noticeEnabled: Bool) {
        self.awaitEnabled = awaitEnabled
        self.noticeEnabled = noticeEnabled
    }
}

/// Maps the core's goods-tracking endpoints + broadcasts into per-`goodsGpn`
/// host-bindable `{ awaitEnabled, noticeEnabled }`. The owning template seeds
/// initial flags from products, forwards toggle intents to the injected core
/// delegates, and corrects flags from the authoritative broadcasts.
public final class DefaultGoodsTracking {

    private var flags: [String: LBGoodsTrackingFlags] = [:]

    /// Internal coalesced "goods-tracking mutated" hook → owning template's single
    /// host-facing `onChange`. NOT public.
    var onMutation: (() -> Void)?

    /// Injected core delegates (default no-op for headless unit tests). The wiring
    /// fills them with `Task { try? await Livebuy.setAwaitGoods/… }` so the
    /// model never builds an HTTP request itself (headless: writes go via core).
    private let setAwait: (String, Bool) -> Void
    private let setNotice: (String, Bool) -> Void

    init(setAwait: @escaping (String, Bool) -> Void = { _, _ in },
         setNotice: @escaping (String, Bool) -> Void = { _, _ in }) {
        self.setAwait = setAwait
        self.setNotice = setNotice
    }

    // MARK: - Read surface

    /// Current flag pair for `goodsGpn` (both false when unseen — single source of
    /// truth defaults to off until a seed / toggle / broadcast).
    public func flags(for goodsGpn: String) -> LBGoodsTrackingFlags {
        flags[goodsGpn] ?? LBGoodsTrackingFlags(awaitEnabled: false, noticeEnabled: false)
    }

    /// 到貨追蹤 (type=1) flag for `goodsGpn`.
    public func awaitEnabled(for goodsGpn: String) -> Bool { flags(for: goodsGpn).awaitEnabled }

    /// 補貨通知 (type=2) flag for `goodsGpn`.
    public func noticeEnabled(for goodsGpn: String) -> Bool { flags(for: goodsGpn).noticeEnabled }

    // MARK: - Seed (initial value; non-clobbering)

    /// Seed the INITIAL flags for `goodsGpn` from `LBProduct.isAwait` /
    /// `isAwaitNotice` (0/1). Non-clobbering: a key already known (seeded / toggled
    /// / broadcast-corrected) is NOT overwritten — re-seeding from a stale product
    /// snapshot MUST NOT clobber an optimistic / authoritative value (D3). Notifies
    /// iff it set a new key.
    func seed(goodsGpn: String, isAwait: Int, isAwaitNotice: Int) {
        guard flags[goodsGpn] == nil else { return }
        flags[goodsGpn] = LBGoodsTrackingFlags(awaitEnabled: isAwait != 0,
                                               noticeEnabled: isAwaitNotice != 0)
        onMutation?()
    }

    // MARK: - Toggle intents (optimistic → delegate to core)

    /// Toggle 到貨追蹤 (type=1): optimistically flip ONLY the await flag, notify
    /// once, then delegate to `setAwaitGoods`. MUST NOT touch the notice flag
    /// (non-mutual-exclusion).
    public func toggleAwait(_ goodsGpn: String) {
        let cur = flags(for: goodsGpn)
        let next = !cur.awaitEnabled
        flags[goodsGpn] = LBGoodsTrackingFlags(awaitEnabled: next, noticeEnabled: cur.noticeEnabled)
        onMutation?()
        setAwait(goodsGpn, next)
    }

    /// Toggle 補貨通知 (type=2): optimistically flip ONLY the notice flag, notify
    /// once, then delegate to `setNoticeGoods`. MUST NOT touch the await flag.
    public func toggleNotice(_ goodsGpn: String) {
        let cur = flags(for: goodsGpn)
        let next = !cur.noticeEnabled
        flags[goodsGpn] = LBGoodsTrackingFlags(awaitEnabled: cur.awaitEnabled, noticeEnabled: next)
        onMutation?()
        setNotice(goodsGpn, next)
    }

    // MARK: - Broadcast correction (authoritative)

    /// Correct the await flag from `AWAIT_GOODS_CHANGED` (authoritative). Touches
    /// ONLY the await flag for `goodsGpn`; notifies iff it changed.
    func applyAwaitBroadcast(goodsGpn: String, enabled: Bool) {
        let cur = flags(for: goodsGpn)
        guard cur.awaitEnabled != enabled else { return }
        flags[goodsGpn] = LBGoodsTrackingFlags(awaitEnabled: enabled, noticeEnabled: cur.noticeEnabled)
        onMutation?()
    }

    /// Correct the notice flag from `NOTICE_GOODS_CHANGED` (authoritative). Touches
    /// ONLY the notice flag for `goodsGpn`; notifies iff it changed.
    func applyNoticeBroadcast(goodsGpn: String, enabled: Bool) {
        let cur = flags(for: goodsGpn)
        guard cur.noticeEnabled != enabled else { return }
        flags[goodsGpn] = LBGoodsTrackingFlags(awaitEnabled: cur.awaitEnabled, noticeEnabled: enabled)
        onMutation?()
    }
}
