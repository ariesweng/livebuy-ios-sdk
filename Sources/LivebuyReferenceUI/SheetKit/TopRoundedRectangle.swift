import SwiftUI

// MARK: - iOS-14-safe top-rounded sheet shape (SheetKit)
//
// `LBPBottomSheet` rounds ONLY the top two corners (`borderRadius: 20px 20px 0 0`).
// `RoundedRectangle` rounds all four; `UIRectCorner`-masked corners via
// `cornerRadius(_:corners:)` need a custom `Path`, which is iOS-13+ safe.
//
// Moved here (from `VideoInfoPanelView.swift`) by `sheetkit-foundation` so the shared
// `BottomSheetPresenter` and every bottom-sheet leaf reference ONE module-internal shape.

struct TopRoundedRectangle: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(radius, min(rect.width, rect.height) / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + r, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + r),
            control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
