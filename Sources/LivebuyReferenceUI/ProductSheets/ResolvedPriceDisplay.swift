import Foundation
import LivebuySDK
import LivebuyUI

// MARK: - ResolvedPriceDisplay — spec-aware, SAME-SOURCE price pair for the product sheets
//
// Spec: `reference-ui-rendering/spec.md`
//   § "LivebuyReferenceUI 商品明細 / 加入購物車 sheet 價格線跟隨 selectedSpec，售價與原價同源原子解析（iOS）"
// Change: ios-product-sheet-spec-price-reference-ui.
//
// ⚠️ FOUR-PLATFORM PARITY CONTRACT BASELINE ⚠️
// iOS is the LEAD platform for this rule. Android (`:livebuy-reference-ui`
// `ResolvedPriceDisplay.kt`), React Native (`resolvedPriceDisplay.ts`) and Flutter
// (`resolved_price_display.dart`) MIRROR THIS FILE VERBATIM — same type name, same
// function name, same field names, same degradation ladder, same test matrix.
// Do NOT "improve" the shape here without re-deriving all four platforms.
//
// ── WHY A SINGLE FUNCTION RETURNING A PAIR (and not two independent resolvers) ──
//
// The sale price and the struck-through original price MUST come from the SAME
// SOURCE. If they are resolved by two independent `??` fallbacks, the two can
// silently disagree the moment their degradation conditions differ — producing a
// FAKE DISCOUNT RATE on screen, e.g.:
//
//     spec sale NT$ 290  ×  product original NT$ 590   → claims 51% off
//     (reality: the product level is NT$ 390 / NT$ 590)
//
// Returning ONE value struct makes the mismatch UNREPRESENTABLE rather than merely
// discouraged-by-comment. Each independent resolver would also unit-test "correct"
// in isolation while the composed screen is wrong — the exact failure mode that is
// most likely to be re-introduced when this rule is mirrored to three more platforms.
//
// ── DEGRADATION LADDER ──
//
//   1. `selectedSpec == nil` (selection incomplete / unresolvable)
//        → the WHOLE PAIR falls back to the product level.
//        Mirrors the view-model's existing stock fallback shape
//        (`variantPicker.selectedSpec?.stock ?? productSheet.detail?.stock ?? 0`,
//        `DefaultPlayerTemplate.swift:1017` — NOT modified by this change).
//   2. `selectedSpec != nil` but its `priceShow` is blank (empty / whitespace-only)
//        → the WHOLE PAIR falls back to the product level.
//   3. otherwise
//        → the WHOLE PAIR is taken from the spec — INCLUDING a blank original price.
//
// ── WHY A BLANK `originalPriceShow` DOES *NOT* TRIGGER FALLBACK ──
//
// This is the single most mirror-fragile clause in the contract, so the reasoning is
// spelled out. The two fields are NOT symmetric:
//
//   • `priceShow` (sale price) is a MANDATORY-TO-DRAW field. A blank sale price
//     cannot be rendered, so a spec carrying one does not stand up as a source at
//     all → the whole pair falls back.
//   • `originalPriceShow` (was-price / strike-through) is an OPTIONAL-TO-DRAW field.
//     "This variant has no was-price" is a LEGITIMATE *no-discount* state, not a
//     data gap — the product level has always treated a blank original the same way.
//
// So a blank original MUST keep the spec source and simply not draw the strike-through.
// The two rejected alternatives, for the record:
//
//   • blank original → fall back the whole pair  ⇒ the screen would show the PRODUCT'S
//     SALE PRICE while the user has a NT$ 290 variant selected. Displayed price ≠ price
//     actually added to cart — far worse than a missing strike-through.
//   • blank original → borrow the product's original, keep the spec's sale price
//     ⇒ violates same-source atomicity outright, i.e. the fake discount above.
//
// ── BLANK CHECKS TRIM; RETURNED STRINGS ARE NEVER TRIMMED ──
//
// Per the SDK's JSON-decoder tolerance rules a free-text field may arrive as `""` or
// whitespace-only, so emptiness is judged AFTER trimming. But trimming is used for
// JUDGEMENT ONLY: the returned strings are the ORIGINALS, byte for byte. Returning a
// trimmed string would change rendered pixels (a merchant may pad `priceShow`
// deliberately) and would let per-platform trimming differences grow into visual drift.

/// A same-source price pair for the product sheets' price row: the sale price plus its
/// optional struck-through original, resolved together so they can never disagree.
///
/// Produced ONLY by ``resolvePriceDisplay(detail:selectedSpec:)`` — do not construct the
/// two fields from different sources at a call site (that is precisely what this type
/// exists to prevent).
public struct ResolvedPriceDisplay: Equatable {

    /// The sale price to draw, verbatim from whichever source won (spec or product).
    public let priceShow: String
    /// The original ("was") price to strike through, verbatim from the SAME source as
    /// ``priceShow``. May be blank — meaning that source genuinely has no was-price.
    public let originalPriceShow: String

    public init(priceShow: String, originalPriceShow: String) {
        self.priceShow = priceShow
        self.originalPriceShow = originalPriceShow
    }

    /// Whether a struck-through original price worth drawing exists.
    ///
    /// True only when ``originalPriceShow`` is non-blank AND differs from ``priceShow``
    /// (an original equal to the sale price is not a discount). Both sides are trimmed
    /// for the comparison only — see the file header note on trimming.
    ///
    /// The sheet MUST read this instead of re-deriving "is there an original?" from
    /// `detail` / `selectedSpec`, so that WHETHER a strike-through is drawn and WHICH
    /// string is drawn always agree.
    public var hasOriginalPrice: Bool {
        let original = ResolvedPriceDisplay.trimmed(originalPriceShow)
        guard !original.isEmpty else { return false }
        return original != ResolvedPriceDisplay.trimmed(priceShow)
    }

    /// Resolves the sheet's price pair from the product detail and the currently selected
    /// spec, ATOMICALLY: both returned fields always come from the same source.
    ///
    /// - Parameters:
    ///   - detail: the product-level detail (`DefaultProductSheet.detail`).
    ///   - selectedSpec: the resolved variant spec (`LBVariantState.selectedSpec`), or nil
    ///     when the selection is incomplete / unresolvable.
    /// - Returns: a ``ResolvedPriceDisplay`` whose two fields are both from `selectedSpec`
    ///   or both from `detail` — never mixed.
    ///
    /// Pure: no I/O, no global state, no mutation. Safe to call per-render.
    public static func resolvePriceDisplay(
        detail: LBProductDetailState,
        selectedSpec: LBSpec?
    ) -> ResolvedPriceDisplay {
        // The product-level pair — the single fallback target for BOTH degradation rungs,
        // so a fallback can never take one field from the spec and the other from here.
        let productLevel = ResolvedPriceDisplay(
            priceShow: detail.priceShow,
            originalPriceShow: detail.originalPriceShow)

        // Rung 1 — selection incomplete / unresolvable → whole pair from the product.
        guard let spec = selectedSpec else { return productLevel }

        // Rung 2 — the spec cannot supply a drawable sale price → whole pair from the
        // product. NOTE this deliberately discards a non-blank `spec.originalPriceShow`
        // too: keeping it would be exactly the mixed-source fake discount this type bans.
        guard !isBlank(spec.priceShow) else { return productLevel }

        // Rung 3 — whole pair from the spec, INCLUDING a blank original price (a genuine
        // "this variant has no was-price" → strike-through simply isn't drawn).
        return ResolvedPriceDisplay(
            priceShow: spec.priceShow,
            originalPriceShow: spec.originalPriceShow)
    }

    /// Blank (empty or whitespace-only) — the emptiness test used by every rung above.
    /// Judgement only; never applied to a returned string.
    static func isBlank(_ value: String) -> Bool {
        trimmed(value).isEmpty
    }

    /// Trimming used for JUDGEMENT ONLY (see file header) — never for returned values.
    static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
