import SwiftUI

// MARK: - SheetGrabHandle — the shared bottom-sheet grab handle (SheetKit)
//
// ONE definition of the `LBPBottomSheet` handle (a 36×4 rounded pill, centered, with the
// design's top/bottom padding), replacing the 4 self-drawn copies that previously lived in
// `VideoInfoPanelView` / `ProductListView` / `ProductDetailSheetView` /
// `NotifyRestockSheetView`. `BottomSheetPresenter` draws this at the card's top and binds the
// drag-to-dismiss gesture to it (so dragging never eats a CTA / tab tap). iOS-14-safe.
struct SheetGrabHandle: View {

    /// The handle pill color — the house `strokeStrong` design literal (`#D8D5DE`), the SAME
    /// value the leaf sheets used, so the handle stays pixel-identical after consolidation.
    private static let handleColor = Color(hex: "#D8D5DE") ?? Color.gray.opacity(0.35)

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: 99)
                .fill(Self.handleColor)
                .frame(width: 36, height: 4)
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}
