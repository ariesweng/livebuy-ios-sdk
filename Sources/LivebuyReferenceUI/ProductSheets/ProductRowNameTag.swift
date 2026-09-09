import Foundation

// MARK: - ProductRowNameTag — pure decision for `.row`'s inline name-tag pill
//         (rb-ios-product-row-name-tag-system, design R39
//          `design/templates/minimal/sdk-components.jsx:LBPProductRow`)
//
// Mirrors this module's established pattern of extracting a pure, zero-dependency
// decision function alongside a SwiftUI view consumer (`ProductRowOverlay.decide`,
// `ProductRowNumberBadge.resolveIndex`) — unit-test-discipline: no SwiftUI host needed
// to exercise the branching.

/// Which inline pill (if any) `ProductRowView`'s `.row` layout draws immediately
/// BEFORE `product.name` (replacing the previous after-price placement for the
/// `out_soon` / `hot` badges — `rb-ios-product-row-name-tag-system` decision 1).
public enum ProductRowNameTag: Equatable {
    /// `mode == .live`, NOT sold out, NOT a flash-sale channel — outline "直播價" pill.
    /// See `resolve(mode:label:soldOut:isFlashSale:)`.
    case livePrice
    /// `mode == .live`, NOT sold out, flash-sale channel (`isFlashSale == true`) —
    /// solid "搶購中" pill (`rb-ios-flash-sale-live-signal-wiring`). The rush-mode
    /// signal this module previously had no source for (see the retired "pipe-first,
    /// no water yet" note this case replaces) is now `header.isFlashSale`, threaded
    /// in from `DefaultPlayerHeaderState.isFlashSale` (`channel-flash-sale-flag-
    /// template`, itself a straight mirror of core `LBChannel.isFlashSale` /
    /// backend `is_flash_sale`).
    case rush
    /// `mode == .vod || .replay`, NOT sold out, backend `label == "out_soon"` — 即將售完.
    case outSoon
    /// `mode == .vod || .replay`, NOT sold out, backend `label == "hot"` — 熱賣中.
    case hot
    /// No tag drawn — either sold out (highest priority, ANY mode), or no matching
    /// case above.
    case none

    /// - Parameters:
    ///   - mode: the row's `ProductRowMode` (`.row` layout only — `.grid` never reads
    ///     `mode` and never calls this).
    ///   - label: `product.label`, the backend single-priority-source conclusion field
    ///     (`sold_out > narrating > out_soon > hot`). Consumed via the EXISTING
    ///     `ProductStatusBadge.fromLabel` for the `.vod`/`.replay` branch only — NOT
    ///     re-derived here.
    ///   - soldOut: the row's ALREADY-RESOLVED sold-out status (the caller's existing
    ///     `ProductStatusBadge.resolve(product) == .soldOut`, which — unlike
    ///     `fromLabel(label)` — also covers the raw-field fallback path: `label == ""`
    ///     with raw `product.soldOut == 1`, the common demo/legacy-backend shape). This
    ///     is the SAME single source of truth `ProductRowView`'s own `soldOut` property
    ///     already computes for the「已售完」price-row swap — passed in here rather
    ///     than re-derived, so there is only ever ONE place that resolves "is this row
    ///     sold out", not two that could drift.
    ///   - isFlashSale: the channel-level 搶購場 flag (`ProductSheetsModel.isFlashSale`,
    ///     ← `DefaultPlayerHeaderState.isFlashSale` ← core `LBChannel.isFlashSale` ←
    ///     backend top-level `is_flash_sale`, independent of `type`/`live_status`).
    ///     Only consulted in the `.live` branch — `.vod`/`.replay` ignore it entirely
    ///     (the design source's `nameTag` `liveMode` branch only applies to
    ///     `live && !replay`).
    ///
    /// Sold-out is the HIGHEST-priority gate, checked BEFORE the `mode` branch and
    /// applying to EVERY mode uniformly — matching the design source's `nameTag`
    /// logic (`design/templates/minimal/sdk-components.jsx:LBPProductRow`), whose
    /// very first step is `p.sold ? null : ...`, unconditional on live/replay/VOD.
    /// A prior revision of this function checked `soldOut` ONLY inside the
    /// `.vod`/`.replay` branch (via `fromLabel(label) == .soldOut`, itself only
    /// reachable when `label` is the explicit string `"sold_out"`) and let `.live`
    /// fall straight through to `.livePrice` with no sold-out check at all — a
    /// sold-out product in LIVE mode incorrectly still showed the "直播價" pill.
    /// Fixed by hoisting the check above `switch mode` and sourcing it from the
    /// caller's full-fallback `soldOut: Bool` (not `fromLabel(label)` alone, which
    /// misses the `label == "" && product.soldOut == 1` raw-fallback shape).
    ///
    /// **Water has arrived** (`rb-ios-flash-sale-live-signal-wiring`): the `.live`
    /// branch used to be a flat `return .livePrice` — this module's doc previously
    /// called that "pipe-first, no water yet" because no call site could express a
    /// rush-mode signal. `isFlashSale` is that signal now, so the `.live` branch is a
    /// two-way split on it instead.
    public static func resolve(
        mode: ProductRowMode, label: String, soldOut: Bool, isFlashSale: Bool
    ) -> ProductRowNameTag {
        guard !soldOut else { return .none }
        switch mode {
        case .live:
            return isFlashSale ? .rush : .livePrice
        case .vod, .replay:
            switch ProductStatusBadge.fromLabel(label) {
            case .outSoon: return .outSoon
            case .hot:     return .hot
            default:       return .none
            }
        }
    }
}
