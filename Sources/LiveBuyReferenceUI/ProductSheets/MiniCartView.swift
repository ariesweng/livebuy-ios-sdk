import SwiftUI
import LiveBuySDK
import LiveBuyUI

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
// PHOTO-LED (rb-align-ios-product-sheets): aligned to the design's `LBPMiniCart`,
// the peek LEADS with a 52×52 product thumbnail. `photos` are remote URLs and the
// reference-ui keeps snapshots deterministic (no network / `AsyncImage`), so — like
// `ProductDetailSheetView`'s 4:3 media — it draws a 52×52 rounded gradient
// placeholder with a monogram (the host can swap in a real image). The rest mirrors
// `LBPMiniCart`: the dark glass card surface, the single-line name, the price line
// (`已售完` when `soldOut == 1`, else `priceShow`), and the trailing circular close
// button. NO「已加入購物車」confirmation line (the design's `LBPMiniCart` has none —
// the peek's mere appearance is the "added" signal). Tapping the card body opens the
// detail; tapping the close button dismisses (matching `onTap` / `onClose`).
//
// iOS-14-safe SwiftUI only. `ZStack` / `HStack` / `VStack` / `Text` / `Button` /
// `RoundedRectangle` / `Circle` / `Color` are all iOS-13+. The dark glass surface
// uses a solid translucent fill (no `.ultraThinMaterial`, which is iOS-15+) so the
// baseline is deterministic on the iOS-14 floor. No `.task` / `AsyncImage` /
// `NavigationStack` / `.foregroundStyle` / `.tint`.

/// The family-3 floating mini-cart peek for one `LBMiniCartPeek`. Renders a compact
/// photo-led glass card — a 52×52 product thumbnail + the product name + a price /
/// sold-out line — with a tap-to-open-detail body and a trailing close button
/// (aligned to the design's `LBPMiniCart`). The container draws it only when a peek
/// exists.
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

    /// Optional accent tag drawn above the name (e.g.「介紹中」for the VOD now-introducing card).
    /// `nil` (mini-cart peek) → no tag (peek byte-identical).
    private let tag: String?

    public init(
        theme: ReferenceUITheme,
        peek: LBMiniCartPeek,
        onDismiss: (() -> Void)? = nil,
        onOpenDetail: (() -> Void)? = nil,
        live: Bool = false,
        fullWidth: Bool = false,
        tag: String? = nil
    ) {
        self.theme = theme
        self.peek = peek
        self.onDismiss = onDismiss
        self.onOpenDetail = onOpenDetail
        self.live = live
        self.fullWidth = fullWidth
        self.tag = tag
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
        if fullWidth {
            cardButton.frame(maxWidth: .infinity)
        } else {
            cardButton.frame(width: 260)
        }
    }

    private var cardButton: some View {
        Button(action: { onOpenDetail?() }) {
            HStack(spacing: 10) {
                productThumb
                infoColumn
                closeButton
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Self.glassFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Self.glassStroke, lineWidth: 0.5))
            )
            .shadow(color: Color.black.opacity(0.25), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Product thumbnail (LBPMiniCart 52×52 ProductMock — deterministic placeholder)
    //
    // Photo-led peek: a 52×52 rounded media leading the card (design `LBPMiniCart`).
    // `photos` are remote URLs; reference-ui keeps snapshots deterministic (no network
    // / AsyncImage), so it draws a gradient placeholder chip with a monogram (host can
    // swap in a real image) — mirroring `ProductDetailSheetView`'s photo placeholder.

    private var productThumb: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(hex: "#FFD7A8") ?? .orange,
                    Color(hex: "#E27D5A") ?? .orange,
                ]),
                startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(Self.monogram(for: peek.name))
                .font(.system(size: 16 * theme.fontScale, weight: .heavy))
                .foregroundColor(.white.opacity(0.92))

            // Real product image (rb-ios-now-introducing-real-image-carousel, 問題 9) — only at
            // runtime (`live`) with a non-empty URL; layered OVER the gradient placeholder so the
            // snapshot path (`live == false`) stays the deterministic placeholder.
            if live, let url = Self.imageURL(peek.pic) {
                RemoteStillImageView(url: url, contentMode: .scaleAspectFit)
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Info column (name + price line)

    private var infoColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Optional accent tag (e.g.「介紹中」for the VOD now-introducing card; nil for the
            // mini-cart peek → not drawn, peek byte-identical). The「介紹中」tag carries the
            // accent equalizer glyph + accent text (對齊設計 `LBLivePinnedCard` 等化器 + accent 文字,
            // 與商品列底部橫幅共用 `EqualizerGlyph`).
            if let tag = tag, !tag.isEmpty {
                HStack(spacing: 3) {
                    EqualizerGlyph(size: 11, color: theme.accent)
                    Text(tag)
                        .font(.system(size: 11 * theme.fontScale, weight: .semibold))
                        .foregroundColor(theme.accent)
                }
            }

            // Product name — single-line, ellipsis-truncated (design 13/600).
            Text(peek.name)
                .font(.system(size: 13 * theme.fontScale, weight: .semibold))
                .foregroundColor(Self.onGlassText)
                .lineLimit(1)
                .truncationMode(.tail)

            // Price line — sold-out → 已售完; else the priceShow (design 11pt dim).
            Text(isSoldOut ? Self.soldOutLabel : peek.priceShow)
                .font(.system(size: 12 * theme.fontScale, weight: isSoldOut ? .semibold : .bold))
                .foregroundColor(isSoldOut ? Self.onGlassTextDim : Self.priceColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Close button (LBPMiniCart trailing close — 22×22 glass circle)
    //
    // Tapping it dismisses WITHOUT opening the detail. Because the whole card is a
    // Button, we make this an inner Button: a child Button intercepts the tap so the
    // outer open-detail action does not also fire (matching the design's
    // `e.stopPropagation()` on `onClose`). A no-op when `onDismiss == nil`.

    private var closeButton: some View {
        Button(action: { onDismiss?() }) {
            ZStack {
                Circle().fill(Self.closeFill)
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Self.onGlassText)
            }
            .frame(width: 22, height: 22)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Decorative design tokens (literal minimal hex via Color(hex:))
    //
    // accent / fontScale come from the resolved theme (above). These are FIXED
    // decorative colors lifted verbatim from the design's `LBPMiniCart`
    // (`design/templates/minimal/sdk-components.jsx`, dark glass overlay) —
    // design-literal, NOT theme-resolved. Kept consistent with `WinClaimModalView`'s
    // surface-token approach (literal hex via `Color(hex:)`, nil-coalesced).

    /// `rgba(20,20,24,0.78)` — the dark glass card fill.
    static let glassFill = (Color(hex: "#141418") ?? Color.black).opacity(0.78)
    /// `rgba(255,255,255,0.10)` — the 0.5pt hairline border on the glass.
    static let glassStroke = Color.white.opacity(0.10)
    /// On-glass primary text (`#fff` in the design).
    static let onGlassText = Color.white
    /// On-glass dim text (`rgba(255,255,255,0.65)` — the price / confirmation line).
    static let onGlassTextDim = Color.white.opacity(0.65)
    /// In-stock price accent (`#FF7B8A` — the design's price-pink on the glass).
    static let priceColor = Color(hex: "#FF7B8A") ?? Color(.systemPink)
    /// The trailing close-circle fill (`rgba(255,255,255,0.18)`).
    static let closeFill = Color.white.opacity(0.18)

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
