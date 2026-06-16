import SwiftUI
import LiveBuySDK
import LiveBuyUI

// MARK: - ProductZoomOverlayView — family-3 product-image lightbox (rb-ios-product-image-zoom-lightbox)
//
// Spec: `reference-ui-rendering/spec.md` (family-3 product + sheets, 商品圖 zoom badge 可點 + 燈箱)
// Design: `design/templates/minimal/screens.jsx` `ProductZoomOverlay` (31-95).
//
// The full-frame product-image zoom viewer, mounted at the `ProductSheetsOverlayView`
// root (ABOVE the `lbBottomSheet` sheet stack) when a sheet's zoom badge is tapped. It
// reads ONE `LBProductDetailState` (`photos` + `name`) — purely a pixel-layer affordance,
// no view-model / template / core state. Behaviour mirrors the design's `ProductZoomOverlay`:
//
//   • dark backdrop (0.92) fade-in; tap the backdrop to close.
//   • centered square product image (84% width, aspect 1:1, radius 16, shadow);
//     tap-to-zoom (1 ⇄ 2.4×); drag-to-pan when zoomed (clamped to ±110*(z-1));
//     a second tap resets to z == 1 with pan zeroed.
//   • top-right circular close button.
//   • bottom gradient caption: product name + hint (zoomed → 拖曳檢視細節, else 點圖片放大).
//
// Photo rendering reuses `ProductDetailSheetView`'s static helpers (`photoURL` / `monogram`)
// + the same gradient placeholder: `live == false` (snapshot / demo) draws the deterministic
// gradient + monogram only; `live == true` overlays `RemoteStillImageView` (.scaleAspectFill).
//
// iOS-14-safe SwiftUI only: `ZStack` / `GeometryReader` / `Button` / `DragGesture` /
// `LinearGradient` / `.scaleEffect` / `.offset` / `edgesIgnoringSafeArea` are all iOS-13+.
// No `.task` / `AsyncImage` / `NavigationStack` / `.foregroundStyle` / `.tint`.
//
// Snapshot determinism: `shown` (the fade-in flag) is `@State` seeded from `shownInitially`
// in `init` (the `ImageRenderer` snapshot path runs no `onAppear`), mirroring
// `BottomSheetPresenter`'s init-seeded presence flag. Snapshot/demo pass `shownInitially: true`
// so the lightbox renders its open state (backdrop opaque, image visible) deterministically.

/// The family-3 full-frame product-image zoom viewer for one `LBProductDetailState`.
public struct ProductZoomOverlayView: View {

    /// The resolved reference-ui theme (FIRST positional argument, always).
    public let theme: ReferenceUITheme
    /// The product whose image is being zoomed (reads `photos` + `name`). Read-only.
    public let detail: LBProductDetailState
    /// `false` (snapshot / demo) → gradient + monogram placeholder only (deterministic baseline);
    /// `true` (host runtime) → load `detail.photos[0]` over the placeholder via `RemoteStillImageView`.
    public let live: Bool
    /// Host-wired close (backdrop tap / close button) → container clears `zoomedDetail`.
    private let onClose: (() -> Void)?

    /// Zoom factor, toggled between `1` and `Self.zoomed` (2.4×). `@State` (default 1).
    @State private var z: CGFloat = 1
    /// Current pan offset (only meaningful when `z > 1`). Clamped to ±`110*(z-1)`.
    @State private var pan: CGSize = .zero
    /// Pan at the START of the active drag (so `onChanged` accumulates from there).
    @State private var panBase: CGSize = .zero
    /// Fade-in presence flag. Seeded from `shownInitially` in `init` (snapshot path has no
    /// `onAppear`); flipped true on `onAppear` for the runtime fade-in.
    @State private var shown: Bool

    /// The toggled zoom factor (design `ZOOMED = 2.4`).
    private static let zoomed: CGFloat = 2.4

    public init(
        theme: ReferenceUITheme,
        detail: LBProductDetailState,
        live: Bool = false,
        shownInitially: Bool = false,
        onClose: (() -> Void)? = nil
    ) {
        self.theme = theme
        self.detail = detail
        self.live = live
        self.onClose = onClose
        self._shown = State(initialValue: shownInitially)
    }

    public var body: some View {
        GeometryReader { geo in
            let side = geo.size.width * 0.84
            ZStack {
                backdrop
                imageCard(side: side)
                closeLayer
                captionLayer
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onAppear { withAnimation(.easeOut(duration: 0.2)) { shown = true } }
    }

    // MARK: - Backdrop (tap to close)

    // Full-bleed dim backdrop — transparent `Button` (the iOS-14-safe recipe used by the
    // SheetKit scrim; an `onTapGesture` on a `Color` renders unreliably headless). Tapping
    // anywhere NOT covered by the image card / close button dismisses.
    private var backdrop: some View {
        Button(action: { onClose?() }) {
            Color.black.opacity(shown ? 0.92 : 0)
                .edgesIgnoringSafeArea(.all)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Image card (tap-to-zoom + drag-to-pan)

    private func imageCard(side: CGFloat) -> some View {
        productImage
            .scaleEffect(z)
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: Color.black.opacity(0.5), radius: 30, x: 0, y: 24)
            .offset(pan)
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown ? 1 : 0.92)
            .contentShape(Rectangle())
            .onTapGesture { toggleZoom() }
            .gesture(dragGesture)
    }

    /// The product photo — gradient + monogram placeholder, with the real image overlaid
    /// when `live`. Mirrors `ProductDetailSheetView.productPhoto`'s placeholder/real-image pattern.
    private var productImage: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(hex: "#FFD7A8") ?? .orange,
                    Color(hex: "#E27D5A") ?? .orange,
                ]),
                startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(ProductDetailSheetView.monogram(for: detail.name))
                .font(.system(size: 64 * theme.fontScale, weight: .heavy))
                .foregroundColor(.white.opacity(0.92))
            if live, let url = ProductDetailSheetView.photoURL(detail) {
                RemoteStillImageView(url: url, contentMode: .scaleAspectFill)
            }
        }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard z > 1 else { return }
                let lim = 110 * (z - 1)
                pan = CGSize(
                    width: Self.clamp(panBase.width + value.translation.width, lim),
                    height: Self.clamp(panBase.height + value.translation.height, lim))
            }
            .onEnded { _ in panBase = pan }
    }

    private func toggleZoom() {
        withAnimation(.timingCurve(0.2, 0.7, 0.2, 1, duration: 0.22)) {
            if z > 1 {
                z = 1; pan = .zero; panBase = .zero
            } else {
                z = Self.zoomed
            }
        }
    }

    private static func clamp(_ v: CGFloat, _ lim: CGFloat) -> CGFloat {
        max(-lim, min(lim, v))
    }

    // MARK: - Close button (top-right)

    private var closeLayer: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Button(action: { onClose?() }) {
                    ZStack {
                        Circle().fill(Color.white.opacity(0.14))
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .frame(width: 36, height: 36)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.top, 14)
                .padding(.trailing, 14)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Bottom caption (name + hint over gradient)

    private var captionLayer: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 4) {
                Text(detail.name)
                    .font(.system(size: 15 * theme.fontScale, weight: .bold))
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text(z > 1 ? Self.hintZoomed : Self.hintIdle)
                    .font(.system(size: 12 * theme.fontScale))
                    .foregroundColor(.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 22)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [Color.black.opacity(0.6), Color.clear]),
                    startPoint: .bottom, endPoint: .top))
        }
        .allowsHitTesting(false)
    }

    static let hintIdle = "點圖片放大"
    static let hintZoomed = "拖曳檢視細節 · 點一下還原"
}

// MARK: - Deterministic demo seed (previews + snapshot tests)

public extension ProductZoomOverlayView {

    /// A deterministic demo lightbox (open state, gradient placeholder, z == 1), action-free.
    /// `shownInitially: true` so the `ImageRenderer` snapshot path renders the open visual.
    static func demo(theme: ReferenceUITheme) -> ProductZoomOverlayView {
        ProductZoomOverlayView(
            theme: theme,
            detail: ProductSheetsModel.demoDetail(),
            live: false,
            shownInitially: true)
    }
}

#if DEBUG
struct ProductZoomOverlayView_Previews: PreviewProvider {
    static var previews: some View {
        ProductZoomOverlayView.demo(theme: ReferenceUIThemePalette.minimal)
            .frame(width: 393, height: 760)
            .background(Color.black)
            .previewLayout(.sizeThatFits)
            .previewDisplayName("product-zoom · open · placeholder")
    }
}
#endif
