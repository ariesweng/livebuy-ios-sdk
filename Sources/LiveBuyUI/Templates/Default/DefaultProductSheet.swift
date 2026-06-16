import LiveBuySDK

// MARK: - DefaultProductSheet — product sheet-stack host-bindable view-models
//
// Spec: `ui-template-foundation/spec.md`
//   § "Default Template 商品 Sheet-Stack 狀態與加購行為"
//   § "Default Template Bindable State 變更通知" (sheet-stack coverage)
// Design: product-sheet-stack-template design.md D1–D7.
//
// Behaviour / view-model layer ONLY (no pixels). core stays headless: it owns the
// `LiveBuy.addToCart(...)` route-B endpoint (`POST /sdk/video/addcart` → `LBCartResult`),
// route A (`CART_ADD_REQUEST` + `LBCartResultCallback`), and `productTap`
// (`PRODUCT_CLICK`). These models MAP the core `LBProduct` (specifications /
// specOptions / stock / soldOut) into a host-bindable product sheet-stack —
// product-detail / variant-picker / qty-stepper / mini-cart / cart CTA — so the
// host can draw `sdk-components.jsx`'s `LBPBottomSheet` / `LBPProductRow` /
// `LBPVariantPicker` / `LBPQtyStepper` / `LBPMiniCart` / `LBPCartCTA`.
//
// Each model mirrors `DefaultGoodsTracking` / `DefaultMomentStates`: PUBLIC read
// surface (`private(set) public var`), an INTERNAL coalesced `onMutation` hook
// (the host observes the owning template's single `onChange`, never the model),
// and INTERNAL mutators that DIFF-then-notify (fire `onMutation` exactly once per
// real change). The add-to-cart intent is DELEGATED to an injected core requester
// (default no-op for headless unit tests) — the template NEVER builds HTTP.

// MARK: - Headless add-to-cart stub error

/// Thrown by the DEFAULT (un-injected) add-to-cart requester so a headless unit
/// test that never wires a real requester sees `addToCart()` fail cleanly (no
/// HTTP, no count change). The real wiring injects `LiveBuy.addToCart(...)`.
enum LBProductSheetError: Error {
    case noRequester
}

// MARK: - Route-B add-to-cart request envelope (injected-requester input)

/// The minimal route-B add-to-cart request the template assembles from the
/// current product-detail + variant selection + qty, and hands to the injected
/// core requester (which calls `LiveBuy.addToCart(...)`). `shopId` is read from
/// the public `channel.shop.id`; `specificationId` is nil for a no-spec product.
/// The template builds NO HTTP — this is just the parameter bundle.
public struct LBCartRequest: Equatable {
    public let shopId: String
    public let goodsId: String
    public let num: Int
    public let specificationId: String?

    public init(shopId: String, goodsId: String, num: Int, specificationId: String?) {
        self.shopId = shopId
        self.goodsId = goodsId
        self.num = num
        self.specificationId = specificationId
    }
}

// MARK: - 1. product-detail — `{ productId, name, priceShow, …, specifications, specOptions }`

/// Host-bindable product-detail state for `LBPBottomSheet` + `LBPProductRow`.
/// Mirrors the relevant `LBProduct` fields directly (D1 — no parallel model) so
/// the host binds in one place. `originalPriceShow` is exposed (may be empty).
public struct LBProductDetailState: Equatable {
    public let productId: String
    public let name: String
    public let priceShow: String
    public let originalPriceShow: String
    public let price: Double
    public let stock: Int
    /// 0/1 — mirrors `LBProduct.soldOut` (API integer, not boolean).
    public let soldOut: Int
    public let photos: [String]
    public let specifications: [LBSpec]
    public let specOptions: [LBSpecOption]

    public init(productId: String, name: String, priceShow: String,
                originalPriceShow: String, price: Double, stock: Int, soldOut: Int,
                photos: [String], specifications: [LBSpec], specOptions: [LBSpecOption]) {
        self.productId = productId
        self.name = name
        self.priceShow = priceShow
        self.originalPriceShow = originalPriceShow
        self.price = price
        self.stock = stock
        self.soldOut = soldOut
        self.photos = photos
        self.specifications = specifications
        self.specOptions = specOptions
    }

    // LBSpec / LBSpecOption are not Equatable; compare by stable identity so a
    // re-feed of the same product does not look "changed".
    public static func == (lhs: LBProductDetailState, rhs: LBProductDetailState) -> Bool {
        lhs.productId == rhs.productId
            && lhs.name == rhs.name
            && lhs.priceShow == rhs.priceShow
            && lhs.originalPriceShow == rhs.originalPriceShow
            && lhs.price == rhs.price
            && lhs.stock == rhs.stock
            && lhs.soldOut == rhs.soldOut
            && lhs.photos == rhs.photos
            && lhs.specifications.map(\.id) == rhs.specifications.map(\.id)
            && lhs.specOptions.map(\.name) == rhs.specOptions.map(\.name)
    }
}

/// product-detail view-model. `openDetail` maps an `LBProduct` (the most recent
/// `diversion == 0` tap, D1) into the detail state; `clearDetail` dismisses it.
/// Single value (new product replaces the previous). Diff-then-notify.
public final class DefaultProductSheet {

    private(set) public var detail: LBProductDetailState?

    var onMutation: (() -> Void)?

    init() {}

    /// Map `product` (a `diversion == 0` `productTap`) into the detail state.
    /// Diff-then-notify: re-opening the SAME product (identical mapped fields) is
    /// a no-op. The owning template resets variant / qty when this fires for a NEW
    /// product (handled at the template level so the three models stay decoupled).
    func openDetail(_ product: LBProduct) {
        let next = LBProductDetailState(
            productId: product.id,
            name: product.name,
            priceShow: product.priceShow,
            originalPriceShow: product.originalPriceShow,
            price: product.price,
            stock: product.stock,
            soldOut: product.soldOut,
            photos: product.photos,
            specifications: product.specifications,
            specOptions: product.specOptions)
        guard next != detail else { return }
        detail = next
        onMutation?()
    }

    /// Dismiss the detail sheet. Diff-then-notify (no-op when already nil).
    func clearDetail() {
        guard detail != nil else { return }
        detail = nil
        onMutation?()
    }
}

// MARK: - 2. variant-picker — groups from specOptions, selectedSpec from specifications

/// One chip group for `LBPVariantPicker` — mapped from one `LBSpecOption`
/// (`{ name, child[] }`). `label` = group name; `options` = selectable values.
public struct LBVariantGroup: Equatable {
    public let label: String
    public let options: [String]

    public init(label: String, options: [String]) {
        self.label = label
        self.options = options
    }
}

/// Host-bindable variant-picker state. `groups` come from `specOptions`;
/// `selection` is template-owned (`groupIndex → optionIndex`); `selectedSpec` /
/// `selectedSpecificationId` are resolved from `specifications` once every group
/// is chosen (D2). When the product has no spec groups, `groups` is empty,
/// `selectedSpec` is the single spec (or nil), and add-to-cart needs no selection.
public struct LBVariantState: Equatable {
    public let groups: [LBVariantGroup]
    /// `groupIndex → optionIndex` (only chosen groups present).
    public let selection: [Int: Int]
    public let selectedSpec: LBSpec?
    public let selectedSpecificationId: String?

    public init(groups: [LBVariantGroup], selection: [Int: Int],
                selectedSpec: LBSpec?, selectedSpecificationId: String?) {
        self.groups = groups
        self.selection = selection
        self.selectedSpec = selectedSpec
        self.selectedSpecificationId = selectedSpecificationId
    }

    public static func == (lhs: LBVariantState, rhs: LBVariantState) -> Bool {
        lhs.groups == rhs.groups
            && lhs.selection == rhs.selection
            && lhs.selectedSpec?.id == rhs.selectedSpec?.id
            && lhs.selectedSpecificationId == rhs.selectedSpecificationId
    }
}

/// variant-picker view-model. `groups` is derived from the current product's
/// `specOptions`; `selection` is updated via `selectVariant`. `selectedSpec` is
/// resolved by `selectedSpec(from:)` — a PURE function matching the chosen option
/// values against each `LBSpec.name` (the backend spec `name` is the joined group
/// values, per the existing `LBSpec.name` convention).
public final class DefaultVariantPicker {

    private(set) public var groups: [LBVariantGroup] = []
    private(set) public var selection: [Int: Int] = [:]
    private(set) public var selectedSpec: LBSpec?
    private(set) public var selectedSpecificationId: String?

    /// Held so `selectVariant` can re-resolve `selectedSpec` from the chosen
    /// options. Reset by `reset(for:)` whenever a new product detail opens.
    private var specifications: [LBSpec] = []

    var onMutation: (() -> Void)?

    init() {}

    /// Snapshot read surface for the host (one immutable value).
    public var state: LBVariantState {
        LBVariantState(groups: groups, selection: selection,
                       selectedSpec: selectedSpec, selectedSpecificationId: selectedSpecificationId)
    }

    /// Re-seed groups / specifications for a NEW product and CLEAR any selection
    /// (D1 — new detail resets variant). When the product has no spec groups,
    /// `groups` is empty and `selectedSpec` becomes the single spec (if any) so a
    /// no-spec product is immediately addable (D2). Diff-then-notify.
    func reset(for product: LBProductDetailState) {
        let newGroups = product.specOptions.map {
            LBVariantGroup(label: $0.name, options: $0.child)
        }
        specifications = product.specifications
        // No spec groups → the single spec (if any) is implicitly selected.
        let resolvedSpec: LBSpec? = newGroups.isEmpty
            ? product.specifications.first
            : nil
        let next = LBVariantState(
            groups: newGroups,
            selection: [:],
            selectedSpec: resolvedSpec,
            selectedSpecificationId: resolvedSpec?.id)
        applyIfChanged(next)
    }

    /// Host chip tap → update selection for one group, then re-resolve the spec.
    /// Out-of-range indices are ignored (defensive). Diff-then-notify.
    func selectVariant(groupIndex: Int, optionIndex: Int) {
        guard groupIndex >= 0, groupIndex < groups.count else { return }
        guard optionIndex >= 0, optionIndex < groups[groupIndex].options.count else { return }
        var nextSelection = selection
        nextSelection[groupIndex] = optionIndex
        let resolved = Self.selectedSpec(groups: groups, selection: nextSelection,
                                         specifications: specifications)
        let next = LBVariantState(
            groups: groups,
            selection: nextSelection,
            selectedSpec: resolved,
            selectedSpecificationId: resolved?.id)
        applyIfChanged(next)
    }

    private func applyIfChanged(_ next: LBVariantState) {
        guard next != state else { return }
        groups = next.groups
        selection = next.selection
        selectedSpec = next.selectedSpec
        selectedSpecificationId = next.selectedSpecificationId
        onMutation?()
    }

    /// PURE resolver (testable in isolation): returns the matching `LBSpec` ONLY
    /// when EVERY group has a chosen option AND a spec whose `name` contains all
    /// chosen option values exists. Returns nil while selection is incomplete or
    /// no spec matches (D2 — incomplete selection ⇒ no specId ⇒ add-to-cart guard
    /// rejects).
    static func selectedSpec(groups: [LBVariantGroup], selection: [Int: Int],
                             specifications: [LBSpec]) -> LBSpec? {
        guard !groups.isEmpty else { return specifications.first }
        // Every group must be chosen.
        guard selection.count == groups.count else { return nil }
        let chosenValues: [String] = groups.indices.compactMap { gi -> String? in
            guard let oi = selection[gi], oi >= 0, oi < groups[gi].options.count else { return nil }
            return groups[gi].options[oi]
        }
        guard chosenValues.count == groups.count else { return nil }
        // A spec matches when its `name` contains all chosen option values.
        return specifications.first { spec in
            chosenValues.allSatisfy { spec.name.contains($0) }
        }
    }
}

// MARK: - 3. qty-stepper — `{ qty, min, max }`

/// Host-bindable quantity state for `LBPQtyStepper`. `max` = chosen spec / product
/// stock; `min` = 1 when in stock, 0 when sold-out / out of stock; `qty` clamped to
/// `[min, max]` (D3). When sold-out, `min == max == qty == 0` (host draws 缺貨).
public struct LBQtyState: Equatable {
    public let qty: Int
    public let min: Int
    public let max: Int

    public init(qty: Int, min: Int, max: Int) {
        self.qty = qty
        self.min = min
        self.max = max
    }
}

/// qty-stepper view-model. `recomputeBounds` derives `{ min, max }` from a stock /
/// soldOut pair and resets / re-clamps `qty`; `setQty` / `incQty` / `decQty` clamp
/// to `[min, max]`. Diff-then-notify.
public final class DefaultQtyStepper {

    private(set) public var qty: Int = 1
    private(set) public var min: Int = 1
    private(set) public var max: Int = 0

    var onMutation: (() -> Void)?

    init() {}

    public var state: LBQtyState { LBQtyState(qty: qty, min: min, max: max) }

    /// Derive bounds from the effective stock + soldOut. soldOut == 1 OR stock <= 0
    /// → `min == max == qty == 0` (D3). Otherwise `min == 1`, `max == stock`, and
    /// `qty` is re-clamped into the new range (switching to a smaller-stock spec
    /// drops `qty` to the new `max`). Diff-then-notify.
    func recomputeBounds(stock: Int, soldOut: Int) {
        let out = soldOut == 1 || stock <= 0
        let newMin = out ? 0 : 1
        let newMax = out ? 0 : stock
        // Re-clamp the current qty into the new range. When (re)entering an
        // in-stock range from 0/unset, start at `min`.
        let base = qty < newMin ? newMin : qty
        let newQty = Swift.min(Swift.max(base, newMin), newMax)
        applyIfChanged(qty: newQty, min: newMin, max: newMax)
    }

    func setQty(_ value: Int) {
        applyIfChanged(qty: clamp(value), min: min, max: max)
    }

    func incQty() { applyIfChanged(qty: clamp(qty + 1), min: min, max: max) }
    func decQty() { applyIfChanged(qty: clamp(qty - 1), min: min, max: max) }

    private func clamp(_ value: Int) -> Int { Swift.min(Swift.max(value, min), max) }

    private func applyIfChanged(qty: Int, min: Int, max: Int) {
        guard qty != self.qty || min != self.min || max != self.max else { return }
        self.qty = qty
        self.min = min
        self.max = max
        onMutation?()
    }
}

// MARK: - 4. mini-cart — `{ productId, name, priceShow, soldOut }`

/// Host-bindable mini-cart peek for `LBPMiniCart` (D4). Compact snapshot of the
/// most recent successful add (or the narrating product as a fallback).
public struct LBMiniCartPeek: Equatable {
    public let productId: String
    public let name: String
    public let priceShow: String
    public let soldOut: Int
    /// Product image URL (raw passthrough) — reference-ui resolves it from the active product's
    /// `photos.first ?? pic` and renders the real image (live-gated). Default `""` keeps existing
    /// callers / demo fixtures byte-identical (reference-ui falls back to the placeholder).
    /// (vod-now-introducing-multi-image-template, 問題 9.)
    public let pic: String

    public init(productId: String, name: String, priceShow: String, soldOut: Int, pic: String = "") {
        self.productId = productId
        self.name = name
        self.priceShow = priceShow
        self.soldOut = soldOut
        self.pic = pic
    }
}

/// mini-cart view-model. `setPeek` records a peek; `dismissMiniCart` clears it.
/// `openDetail` is a host-bound intent that asks the owning template to re-open
/// the product detail — exposed as a closure the template fills (the model itself
/// owns no product list). Diff-then-notify.
public final class DefaultMiniCart {

    private(set) public var peek: LBMiniCartPeek?

    var onMutation: (() -> Void)?

    /// Template-injected「open detail from the peek」forwarder (default no-op for
    /// headless tests). The template fills it so `openDetail()` re-sets the
    /// product-detail state for the peeked product.
    var openDetailForwarder: ((String) -> Void)?

    init() {}

    func setPeek(_ peek: LBMiniCartPeek) {
        guard peek != self.peek else { return }
        self.peek = peek
        onMutation?()
    }

    /// Fallback peek from the narrating product (only when there is no peek yet —
    /// a successful add wins, D4). Diff-then-notify.
    func seedFallback(_ peek: LBMiniCartPeek) {
        guard self.peek == nil else { return }
        self.peek = peek
        onMutation?()
    }

    public func dismissMiniCart() {
        guard peek != nil else { return }
        peek = nil
        onMutation?()
    }

    /// Re-open the peeked product's detail (host intent). No-op when no peek /
    /// no forwarder wired.
    public func openDetail() {
        guard let id = peek?.productId else { return }
        openDetailForwarder?(id)
    }
}

// MARK: - 5. cart CTA — `{ count }` + openCart passthrough

/// Host-bindable cart CTA state for `LBPCartCTA` (D4). `count` is the per-session
/// number of successful route-B adds through this template (NOT a persisted cart;
/// the real cart / `buy_no` lives on the backend, host reads it from the result).
public struct LBCartCTAState: Equatable {
    public let count: Int
    public init(count: Int) { self.count = count }
}

/// cart CTA view-model. `incrementOnAdd` bumps the session count on a successful
/// add; `resetForSession` zeroes it on release / new-video (D4 / OQ2); `openCart`
/// is a host-bound passthrough intent. Diff-then-notify.
public final class DefaultCartCTA {

    private(set) public var count: Int = 0

    var onMutation: (() -> Void)?

    /// Template-injected「open cart」passthrough (default no-op). Host wires this
    /// to its own checkout entry — the template owns NO checkout page.
    var openCartForwarder: (() -> Void)?

    init() {}

    public var state: LBCartCTAState { LBCartCTAState(count: count) }

    func incrementOnAdd() {
        count += 1
        onMutation?()
    }

    func resetForSession() {
        guard count != 0 else { return }
        count = 0
        onMutation?()
    }

    public func openCart() { openCartForwarder?() }
}
