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
struct NowIntroducingCarouselView: View {

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

    var body: some View {
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

                if peeks.count > 1 {
                    pageDots(count: peeks.count, current: i)
                }
            }
            // Swipe left → next page, right → previous (clamped). Fire on `.onEnded` so a
            // below-threshold drag is a no-op.
            .gesture(
                DragGesture()
                    .onEnded { value in
                        if value.translation.width <= -Self.swipeThreshold {
                            index = min(i + 1, peeks.count - 1)
                        } else if value.translation.width >= Self.swipeThreshold {
                            index = max(i - 1, 0)
                        }
                    }
            )
        }
    }

    /// Page dots — one per card, the current one accent-filled, the rest dim.
    private func pageDots(count: Int, current: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { idx in
                Circle()
                    .fill(idx == current ? theme.accent : Color.white.opacity(0.4))
                    .frame(width: 6, height: 6)
            }
        }
    }

    static let swipeThreshold: CGFloat = 40
    static let introducingTag = "介紹中"
}
