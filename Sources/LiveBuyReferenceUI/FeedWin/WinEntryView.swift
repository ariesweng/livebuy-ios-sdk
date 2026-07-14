import SwiftUI
import LiveBuySDK
import LiveBuyUI

// MARK: - WinEntryView — family-2 feed-win surface 2 (unclaimed-win entry)
//
// Spec: `reference-ui-rendering/spec.md` (family-2 feed-win, surface 2)
// Design: rb-ios-feed-win design.md D-3 #2.
//   Design source: `design/templates/minimal/moments.jsx` · `LBWinEntry`
//     (the floating, pulsing round gift-icon button pinned bottom-trailing, with
//     an accent gradient fill, a pulsing accent ring, and a count badge top-right).
//
// This is family-2 SURFACE 2. It follows the documented SUB-VIEW INPUT PATTERN
// from `FeedWinOverlayView.swift` EXACTLY:
//   1. `theme: ReferenceUITheme`            — FIRST positional argument, always.
//   2. the bound SNAPSHOT VALUES it renders — `unclaimedCount` (drives whether the
//      entry draws at all + the badge number) and `unclaimedWinners` (the by-value
//      mirror of `DefaultWinClaim.unclaimedWinners`; the container opens the claim
//      sheet on the EARLIEST one, so this surface itself never records / removes /
//      reorders — it is read-only). Passed BY VALUE from `FeedWinModel`.
//   3. optional action closure, trailing, defaulting to `nil` (`onTap`). The
//      container / host wires it to open the claim sheet on the earliest unclaimed
//      winner; this surface does NOT own the open intent and renders correctly with
//      it nil (so demo / snapshot instances construct action-free).
//
// One-way data flow (D-1): this view reads ONLY its passed-in values — it never
// reaches back into `FeedWinModel` or `DefaultPlayerTemplate`, and it neither
// records a win nor removes one (those live in `DefaultWinClaim`). It only surfaces
// a single `onTap` open intent; the container funnels that to the claim sheet.
//
// Visibility rule (D-3): the entry is drawn ONLY when `unclaimedCount > 0`. At 0 it
// renders nothing (an `EmptyView`-equivalent zero-size view) so the container's
// bottom-trailing slot is visually empty when there is nothing to claim.
//
// iOS-14-safe (D-7): uses only `ZStack` / `Button` / `Circle` / `Image(systemName:)`
// / `LinearGradient` / `Capsule` / `.shadow` / `.scaleEffect` / `withAnimation` —
// all iOS-13+. The pulsing ring uses the iOS-14-safe `Animation.repeatForever`
// (no `.task` / `.symbolEffect` / `.foregroundStyle` / iOS-17 APIs). The one
// `onChange(of:)` used to (re)start the pulse is iOS-14+, matching this layer's
// floor.

/// The family-2 unclaimed-win entry. A floating, pulsing round gift-icon button
/// pinned bottom-trailing by the container; drawn ONLY when `unclaimedCount > 0`,
/// with a count badge == `unclaimedCount`. Tapping surfaces the `onTap` open
/// intent (the container opens the claim sheet on the earliest unclaimed winner).
public struct WinEntryView: View {

    // MARK: - Inputs (documented sub-view input pattern)

    /// The resolved reference-ui theme (FIRST positional argument, always).
    public let theme: ReferenceUITheme

    /// Distinct unclaimed-win count (`DefaultWinClaim.unclaimedCount`). The entry
    /// is drawn ONLY when this is `> 0`, and the badge number equals this count.
    public let unclaimedCount: Int

    /// Unclaimed winners, insertion-ordered, deduped by id
    /// (`DefaultWinClaim.unclaimedWinners`), passed BY VALUE. The container opens
    /// the claim sheet on `unclaimedWinners.first` (earliest); this read-only
    /// surface keeps the value so the wired-intent contract is explicit, but it
    /// NEVER records / removes / reorders winners.
    public let unclaimedWinners: [LBWinner]

    /// Open-claim intent. The entry does NOT own the action — the container / host
    /// funnels it to the claim sheet on the earliest unclaimed winner (D-3).
    /// Default `nil` so demo / snapshot instances construct action-free.
    public let onTap: (() -> Void)?

    /// Local pulse-ring animation state. Driven purely by the on-appear / count
    /// change toggle below (never by a core call). The ring scales + fades on a
    /// repeating cycle, mirroring `lbp-pulse-dot 1.8s infinite`.
    @State private var pulsing = false

    /// Continuous-animation throttling gate (ios-power-profile-animation-throttle-reference-ui).
    /// Read-only power-profile / reduce-motion / visibility policy: the pulse's
    /// `repeatForever` driver only STARTS when this allows it (device not hot, Reduce Motion
    /// off). Defaults to a neutral "animate" value when unset (direct-constructed snapshot /
    /// preview instances) — and since `ImageRenderer` never fires `.onAppear`, the resting
    /// frame is captured regardless, so the golden stays byte-identical.
    @Environment(\.continuousAnimationGate) private var motionGate

    public init(
        theme: ReferenceUITheme,
        unclaimedCount: Int,
        unclaimedWinners: [LBWinner] = [],
        onTap: (() -> Void)? = nil
    ) {
        self.theme = theme
        self.unclaimedCount = unclaimedCount
        self.unclaimedWinners = unclaimedWinners
        self.onTap = onTap
    }

    // MARK: - Body

    public var body: some View {
        // Visibility rule (D-3): nothing to claim → draw nothing. A zero-frame
        // container keeps the surface inert in the bottom-trailing slot at count 0.
        if unclaimedCount > 0 {
            entryButton
        }
    }

    // MARK: - Entry button (`LBWinEntry`)

    /// The 48×48 floating gift-icon button: an accent → darker-accent diagonal
    /// gradient circle with a soft accent drop shadow, a pulsing accent ring, the
    /// white gift glyph, and the count badge top-trailing.
    private var entryButton: some View {
        Button(action: { onTap?() }) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    // Gradient fill: `linear-gradient(135deg, accent, lbShade(accent,-0.28))`.
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [theme.accent, Self.darkened(theme.accent, by: Self.shadeAmount)]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        // box-shadow: `0 6px 18px accent66` (accent @ 0.4 alpha).
                        .shadow(color: theme.accent.opacity(Self.shadowOpacity),
                                radius: Self.shadowRadius, x: 0, y: Self.shadowY)

                    // Pulsing ring (`span inset:-3, 2px solid accent, lbp-pulse-dot`).
                    Circle()
                        .stroke(theme.accent, lineWidth: Self.ringWidth)
                        .frame(width: Self.entrySize + Self.ringInset * 2,
                               height: Self.entrySize + Self.ringInset * 2)
                        .scaleEffect(pulsing ? Self.ringScaleMax : Self.ringScaleMin)
                        .opacity(pulsing ? Self.ringOpacityMin : Self.ringOpacityMax)

                    // White gift glyph (the design's hand-drawn gift SVG → SF gift).
                    Image(systemName: "gift.fill")
                        .font(.system(size: Self.glyphSize, weight: .semibold))
                        .foregroundColor(.white)
                }
                .frame(width: Self.entrySize, height: Self.entrySize)

                // Count badge top-trailing (white fill, accent text, 2pt accent
                // border) — drawn whenever the entry is (count is always > 0 here).
                countBadge
                    .offset(x: Self.badgeOffsetX, y: Self.badgeOffsetY)
            }
        }
        .buttonStyle(PlainButtonStyle())
        // Start the repeating pulse on appear and restart it if the count changes
        // (a fresh win arriving re-draws attention). iOS-14-safe. Each path runs through
        // `startPulse()`, which re-applies the throttling gate — so under thermal pressure
        // a fresh win does NOT start the ring, and cooling back down resumes it.
        .onAppear { startPulse() }
        .onChange(of: unclaimedCount) { _ in startPulse() }
        // Re-evaluate when the power-profile / reduce-motion gate flips (heat → freeze,
        // cool → resume). `ContinuousAnimationGate` is `Equatable`.
        .onChange(of: motionGate) { _ in startPulse() }
        // Off-screen (incl. count → 0 where the body collapses to nothing): reset the ring to
        // its resting state WITHOUT animation, so no `repeatForever` driver survives off-screen.
        .onDisappear { pulsing = false }
        .accessibilityIdentifier(LBAccessibilityID.winEntry)
    }

    /// The count chip (`LBWinEntry` badge): white background, accent text, 2pt
    /// accent border, the unclaimed count (very large counts clamp to `99+`).
    private var countBadge: some View {
        Text(Self.badgeText(unclaimedCount))
            .font(.system(size: Self.badgeFontSize, weight: .heavy))
            .foregroundColor(theme.accent)
            .padding(.horizontal, Self.badgeHPadding)
            .frame(minWidth: Self.badgeMinWidth, minHeight: Self.badgeHeight)
            .background(
                Capsule().fill(Color.white)
            )
            .overlay(
                Capsule().stroke(theme.accent, lineWidth: Self.badgeBorderWidth)
            )
    }

    // MARK: - Pulse driver

    /// (Re)start the repeating pulse. Sets the ring to its at-rest state, then — ONLY when the
    /// throttling gate allows it — animates to the expanded / faded state on a forever-repeating
    /// cycle (mirrors the design's `lbp-pulse-dot 1.8s infinite`). Under thermal pressure /
    /// Reduce Motion the ring is left at rest (`pulsing == false`), no `repeatForever` driver
    /// starts. Pure presentation; only ever skips the animation DRIVER — the ring / glyph / badge
    /// still render at their resting positions.
    private func startPulse() {
        pulsing = false
        guard motionGate.allowsAnimation(visible: true) else { return }
        withAnimation(.easeOut(duration: Self.pulseDuration).repeatForever(autoreverses: false)) {
            pulsing = true
        }
    }

    // MARK: - Badge text

    /// Clamp very large counts so the chip stays compact (design badge is a small
    /// chip). `99+` past 99 — matches the cart-badge convention used by the rail.
    static func badgeText(_ count: Int) -> String {
        count > 99 ? "99+" : "\(count)"
    }

    // MARK: - Accent shade (iOS-14-safe, mirrors design `lbShade`)

    /// Darken a `Color` toward black by `amount` (0…1), mirroring the design's
    /// `lbShade(hex, -amount)`: `c' = c * (1 - amount)`. Resolves the Color through
    /// `UIColor` (iOS-13+) so it works for any resolved accent, not just the
    /// minimal-palette hex; falls back to the input color if components are
    /// unavailable (e.g. a pattern color).
    static func darkened(_ color: Color, by amount: CGFloat) -> Color {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return color }
        let f = 1 - amount
        return Color(.sRGB,
                     red: Double(r * f),
                     green: Double(g * f),
                     blue: Double(b * f),
                     opacity: Double(a))
    }
}

// MARK: - Design tokens (lifted from moments.jsx · LBWinEntry)

private extension WinEntryView {
    // Button
    static let entrySize: CGFloat = 48         // width/height 48
    static let glyphSize: CGFloat = 22          // gift SVG 22×22
    static let shadeAmount: CGFloat = 0.28      // lbShade(accent, -0.28)

    // Drop shadow: `0 6px 18px accent66` (0x66 ≈ 0.4 alpha)
    static let shadowOpacity: Double = 0.4
    static let shadowRadius: CGFloat = 9        // CSS 18px blur ≈ 9pt SwiftUI radius
    static let shadowY: CGFloat = 6             // CSS y-offset 6

    // Pulsing ring: `inset:-3` (extends 3pt past the 48 circle), `2px solid accent`
    static let ringInset: CGFloat = 3
    static let ringWidth: CGFloat = 2
    static let ringScaleMin: CGFloat = 1.0
    static let ringScaleMax: CGFloat = 1.18     // gentle expand on the pulse
    static let ringOpacityMax: Double = 0.9
    static let ringOpacityMin: Double = 0.0     // fade out as it expands
    static let pulseDuration: Double = 1.8      // lbp-pulse-dot 1.8s

    // Count badge: `top:-2, right:-2`, minWidth 18, height 18, padding 0 4,
    // fontSize 10 weight 800, white bg, accent text, 2px accent border
    static let badgeMinWidth: CGFloat = 18
    static let badgeHeight: CGFloat = 18
    static let badgeFontSize: CGFloat = 10
    static let badgeHPadding: CGFloat = 4
    static let badgeBorderWidth: CGFloat = 2
    static let badgeOffsetX: CGFloat = 2        // right:-2 → nudge out past the edge
    static let badgeOffsetY: CGFloat = -2       // top:-2
}

// MARK: - Deterministic demo data (previews + snapshot test)

public extension WinEntryView {

    /// A deterministic unclaimed-win set for previews / the snapshot test: two
    /// winners (a product award + a discount award), insertion-ordered, so a
    /// `count == 2` badge renders. Built ONLY from real public `LBWinner` /
    /// `LBAward` fields — no private template construction.
    static var demoUnclaimedWinners: [LBWinner] {
        [
            LBWinner(
                id: "demo-ticket-1",
                eventId: 9001,
                title: "週年慶抽獎",
                award: LBAward(type: "product", code: "PRD-AURORA-001", name: "極光保溫瓶")
            ),
            LBWinner(
                id: "demo-ticket-2",
                eventId: 9002,
                title: "限時加碼",
                award: LBAward(type: "discount", code: "SAVE15", name: "全站 85 折券")
            )
        ]
    }

    /// A deterministic demo instance of the entry: the minimal-palette theme is
    /// supplied by the caller; the count + winners are the deterministic demo set.
    /// Action-free (no `onTap`) so previews / snapshot tests render statically.
    static func demo(theme: ReferenceUITheme = ReferenceUIThemePalette.minimal) -> WinEntryView {
        WinEntryView(
            theme: theme,
            unclaimedCount: demoUnclaimedWinners.count,
            unclaimedWinners: demoUnclaimedWinners
        )
    }
}

// MARK: - Preview (deterministic demo)

#if DEBUG
struct WinEntryView_Previews: PreviewProvider {
    static var previews: some View {
        WinEntryView.demo()
            .padding(40)
            .background(Color.black)
            .previewLayout(.sizeThatFits)
    }
}
#endif
