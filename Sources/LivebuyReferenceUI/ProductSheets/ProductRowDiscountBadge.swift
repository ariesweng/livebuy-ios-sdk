import Foundation

/// Pure `.row` price-block discount-percentage calculation (rb-ios-product-row-layout-and-
/// price-color, design R45). Zero SwiftUI dependency — mirrors this module's existing
/// pure-function siblings (`ProductRowOverlay.decide`, `ProductRowNameTag.resolve`,
/// `ProductRowNumberBadge.resolveIndex`), independently unit-testable without a view host.
///
/// Reads `LBProduct`'s raw numeric `price` / `originalPrice` fields directly — NOT the
/// pre-formatted `priceShow` / `originalPriceShow` display strings (locale-formatted text like
/// `"NT$590"`, not parseable numbers).
///
/// Formula: `floor((originalPrice - price) / originalPrice * 100)` — verified against design
/// source `design/templates/minimal/sdk-components.jsx`'s own hand-authored demo data
/// (`originalPrice: 890, price: 590` → the design's literal `off: 33`). `floor(33.708...) == 33`
/// matches; `round(33.708...) == 34` does NOT — this is the deciding evidence for `floor` over
/// `round` (the design source has no explicit rounding-rule comment; the demo data is the only
/// available ground truth).
public enum ProductRowDiscountBadge {
    /// `nil` whenever there is nothing meaningful to show: no `originalPrice`, `originalPrice`
    /// not actually higher than `price` (mirrors the pre-existing original-price-strikethrough
    /// guard's intent — the caller is expected to already gate on the `originalPriceShow`
    /// non-empty/non-equal check before calling this too, but this function re-derives its own
    /// defensive `nil` rather than trusting the caller), a non-positive `originalPrice` (avoids
    /// a divide-by-zero), or a computed percentage that floors down to `0` (e.g. `originalPrice:
    /// 101, price: 100` → `0.99...%` → `floor` → `0` — a real, if rare, floor-rounding boundary,
    /// not an error — showing a misleading "0%" badge would be worse than showing nothing).
    public static func percent(price: Double, originalPrice: Double?) -> Int? {
        guard let originalPrice = originalPrice, originalPrice > price, originalPrice > 0 else {
            return nil
        }
        let off = Int(floor((originalPrice - price) / originalPrice * 100))
        return off > 0 ? off : nil
    }
}
