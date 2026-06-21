import SwiftUI

// MARK: - SheetHeaderCloseButton — shared sheet-header close affordance
//
// Spec: `reference-ui-rendering/spec.md` (rb-ios-sheet-header-close-unify)
// Design: `design/templates/minimal/screens.jsx` — every sheet header's close button is a
//          TRANSPARENT circular tap target + `Icons.close` + `theme.surface.text`, calling `onClose`
//          (`ProductListSheet` / `ProductDetailSheet` / `AddToCartSheet` / `NotifyRestockSheet` /
//          `VideoInfoSheet` share the one regime).
//
// Before this change the close glyphs diverged: ProductListView used a transparent `xmark`
// (but it was DECORATIVE — no action), while ProductDetailSheetView / AddToCartSheetView /
// NotifyRestockSheetView drew a `Circle(bgSunken)` + `xmark 11pt`. This shared leaf collapses
// all sheet-header close icons onto ONE transparent style aligned to ProductListView / the design,
// and every host wires it to an actual dismiss path. VideoInfoPanel — which previously had NO
// explicit close icon — also adopts it.
//
// Pure presentation: the button only forwards `onTap`. The container owns the presentation
// binding (`listPresented` / `infoPanelPresented` / `dismissDetail()`); this leaf never reaches
// back into a view-model. `onTap == nil` (demo / snapshot) → tap is a no-op (zero-pixel wiring).
//
// iOS-14-safe: `Button` / `ZStack` / `Image` / `.contentShape` are all iOS-13+.

/// The shared transparent sheet-header close button: a 32×32 transparent tap target with an
/// `xmark` glyph in `theme.text`, aligned to ProductListView's close icon and the design's
/// `Icons.close`. Forwards `onTap` (the container wires it to the sheet's dismiss path).
public struct SheetHeaderCloseButton: View {

    /// The resolved reference-ui theme (FIRST positional argument, always).
    public let theme: ReferenceUITheme

    /// Host / container-wired dismiss. nil for demo / snapshot instances — tap is a no-op.
    private let onTap: (() -> Void)?

    public init(theme: ReferenceUITheme, onTap: (() -> Void)? = nil) {
        self.theme = theme
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: { onTap?() }) {
            ZStack {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(theme.text)
            }
            .frame(width: 32, height: 32)        // transparent tap target — NO background fill
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier(LBAccessibilityID.sheetHeaderClose)
    }
}
