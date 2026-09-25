// MARK: - WidgetLoadingDisplayState — family-5 widget surface three-way display decision
//
// Spec: `reference-ui-rendering/spec.md` (family-5 widget surfaces — 首次載入佔位).
// Design: rb-ios-widget-loading-placeholder design.md D4.
// Change: rb-ios-widget-loading-placeholder.
//
// Shared PURE decision for both `CarouselView` and `VideoShopGridView`: given the widget
// content's "first load in flight" signal (`WidgetModel.isLoading`) and whether any cards are
// available, decide which of the three surface states to render. Independently unit-testable
// without constructing / rendering a SwiftUI view. `loading` takes precedence over `empty` —
// while the first page is in flight `hasCards` is normally `false` too (nothing has loaded
// yet), but the loading placeholder MUST show regardless, never mistaken for "confirmed empty".

/// Three-way family-5 widget surface display state.
enum WidgetSurfaceDisplayState: Equatable {
    /// First page load in flight (`WidgetModel.isLoading == true`) — draw the centered
    /// `LoadingMarkAnimationView` placeholder sized to a real card row (header still shows).
    case loading
    /// Not loading AND no cards — CONFIRMED empty list. The whole surface (header included)
    /// renders NOTHING (replaces the old "目前沒有影片" text row).
    case empty
    /// Not loading AND at least one card — the existing (unchanged) content rendering.
    case content

    /// Pure derivation. See type doc for the `loading`-before-`empty` precedence rule.
    static func resolve(isLoading: Bool, hasCards: Bool) -> WidgetSurfaceDisplayState {
        if isLoading { return .loading }
        if !hasCards { return .empty }
        return .content
    }
}
