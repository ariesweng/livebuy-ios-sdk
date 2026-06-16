import SwiftUI
import LiveBuySDK
import LiveBuyUI

// MARK: - LiveBuyReferenceUI — iOS reference-ui pixel layer namespace
//
// Spec: `reference-ui-rendering/spec.md`
// Design: rb-ios-scaffold design.md D-B / D-C / D-H.
//
// This is the ONLY iOS product allowed to carry SwiftUI pixel-rendering code.
// Dependency is strictly one-way: LiveBuyReferenceUI → LiveBuyUI → LiveBuySDK.
// `LiveBuyUI` (template) stays headless / zero-pixel; `LiveBuySDK` (core) stays
// headless. Pixels live ONLY here.
//
// SwiftUI is the rendering technology (D-B). The package `platforms` floor stays
// `.iOS(.v14)`; anything requiring a SwiftUI API above iOS 14 MUST be guarded
// with `@available` / `if #available`. The smoke view below uses ONLY
// iOS-14-safe SwiftUI so it needs no guard — that is the pattern family changes
// must follow.

/// Namespace marker for the iOS reference-ui pixel layer.
public enum LiveBuyReferenceUI {
    /// Human-readable layer identity (handy for diagnostics / smoke assertions).
    public static let layerName = "reference-ui"
}

// MARK: - ReferenceUISmokeView — minimal chain-proof view (D-H)
//
// The scaffold's sole pixel artifact: it proves the chain
// LiveBuyReferenceUI → LiveBuyUI → LiveBuySDK compiles and renders. It binds ONE
// existing, stable, host-readable `livebuy-ui` view-model type (`LBStartScreenPhase`,
// a public moment-state enum from `LiveBuyUI`) to prove the template import is
// reachable, and paints a deterministic themed layout.
//
// It does NOT render any family's full pixels (player-shell / feed-win /
// product-sheets / moments / widget / gap-surfaces) — that is each family
// change's job.

/// A minimal, deterministic SwiftUI view that renders the resolved
/// `ReferenceUITheme` accent + a label. iOS-14-safe only.
public struct ReferenceUISmokeView: View {

    /// The resolved reference-ui theme (from `ReferenceUIThemeResolver`).
    public let theme: ReferenceUITheme

    /// A bound `livebuy-ui` view-model value — proves the `LiveBuyUI` (template)
    /// type is reachable from this layer. `LBStartScreenPhase` is an existing,
    /// stable, host-readable moment-state enum exported by `LiveBuyUI`; binding
    /// it here carries NO family-pixel semantics — it only labels the smoke view.
    public let phase: LBStartScreenPhase

    public init(theme: ReferenceUITheme,
                phase: LBStartScreenPhase = .done) {
        self.theme = theme
        self.phase = phase
    }

    public var body: some View {
        VStack(spacing: 12) {
            // Accent swatch — the resolved accent token, drawn as a rounded chip.
            RoundedRectangle(cornerRadius: theme.cornerRadius)
                .fill(theme.accent)
                .frame(width: 120, height: 48)

            // A themed label that also references the bound view-model, proving
            // the LiveBuyUI type is reachable and usable from reference-ui.
            Text("reference-ui · \(Self.label(for: phase))")
                .font(.system(size: 14 * theme.fontScale, weight: .semibold))
                .foregroundColor(theme.text)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background)
    }

    /// Deterministic label for the bound moment-state phase. Pure, no pixels.
    static func label(for phase: LBStartScreenPhase) -> String {
        switch phase {
        case .loading:   return "loading"
        case .splash:    return "splash"
        case .buffering: return "buffering"
        case .done:      return "ready"
        }
    }
}
