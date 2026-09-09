import SwiftUI
import LivebuySDK
import LivebuyUI

// MARK: - MiniCartView — family-3 product sheet-stack surface 2 (mini-cart peek)
//
// Spec: `reference-ui-rendering/spec.md` (family-3 product + sheets, surface 2)
// Design: rb-ios-product-sheets design.md D-4 (`LBPMiniCart`) +
//          `design/templates/minimal/sdk-components.jsx` `LBPMiniCart` (lines 675-713) +
//          `design/templates/minimal/screens.jsx` `LBPMiniCart` call-site (lines 256-263).
//
// The floating mini-cart peek for the most-recent successful add. It is the second
// of the four family-3 surface sub-views composed by `ProductSheetsOverlayView`, and
// it implements the agreed SUB-VIEW INPUT PATTERN documented in
// `ProductSheetsOverlayView.swift`:
//
//   1. `theme: ReferenceUITheme`            — FIRST positional argument.
//   2. bound SNAPSHOT VALUE                 — `peek: LBMiniCartPeek` — passed BY
//      VALUE from `ProductSheetsModel.miniCartPeek` (never the model, never the
//      template). The container renders this sub-view ONLY when its `miniCartPeek`
//      snapshot is non-nil (an absent peek → no floating card), so the sub-view
//      itself binds a NON-OPTIONAL peek.
//   3. action closures (LAST, each `= nil`):
//        • `onDismiss`    → `ProductSheetsModel.dismissMiniCart()` (the close button;
//                            `DefaultMiniCart.dismissMiniCart()`).
//        • `onOpenDetail` → `ProductSheetsModel.openMiniCartDetail()` (tap the peek;
//                            `DefaultMiniCart.openDetail()` — the template re-opens
//                            the peeked product's detail from its products snapshot).
//
// This sub-view reads ONLY its passed-in values; it never reaches back into
// `ProductSheetsModel` / `DefaultPlayerTemplate` (one-way data flow, D-1 / D-4). It
// renders correctly with all actions nil (so demo / snapshot tests construct it
// action-free). It NEVER records / clears the peek itself (task 4.2) — that is the
// template's `DefaultMiniCart`; this layer only forwards the close / open intents.
//
// PHOTO-LED (rb-align-ios-product-sheets, restyled rb-ios-vod-live-product-card-
// restyle / R31): aligned to the design's `LBPMiniCart`, the peek LEADS with a
// product thumbnail (56×56 square as of `rb-ios-minicart-image-square-cover`,
// only left two corners rounded, flush against the card's white background).
// The rest mirrors `LBPMiniCart`: the white card surface, the single-line
// name, the price line (`已售完` when `soldOut == 1`, else `priceShow`, in
// the merchant accent color), and the close button now absolutely-positioned
// at the card's top-right corner. NO「已加入購物車」confirmation line (the
// design's `LBPMiniCart` has none — the peek's mere appearance is the
// "added" signal). Tapping the card body opens the detail; tapping the
// close button dismisses (matching `onTap` / `onClose`).
//
// iOS-14-safe SwiftUI only. `ZStack` / `HStack` / `VStack` / `Text` / `Button` /
// `RoundedRectangle` / `Circle` / `Color` are all iOS-13+. No `.ultraThinMaterial`
// (iOS-15+), `.task` / `AsyncImage` / `NavigationStack` / `.foregroundStyle` / `.tint`.

/// The family-3 floating mini-cart peek for one `LBMiniCartPeek`. Renders a compact
/// photo-led white card (R31) — a 56×56 square product thumbnail (`rb-ios-minicart-
/// image-square-cover`) + the product name + a
/// price / sold-out line — with a tap-to-open-detail body and a top-right-overlaid
/// close button (aligned to the design's `LBPMiniCart`). The container draws it
/// only when a peek exists.
public struct MiniCartView: View {

    /// The resolved reference-ui theme (FIRST positional argument, always).
    public let theme: ReferenceUITheme

    /// The mini-cart peek snapshot (`DefaultMiniCart.peek`) — the most-recent
    /// successful add. Read-only; non-optional (the container gates on non-nil).
    public let peek: LBMiniCartPeek

    /// Host-wired close. The container forwards `model.dismissMiniCart()` →
    /// `DefaultMiniCart.dismissMiniCart()`. nil for demo / snapshot instances — the
    /// card renders correctly action-free.
    private let onDismiss: (() -> Void)?
    /// Host-wired peek tap. The container forwards `model.openMiniCartDetail()` →
    /// `DefaultMiniCart.openDetail()` (the template re-opens the peeked product's
    /// detail). nil for demo / snapshot instances.
    private let onOpenDetail: (() -> Void)?

    /// `false` (snapshot / demo / mini-cart peek) → the thumbnail draws the deterministic
    /// gradient placeholder only. `true` (host runtime, VOD now-introducing card) → load
    /// `peek.pic` over the placeholder via `RemoteStillImageView`
    /// (rb-ios-now-introducing-real-image-carousel, 問題 9).
    private let live: Bool

    /// `false` (mini-cart peek) → the card is a fixed 260pt floating card. `true` (VOD
    /// now-introducing card) → the card fills the available width to the left
    /// (`.frame(maxWidth: .infinity)`, 問題 9).
    private let fullWidth: Bool

    // (rb-ios-minicart-design-align) The `tag: String?` parameter (an optional accent caption,
    // e.g.「介紹中」) has been REMOVED — the design's `LBPMiniCart` (`sdk-components.jsx`) has no
    // tag / caption concept at all, and the only call site that ever passed a non-nil value
    // (`PlayerShell/NowIntroducingCarouselView.swift`) has been updated to stop passing it. No
    // other call site in this repo passed a non-nil `tag` (verified via `grep` across
    // `ios/Sources` / `ios/Tests`), so this is a clean removal, not a source-compat shim.

    public init(
        theme: ReferenceUITheme,
        peek: LBMiniCartPeek,
        onDismiss: (() -> Void)? = nil,
        onOpenDetail: (() -> Void)? = nil,
        live: Bool = false,
        fullWidth: Bool = false
    ) {
        self.theme = theme
        self.peek = peek
        self.onDismiss = onDismiss
        self.onOpenDetail = onOpenDetail
        self.live = live
        self.fullWidth = fullWidth
    }

    // MARK: - Derived presentation (pure)

    /// Whether the peeked product is sold out (`soldOut == 1`). Drives the price
    /// line: sold-out shows `已售完`, in-stock shows `priceShow`.
    private var isSoldOut: Bool { peek.soldOut == 1 }

    public var body: some View {
        // The whole card body is the open-detail affordance (design `onTap`); the
        // trailing close button stops the tap from reaching the body (design
        // `onClose` calls `e.stopPropagation()`), so it dismisses without opening.
        // mini-cart peek: a fixed-width 260pt floating card (`.frame(width: 260)` — exact,
        // byte-identical baseline). VOD now-introducing card (`fullWidth`): fill the width to
        // the left (rb-ios-now-introducing-real-image-carousel, 問題 9 — container handles padding).
        cardBody
    }

    @ViewBuilder
    private var cardBody: some View {
        if fullWidth {
            cardButton.frame(maxWidth: .infinity)
        } else {
            cardButton.frame(width: 260)
        }
    }

    private var cardButton: some View {
        Button(action: { onOpenDetail?() }) {
            // (rb-ios-minicart-design-align) Padding matches `LBPMiniCart` exactly: the container's
            // own inset is RIGHT-ONLY (design `padding: '0 8px 0 0'`) via `.padding(.trailing, 8)`
            // below — `productThumb` therefore carries ZERO padding on any side (flush against the
            // card's top/left/bottom edges), and `infoColumn` carries its own top/bottom inset
            // (design info `div`'s `padding: '8px 0'`). The image/text horizontal gap comes solely
            // from this HStack's `spacing: 10` (design `gap: 10`), not from either child's padding.
            HStack(spacing: 10) {
                productThumb
                infoColumn
                    .padding(.vertical, 8)
            }
            .padding(.trailing, 8)
            .background(
                RoundedRectangle(cornerRadius: Self.cardCornerRadius)
                    .fill(Self.cardBackground)
            )
            // Close button (R31): moved OFF the content HStack onto an absolute
            // top-right overlay (design `top:3,right:3`) — see `closeButton`.
            .overlay(closeButton, alignment: .topTrailing)
            // R31: `boxShadow: '0 6px 18px rgba(0,0,0,0.15)'` — replaces the retired
            // dark-glass card's `0.25`-opacity shadow. Blur-radius halving convention
            // matches `LiveOverlayChromeView.pinnedCard(_:)`'s own `18px → 9pt` shadow.
            .shadow(color: Color.black.opacity(0.15), radius: 9, x: 0, y: 6)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Product thumbnail (LBPMiniCart 56×56 ProductMock — deterministic placeholder)
    //
    // Photo-led peek: a 56-wide rounded media leading the card (design `LBPMiniCart`,
    // R31: width 52→60; R34 (2026-09-04, `rb-ios-product-detail-image-gallery`): 60→56
    // (`3.5rem`) — only the LEFT two corners rounded, flush against the card's right
    // content edge. `rb-ios-minicart-image-square-cover` (2026-09-05): the frame's
    // HEIGHT was changed from an explicit `52` to `56` to make it a true 56×56 square
    // (matching every other product-card thumbnail in the SDK — the live pinned card
    // 100×100, the product row 64×64, the add-to-cart sheet 96×96), and the runtime
    // `RemoteStillImageView` was switched from `.scaleAspectFit` to `.scaleAspectFill`
    // so the real image fills the square edge-to-edge (cropped) instead of letterboxing.
    // `photos` are remote URLs; reference-ui keeps snapshots deterministic (no network /
    // AsyncImage), so it draws a gradient placeholder chip with a monogram (host can
    // swap in a real image) — mirroring `ProductDetailSheetView`'s photo placeholder.

    private var productThumb: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    ReferenceUIProductPlaceholderPalette.top,
                    ReferenceUIProductPlaceholderPalette.bottom,
                ]),
                startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(Self.monogram(for: peek.name))
                .font(.system(size: 16 * theme.fontScale, weight: .heavy))
                .foregroundColor(.white.opacity(0.92))

            // Real product image (rb-ios-now-introducing-real-image-carousel, 問題 9) — only at
            // runtime (`live`) with a non-empty URL; layered OVER the gradient placeholder so the
            // snapshot path (`live == false`) stays the deterministic placeholder.
            if live, let url = Self.imageURL(peek.pic) {
                RemoteStillImageView(url: url, contentMode: .scaleAspectFill)
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(LeftRoundedRectangle(radius: Self.cardCornerRadius))
    }

    // MARK: - Info column (name + price line)

    private var infoColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            // (rb-ios-minicart-design-align) The design's `LBPMiniCart` has no tag / caption field
            // at all (`screens.jsx`'s sole call site passes no such prop) — the accent tag this
            // view previously drew here (e.g.「介紹中」for the VOD now-introducing card) was a
            // design deviation the user asked to remove. The `tag: String?` parameter that drove
            // it has been removed entirely (see the property declaration above) — there is no
            // longer anything to render here.

            // Product name — single-line, ellipsis-truncated (design 13/600). R31: white
            // card → `theme.text` (was the glass card's fixed white). `paddingRight: 26`
            // (design) reserves room under the now-absolute top-right close button.
            Text(peek.name)
                .font(.system(size: 13 * theme.fontScale, weight: .semibold))
                .foregroundColor(theme.text)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.trailing, 26)

            // Price line — sold-out → 已售完 (dim); else the priceShow in the merchant
            // accent color (R31: was a fixed `#FF7B8A` price-pink on the dark glass card).
            Text(isSoldOut ? Self.soldOutLabel : peek.priceShow)
                .font(.system(size: 12 * theme.fontScale, weight: isSoldOut ? .semibold : .bold))
                .foregroundColor(isSoldOut ? Self.textDim : theme.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Close button (LBPMiniCart top-right close — 22×22, R31)
    //
    // R31: moved from the content row's trailing end to an absolute top-right overlay
    // (design `top:3,right:3`), transparent background (was a translucent white glass
    // circle), icon tinted `theme.text` (was fixed white). Tapping it dismisses WITHOUT
    // opening the detail. Because the whole card is a Button, we make this an inner
    // Button: a child Button intercepts the tap so the outer open-detail action does not
    // also fire (matching the design's `e.stopPropagation()` on `onClose`). A no-op when
    // `onDismiss == nil`. `.contentShape(Rectangle())` keeps the full 22×22 tap target
    // even though the fill is now transparent.

    private var closeButton: some View {
        Button(action: { onDismiss?() }) {
            ZStack {
                Circle().fill(Color.clear)
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(theme.text)
            }
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.top, 3)
        .padding(.trailing, 3)
    }

    // MARK: - Decorative design tokens (literal minimal hex via Color(hex:))
    //
    // accent / text / fontScale come from the resolved theme (above). These are FIXED
    // decorative tokens lifted verbatim from the design's `LBPMiniCart`
    // (`design/templates/minimal/sdk-components.jsx:881-920`, R31 white-card restyle,
    // `rb-ios-vod-live-product-card-restyle`) — design-literal, NOT theme-resolved
    // (except where the design itself now points at `theme.surface.text` /
    // `theme.surface.textDim` / `accent`, which map onto this module's flat
    // `ReferenceUITheme.text` / `.accent`). `textDim` mirrors the established
    // `#6B6775` dim-text token used across this module (e.g. `ProductRowView.textDim`,
    // `WinClaimModalView.textDim`).

    /// `#fff` — the white card fill (R31; was the dark glass card's `rgba(20,20,24,0.78)`).
    static let cardBackground = Color(hex: "#FFFFFF") ?? Color.white
    /// `0.25rem` ≈ 4pt (R31 design Decisions: `1rem = 16px` web convention) — the card's
    /// corner radius (was `16`), also reused by `productThumb`'s left-corner radius.
    static let cardCornerRadius: CGFloat = 4
    /// Dim text token (`#6B6775`, this module's established dim-text hex) — the
    /// sold-out price line.
    static let textDim = Color(hex: "#6B6775") ?? Color.gray

    // MARK: - Fixed localized copy (static presentation strings)

    /// Sold-out price-line label (design `已售完`).
    static let soldOutLabel = "已售完"

    /// Up-to-2-char monogram from the product name (deterministic, pure) — for the
    /// photo placeholder. Mirrors `ProductDetailSheetView.monogram(for:)`.
    static func monogram(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "LB" }
        return String(trimmed.prefix(2)).uppercased()
    }

    /// A non-empty image URL (whitespace-trimmed) for the real product image, or nil
    /// (empty / blank → keep the gradient placeholder). Pure.
    static func imageURL(_ pic: String) -> URL? {
        let s = pic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        return URL(string: s)
    }
}

// MARK: - iOS-14-safe left-rounded rectangle (R31 `productThumb`)
//
// `productThumb` rounds ONLY the top-left and bottom-left corners (design
// `borderRadius: '0.25rem 0 0 0.25rem'` — flush against the card's right content
// edge). `RoundedRectangle` rounds all four; `UIRectCorner`-masked corners via
// `cornerRadius(_:corners:)` need a custom `Path`, which is iOS-13+ safe. Mirrors
// `SheetKit/TopRoundedRectangle.swift`'s custom-Path approach (no `UIRectCorner` /
// iOS-16 `UnevenRoundedRectangle`), generalized to the left edge instead of the top.

struct LeftRoundedRectangle: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(radius, min(rect.width, rect.height) / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.minY + r),
            control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + r, y: rect.maxY),
            control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Deterministic demo seed (previews + snapshot tests)
//
// A fully-populated peek so previews / the snapshot test render the card's "happy
// path" deterministically (no live player). Reuses the container's documented
// construction recipe (`ProductSheetsModel.demoMiniCartPeek`) so the demo fixture
// stays consistent with the rest of family-3. `LBMiniCartPeek` HAS a public
// memberwise init reachable from reference-ui, so the seed needs no `LBSpecOption`
// (the compile barrier noted in the container recipe).

public extension MiniCartView {

    /// A deterministic in-stock demo peek (most-recent successful add) — reuses the
    /// container recipe's `demoMiniCartPeek`.
    static var demoPeek: LBMiniCartPeek { ProductSheetsModel.demoMiniCartPeek }

    /// A deterministic SOLD-OUT demo peek (price line shows `已售完`).
    static var demoSoldOutPeek: LBMiniCartPeek {
        LBMiniCartPeek(
            productId: "demo-prod-002",
            name: "Aurora 霧面唇釉 #07 玫瑰棕(完售)",
            priceShow: "NT$ 390",
            soldOut: 1)
    }

    /// A deterministic demo card for an in-stock peek, action-free.
    static func demo(theme: ReferenceUITheme) -> MiniCartView {
        MiniCartView(theme: theme, peek: demoPeek)
    }
}

#if DEBUG
struct MiniCartView_Previews: PreviewProvider {
    static var previews: some View {
        let theme = ReferenceUIThemePalette.minimal
        Group {
            // In-stock peek (photo + name + priceShow).
            MiniCartView.demo(theme: theme)
                .previewDisplayName("in-stock peek")

            // Sold-out peek (已售完).
            MiniCartView(theme: theme, peek: MiniCartView.demoSoldOutPeek)
                .previewDisplayName("sold-out peek")
        }
        .padding(24)
        .background(Color.black.opacity(0.4))
        .previewLayout(.sizeThatFits)
    }
}
#endif
