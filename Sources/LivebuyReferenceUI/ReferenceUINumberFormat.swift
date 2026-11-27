import Foundation

/// Pure numeric helpers for reference-ui display code (rb-ios-price-int-conversion-guard).
///
/// Swift's `Int(_: Double)` traps (crashes the host App) when the value is NaN / ±infinity or
/// falls outside `Int.min...Int.max`. `LBProduct.price` / `originalPrice` are unbounded
/// `Double`s decoded straight from the API, so any display code that turns them into an
/// integer MUST go through `safeInt` instead of calling `Int(_:)` directly.
enum ReferenceUINumberFormat {
    /// Truncates `value` toward zero (same result as `Int(value)` for every value `Int(value)`
    /// can handle) and returns `nil` instead of trapping when the result is not representable
    /// as `Int` (non-finite, or outside `Int.min...Int.max`).
    static func safeInt(_ value: Double) -> Int? {
        guard value.isFinite else { return nil }
        return Int(exactly: value.rounded(.towardZero))
    }
}
