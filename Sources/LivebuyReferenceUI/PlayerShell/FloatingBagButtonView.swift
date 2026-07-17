import SwiftUI
import LivebuyUI

// MARK: - FloatingBagButtonView — family-1 floating shopping-bag affordance (LBPBagButton)
//
// Spec: `reference-ui-rendering/spec.md` (family-1 player-shell)
// Design: `design/templates/minimal/sdk-components.jsx` `LBPBagButton` (:602-628).
//
// The design renders the bag SEPARATELY from the side rail ("rendered separately …
// so it can sit lower next to the mini-cart strip") — anchored lower (`right:10;
// bottom:16+safe`) than `LBPSideRail` (`bottom:80+safe`). This view is that separate
// affordance, composed by `PlayerShellView` at the lower anchor; it is NOT part of
// the rail's vertical stack.
//
// One-way data flow: reads ONLY `theme` + `bagCount`; the tap surfaces a single
// host-wired `onTap` (the shell forwards it to the existing goods path —
// `performGoodsTap` + host `onOpenProductList`). Renders correctly with `onTap` nil
// (demo / snapshot instances are inert).
//
// iOS-14-safe SwiftUI only: `ZStack` / `Circle` / `Image(systemName:)` / `Capsule`
// — all iOS-13+. No `Lazy*` / `ScrollView` / `.task` / `.foregroundStyle` / `.tint`.

/// The floating shopping-bag button (`LBPBagButton`): a 48×48 white circle with the
/// accent-tinted bag glyph and a soft drop shadow, plus a cart count badge when
/// `bagCount > 0` (accent fill, white text, 2pt white border, `99+` clamp).
public struct FloatingBagButtonView: View {

    /// The resolved reference-ui theme (FIRST positional argument, always).
    public let theme: ReferenceUITheme

    /// Shopping-bag badge count. `> 0` → draw the count badge.
    public let bagCount: Int

    /// Tap intent → host opens the product list (the shell forwards to the existing
    /// goods path). Default nil so demo / snapshot instances are inert.
    public let onTap: (() -> Void)?

    public init(
        theme: ReferenceUITheme,
        bagCount: Int,
        onTap: (() -> Void)? = nil
    ) {
        self.theme = theme
        self.bagCount = bagCount
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: { onTap?() }) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 6)
                    Image(systemName: "bag")
                        .font(.system(size: Self.glyphSize, weight: .semibold))
                        .foregroundColor(theme.accent)
                }
                .frame(width: Self.size, height: Self.size)

                if bagCount > 0 {
                    badge.offset(x: 2, y: -2)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier(LBAccessibilityID.playerBag)
    }

    /// Cart count badge (`LBPBagButton` count chip). Consistent with the rail /
    /// bottom-bar badge convention (`99+` past 99).
    private var badge: some View {
        Text(Self.badgeText(bagCount))
            .font(.system(size: Self.badgeFontSize, weight: .heavy))
            .foregroundColor(.white)
            .padding(.horizontal, 5)
            .frame(minWidth: Self.badgeMinWidth, minHeight: Self.badgeHeight)
            .background(Capsule().fill(theme.accent))
            .overlay(Capsule().stroke(Color.white, lineWidth: Self.badgeBorderWidth))
    }

    /// Clamp very large counts so the badge stays compact (`99+` past 99) — matches
    /// `OperationRailView` / `LiveBottomBarView` badge convention.
    static func badgeText(_ count: Int) -> String {
        count > 99 ? "99+" : "\(count)"
    }

    // MARK: - Design tokens (LBPBagButton)

    private static let size: CGFloat = 48          // 48×48 floating bag
    private static let glyphSize: CGFloat = 22     // Icons.bag size 22
    private static let badgeMinWidth: CGFloat = 20 // count chip minWidth
    private static let badgeHeight: CGFloat = 20   // count chip height
    private static let badgeFontSize: CGFloat = 11 // fontSize 11, weight 800
    private static let badgeBorderWidth: CGFloat = 2 // 2px solid #fff border
}

// MARK: - Preview (deterministic demo — with / without badge)

#if DEBUG
struct FloatingBagButtonView_Previews: PreviewProvider {
    static var previews: some View {
        HStack(spacing: 24) {
            FloatingBagButtonView(theme: ReferenceUIThemePalette.minimal, bagCount: 3)
            FloatingBagButtonView(theme: ReferenceUIThemePalette.minimal, bagCount: 0)
        }
        .padding()
        .background(Color.black)
        .previewLayout(.sizeThatFits)
    }
}
#endif
