import LivebuySDK

// MARK: - DefaultProductSheet — product sheet-stack host-bindable view-models
//
// Spec: `ui-template-foundation/spec.md`
//   § "Default Template 商品 Sheet-Stack 狀態與加購行為"
//   § "Default Template Bindable State 變更通知" (sheet-stack coverage)
// Design: product-sheet-stack-template design.md D1–D7.
//
// Behaviour / view-model layer ONLY (no pixels). core stays headless: it owns the
// `Livebuy.addToCart(...)` route-B endpoint (`POST /sdk/video/addcart` → `LBCartResult`),
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
/// HTTP, no count change). The real wiring injects `Livebuy.addToCart(...)`.
enum LBProductSheetError: Error {
    case noRequester
}

// MARK: - Route-B add-to-cart request envelope (injected-requester input)

/// The minimal route-B add-to-cart request the template assembles from the
/// current product-detail + variant selection + qty, and hands to the injected
/// core requester (which calls `Livebuy.addToCart(...)`). `shopId` is read from
/// the public `channel.shop.id`; `specificationId` is nil for a no-spec product.
/// The template builds NO HTTP — this is just the parameter bundle.
public struct LBCartRequest: Equatable {
    public let shopId: String
    public let goodsId: String
    public let num: Int
    public let specificationId: String?
    /// 當前影片短碼（cart-add-tier2）。透傳給 `LivebuySDK.addToCart(videoId:)`，使
    /// 後續 `CART_ADD_REQUEST.video_id` 為當前影片。無 player / channel 時為 nil。
    public let videoId: String?

    public init(shopId: String, goodsId: String, num: Int, specificationId: String?, videoId: String? = nil) {
        self.shopId = shopId
        self.goodsId = goodsId
        self.num = num
        self.specificationId = specificationId
        self.videoId = videoId
    }
}

// MARK: - 1. product-detail — `{ productId, name, priceShow, …, specifications, specOptions }`

/// One「更多商品」推薦卡片 — mapped from `LBChannel.otherGoods[]`
/// (expose-other-goods-recommendations-template design.md D2). Deliberately
/// minimal: just enough to render a recommendation card and switch videos
/// (`videoId`) — NOT the full `LBProduct` (no `specifications` / `specOptions`;
/// a tap into the nested detail re-maps a full `LBProductDetailState` via the
/// existing `onProductTap` path instead). `originalPriceShow` is the one
/// exception carved out of that "deliberately minimal" set
/// (add-recommendation-original-price-template-ios) — it was simply missing
/// from D2's original field list, not a decision to omit it; reference-ui's
/// `.grid` card strikethrough rendering needs it to show a struck-through
/// original price alongside `priceShow`.
public struct LBProductRecommendation: Equatable {
    public let productId: String
    public let name: String
    public let priceShow: String
    public let pic: String
    /// Cross-video product reference (`LBProduct.videoId`). `nil` when the
    /// backend omits `video_id` on this `other_goods[]` entry — reference-ui
    /// MUST hide/disable the switch-video affordance rather than fabricate one
    /// (design.md D2).
    public let videoId: String?
    /// 0/1 — mirrors `LBProduct.soldOut` (API integer, not boolean).
    public let soldOut: Int
    /// Struck-through original price display string — direct mirror of
    /// `LBProduct.originalPriceShow` (same convention as
    /// `LBProductDetailState.originalPriceShow`). `""` when the source product
    /// has no original price (add-recommendation-original-price-template-ios).
    public let originalPriceShow: String

    public init(productId: String, name: String, priceShow: String, pic: String,
                videoId: String?, soldOut: Int, originalPriceShow: String = "") {
        self.productId = productId
        self.name = name
        self.priceShow = priceShow
        self.pic = pic
        self.videoId = videoId
        self.soldOut = soldOut
        self.originalPriceShow = originalPriceShow
    }
}

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
    /// 「更多商品」推薦清單 — filtered `LBChannel.otherGoods` (current product
    /// excluded), FULL list, NOT pre-truncated to a card count
    /// (expose-other-goods-recommendations-template design.md D1 — truncation is
    /// reference-ui's job). Empty when the channel has no other goods, or when
    /// this detail was opened without a channel context.
    public let recommendations: [LBProductRecommendation]

    public init(productId: String, name: String, priceShow: String,
                originalPriceShow: String, price: Double, stock: Int, soldOut: Int,
                photos: [String], specifications: [LBSpec], specOptions: [LBSpecOption],
                recommendations: [LBProductRecommendation] = []) {
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
        self.recommendations = recommendations
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
            && lhs.recommendations == rhs.recommendations
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
    /// `otherGoods` is the owning channel's `LBChannel.otherGoods` (empty when no
    /// channel context, e.g. a headless unit test) — mapped into `recommendations`
    /// via the pure `recommendations(from:excluding:)` resolver.
    /// Diff-then-notify: re-opening the SAME product (identical mapped fields) is
    /// a no-op. The owning template resets variant / qty when this fires for a NEW
    /// product (handled at the template level so the three models stay decoupled).
    func openDetail(_ product: LBProduct, otherGoods: [LBProduct] = []) {
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
            specOptions: product.specOptions,
            recommendations: Self.recommendations(from: otherGoods, excluding: product.id))
        guard next != detail else { return }
        detail = next
        onMutation?()
    }

    /// PURE mapper (testable in isolation, expose-other-goods-recommendations-template
    /// design.md D1/D2): excludes `productId` itself from `otherGoods` (data-correctness
    /// concern, owned by template — see design.md D1) and maps the remainder into the
    /// minimal `LBProductRecommendation` shape. Does NOT truncate to any card count —
    /// truncation is reference-ui's job (design.md D1). `originalPriceShow` is a direct
    /// passthrough of the source `LBProduct.originalPriceShow` (add-recommendation-
    /// original-price-template-ios) — already `""` on the source when there is no
    /// original price, so no extra nil/empty handling is needed here.
    static func recommendations(from otherGoods: [LBProduct], excluding productId: String) -> [LBProductRecommendation] {
        otherGoods
            .filter { $0.id != productId }
            .map {
                LBProductRecommendation(productId: $0.id, name: $0.name, priceShow: $0.priceShow,
                                        pic: $0.pic, videoId: $0.videoId, soldOut: $0.soldOut,
                                        originalPriceShow: $0.originalPriceShow)
            }
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

/// One spec-option group's CASCADING purchasability snapshot
/// (rb-ios-variant-cascading-availability-template). `availableOptions[i]` corresponds
/// to `LBVariantGroup.options[i]` (same order, same length) — `true` when choosing that
/// value, together with whatever is CURRENTLY chosen in every OTHER group, still resolves
/// to at least one `stock > 0` `LBSpec`. Read via `DefaultVariantPicker.optionAvailability`
/// (or the underlying pure `DefaultVariantPicker.optionAvailability(groups:selection:specifications:)`),
/// which returns one `LBVariantGroupAvailability` per `groups` entry, in the same order.
///
/// This is a PURE DERIVATION for host/reference-ui to decide which chips to grey out /
/// disable, and how the not-yet-chosen groups should re-narrow once an earlier group is
/// picked (multi-group "cascading" disable). It does NOT gate `selectVariant(groupIndex:
/// optionIndex:)` — the template still allows selecting any in-range option regardless of
/// its availability flag; whether to block the tap in the UI is a reference-ui decision.
public struct LBVariantGroupAvailability: Equatable {
    public let groupIndex: Int
    public let availableOptions: [Bool]

    public init(groupIndex: Int, availableOptions: [Bool]) {
        self.groupIndex = groupIndex
        self.availableOptions = availableOptions
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

    /// Cascading purchasability snapshot for the CURRENT `groups` / `selection` /
    /// `specifications` (rb-ios-variant-cascading-availability-template). Read-through,
    /// recomputed on every access (no caching, no mutation, no notification) — matches
    /// the `state` computed-property pattern. See `LBVariantGroupAvailability` /
    /// `optionAvailability(groups:selection:specifications:)` for the shape and algorithm.
    public var optionAvailability: [LBVariantGroupAvailability] {
        Self.optionAvailability(groups: groups, selection: selection, specifications: specifications)
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

    /// Reset to no-product state (teardown / video-switch,
    /// ios-product-sheet-stack-video-switch-reset-template) — mirrors `reset(for:)`
    /// but with no product to re-seed from: `specifications` is cleared directly
    /// (it is not part of `LBVariantState`, so `applyIfChanged` alone would not
    /// touch it). Diff-then-notify via the existing `applyIfChanged` path.
    func clear() {
        specifications = []
        applyIfChanged(LBVariantState(groups: [], selection: [:], selectedSpec: nil, selectedSpecificationId: nil))
    }

    /// PURE resolver (testable in isolation): returns the matching `LBSpec` ONLY
    /// when EVERY group has a chosen option AND a spec whose `name` matches all
    /// chosen option values (via `specNameMatches`, see below) exists. Returns nil
    /// while selection is incomplete or no spec matches (D2 — incomplete selection
    /// ⇒ no specId ⇒ add-to-cart guard rejects).
    static func selectedSpec(groups: [LBVariantGroup], selection: [Int: Int],
                             specifications: [LBSpec]) -> LBSpec? {
        guard !groups.isEmpty else { return specifications.first }
        // Every group must be chosen.
        guard selection.count == groups.count else { return nil }
        let chosen: [(groupIndex: Int, value: String)] = groups.indices.compactMap { gi -> (Int, String)? in
            guard let oi = selection[gi], oi >= 0, oi < groups[gi].options.count else { return nil }
            return (gi, groups[gi].options[oi])
        }
        guard chosen.count == groups.count else { return nil }
        // A spec matches when its `name` matches every chosen option value
        // (rb-ios-variant-cascading-availability-template — precise per-group matching,
        // see `specNameMatches` doc comment for why plain `.contains` is unsafe here).
        return specifications.first { spec in
            chosen.allSatisfy { specNameMatches(spec.name, value: $0.value, siblingOptions: groups[$0.groupIndex].options) }
        }
    }

    // MARK: - Cascading availability (rb-ios-variant-cascading-availability-template)
    //
    // Backing algorithm for `optionAvailability` (public instance property above) and the
    // precise spec-name matcher shared with `selectedSpec` (D2 refactor — the two resolvers
    // MUST agree on what counts as a match, or a UI built on `optionAvailability` could
    // disagree with what `selectedSpec` actually resolves once the user finishes selecting).

    /// PURE matcher (testable in isolation): does `name` correspond to `value`, one option
    /// chosen for a SINGLE spec-option group, WITHOUT being fooled by another option in the
    /// SAME group that happens to contain `value` as a literal substring?
    ///
    /// `LBSpec.name`'s multi-group join convention (what separator, if any, the backend uses
    /// to concatenate e.g. a chosen color + a chosen size into one spec name) has no
    /// documented/verified format anywhere in this repo, and every existing fixture only
    /// exercises a single spec-option group — so this deliberately does NOT assume any
    /// separator (unlike splitting `name` into tokens by a guessed delimiter, which would
    /// silently break full-selection resolution if the guess is wrong). Instead it stays
    /// substring-based (like the code this replaces) but first MASKS OUT of `name` any other
    /// option in `siblingOptions` (the full option list of `value`'s OWN group) that is
    /// STRICTLY LONGER than `value` and itself contains `value` as a substring — e.g. group
    /// `[S, XS]`: checking `value == "S"` against `name == "XS"` first removes the sibling
    /// `"XS"` from `name` (leaving `""`), so the leftover no longer contains `"S"` and the
    /// match correctly fails. Checking `value == "XS"` finds no longer sibling containing
    /// `"XS"` itself, so `name` is used as-is and the match correctly succeeds.
    ///
    /// Known simplification: does not attempt to fully disambiguate pathological cases where
    /// the SAME literal string is reused as an option value across two DIFFERENT groups and
    /// also happens to collide as a substring in a spec name — real product catalogs (color /
    /// size / capacity …) are not expected to hit this (see design.md D1 Risks).
    static func specNameMatches(_ name: String, value: String, siblingOptions: [String]) -> Bool {
        let longerSiblings = siblingOptions.filter {
            $0 != value && $0.count > value.count && $0.contains(value)
        }
        let masked = longerSiblings.reduce(name) { $0.replacingOccurrences(of: $1, with: "") }
        return masked.contains(value)
    }

    /// PURE (testable in isolation): for EVERY group in `groups`, for EVERY option value in
    /// that group, computes whether choosing that value — together with whatever is
    /// CURRENTLY chosen (`selection`) in every OTHER group — still resolves to at least one
    /// `stock > 0` `LBSpec`. Returns one `LBVariantGroupAvailability` per `groups` entry, IN
    /// THE SAME ORDER, each holding a `[Bool]` parallel to that group's `options`.
    ///
    /// A group's OWN currently-chosen option is NOT held fixed when evaluating that SAME
    /// group's own options — every option in a group (including the one already selected) is
    /// re-checked against the OTHER groups' current selections only. This means that once a
    /// combination becomes invalid across two dimensions (e.g. picking a 2nd group's value
    /// that has no in-stock spec together with the 1st group's already-chosen value), BOTH
    /// group's conflicting chips report unavailable, not just the one just tapped — standard
    /// cascading-picker UX. Callers that want a different policy (e.g. never flag the
    /// group's own current selection) can special-case that themselves; this function reports
    /// the full, unfiltered result.
    ///
    /// `groups.isEmpty` (no-spec product) → `[]` (nothing to render).
    static func optionAvailability(groups: [LBVariantGroup], selection: [Int: Int],
                                   specifications: [LBSpec]) -> [LBVariantGroupAvailability] {
        guard !groups.isEmpty else { return [] }
        return groups.indices.map { gi in
            let group = groups[gi]
            // Values currently chosen in every OTHER group (this group's own selection is
            // deliberately excluded — see doc comment above).
            let otherChosen: [(groupIndex: Int, value: String)] = groups.indices.compactMap { ogi in
                guard ogi != gi, let oi = selection[ogi], oi >= 0, oi < groups[ogi].options.count else { return nil }
                return (ogi, groups[ogi].options[oi])
            }
            let flags = group.options.map { value -> Bool in
                let candidates = otherChosen + [(groupIndex: gi, value: value)]
                return specifications.contains { spec in
                    spec.stock > 0 && candidates.allSatisfy {
                        specNameMatches(spec.name, value: $0.value, siblingOptions: groups[$0.groupIndex].options)
                    }
                }
            }
            return LBVariantGroupAvailability(groupIndex: gi, availableOptions: flags)
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

    /// Reset to this class's own construction-time defaults (teardown /
    /// video-switch, ios-product-sheet-stack-video-switch-reset-template).
    /// Diff-then-notify via the existing `applyIfChanged(qty:min:max:)` path.
    func clear() {
        applyIfChanged(qty: 1, min: 1, max: 0)
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
