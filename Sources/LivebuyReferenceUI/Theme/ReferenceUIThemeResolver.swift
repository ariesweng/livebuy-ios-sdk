import SwiftUI
import LivebuySDK
import LivebuyUI

// MARK: - ReferenceUIThemeResolver — pure theme merge
//
// Spec: `reference-ui-rendering/spec.md`
//   § "Reference-UI 主題解析合併序 sdkConfig.theme > host options > minimal palette"
// Design: rb-ios-scaffold design.md D-E.
//
// Pure function: inputs three sources, outputs a resolved `ReferenceUITheme`,
// NO implicit global side effects (`docs/unit-test-discipline.md`). Merge order
// (high → low):
//
//     sdkConfig.theme (core)  >  LBUIOptions (host)  >  minimal palette (fallback)
//
// Each token resolves INDEPENDENTLY through the chain — a core theme that
// supplies only `primaryColor` still lets `fontScale` fall through to host /
// minimal. This is intentional per-field merge (not all-or-nothing).
//
// This resolver is and stays INDEPENDENT of `widget_color` / `widget_bgcolor`:
// those two MUST NOT become inputs here, and this output MUST NOT vary with them
// (`reference-ui-rendering` § 解析器輸出不受 widget 顏色影響). They are applied in a
// SEPARATE, NARROWER step that runs after this one and only on the three widget
// surfaces — `ReferenceUIWidgetEmbedTheme.derive` (rb-ios-widget-embed-colors).
// Wiring them in here would tint the player and every sheet, since `background` /
// `text` are global tokens. Effective order:
//
//   sdkConfig.theme  >  widget colors (widget surfaces only)  >  LBUIOptions  >  minimal

public enum ReferenceUIThemeResolver {

    /// Resolve the effective reference-ui theme from the three sources.
    ///
    /// - Parameters:
    ///   - coreTheme:    `sdkConfig.theme` (core global theme), highest priority.
    ///   - hostOptions:  the host-supplied `LBUIOptions` (its `.theme`), middle.
    ///   - fallback:     the lowest-priority palette (default: minimal).
    /// - Returns: the merged `ReferenceUITheme`.
    public static func resolve(coreTheme: SDKConfig.Theme?,
                               hostOptions: LBUIOptions?,
                               fallback: ReferenceUITheme = ReferenceUIThemePalette.minimal) -> ReferenceUITheme {
        let hostTheme = hostOptions?.theme

        // primaryColor → accent (per-field chain: core > host > fallback).
        let accent = firstColor(coreTheme?.primaryColor, hostTheme?.primaryColor) ?? fallback.accent

        // fontScale (Float on the wire) → CGFloat (core > host > fallback).
        let fontScale = firstFontScale(coreTheme?.fontScale, hostTheme?.fontScale) ?? fallback.fontScale

        // background / text / cornerRadius have no core/host wire field today, so
        // they take the fallback palette directly (future family changes may add
        // host inputs; the chain shape stays the same).
        return ReferenceUITheme(
            accent: accent,
            background: fallback.background,
            text: fallback.text,
            cornerRadius: fallback.cornerRadius,
            fontScale: fontScale
        )
    }

    /// First parseable hex color from the priority-ordered hex strings, or nil.
    private static func firstColor(_ candidates: String?...) -> Color? {
        for candidate in candidates {
            if let hex = candidate, let color = Color(hex: hex) {
                return color
            }
        }
        return nil
    }

    /// First present font scale from the priority-ordered values, or nil.
    private static func firstFontScale(_ candidates: Float?...) -> CGFloat? {
        for candidate in candidates {
            if let value = candidate {
                return CGFloat(value)
            }
        }
        return nil
    }
}
