import SwiftUI
import LivebuyUI

// MARK: - BidWonModalView — flash-sale「恭喜搶購成功」centered popup
//
// Spec: `reference-ui-rendering/spec.md` §「LivebuyReferenceUI 搶購得標視窗（iOS）」(rb-ios-flash-sale-bid).
// Design: `design/templates/minimal/moments.jsx` `LBBidWonModal` (claude-design-sync.md D10).
//
// Binds `DefaultPlayerTemplate.bidWon` (`DefaultBidWon`, live-bid-ios-template) through
// `ProductSheetsModel.bidWonItems` / `bidWonPresented`; the container
// (`ProductSheetsOverlayView`) mounts it at the player overlay root while `bidWonPresented` and
// wires「確定」→ `confirmBidWin()`、「取消」→ `dismissBidWon()`. This view is PURE presentation:
// the only local state is the visible page index.
//
// Layout (design): black 0.6 scrim (NOT tappable to close), white card 84% / max 320 wide,
// radius 20, padding 44/20/20, 16pt gaps; a 60pt white circular merchant logo with a 4pt white
// border, half above the card's top edge — the filled storefront glyph (accent) always sits
// underneath and the real logo is layered on top only when one resolves (loading / failure keep
// the glyph visible); title (accent 20/800), product name (15/700, wraps, never truncated),
// 「數量 x{num}」(13.5/500 textDim); one item → no dots, several → horizontal swipe (40pt
// threshold) + 6pt pagination dots; bottom「取消」outline /「確定」filled, equal width. No close
// button.
//
// iOS-14-safe SwiftUI only (`GeometryReader` / `ZStack` / `Circle` / `RoundedRectangle` /
// `DragGesture` / `onTapGesture`).

public struct BidWonModalView: View {
    @ObservedObject var l10n = ReferenceUILanguage.shared

    public let theme: ReferenceUITheme
    public let items: [LBBidWonItem]
    /// The resolved merchant logo, or nil → glyph only. The container resolves it through the
    /// existing logo gate (`PlayerHeaderBarView.resolvedShopLogoURL(live:urlString:)`), so demo /
    /// snapshot paths (`live == false`) never load an image.
    public let shopLogoURL: URL?
    public let onConfirm: (() -> Void)?
    public let onCancel: (() -> Void)?

    @State private var page: Int

    public init(theme: ReferenceUITheme, items: [LBBidWonItem], shopLogoURL: URL? = nil,
                initialPage: Int = 0,
                onConfirm: (() -> Void)? = nil, onCancel: (() -> Void)? = nil) {
        self.theme = theme
        self.items = items
        self.shopLogoURL = shopLogoURL
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        self._page = State(initialValue: Self.clampPage(initialPage, count: items.count))
    }

    static let scrimColor = Color.black.opacity(0.6)
    static let textDim = Color(hex: "#6B6775") ?? Color.gray
    static let dotInactive = Color(hex: "#D8DBE0") ?? Color.gray.opacity(0.3)
    static let swipeThreshold: CGFloat = 40
    static let logoSize: CGFloat = 60
    static let logoBorder: CGFloat = 4

    // MARK: - Pure helpers

    static func cardWidth(containerWidth: CGFloat) -> CGFloat { min(containerWidth * 0.84, 320) }

    static func clampPage(_ page: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(page, 0), count - 1)
    }

    /// Next page after a horizontal swipe of `dx`: `< 40pt` or a single item → unchanged; left
    /// swipe → +1, right → −1, never past either end (design `onSwipeEnd`).
    static func pageAfterSwipe(current: Int, dx: CGFloat, count: Int) -> Int {
        guard count > 1, abs(dx) >= swipeThreshold else { return current }
        let next = dx < 0 ? current + 1 : current - 1
        return (0..<count).contains(next) ? next : current
    }

    static func showsDots(count: Int) -> Bool { count > 1 }

    // MARK: - Body

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                // Scrim swallows taps but does NOT close (design: no backdrop dismiss).
                Self.scrimColor
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {}
                if !items.isEmpty {
                    card
                        .frame(width: Self.cardWidth(containerWidth: geo.size.width))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private var currentItem: LBBidWonItem { items[Self.clampPage(page, count: items.count)] }

    private var card: some View {
        VStack(spacing: 16) {
            itemText
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 16).onEnded { value in
                    page = Self.pageAfterSwipe(current: page, dx: value.translation.width,
                                               count: items.count)
                })
            if Self.showsDots(count: items.count) {
                dots
            }
            buttons
        }
        .padding(.top, 44)
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(theme.background)
                .shadow(color: Color.black.opacity(0.35), radius: 32, x: 0, y: 24))
        .overlay(logo.offset(y: -Self.logoSize / 2), alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(LBAccessibilityID.bidWonModal)
    }

    private var logo: some View {
        let inner = Self.logoSize - Self.logoBorder * 2
        return ZStack {
            Circle().fill(Color.white)
            StorefrontFillGlyph(size: 30, color: theme.accent)
            if let url = shopLogoURL {
                RemoteStillImageView(url: url, contentMode: .scaleAspectFill)
                    .frame(width: inner, height: inner)
                    .clipShape(Circle())
            }
        }
        .frame(width: Self.logoSize, height: Self.logoSize)
        .shadow(color: Color.black.opacity(0.2), radius: 11, x: 0, y: 8)
    }

    private var itemText: some View {
        VStack(spacing: 0) {
            Text(ReferenceUIStrings.text("bid_won_title"))
                .font(.system(size: 20 * theme.fontScale, weight: .heavy))
                .foregroundColor(theme.accent)
            Text(currentItem.name)
                .font(.system(size: 15 * theme.fontScale, weight: .bold))
                .foregroundColor(theme.text)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
            Text(ReferenceUIStrings.text("bid_won_qty", ["num": String(currentItem.num)]))
                .font(.system(size: 13.5 * theme.fontScale, weight: .medium))
                .foregroundColor(Self.textDim)
                .padding(.top, 6)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    private var dots: some View {
        HStack(spacing: 5) {
            ForEach(0..<items.count, id: \.self) { i in
                Circle()
                    .fill(i == page ? theme.accent : Self.dotInactive)
                    .frame(width: 6, height: 6)
                    .onTapGesture { page = i }
            }
        }
        .accessibilityIdentifier(LBAccessibilityID.bidWonPaginationDots)
    }

    private var buttons: some View {
        HStack(spacing: 12) {
            Button(action: { onCancel?() }) {
                Text(ReferenceUIStrings.text("common_cancel"))
                    .font(.system(size: 15 * theme.fontScale, weight: .heavy))
                    .foregroundColor(theme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: 12).stroke(theme.accent, lineWidth: 1.5))
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityIdentifier(LBAccessibilityID.bidWonCancel)

            Button(action: { onConfirm?() }) {
                Text(ReferenceUIStrings.text("common_confirm"))
                    .font(.system(size: 15 * theme.fontScale, weight: .heavy))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(theme.accent)
                            .shadow(color: theme.accent.opacity(0.27), radius: 8, x: 0, y: 6))
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityIdentifier(LBAccessibilityID.bidWonConfirm)
        }
    }
}
