import SwiftUI
import LiveBuySDK
import LiveBuyUI

// MARK: - WinClaimModalView — family-2 feed-win surface 3 (EMAIL-LESS claim sheet)
//
// Spec: `reference-ui-rendering/spec.md` (family-2 feed-win, surface 3)
// Design: rb-ios-feed-win design.md D-4 #3 (`LBWinSheet`) +
//          `design/templates/minimal/moments.jsx` `LBWinSheet` (lines 582-650) +
//          `design/templates/minimal/sdk-components.jsx` `LBPButton` (primary).
//
// The EMAIL-LESS win-claim sheet for ONE `LBWinner`. It is the third of the three
// family-2 surface sub-views composed by `FeedWinOverlayView`, and it implements
// the agreed SUB-VIEW INPUT PATTERN documented in `FeedWinOverlayView.swift`:
//
//   1. `theme: ReferenceUITheme`            — FIRST positional argument.
//   2. bound SNAPSHOT VALUES               — `winner: LBWinner`,
//      `presentation: LBAwardPresentation`, `resultState: LBAwardClaimResultState?`
//      — passed BY VALUE from `FeedWinModel` (never the model, never the template).
//   3. action closures (LAST, each `= nil`) — `onClaim: (() -> Void)?` (funnels to
//      `DefaultWinClaim.submit(winner:)` → core `requestAwardClaim(winner, nil)`),
//      `onDismiss: (() -> Void)?` (「稍後再看」 dismiss).
//
// This sub-view reads ONLY its passed-in values; it never reaches back into
// `FeedWinModel` / `DefaultPlayerTemplate` (one-way data flow, D-1 / D-4). It also
// renders correctly with all actions nil (so demo / snapshot tests construct it
// action-free).
//
// EMAIL-LESS (D-4): there is NO email / contact input field anywhere in this
// sheet. The Default win-claim flow collects no email — `onClaim` funnels straight
// to `submit(winner:)` (contact always nil). The sheet is a VIEW-style sheet:
// 恭喜中獎 + award detail + product/discount-routed CTA + 「稍後再看」.
//
// CTA routing (`presentation`, classified by `DefaultWinClaim.awardPresentation`):
//   • `.product`  → CTA「查看獎品」, award caption「獲得獎品」, gift glyph.
//   • `.discount` → CTA「立即使用」, award caption「獲得優惠」, discount glyph.
//
// Result-state feedback (`resultState`, mapped by `DefaultWinClaim.consumeResult`):
//   • nil                       → the pre-submit prompt (恭喜中獎 + award + CTA).
//   • `.successDiscount(code)`  → success banner + the discount `awardCode` shown.
//   • `.successProduct`         → success banner (no code).
//   • `.failureRetryable`       → failure banner + 重試 (re-invokes `onClaim`).
//
// iOS-14-safe SwiftUI only. `VStack` / `HStack` / `ZStack` / `Text` / `Button` /
// `RoundedRectangle` / `Circle` / `LinearGradient` / `ForEach` are all iOS-13+.
// The view is a CENTERED MODAL (LBWinSheet): a full-bleed dark scrim + a centered
// fully-rounded card (no grab handle, no titled header) with a top-right close
// circle and a static confetti fan behind the gift badge. No `.task` / `AsyncImage`
// / `NavigationStack` / `.foregroundStyle` / `.tint`.

/// The family-2 EMAIL-LESS win-claim sheet for one `LBWinner`. Renders the award
/// detail with a product/discount-routed CTA, the「稍後再看」dismiss, and — once a
/// claim result arrives — the success / failure feedback (discount success shows
/// the `awardCode`). No email / contact field anywhere.
public struct WinClaimModalView: View {

    /// The resolved reference-ui theme (FIRST positional argument, always).
    public let theme: ReferenceUITheme

    /// The winner this sheet claims for (`unclaimedWinners` earliest). Read-only.
    public let winner: LBWinner
    /// CTA classification (`DefaultWinClaim.awardPresentation(for:)`). Read-only.
    public let presentation: LBAwardPresentation
    /// Latest mapped claim-result feedback (`DefaultWinClaim.resultState`); nil
    /// until a result arrives. Drives the success / failure banner. Read-only.
    public let resultState: LBAwardClaimResultState?

    /// Host-wired claim submit. The container forwards
    /// `model.submitClaim(for: winner)` → `DefaultWinClaim.submit(winner:)`
    /// (internally core `requestAwardClaim(winner, nil)`, contact ALWAYS nil). nil
    /// for demo / snapshot instances — the sheet renders correctly action-free.
    private let onClaim: (() -> Void)?
    /// Host-wired「稍後再看」/ close dismiss. nil for demo / snapshot instances.
    private let onDismiss: (() -> Void)?

    public init(
        theme: ReferenceUITheme,
        winner: LBWinner,
        presentation: LBAwardPresentation,
        resultState: LBAwardClaimResultState?,
        onClaim: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.theme = theme
        self.winner = winner
        self.presentation = presentation
        self.resultState = resultState
        self.onClaim = onClaim
        self.onDismiss = onDismiss
    }

    // MARK: - Derived presentation (pure)

    /// Whether the award is a discount (vs a product). Drives glyph / caption / CTA.
    private var isDiscount: Bool { presentation == .discount }

    /// The terminal success banner content (or nil while not yet successful).
    /// `.successDiscount` carries the `awardCode` to surface; `.successProduct`
    /// carries no code.
    private var successCode: String? {
        if case let .successDiscount(awardCode) = resultState { return awardCode }
        return nil
    }
    private var isSuccess: Bool {
        switch resultState {
        case .successProduct, .successDiscount: return true
        default: return false
        }
    }
    private var isFailure: Bool { resultState == .failureRetryable }

    public var body: some View {
        // Centered modal (LBWinSheet): full-bleed dark scrim (tap = dismiss) with a
        // centered, fully-rounded card. NOT a bottom sheet — no grab handle, no
        // titled header; the card carries only a top-right close circle + confetti.
        ZStack {
            Self.scrimColor
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { onDismiss?() }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(LBAccessibilityID.winClaimScrim)
            card
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Centered modal card (LBWinSheet 82% / maxWidth 320, radius 20)

    private var card: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 14) {
                // Confetti fans out behind the gift badge (paint order: behind).
                ZStack {
                    confettiLayer
                    giftBadge
                }
                congratsBlock
                awardCard
                if isSuccess || isFailure {
                    resultBanner
                }
                actions
            }
            .padding(.top, 28)
            .padding(.horizontal, 22)
            .padding(.bottom, 20)

            closeButton
                .padding(.top, 12)
                .padding(.trailing, 12)
        }
        .frame(maxWidth: 320)
        .background(theme.background)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color.black.opacity(0.35), radius: 32, x: 0, y: 24)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(LBAccessibilityID.winClaimSheet)
    }

    // MARK: - Top-right close circle (LBWinSheet close-only header)

    private var closeButton: some View {
        Button(action: { onDismiss?() }) {
            ZStack {
                Circle().fill(Self.bgSunken)
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Self.textDim)
            }
            .frame(width: 28, height: 28)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier(LBAccessibilityID.winClaimClose)
    }

    // MARK: - Confetti (LBWinSheet — 22 static fan-out squares behind the badge)
    //
    // Deterministic port of the design's `CONFETTI` map: 22 colored squares fanned
    // over a ~160° arc, anchored at the gift-badge center, skewed slightly upward
    // (ty − 20). Static (no animation) so the snapshot baseline is deterministic;
    // the card `clipShape` trims any square that overflows the rounded card.
    private var confettiLayer: some View {
        ZStack {
            ForEach(0..<22, id: \.self) { i in
                let p = Self.confetti(i, accent: theme.accent)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(p.color)
                    .frame(width: p.size, height: p.size)
                    .rotationEffect(.degrees(p.rotation))
                    .offset(x: p.tx, y: p.ty)
            }
        }
    }

    // MARK: - Gift badge (accent gradient circle + gift glyph — LBWinSheet top)
    //
    // The TOP badge ALWAYS shows the gift glyph regardless of award type (design
    // `LBWinSheet` line 622 `giftSvg`); the discount/tag glyph lives ONLY in the award
    // card (`awardCard`, routed by `isDiscount`). Aligns iOS to Android / Flutter
    // (both always-gift) — fixes an iOS-only divergence where the top badge routed.

    private var giftBadge: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [theme.accent, Self.shade(theme.accent)]),
                startPoint: .topLeading, endPoint: .bottomTrailing)
            // iOS-14-safe SF Symbol glyph — ALWAYS gift (design LBWinSheet top badge).
            Image(systemName: "gift.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(.white)
        }
        .frame(width: 64, height: 64)
        .clipShape(Circle())
        .shadow(color: theme.accent.opacity(0.33), radius: 11, x: 0, y: 8)
    }

    // MARK: - Congrats block (恭喜中獎 + subline)

    private var congratsBlock: some View {
        VStack(spacing: 4) {
            Text(Self.congratsTitle)
                .font(.system(size: 19 * theme.fontScale, weight: .heavy))
                .foregroundColor(theme.text)
            // Fixed congrats subline (LBWinSheet) — always the design copy, never
            // winner.title.
            Text(Self.congratsSubline)
                .font(.system(size: 12.5 * theme.fontScale))
                .foregroundColor(Self.textDim)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 22)
    }

    // MARK: - Award card (獲得獎品 / 獲得優惠 + award.name — LBWinSheet card)

    private var awardCard: some View {
        HStack(spacing: 12) {
            // Glyph chip — accent-tinted rounded square.
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(theme.accent.opacity(0.10))
                Image(systemName: isDiscount ? "tag" : "gift")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(theme.accent)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(isDiscount ? Self.awardCaptionDiscount : Self.awardCaptionProduct)
                    .font(.system(size: 11 * theme.fontScale, weight: .semibold))
                    .foregroundColor(Self.textDim)
                Text(winner.award.name.isEmpty ? Self.awardNameFallback : winner.award.name)
                    .font(.system(size: 14 * theme.fontScale, weight: .bold))
                    .foregroundColor(theme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Self.bgSunken)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Self.stroke, lineWidth: 1))
        )
    }

    // MARK: - Result banner (success / failure feedback)
    //
    // Only rendered once a claim result has arrived. Success → tinted success
    // banner; `.successDiscount` additionally surfaces the `awardCode` in a
    // monospaced code chip. Failure → retryable failure banner.

    @ViewBuilder
    private var resultBanner: some View {
        if isSuccess {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Self.successColor)
                    Text(Self.successTitle)
                        .font(.system(size: 13 * theme.fontScale, weight: .bold))
                        .foregroundColor(theme.text)
                    Spacer(minLength: 0)
                }
                // Discount success → surface the awardCode in a code chip.
                if let code = successCode {
                    HStack(spacing: 8) {
                        Text(Self.codeLabel)
                            .font(.system(size: 12 * theme.fontScale))
                            .foregroundColor(Self.textDim)
                        Text(code)
                            .font(.system(size: 14 * theme.fontScale, weight: .bold, design: .monospaced))
                            .foregroundColor(theme.accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(theme.accent.opacity(0.10)))
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Self.successColor.opacity(0.10)))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(LBAccessibilityID.winClaimResultBanner)
        } else {
            // Failure (retryable).
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(theme.accent)
                Text(Self.failureTitle)
                    .font(.system(size: 13 * theme.fontScale, weight: .semibold))
                    .foregroundColor(theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(theme.accent.opacity(0.08)))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(LBAccessibilityID.winClaimResultBanner)
        }
    }

    // MARK: - Actions (primary CTA + 「稍後再看」)
    //
    // Primary CTA wording routes by `presentation` (查看獎品 / 立即使用) pre-result;
    // on `.failureRetryable` it becomes 重試 (re-invokes `onClaim`); on success it
    // confirms / closes (the success path's primary closes the sheet).

    private var actions: some View {
        VStack(spacing: 8) {
            Button(action: { primaryAction() }) {
                Text(primaryTitle)
                    .font(.system(size: 15 * theme.fontScale, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(theme.accent))
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityIdentifier(LBAccessibilityID.winClaimPrimary)

            Button(action: { onDismiss?() }) {
                Text(Self.laterLabel)
                    .font(.system(size: 13 * theme.fontScale, weight: .semibold))
                    .foregroundColor(Self.textDim)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityIdentifier(LBAccessibilityID.winClaimSecondary)
        }
    }

    /// Primary CTA title — routed by result-state then by presentation.
    private var primaryTitle: String {
        if isSuccess { return Self.successDoneLabel }
        if isFailure { return Self.retryLabel }
        return isDiscount ? Self.ctaDiscount : Self.ctaProduct
    }

    /// Primary CTA action — success closes; failure / pre-submit submit the claim.
    private func primaryAction() {
        if isSuccess { onDismiss?(); return }
        onClaim?()
    }

    // MARK: - Decorative design tokens (literal minimal hex via Color(hex:))
    //
    // accent / text / background come from the resolved theme. These are FIXED
    // decorative colors lifted verbatim from the design's `theme.surface.*`
    // (light mode, `design/brands/livebuy/tokens.jsx`) — design-literal, NOT
    // theme-resolved. Kept consistent with `VideoInfoPanelView` so the two sheets
    // read as one family.

    /// `theme.surface.textDim` (secondary / caption text).
    static let textDim = Color(hex: "#6B6775") ?? Color.gray
    /// `theme.surface.stroke` (hairline border).
    static let stroke = Color(hex: "#ECEAF0") ?? Color.gray.opacity(0.2)
    /// `theme.surface.bgSunken` (sunken card / close-circle fill — light mode).
    static let bgSunken = Color(hex: "#F4F4F6") ?? Color.gray.opacity(0.08)
    /// Success accent (`#0FC3B4` — the LBWinSheet confetti teal).
    static let successColor = Color(hex: "#0FC3B4") ?? Color.green
    /// Modal scrim (`LBWinSheet` `rgba(0,0,0,0.6)`).
    static let scrimColor = Color.black.opacity(0.6)

    /// A darker shade of `color` for the gift-badge gradient end-stop (mirrors the
    /// design's `lbShade(accent, -0.3)`). Pure, iOS-14-safe (UIColor HSB).
    static func shade(_ color: Color) -> Color {
        let ui = UIColor(color)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return color }
        return Color(hue: Double(h), saturation: Double(s),
                     brightness: Double(max(0, b - 0.3)), opacity: Double(a))
    }

    /// One confetti square's deterministic placement — a direct port of the design
    /// `LBWinSheet` `CONFETTI` map (22 squares fanned over ~160°, anchored at the
    /// badge center, skewed up by 20pt). Pure / deterministic. Palette index 3 is
    /// the resolved `accent`; the rest are design-literal.
    static func confetti(_ i: Int, accent: Color)
        -> (tx: CGFloat, ty: CGFloat, rotation: Double, color: Color, size: CGFloat) {
        let angDeg = -90.0 + ((Double(i) / 21.0) * 160.0 - 80.0)
        let ang = angDeg * .pi / 180.0
        let dist = 40.0 + Double(i % 4) * 16.0
        let cols: [Color] = [
            Color(hex: "#F03246") ?? .red,
            Color(hex: "#0FC3B4") ?? .green,
            Color(hex: "#F39C12") ?? .orange,
            accent,
            .white,
        ]
        return (
            tx: CGFloat(cos(ang) * dist),
            ty: CGFloat(sin(ang) * dist - 20.0),
            rotation: Double((i * 47) % 360),
            color: cols[i % 5],
            size: CGFloat(5 + (i % 3) * 2))
    }

    // MARK: - Fixed localized copy (static presentation strings)

    static let congratsTitle = "恭喜中獎!"
    static let congratsSubline = "你抽中了直播間的限定獎品"
    static let awardCaptionProduct = "獲得獎品"
    static let awardCaptionDiscount = "獲得優惠"
    static let awardNameFallback = "直播間限定獎品"
    static let ctaProduct = "查看獎品"
    static let ctaDiscount = "立即使用"
    static let laterLabel = "稍後再看"
    static let retryLabel = "重試"
    static let successDoneLabel = "完成"
    static let successTitle = "領取成功"
    static let failureTitle = "領取失敗,請稍後再試"
    static let codeLabel = "折扣碼"
}

// MARK: - Deterministic demo seed (previews + snapshot tests)
//
// Fully-populated winners (product + discount) so previews / the snapshot test
// render the sheet's "happy path" deterministically (no live player). Award type
// drives the demo `presentation` via the SAME rule the template's classifier uses
// (`type == "discount"` → .discount, else .product).

public extension WinClaimModalView {

    /// A deterministic demo product winner (CTA「查看獎品」).
    static var demoProductWinner: LBWinner {
        LBWinner(
            id: "demo-win-product-001",
            eventId: 4201,
            title: "週年慶限定抽獎",
            award: LBAward(
                type: "product",
                code: "SKU-AURORA-LIP",
                name: "Aurora 霧面唇釉 #03 珊瑚橘"))
    }

    /// A deterministic demo discount winner (CTA「立即使用」+ awardCode).
    static var demoDiscountWinner: LBWinner {
        LBWinner(
            id: "demo-win-discount-001",
            eventId: 4202,
            title: "整點快閃抽獎",
            award: LBAward(
                type: "discount",
                code: "LIVE5OFF",
                name: "全館 5 折優惠券"))
    }

    /// CTA classification for a demo winner — the SAME rule the template's public
    /// classifier (`DefaultWinClaim.awardPresentation`) applies. Pure.
    static func demoPresentation(for winner: LBWinner) -> LBAwardPresentation {
        (winner.award.type == "discount") ? .discount : .product
    }

    /// A deterministic demo sheet for a product win, pre-submit (no result yet).
    static func demo(theme: ReferenceUITheme) -> WinClaimModalView {
        WinClaimModalView(
            theme: theme,
            winner: demoProductWinner,
            presentation: demoPresentation(for: demoProductWinner),
            resultState: nil)
    }
}

#if DEBUG
struct WinClaimModalView_Previews: PreviewProvider {
    static var previews: some View {
        let theme = ReferenceUIThemePalette.minimal
        Group {
            // Product win, pre-submit (CTA「查看獎品」).
            WinClaimModalView.demo(theme: theme)
                .previewDisplayName("product · pre-submit")

            // Discount win, pre-submit (CTA「立即使用」).
            WinClaimModalView(
                theme: theme,
                winner: WinClaimModalView.demoDiscountWinner,
                presentation: .discount,
                resultState: nil)
                .previewDisplayName("discount · pre-submit")

            // Discount success → awardCode shown.
            WinClaimModalView(
                theme: theme,
                winner: WinClaimModalView.demoDiscountWinner,
                presentation: .discount,
                resultState: .successDiscount(awardCode: "LIVE5OFF"))
                .previewDisplayName("discount · success code")

            // Retryable failure → 重試.
            WinClaimModalView(
                theme: theme,
                winner: WinClaimModalView.demoProductWinner,
                presentation: .product,
                resultState: .failureRetryable)
                .previewDisplayName("product · failure")
        }
        .frame(width: 393, height: 520)
        .previewLayout(.sizeThatFits)
    }
}
#endif

// MARK: - Deprecated former name (source-compatibility shim)
//
// This surface is a CENTERED MODAL (full-bleed scrim + centered card, no grab
// handle) — NOT a bottom sheet. It was renamed `WinClaimSheetView` →
// `WinClaimModalView` to match its true nature and its modal siblings
// (`GuestNameEditModalView` / `AuthGateModalView`). The old name is kept as a
// deprecated typealias for one release cycle so a host that constructs the
// drop-in surface directly does not break. See change `rename-winclaim-to-modal`.
@available(*, deprecated, renamed: "WinClaimModalView")
public typealias WinClaimSheetView = WinClaimModalView
