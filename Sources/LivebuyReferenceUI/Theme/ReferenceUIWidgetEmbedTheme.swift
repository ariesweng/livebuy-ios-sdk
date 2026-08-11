import SwiftUI

// MARK: - ReferenceUIWidgetEmbedTheme — widget-scope embed-color derivation
//
// Spec: `widget-embed-colors/spec.md`
// Design: rb-ios-widget-embed-colors design.md D1 / D2 / D4 / D5.
//
// A SECOND, NARROWER step that runs AFTER `ReferenceUIThemeResolver` and ONLY on
// the widget surfaces (`CarouselView` / `ScrollableCarouselView` /
// `VideoShopGridView`). It takes the already-resolved theme and overlays the two
// web-embed colors from `POST /sdk/widget`:
//
//     ReferenceUIThemeResolver.resolve(...)   →  ReferenceUITheme   (global)
//                                                      │
//              widgetColor / widgetBgcolor  ──▶  derive(...)        (widget only)
//                                                      │
//                                                      ▼
//                        CarouselView / ScrollableCarouselView / VideoShopGridView
//
// WHY A SEPARATE STEP INSTEAD OF FEEDING THE RESOLVER: `background` / `text` are
// GLOBAL tokens — `PlayerShellView`, `VideoInfoPanel`, the product sheets,
// `WinClaimSheet`, `AuthGateModalView` and dozens of other surfaces read them.
// Injecting a merchant's widget colors into the resolver would tint the player
// and every sheet. The resolver therefore stays UNTOUCHED and still MUST NOT see
// these two values (`reference-ui-rendering` § resolver 輸出不受 widget 顏色影響).
//
// Effective priority (high → low):
//
//     sdkConfig.theme  >  widget colors (here)  >  LBUIOptions  >  minimal palette
//
// Pure — no global reads, no side effects (`docs/unit-test-discipline.md`).

public enum ReferenceUIWidgetEmbedTheme {

    /// `widget_color == 2`（色彩反轉）的文字色，對齊 web embed 渲染端的 `#ffffff`.
    public static let invertedTextHex = "#FFFFFF"

    /// Resolved `#FFFFFF` for the inverted text mode.
    public static let invertedText = Color(hex: invertedTextHex) ?? .white

    /// The wire value of `widget_color` meaning「色彩反轉」(inverted text).
    public static let invertedColorMode = 2

    /// Overlay the `/sdk/widget` embed colors onto an already-resolved theme.
    ///
    /// - `widgetColor` `2`（色彩反轉）→ `text` becomes `#FFFFFF`. `1`（預設色彩）
    ///   and every other value leave `text` UNTOUCHED. Web's `1` means "emit no
    ///   color override" — its native equivalent is keeping the resolved `text`,
    ///   NOT adopting the third-party page's `#3C3C3C` body default (D1).
    /// - `widgetBgcolor` overrides `background` ONLY when it parses as a hex
    ///   color. The empty string `""`（後端的「透明」表示法）, a missing value and
    ///   any unparseable string all mean "leave it alone" (D2) — `Color(hex:)` is
    ///   failable and rejects `""` on its `count == 6` guard, so all three land on
    ///   the same branch without a special case.
    ///
    /// Value-domain tolerance (numeric string `"2"` → `2`, unparseable → `1`) is
    /// core's job per `widget-decode-robustness`; this function does NOT redo it.
    ///
    /// - Returns: a theme where at most `text` / `background` differ. When nothing
    ///   is configured the result is EQUAL to `theme` (D6 — keeps the existing
    ///   snapshot baselines byte-identical).
    public static func derive(from theme: ReferenceUITheme,
                              widgetColor: Int,
                              widgetBgcolor: String?) -> ReferenceUITheme {
        let text = widgetColor == invertedColorMode ? invertedText : theme.text
        let background = widgetBgcolor.flatMap { Color(hex: $0) } ?? theme.background

        return ReferenceUITheme(
            accent: theme.accent,
            background: background,
            text: text,
            cornerRadius: theme.cornerRadius,
            fontScale: theme.fontScale
        )
    }
}
