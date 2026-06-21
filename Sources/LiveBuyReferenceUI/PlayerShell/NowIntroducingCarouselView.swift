import SwiftUI
import LiveBuyUI

// MARK: - NowIntroducingCarouselView — VOD now-introducing products carousel
//
// Spec: `reference-ui-rendering/spec.md` (rb-ios-now-introducing-real-image-carousel, 問題 10)
// Design: 使用者拍板 — 滿寬整列卡 + 橫向分頁輪播 + 分頁點（extends the design's `LBLivePinnedCard`,
//          which only had a single card).
//
// Multiple products can be introduced at the same VOD playhead (overlapping
// `[beginTime, endTime)` windows → `DefaultPlayerTemplate.vodActiveProducts`). This carousel
// shows ONE full-width card at a time (`MiniCartView(fullWidth: true, tag: "介紹中")`) plus page
// dots, and swipes left/right to change the current page.
//
// SNAPSHOT-SAFE: it draws ONLY the current card + page dots — NO `TabView` / `ScrollView` /
// `GeometryReader` / `Lazy*` (those render BLANK through the `ImageRenderer` snapshot path).
// Off-screen cards are simply not rendered (the index selects which `MiniCartView` is drawn).
//
// Read-only presentation: tap → `onOpenDetail(productId)` (→ host → core `performProductTap`),
// close → `onDismiss(productId)` (container hides that product locally). Never calls core.
//
// iOS-14-safe: `VStack` / `HStack` / `Circle` / `DragGesture` / `@State` are all iOS-13+.

/// The VOD now-introducing products carousel. Renders the current full-width card + page dots,
/// swipe to change the page. Container passes the (dismissed-filtered) peeks and the live flag.
public struct NowIntroducingCarouselView: View {

    let theme: ReferenceUITheme

    /// The now-introducing products as peeks (already dismissed-filtered + `pic`-resolved by the
    /// container). One card per peek; the carousel shows one at a time.
    let peeks: [LBMiniCartPeek]

    /// `true` (runtime) → cards load the real product image; `false` (snapshot) → placeholder.
    let live: Bool

    /// Close one product (by id) — the container hides it locally (`Set<String>`).
    let onDismiss: ((String) -> Void)?

    /// Open one product's detail (by id) — the container forwards `model.performProductTap`.
    let onOpenDetail: ((String) -> Void)?

    @State private var index: Int = 0

    /// Public init — same shape as the synthesized memberwise init (so the internal
    /// player-shell composition keeps compiling), exposed so a host / QA gallery can
    /// mount this surface like its public siblings (`OperationRailView`, etc.).
    public init(theme: ReferenceUITheme,
                peeks: [LBMiniCartPeek],
                live: Bool,
                onDismiss: ((String) -> Void)? = nil,
                onOpenDetail: ((String) -> Void)? = nil) {
        self.theme = theme
        self.peeks = peeks
        self.live = live
        self.onDismiss = onDismiss
        self.onOpenDetail = onOpenDetail
    }

    public var body: some View {
        if peeks.isEmpty {
            EmptyView()
        } else {
            // Clamp the page index — `peeks` can shrink as the playhead advances / cards dismiss.
            let i = min(max(index, 0), peeks.count - 1)
            let peek = peeks[i]
            VStack(spacing: 6) {
                MiniCartView(
                    theme: theme,
                    peek: peek,
                    onDismiss: { onDismiss?(peek.productId) },
                    onOpenDetail: { onOpenDetail?(peek.productId) },
                    live: live,
                    fullWidth: true,
                    tag: Self.introducingTag)
                    .accessibilityIdentifier(LBAccessibilityID.nowIntroducingCard)

                if peeks.count > 1 {
                    pageDots(count: peeks.count, current: i)
                }
            }
            // Swipe left → next page, right → previous (clamped). `.highPriorityGesture`
            // (minDistance 10) so a committed horizontal drag wins over the card's Button
            // AND the outer full-screen video-switch gesture (which previously swallowed it).
            // Direction-gated: act ONLY on a predominantly-horizontal drag — a vertical drag
            // is a no-op here so the outer up/down video-switch keeps working. A tap (< 10pt)
            // falls through to the card Button / page dots. Fire on `.onEnded`.
            .highPriorityGesture(
                DragGesture(minimumDistance: 10)
                    .onEnded { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        if value.translation.width <= -Self.swipeThreshold {
                            index = min(i + 1, peeks.count - 1)
                        } else if value.translation.width >= Self.swipeThreshold {
                            index = max(i - 1, 0)
                        }
                    }
            )
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(LBAccessibilityID.nowIntroCarousel)
        }
    }

    /// Page dots — one per card, the current one accent-filled, the rest dim. Each dot is
    /// TAPPABLE (tap → that page) — a guaranteed switch independent of drag arbitration. The
    /// 6×6 dot keeps its exact pixels/layout; `contentShape(Rectangle().inset(by: -7))`
    /// enlarges the tap target to ~20×20 WITHOUT rendering or changing layout (snapshot
    /// byte-identical).
    private func pageDots(count: Int, current: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { idx in
                Circle()
                    .fill(idx == current ? theme.accent : Color.white.opacity(0.4))
                    .frame(width: 6, height: 6)
                    .contentShape(Rectangle().inset(by: -7))
                    .onTapGesture { index = idx }
                    .accessibilityIdentifier(LBAccessibilityID.nowIntroducingDot(idx))
            }
        }
    }

    static let swipeThreshold: CGFloat = 40
    static let introducingTag = "介紹中"
}
