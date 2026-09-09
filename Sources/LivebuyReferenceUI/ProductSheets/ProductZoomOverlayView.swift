import SwiftUI
import LivebuySDK
import LivebuyUI

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
// The photo SOURCE is SPEC-AWARE (ios-product-sheet-spec-photo-reference-ui): `photoURL` is
// given this view's `selectedSpec`, so the lightbox magnifies the same photo the sheet drew
// rather than always the product-level one. The resolution itself lives in the shared pure
// function `ResolvedProductPhoto` — this view re-uses it, it does not re-derive the ladder.
//
// `overridePhotoURL` (rb-ios-product-detail-image-gallery, design R34) lets a caller with a
// MORE SPECIFIC notion of "which photo" (the product-detail gallery's currently-selected
// page) win over the resolver's `primaryPhoto` — an ADDITIVE override, not a rewrite of the
// resolver's own degradation ladder (`ResolvedProductPhoto` is untouched by this change). A
// nil / blank-after-trim override is treated as "no override supplied" and falls through to
// the existing `photoURL(detail:selectedSpec:)` resolution, so every EXISTING call site
// (defaulted `nil`) is byte-identical.
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
    /// The currently selected variant spec (`LBVariantState.selectedSpec`), so the lightbox
    /// magnifies THE SAME photo the sheet is showing (ios-product-sheet-spec-photo-reference-ui).
    /// The container passes `model.variant.selectedSpec`; defaults to `nil` = "no selected-spec
    /// context" → the product level, keeping existing call sites / `demo(theme:)` unchanged.
    ///
    /// Without this the sheet would show the 玫瑰棕 photo and tapping zoom would show 珊瑚橘 —
    /// a NEW cross-surface inconsistency of exactly the kind that change removes. Read-only.
    public let selectedSpec: LBSpec?
    /// The specific gallery-page photo string to magnify (verbatim, untrimmed — same shape as
    /// `ResolvedProductPhoto.primaryPhoto`), or nil (rb-ios-product-detail-image-gallery, design
    /// R34). When non-nil and non-blank-after-trim it WINS over the resolved `primaryPhoto` —
    /// this is how the lightbox tracks the product-detail multi-image gallery's CURRENTLY
    /// SELECTED page rather than always the resolver's primary. Defaults to `nil`, which falls
    /// through to the pre-existing `photoURL(detail:selectedSpec:)` resolution unchanged — every
    /// EXISTING call site (never passes this) renders byte-identical. See `displayPhotoURL(...)`.
    public let overridePhotoURL: String?
    /// `false` (snapshot / demo) → gradient + monogram placeholder only (deterministic baseline);
    /// `true` (host runtime) → load the resolved photo (see ``selectedSpec``) over the
    /// placeholder via `RemoteStillImageView`.
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
        selectedSpec: LBSpec? = nil,
        overridePhotoURL: String? = nil,
        live: Bool = false,
        shownInitially: Bool = false,
        onClose: (() -> Void)? = nil
    ) {
        self.theme = theme
        self.detail = detail
        self.selectedSpec = selectedSpec
        self.overridePhotoURL = overridePhotoURL
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
        // E2E: the full-frame zoom overlay/backdrop root (visual-only container;
        // the dim backdrop tap-to-close Button is a child).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(LBAccessibilityID.zoomOverlay)
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
            // E2E: the zoomable product image (image-zoom-image).
            .accessibilityIdentifier(LBAccessibilityID.imageZoomImage)
    }

    /// The product photo — gradient + monogram placeholder, with the real image overlaid
    /// when `live`. Mirrors `ProductDetailSheetView.productPhoto`'s placeholder/real-image pattern.
    ///
    /// WHICH photo is resolved by ``displayPhotoURL(overridePhotoURL:detail:selectedSpec:)`` —
    /// `overridePhotoURL` (the gallery's current page, when supplied) wins over the SAME pure
    /// function the sheet uses (`ResolvedProductPhoto`, fed the same `selectedSpec`), so the
    /// magnified image is always the image the user just tapped.
    private var productImage: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    ReferenceUIProductPlaceholderPalette.top,
                    ReferenceUIProductPlaceholderPalette.bottom,
                ]),
                startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(ProductDetailSheetView.monogram(for: detail.name))
                .font(.system(size: 64 * theme.fontScale, weight: .heavy))
                .foregroundColor(.white.opacity(0.92))
            if live, let url = Self.displayPhotoURL(
                overridePhotoURL: overridePhotoURL, detail: detail, selectedSpec: selectedSpec) {
                RemoteStillImageView(url: url, contentMode: .scaleAspectFill)
            }
        }
    }

    /// The photo URL to magnify: `overridePhotoURL` (trimmed) when it is non-nil and non-blank
    /// after trimming, otherwise the pre-existing resolved-primary path unchanged
    /// (rb-ios-product-detail-image-gallery). Pure — mirrors
    /// `ProductDetailSheetView.photoURL`'s trim-for-URL-construction convention (the override
    /// string itself is verbatim per `ResolvedProductPhoto`'s "trim judges, never the value"
    /// rule; trimming here is a URL-construction requirement only).
    ///
    /// A blank-after-trim override (e.g. the gallery's current page happens to be a blank
    /// entry) is treated the SAME as "no override supplied" — falling through to the resolved
    /// primary is a strictly safer default than magnifying nothing.
    static func displayPhotoURL(
        overridePhotoURL: String?,
        detail: LBProductDetailState,
        selectedSpec: LBSpec?
    ) -> URL? {
        if let override = overridePhotoURL {
            let trimmed = override.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return URL(string: trimmed) }
        }
        return ProductDetailSheetView.photoURL(detail, selectedSpec: selectedSpec)
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
                // E2E: the top-right zoom close button (zoom-close).
                .accessibilityIdentifier(LBAccessibilityID.zoomClose)
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
