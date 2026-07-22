import Foundation
import LivebuySDK
import LivebuyUI

// MARK: - ResolvedProductPhoto — spec-aware product photo SOURCE for the product sheets
//
// Spec: `reference-ui-rendering/spec.md`
//   § "LivebuyReferenceUI 商品明細 / 加入購物車 sheet 與 zoom 燈箱的商品主圖跟隨 selectedSpec，
//      來源有效性與所繪項目同述詞解析（iOS）"
// Change: ios-product-sheet-spec-photo-reference-ui.
// Sibling: `ResolvedPriceDisplay.swift` (ios-product-sheet-spec-price-reference-ui) — same
// skeleton, same degradation-ladder shape, same "single shared fallback target" structure.
//
// ⚠️ FOUR-PLATFORM PARITY CONTRACT BASELINE ⚠️
// iOS is the LEAD platform for this rule. Android (`:livebuy-reference-ui`
// `ResolvedProductPhoto.kt`), React Native (`resolvedProductPhoto.ts`) and Flutter
// (`resolved_product_photo.dart`) MIRROR THIS FILE VERBATIM — same type name, same function
// name, same field names, same degradation ladder, same `primaryPhoto` predicate, same test
// matrix. Do NOT "improve" the shape here without re-deriving all four platforms.
// The ONE thing that is NOT part of the contract is `primaryPhotoURL` — see its own note.
//
// ── WHY THE RESULT IS THE WHOLE ARRAY (and not a single resolved URL) ──
//
// What this resolution decides is the SOURCE (the selected spec, or the product level).
// "Which one of its photos do we draw" is a DERIVED question, asked after the source is
// settled. If the function returned a single value, the source decision would be buried
// inside that value and lost: every additional consumer (the zoom lightbox today, a
// multi-image gallery tomorrow) would have to RE-DERIVE the degradation ladder for itself
// — and the moment two derivations disagree, the screen shows the spec's photo in the
// sheet and the product's photo in the lightbox.
//
// That is the same failure mode `ResolvedPriceDisplay` exists to make unrepresentable
// (two independent `??` fallbacks silently disagreeing), transposed onto photos. Returning
// the array makes the source decision happen EXACTLY ONCE; every consumer reads the same
// resolved source, and `primaryPhoto` is the single place that answers "which one".
//
// ── DEGRADATION LADDER ──
//
//   1. `selectedSpec == nil` (selection incomplete / unresolvable)
//        → the product level. Mirrors the view-model's existing stock fallback shape
//        (`variantPicker.selectedSpec?.stock ?? productSheet.detail?.stock ?? 0`,
//        `DefaultPlayerTemplate.swift:1017` — NOT modified by this change) and the
//        sibling price resolver's rung 1.
//   2. `selectedSpec != nil` but its `photos` is empty, OR contains no entry that is
//      non-blank after trimming
//        → the product level (that source cannot draw anything, so it does not stand up
//        as a source at all).
//   3. otherwise
//        → the spec's photos.
//
// ── THE MOST MIRROR-FRAGILE CLAUSE: `primaryPhoto` IS *NOT* `photos.first` ──
//
// `primaryPhoto` is the FIRST NON-BLANK entry, not the first entry. This is load-bearing,
// and an implementation that uses `photos.first` will still pass the two obvious tests
// ("spec has no photos" / "spec's first photo is valid") while being wrong:
//
//     spec.photos == ["", "https://cdn/spec-rose.jpg"]
//
//   • rung 2 asks "does this source have anything drawable?" → YES → the source is
//     LOCKED to the spec, no fallback to the product level.
//   • a `photos.first` display predicate then reads `""` → nil → the sheet draws the
//     gradient + monogram PLACEHOLDER.
//
// So the user picks a variant that demonstrably HAS a photo and sees a monogram, with no
// product photo to fall back to either — strictly WORSE than before this change. The fix
// is not a bigger comment: "is this source valid" and "what do we draw" MUST BE THE SAME
// PREDICATE. `resolveProductPhoto` therefore spells rung 2 as `primaryPhoto == nil` on a
// candidate value, so the two are coupled STRUCTURALLY and cannot drift apart.
//
// Side effect, deliberate and accepted: the PRODUCT level gets the same predicate, so
// `detail.photos == ["", "https://…"]` now loads that photo instead of drawing a
// placeholder. A strict improvement, observable only on the host-runtime path that loads
// real images (`live == true`); the snapshot path never loads images, so baselines are
// untouched.
//
// ── BLANK CHECKS TRIM; RETURNED STRINGS ARE NEVER TRIMMED ──
//
// Per the SDK's JSON-decoder tolerance rules a free-text field may arrive as `""` or
// whitespace-only, so emptiness is judged AFTER trimming. Trimming is for JUDGEMENT ONLY:
// `photos` and `primaryPhoto` hand back the ORIGINAL strings, byte for byte, and `photos`
// is a VERBATIM copy of the winning source — never filtered, reordered, or cleaned up.
// (Filtering out the blanks here would quietly change indices, which a future gallery
// would then disagree with.)

/// The resolved product-photo SOURCE for the product sheets: whichever array of photo
/// strings won — the selected spec's, or the product's — together with the single answer
/// to "which one do we draw".
///
/// Produced ONLY by ``resolveProductPhoto(detail:selectedSpec:)`` — do not pick a photo out
/// of `detail.photos` / `selectedSpec.photos` at a call site (that is precisely what this
/// type exists to prevent).
public struct ResolvedProductPhoto: Equatable {

    /// The winning source's photo strings, VERBATIM — same order, same elements, blanks
    /// included. Never a mix of the two sources, never filtered or reordered.
    public let photos: [String]

    public init(photos: [String]) {
        self.photos = photos
    }

    /// The photo to draw: the FIRST entry that is non-blank after trimming, returned
    /// VERBATIM (untrimmed). `nil` when this source has nothing drawable.
    ///
    /// NOT `photos.first` — see the file header. This predicate is also what
    /// ``resolveProductPhoto(detail:selectedSpec:)`` uses to decide whether a source is
    /// valid at all, so "the ladder picked this source" and "this source can be drawn"
    /// are the same statement by construction.
    public var primaryPhoto: String? {
        photos.first { !ResolvedProductPhoto.isBlank($0) }
    }

    /// Whether there is a photo worth drawing — i.e. whether the caller should load an
    /// image instead of the deterministic gradient + monogram placeholder.
    ///
    /// The sheets MUST read this (or ``primaryPhotoURL``) instead of re-deriving
    /// "are there photos?" from `detail` / `selectedSpec`, so that WHETHER an image is
    /// drawn and WHICH image is drawn always agree.
    public var hasPhoto: Bool { primaryPhoto != nil }

    /// ⚠️ iOS-LOCAL ADAPTER — **NOT part of the four-platform contract.** ⚠️
    ///
    /// ``primaryPhoto`` as a `Foundation.URL`, or nil when there is nothing to draw / the
    /// string is not a usable URL. Android / React Native / Flutter MUST mirror
    /// ``photos`` / ``primaryPhoto`` / ``hasPhoto`` and then wrap them in whatever their
    /// own image pipeline wants (`Uri` / `{ uri: … }` / `Uri`) — they MUST NOT mirror the
    /// shape of this property.
    ///
    /// Trimming here is a URL-CONSTRUCTION requirement, not a rendering decision:
    /// `URL(string: " https://x ")` fails. It does not contradict the "returned strings are
    /// never trimmed" rule — ``primaryPhoto`` itself is still verbatim. Preserves the prior
    /// `ProductDetailSheetView.photoURL` behaviour exactly.
    public var primaryPhotoURL: URL? {
        guard let photo = primaryPhoto else { return nil }
        return URL(string: ResolvedProductPhoto.trimmed(photo))
    }

    /// Resolves the sheet's product-photo SOURCE from the product detail and the currently
    /// selected spec.
    ///
    /// - Parameters:
    ///   - detail: the product-level detail (`DefaultProductSheet.detail`).
    ///   - selectedSpec: the resolved variant spec (`LBVariantState.selectedSpec`), or nil
    ///     when the selection is incomplete / unresolvable.
    /// - Returns: a ``ResolvedProductPhoto`` whose ``photos`` is a verbatim copy of either
    ///   `selectedSpec.photos` or `detail.photos` — never a mix, never filtered.
    ///
    /// Pure: no I/O, no global state, no mutation. Safe to call per-render.
    public static func resolveProductPhoto(
        detail: LBProductDetailState,
        selectedSpec: LBSpec?
    ) -> ResolvedProductPhoto {
        // The product-level source — the single shared fallback target for BOTH degradation
        // rungs, so a fallback can never assemble a result out of two sources.
        let productLevel = ResolvedProductPhoto(photos: detail.photos)

        // Rung 1 — selection incomplete / unresolvable → product level.
        guard let spec = selectedSpec else { return productLevel }

        // Rung 2 — the spec source cannot draw anything → product level.
        //
        // The validity test is deliberately expressed as `primaryPhoto == nil` ON THE
        // CANDIDATE ITSELF rather than as a separate `contains(where:)` scan. That is what
        // makes "this source is valid" and "this source has something to draw" ONE
        // predicate instead of two that can drift — see the file header's `["", "url"]`
        // walkthrough for what drift costs.
        let specLevel = ResolvedProductPhoto(photos: spec.photos)
        guard specLevel.primaryPhoto != nil else { return productLevel }

        // Rung 3 — the spec source wins, verbatim (blanks and ordering preserved).
        return specLevel
    }

    /// Blank (empty or whitespace-only) — the emptiness test used by ``primaryPhoto`` and,
    /// through it, by the ladder's rung 2. Judgement only; never applied to a returned value.
    static func isBlank(_ value: String) -> Bool {
        trimmed(value).isEmpty
    }

    /// Trimming used for JUDGEMENT and for URL construction only (see file header) —
    /// never for the strings handed back in ``photos`` / ``primaryPhoto``.
    static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
