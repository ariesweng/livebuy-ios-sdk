import Foundation
import LivebuySDK

// MARK: - 搶購得標視窗（live-bid-ios-template）
//
// Zero-pixel state for the「恭喜搶購成功」popup. Fed by core `BID_WON` (both `ordered` and
// `failed` — the viewer did win; `failed` only means the auto-order did not land in a cart).
// 「確定」confirms every listed win in one `confirmBidWin` call (marks them read, like the web
// `/video/bidconfirm`); 「取消」only closes. reference-ui renders it (pending design).

/// One won bid shown in the popup.
public struct LBBidWonItem: Equatable {
    public let buyingId: String
    public let productId: String
    /// `""` when the product has no named spec.
    public let specificationId: String
    /// Backend-composed name, e.g. `"保溫杯(紅)"`.
    public let name: String
    public let num: Int
    /// `ordered` / `failed` (core `BID_WON.status`).
    public let status: String

    public init(buyingId: String, productId: String, specificationId: String,
                name: String, num: Int, status: String) {
        self.buyingId = buyingId
        self.productId = productId
        self.specificationId = specificationId
        self.name = name
        self.num = num
        self.status = status
    }

    /// Map a `BID_WON` params dictionary; `nil` without a non-empty `buying_id`.
    static func from(params: [String: Any]) -> LBBidWonItem? {
        guard let id = params["buying_id"] as? String, !id.isEmpty else { return nil }
        return LBBidWonItem(buyingId: id,
                            productId: params["product_id"] as? String ?? "",
                            specificationId: params["specification_id"] as? String ?? "",
                            name: params["name"] as? String ?? "",
                            num: params["num"] as? Int ?? 0,
                            status: params["status"] as? String ?? "")
    }
}

/// Bid-won popup view-model. Diff-then-notify via `onMutation` (coalesced by the template).
public final class DefaultBidWon {

    private(set) public var items: [LBBidWonItem] = []
    private(set) public var isPresented: Bool = false

    var onMutation: (() -> Void)?

    /// Injected confirm sink: receives every listed `buyingId` once per「確定」. The template
    /// wires it to `Livebuy.confirmBidWin`; default no-op (headless tests).
    var confirmForwarder: ([String]) -> Void = { _ in }

    init() {}

    /// Add a win (dedupe by `buyingId`) and present the popup.
    func record(_ item: LBBidWonItem) {
        guard !items.contains(where: { $0.buyingId == item.buyingId }) else {
            if !isPresented {
                isPresented = true
                onMutation?()
            }
            return
        }
        items.append(item)
        isPresented = true
        onMutation?()
    }

    /// 「確定」: confirm every listed win once, then clear + close (fire-and-forget, like the web).
    func confirm() {
        let ids = items.map(\.buyingId)
        if !ids.isEmpty { confirmForwarder(ids) }
        clear()
    }

    /// 「取消」/ video switch: clear + close without confirming.
    func clear() {
        guard !items.isEmpty || isPresented else { return }
        items = []
        isPresented = false
        onMutation?()
    }
}
