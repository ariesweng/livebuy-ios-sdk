import SwiftUI
import LivebuySDK
import LivebuyUI

// MARK: - WinEntryView — family-2 feed-win surface 2 (unclaimed-win entry +
//         activity-join entry)
//
// Spec: `reference-ui-rendering/spec.md` (family-2 feed-win, surface 2)
// Design: rb-ios-win-entry-restyle design.md D-1 / D-2 / D-3.
//   Design source: `design/templates/minimal/moments.jsx` · `LBWinEntry`
//     (a floating 48×48 SQUARE button, `cornerRadius 10`, solid white background,
//     no pulsing ring, a two-tone gift/trophy glyph — outer `#F03246` / inner
//     white, `evenodd` fill — and a bottom translucent-dark "領獎" text label; no
//     count badge).
//
// rb-ios-live-activity-sheet (2026-08-29): `LBWinEntry` is ONE component with TWO
// uses in the design (`variant="win"` / `variant="activity"`, same file,
// `components.md` registers both under the one `LBWinEntry` entry — see
// `design/contract/claude-design-sync.md` R24/R26). This view now takes a
// `variant: WinEntryVariant` (default `.win`, source-compatible) so BOTH uses share
// this one type instead of duplicating the 48×48 frame / corner radius / glyph
// structure into a second type (design.md D1). The `.activity` variant renders a
// SEPARATE floating entry (translucent dark background, "活動" label) that opens
// `LiveActivitySheetView` bound to `DefaultActiveEvent.currentActivity`; see
// `FeedWinOverlayView.swift` for how the two entries stack.
//
// This is family-2 SURFACE 2. It follows the documented SUB-VIEW INPUT PATTERN
// from `FeedWinOverlayView.swift` EXACTLY:
//   1. `theme: ReferenceUITheme`            — FIRST positional argument, always.
//   2. the bound SNAPSHOT VALUES it renders — `unclaimedCount` (drives `.win`'s
//      visibility) and `unclaimedWinners` (the by-value mirror of
//      `DefaultWinClaim.unclaimedWinners`; the container opens the claim sheet on
//      the EARLIEST one, so this surface itself never records / removes /
//      reorders — it is read-only), plus `variant` / `isActive` (`.activity`'s
//      visibility gate, added rb-ios-live-activity-sheet). Passed BY VALUE from
//      `FeedWinModel`.
//   3. optional action closure, trailing, defaulting to `nil` (`onTap`). The
//      container / host wires it to open the claim sheet on the earliest unclaimed
//      winner (`.win`) / the activity sheet (`.activity`); this surface does NOT
//      own the open intent and renders correctly with it nil (so demo / snapshot
//      instances construct action-free).
//
// One-way data flow (D-1): this view reads ONLY its passed-in values — it never
// reaches back into `FeedWinModel` or `DefaultPlayerTemplate`, and it neither
// records a win nor removes one (those live in `DefaultWinClaim`), nor does it know
// anything about `DefaultActiveEvent` (`isActive` is a plain `Bool` the container
// already resolved — design.md D2). It only surfaces a single `onTap` open intent;
// the container funnels that to the claim sheet / activity sheet.
//
// Visibility rule (D-3, unchanged by rb-ios-win-entry-restyle): `.win` is drawn
// ONLY when `unclaimedCount > 0`; `.activity` is drawn ONLY when `isActive` is
// `true` (rb-ios-live-activity-sheet, design.md D2 — deliberately the SAME
// "component decides internally" placement as `.win`, so both variants share one
// mental model for "who decides visibility"). Otherwise each renders nothing (an
// `EmptyView`-equivalent zero-size view) so the container's slot is visually empty.
// rb-ios-win-entry-restyle removed the count-badge VISUAL that used to sit on top
// of `.win` — this show/hide gate itself is untouched.
//
// iOS-14-safe: uses only `ZStack` / `Button` / `RoundedRectangle` / `Path` / `Text`
// — all iOS-13+. rb-ios-win-entry-restyle removed the pulsing-ring animation
// entirely, so this view no longer reads `@Environment(\.continuousAnimationGate)`
// or drives any `repeatForever` animation.

/// The `LBWinEntry` variant a `WinEntryView` instance renders (design.md D1,
/// rb-ios-live-activity-sheet). Both cases share the identical 48×48 square frame,
/// corner radius, and gift/trophy glyph — only background color, bottom label text,
/// and accessibility identity differ.
public enum WinEntryVariant: Equatable {
    /// 中獎查看入口（既有，`rb-ios-win-entry-restyle`）— white background, "領獎" 標籤,
    /// visible when `unclaimedCount > 0`.
    case win
    /// 活動參加入口（本 change 新增）— translucent dark background, "活動" 標籤,
    /// visible when `isActive == true`.
    case activity
}

/// The family-2 unclaimed-win entry. A floating 48×48 square button pinned by the
/// container, drawn ONLY when `unclaimedCount > 0`. Renders the design's two-tone
/// gift/trophy glyph over a white background with a bottom "領獎" text label — no
/// pulsing ring, no count badge (rb-ios-win-entry-restyle). Tapping surfaces the
/// `onTap` open intent (the container opens the claim sheet on the earliest
/// unclaimed winner).
public struct WinEntryView: View {
    /// Observed so a runtime language switch re-renders this view's localized copy
    /// (`rb-ios-i18n-string-table`; see `ReferenceUILanguage`).
    @ObservedObject var l10n = ReferenceUILanguage.shared

    // MARK: - Inputs (documented sub-view input pattern)

    /// The resolved reference-ui theme (FIRST positional argument, always — the
    /// documented sub-view input pattern). This design hardcodes both the glyph
    /// fill and the button background (design.md D-1/D-2), so `theme` is not read
    /// internally; the parameter stays for pattern consistency with the other
    /// family-2 surfaces.
    public let theme: ReferenceUITheme

    /// Which `LBWinEntry` use this instance renders (rb-ios-live-activity-sheet,
    /// design.md D1). Defaults to `.win` so every existing call site stays
    /// source-compatible.
    public let variant: WinEntryVariant

    /// Distinct unclaimed-win count (`DefaultWinClaim.unclaimedCount`). `.win`'s
    /// visibility gate — drawn ONLY when this is `> 0` (D-3's gate; unaffected by
    /// rb-ios-win-entry-restyle). Ignored for `.activity`.
    public let unclaimedCount: Int

    /// Unclaimed winners, insertion-ordered, deduped by id
    /// (`DefaultWinClaim.unclaimedWinners`), passed BY VALUE. The container opens
    /// the claim sheet on `unclaimedWinners.first` (earliest); this read-only
    /// surface keeps the value so the wired-intent contract is explicit, but it
    /// NEVER records / removes / reorders winners. Ignored for `.activity`.
    public let unclaimedWinners: [LBWinner]

    /// `.activity`'s visibility gate (rb-ios-live-activity-sheet, design.md D2) —
    /// drawn ONLY when `true`. The container resolves this from
    /// `DefaultActiveEvent.currentActivity != nil`; this view stays a pure
    /// presentation component and never imports `LivebuyUI` / holds a
    /// `DefaultActiveEvent` reference itself. Ignored for `.win` (which uses
    /// `unclaimedCount` instead — the two gates are intentionally NOT unified onto
    /// one field, see design.md D2).
    public let isActive: Bool

    /// Open-claim / open-activity intent. The entry does NOT own the action — the
    /// container / host funnels it to the claim sheet (`.win`) or the activity
    /// sheet (`.activity`). Default `nil` so demo / snapshot instances construct
    /// action-free.
    public let onTap: (() -> Void)?

    public init(
        theme: ReferenceUITheme,
        variant: WinEntryVariant = .win,
        unclaimedCount: Int = 0,
        unclaimedWinners: [LBWinner] = [],
        isActive: Bool = false,
        onTap: (() -> Void)? = nil
    ) {
        self.theme = theme
        self.variant = variant
        self.unclaimedCount = unclaimedCount
        self.unclaimedWinners = unclaimedWinners
        self.isActive = isActive
        self.onTap = onTap
    }

    // MARK: - Body

    public var body: some View {
        // Visibility rule: `.win` — nothing to claim → draw nothing (D-3).
        // `.activity` — no current activity → draw nothing (design.md D2,
        // rb-ios-live-activity-sheet). Both gates are decided HERE, inside the
        // component's own body — deliberately symmetric with the pre-existing
        // `.win` placement (the container always instantiates this view; it never
        // conditionally mounts it), so there is exactly one mental model for "who
        // decides visibility" across both variants.
        switch variant {
        case .win:
            if unclaimedCount > 0 {
                entryButton
            }
        case .activity:
            if isActive {
                entryButton
            }
        }
    }

    // MARK: - Entry button (`LBWinEntry`)

    /// The 48×48 floating square button: background / label vary by `variant`
    /// (design.md D1 §1.4/1.5), the two-tone gift/trophy glyph is centered on the
    /// full button area and is 100% SHARED between variants (design.md D4 — no
    /// second glyph path).
    private var entryButton: some View {
        Button(action: { onTap?() }) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: Self.cornerRadius)
                    .fill(backgroundColor)

                // Glyph — centered on the FULL 48×48 button area. The design's
                // icon slot is `flex:1` inside the button's own 48pt height (the
                // label below is absolutely positioned and does not shrink it),
                // so the glyph centers on the whole button, not on the area
                // remaining above the label (design.md D-2).
                glyph
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

                label
            }
            .frame(width: Self.entrySize, height: Self.entrySize)
            // Clip so the label's straight bottom edges follow the button's
            // rounded corners (mirrors the design's `overflow: hidden`, D-2).
            .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityLabel(accessibilityLabelText)
    }

    /// Button background — `.win` solid white (unchanged); `.activity` translucent
    /// dark `rgb(58 58 58 / 30%)` (design.md 1.4, `moments.jsx` `LBWinEntry`
    /// `variant="activity"` — NOT `theme.accent`, a design-literal like the glyph).
    private var backgroundColor: Color {
        switch variant {
        case .win: return Color.white
        case .activity: return Self.activityBackground
        }
    }

    /// Bottom label text — `.win` "領獎" (unchanged); `.activity` "活動"
    /// (design.md 1.5).
    private var labelText: String {
        switch variant {
        case .win: return Self.winLabelText
        case .activity: return Self.activityLabelText
        }
    }

    /// Accessibility identifier — `.activity` gets a NEW, independent id
    /// (`LBAccessibilityID.activityEntry`, design.md D5): both entries can now be
    /// on screen SIMULTANEOUSLY, so E2E / QA scripts must be able to address each
    /// one separately. `.win` keeps its existing id unchanged.
    private var accessibilityIdentifier: String {
        switch variant {
        case .win: return LBAccessibilityID.winEntry
        case .activity: return LBAccessibilityID.activityEntry
        }
    }

    /// Accessibility label (mirrors the design source's `aria-label`) — "查看中獎"
    /// for `.win`, "參加活動" for `.activity` (design.md 1.7, `moments.jsx`
    /// `LBWinEntry`'s `aria-label={isActivity ? '參加活動' : '查看中獎'}`).
    private var accessibilityLabelText: String {
        switch variant {
        case .win: return Self.winAccessibilityLabel
        case .activity: return Self.activityAccessibilityLabel
        }
    }

    /// The two-tone gift/trophy glyph: outer silhouette filled hardcoded
    /// `#F03246` (NOT `theme.accent` — a deliberate divergence from this module's
    /// usual accent-coloring convention, per design.md D-1), inner cutouts filled
    /// white, both drawn with `evenodd` fill (mirrors the SVG's inherited
    /// `fill-rule="evenodd"`). The two `Path`s are authored in the native
    /// `0...200` SVG coordinate space and scaled down into the `glyphSize` box
    /// via `CGAffineTransform` at render time (design.md D-1's coordinate-system
    /// decision).
    private var glyph: some View {
        let scale = Self.glyphSize / 200
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        return ZStack {
            WinEntryGiftGlyph.outlinePath()
                .applying(transform)
                .fill(Self.glyphOuterColor, style: FillStyle(eoFill: true))
            WinEntryGiftGlyph.innerPath()
                .applying(transform)
                .fill(Color.white, style: FillStyle(eoFill: true))
        }
        .frame(width: Self.glyphSize, height: Self.glyphSize)
    }

    /// The bottom translucent-dark text label ("領獎" / "活動" per `variant`, the
    /// design's absolutely positioned `bottom:0` span, `rgba(55,60,68,0.8)`
    /// background — SAME background for both variants, only the text differs,
    /// D-2 / design.md 1.5).
    private var label: some View {
        Text(labelText)
            .font(.system(size: Self.labelFontSize, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: Self.labelHeight)
            .background(Self.labelBackground)
    }
}

// MARK: - WinEntryGiftGlyph — mechanically ported two-path gift/trophy glyph
//
// Design: rb-ios-win-entry-restyle design.md D-1. Coordinates are copied AS-IS
// from `design/templates/minimal/moments.jsx`'s `LBWinEntry` two
// `<path d="...">` strings (`viewBox 0 0 200 200`) via a one-off parser script
// (discarded after use) that machine-translated each `M`/`L`/`C`/`Z` SVG path
// command into the matching `Path` builder call — neither string contains an
// `a`/`A` elliptical-arc command, so no arc→bezier conversion
// (`icon-authoring.md` rule 1) is needed. The generated segment counts were
// cross-checked against the original `d` strings' command counts (task 1.2).
enum WinEntryGiftGlyph {

    /// Outer silhouette (`fill={giftFill}` in the design, filled hardcoded
    /// `#F03246` at the call site). A single closed subpath (1 `M` + 68 `C` + 8
    /// `L` + 1 `Z`, cross-checked against the original `d` string's command
    /// counts — task 1.2).
    static func outlinePath() -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 24.78, y: 199.49))
        p.addCurve(to: CGPoint(x: 23.75, y: 199), control1: CGPoint(x: 24.46, y: 199.22), control2: CGPoint(x: 23.99, y: 199))
        p.addCurve(to: CGPoint(x: 19.75, y: 197.14), control1: CGPoint(x: 23.19, y: 199), control2: CGPoint(x: 21.24, y: 198.09))
        p.addCurve(to: CGPoint(x: 14.89, y: 192.38), control1: CGPoint(x: 18.15, y: 196.11), control2: CGPoint(x: 15.83, y: 193.84))
        p.addCurve(to: CGPoint(x: 12.56, y: 187.82), control1: CGPoint(x: 13.39, y: 190.04), control2: CGPoint(x: 13.25, y: 189.77))
        p.addLine(to: CGPoint(x: 11.88, y: 185.88))
        p.addLine(to: CGPoint(x: 11.81, y: 139.62))
        p.addLine(to: CGPoint(x: 11.74, y: 93.37))
        p.addLine(to: CGPoint(x: 10.32, y: 92.62))
        p.addCurve(to: CGPoint(x: 2.05, y: 84.66), control1: CGPoint(x: 6.32, y: 90.52), control2: CGPoint(x: 3.64, y: 87.94))
        p.addCurve(to: CGPoint(x: 1, y: 82.04), control1: CGPoint(x: 1.47, y: 83.48), control2: CGPoint(x: 1, y: 82.3))
        p.addCurve(to: CGPoint(x: 0.5, y: 80.93), control1: CGPoint(x: 1, y: 81.78), control2: CGPoint(x: 0.77, y: 81.28))
        p.addCurve(to: CGPoint(x: 0, y: 70.42), control1: CGPoint(x: 0.02, y: 80.32), control2: CGPoint(x: 0, y: 79.92))
        p.addCurve(to: CGPoint(x: 0.35, y: 60.42), control1: CGPoint(x: 0, y: 62.18), control2: CGPoint(x: 0.06, y: 60.53))
        p.addCurve(to: CGPoint(x: 0.88, y: 59.45), control1: CGPoint(x: 0.54, y: 60.34), control2: CGPoint(x: 0.78, y: 59.91))
        p.addCurve(to: CGPoint(x: 10, y: 48.69), control1: CGPoint(x: 1.73, y: 55.46), control2: CGPoint(x: 5.74, y: 50.72))
        p.addCurve(to: CGPoint(x: 27.37, y: 47.01), control1: CGPoint(x: 13.4, y: 47.07), control2: CGPoint(x: 12.63, y: 47.15))
        p.addCurve(to: CGPoint(x: 40.96, y: 46.42), control1: CGPoint(x: 40.18, y: 46.88), control2: CGPoint(x: 40.87, y: 46.85))
        p.addCurve(to: CGPoint(x: 40.61, y: 45.48), control1: CGPoint(x: 41, y: 46.17), control2: CGPoint(x: 40.85, y: 45.75))
        p.addCurve(to: CGPoint(x: 38.68, y: 42.12), control1: CGPoint(x: 40.08, y: 44.89), control2: CGPoint(x: 39.78, y: 44.39))
        p.addCurve(to: CGPoint(x: 37, y: 38.32), control1: CGPoint(x: 37.48, y: 39.69), control2: CGPoint(x: 37, y: 38.59))
        p.addCurve(to: CGPoint(x: 36.51, y: 36.48), control1: CGPoint(x: 37, y: 38.19), control2: CGPoint(x: 36.78, y: 37.36))
        p.addCurve(to: CGPoint(x: 36.61, y: 21.62), control1: CGPoint(x: 35.43, y: 32.95), control2: CGPoint(x: 35.48, y: 25.46))
        p.addCurve(to: CGPoint(x: 46.63, y: 6.53), control1: CGPoint(x: 38.41, y: 15.53), control2: CGPoint(x: 41.86, y: 10.34))
        p.addCurve(to: CGPoint(x: 48.88, y: 4.82), control1: CGPoint(x: 47.59, y: 5.76), control2: CGPoint(x: 48.61, y: 4.99))
        p.addCurve(to: CGPoint(x: 57.08, y: 1.21), control1: CGPoint(x: 51.93, y: 2.96), control2: CGPoint(x: 54.37, y: 1.88))
        p.addCurve(to: CGPoint(x: 59.68, y: 0.35), control1: CGPoint(x: 58.2, y: 0.93), control2: CGPoint(x: 59.37, y: 0.54))
        p.addCurve(to: CGPoint(x: 70.85, y: 0.37), control1: CGPoint(x: 60.49, y: -0.16), control2: CGPoint(x: 70.17, y: -0.14))
        p.addCurve(to: CGPoint(x: 72.72, y: 1.01), control1: CGPoint(x: 71.1, y: 0.57), control2: CGPoint(x: 71.95, y: 0.85))
        p.addCurve(to: CGPoint(x: 83.48, y: 6.67), control1: CGPoint(x: 76.52, y: 1.76), control2: CGPoint(x: 80.21, y: 3.7))
        p.addCurve(to: CGPoint(x: 89.37, y: 13.78), control1: CGPoint(x: 85.08, y: 8.11), control2: CGPoint(x: 88.41, y: 12.13))
        p.addCurve(to: CGPoint(x: 90.67, y: 16), control1: CGPoint(x: 89.65, y: 14.24), control2: CGPoint(x: 90.23, y: 15.24))
        p.addCurve(to: CGPoint(x: 95.51, y: 25.88), control1: CGPoint(x: 91.75, y: 17.84), control2: CGPoint(x: 93.99, y: 22.43))
        p.addCurve(to: CGPoint(x: 97.5, y: 30.75), control1: CGPoint(x: 95.92, y: 26.8), control2: CGPoint(x: 96.14, y: 27.35))
        p.addCurve(to: CGPoint(x: 98.48, y: 33.19), control1: CGPoint(x: 97.78, y: 31.44), control2: CGPoint(x: 98.22, y: 32.53))
        p.addCurve(to: CGPoint(x: 99.19, y: 35.12), control1: CGPoint(x: 98.75, y: 33.84), control2: CGPoint(x: 99.07, y: 34.71))
        p.addCurve(to: CGPoint(x: 100.01, y: 35.88), control1: CGPoint(x: 99.36, y: 35.69), control2: CGPoint(x: 99.57, y: 35.88))
        p.addCurve(to: CGPoint(x: 100.84, y: 35.12), control1: CGPoint(x: 100.46, y: 35.88), control2: CGPoint(x: 100.67, y: 35.69))
        p.addCurve(to: CGPoint(x: 101.53, y: 33.35), control1: CGPoint(x: 100.96, y: 34.71), control2: CGPoint(x: 101.27, y: 33.91))
        p.addCurve(to: CGPoint(x: 102.01, y: 32.1), control1: CGPoint(x: 101.79, y: 32.78), control2: CGPoint(x: 102, y: 32.22))
        p.addCurve(to: CGPoint(x: 102.5, y: 30.88), control1: CGPoint(x: 102.01, y: 31.98), control2: CGPoint(x: 102.23, y: 31.43))
        p.addCurve(to: CGPoint(x: 102.99, y: 29.55), control1: CGPoint(x: 102.77, y: 30.32), control2: CGPoint(x: 102.99, y: 29.73))
        p.addCurve(to: CGPoint(x: 103.48, y: 28.3), control1: CGPoint(x: 103, y: 29.37), control2: CGPoint(x: 103.22, y: 28.81))
        p.addCurve(to: CGPoint(x: 104.64, y: 25.75), control1: CGPoint(x: 103.75, y: 27.79), control2: CGPoint(x: 104.27, y: 26.64))
        p.addCurve(to: CGPoint(x: 106.13, y: 22.38), control1: CGPoint(x: 105.01, y: 24.86), control2: CGPoint(x: 105.68, y: 23.34))
        p.addCurve(to: CGPoint(x: 107.1, y: 20.25), control1: CGPoint(x: 106.58, y: 21.41), control2: CGPoint(x: 107.02, y: 20.46))
        p.addCurve(to: CGPoint(x: 108.37, y: 17.88), control1: CGPoint(x: 107.18, y: 20.04), control2: CGPoint(x: 107.76, y: 18.98))
        p.addCurve(to: CGPoint(x: 109.81, y: 15.25), control1: CGPoint(x: 108.99, y: 16.77), control2: CGPoint(x: 109.64, y: 15.59))
        p.addCurve(to: CGPoint(x: 116.04, y: 7.1), control1: CGPoint(x: 110.84, y: 13.2), control2: CGPoint(x: 114.1, y: 8.93))
        p.addCurve(to: CGPoint(x: 126.62, y: 1.2), control1: CGPoint(x: 119.07, y: 4.23), control2: CGPoint(x: 122.94, y: 2.07))
        p.addCurve(to: CGPoint(x: 129.27, y: 0.33), control1: CGPoint(x: 127.86, y: 0.91), control2: CGPoint(x: 129.05, y: 0.52))
        p.addCurve(to: CGPoint(x: 134.65, y: 0), control1: CGPoint(x: 129.57, y: 0.08), control2: CGPoint(x: 130.86, y: 0))
        p.addCurve(to: CGPoint(x: 140.63, y: 0.5), control1: CGPoint(x: 139.15, y: 0), control2: CGPoint(x: 139.74, y: 0.05))
        p.addCurve(to: CGPoint(x: 142.15, y: 1), control1: CGPoint(x: 141.16, y: 0.78), control2: CGPoint(x: 141.85, y: 1))
        p.addCurve(to: CGPoint(x: 151.19, y: 4.83), control1: CGPoint(x: 143.57, y: 1), control2: CGPoint(x: 148.42, y: 3.05))
        p.addCurve(to: CGPoint(x: 161.49, y: 16.62), control1: CGPoint(x: 155.32, y: 7.47), control2: CGPoint(x: 159.24, y: 11.96))
        p.addCurve(to: CGPoint(x: 159.81, y: 44.94), control1: CGPoint(x: 165.93, y: 25.84), control2: CGPoint(x: 165.3, y: 36.56))
        p.addCurve(to: CGPoint(x: 159.09, y: 46.62), control1: CGPoint(x: 159.34, y: 45.66), control2: CGPoint(x: 159.01, y: 46.42))
        p.addCurve(to: CGPoint(x: 172.68, y: 47.06), control1: CGPoint(x: 159.21, y: 46.93), control2: CGPoint(x: 161.21, y: 46.99))
        p.addCurve(to: CGPoint(x: 187.62, y: 47.69), control1: CGPoint(x: 185.71, y: 47.15), control2: CGPoint(x: 186.17, y: 47.16))
        p.addCurve(to: CGPoint(x: 192.38, y: 50.03), control1: CGPoint(x: 189.35, y: 48.31), control2: CGPoint(x: 190.95, y: 49.1))
        p.addCurve(to: CGPoint(x: 197.07, y: 54.76), control1: CGPoint(x: 193.55, y: 50.81), control2: CGPoint(x: 196.23, y: 53.5))
        p.addCurve(to: CGPoint(x: 199, y: 58.95), control1: CGPoint(x: 197.91, y: 56.01), control2: CGPoint(x: 199, y: 58.38))
        p.addCurve(to: CGPoint(x: 199.5, y: 60.07), control1: CGPoint(x: 199, y: 59.22), control2: CGPoint(x: 199.22, y: 59.72))
        p.addCurve(to: CGPoint(x: 200, y: 70.57), control1: CGPoint(x: 199.98, y: 60.68), control2: CGPoint(x: 200, y: 61.08))
        p.addCurve(to: CGPoint(x: 199.64, y: 80.74), control1: CGPoint(x: 200, y: 78.84), control2: CGPoint(x: 199.94, y: 80.49))
        p.addCurve(to: CGPoint(x: 199.11, y: 81.83), control1: CGPoint(x: 199.44, y: 80.9), control2: CGPoint(x: 199.21, y: 81.39))
        p.addCurve(to: CGPoint(x: 190.02, y: 92.5), control1: CGPoint(x: 198.27, y: 85.83), control2: CGPoint(x: 194.71, y: 90))
        p.addLine(to: CGPoint(x: 188.38, y: 93.38))
        p.addLine(to: CGPoint(x: 188.25, y: 139.75))
        p.addLine(to: CGPoint(x: 188.12, y: 186.12))
        p.addLine(to: CGPoint(x: 187.43, y: 187.83))
        p.addCurve(to: CGPoint(x: 182.13, y: 195.61), control1: CGPoint(x: 185.99, y: 191.38), control2: CGPoint(x: 184.41, y: 193.71))
        p.addCurve(to: CGPoint(x: 175.31, y: 199.26), control1: CGPoint(x: 180.04, y: 197.36), control2: CGPoint(x: 179.02, y: 197.9))
        p.addCurve(to: CGPoint(x: 174.5, y: 199.78), control1: CGPoint(x: 174.87, y: 199.43), control2: CGPoint(x: 174.5, y: 199.66))
        p.addCurve(to: CGPoint(x: 99.94, y: 199.99), control1: CGPoint(x: 174.5, y: 199.91), control2: CGPoint(x: 142.62, y: 200))
        p.addCurve(to: CGPoint(x: 24.78, y: 199.49), control1: CGPoint(x: 26.17, y: 199.98), control2: CGPoint(x: 25.37, y: 199.98))
        p.closeSubpath()
        return p
    }

    /// Inner cutouts (`fill="#FFFFFF"` in the design). 4 independent closed
    /// subpaths (4 `M` + 48 `C` + 18 `L` + 4 `Z`, cross-checked against the
    /// original `d` string's command counts — task 1.2) — combined with
    /// `evenodd` fill at the call site, these render as negative-space cutouts
    /// through the outer silhouette.
    static func innerPath() -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 76.75, y: 153.3))
        p.addCurve(to: CGPoint(x: 76.45, y: 106.3), control1: CGPoint(x: 76.75, y: 117.31), control2: CGPoint(x: 76.68, y: 106.53))
        p.addCurve(to: CGPoint(x: 43.95, y: 106), control1: CGPoint(x: 76.22, y: 106.07), control2: CGPoint(x: 68.66, y: 106))
        p.addLine(to: CGPoint(x: 11.75, y: 106))
        p.addLine(to: CGPoint(x: 11.75, y: 99.62))
        p.addLine(to: CGPoint(x: 11.75, y: 93.24))
        p.addLine(to: CGPoint(x: 12.44, y: 93.4))
        p.addCurve(to: CGPoint(x: 13.62, y: 93.85), control1: CGPoint(x: 12.82, y: 93.5), control2: CGPoint(x: 13.35, y: 93.69))
        p.addCurve(to: CGPoint(x: 76.25, y: 94), control1: CGPoint(x: 14.32, y: 94.23), control2: CGPoint(x: 75.53, y: 94.39))
        p.addCurve(to: CGPoint(x: 76.81, y: 76.43), control1: CGPoint(x: 76.74, y: 93.74), control2: CGPoint(x: 76.75, y: 93.45))
        p.addLine(to: CGPoint(x: 76.88, y: 59.12))
        p.addLine(to: CGPoint(x: 82.5, y: 59.12))
        p.addLine(to: CGPoint(x: 88.12, y: 59.12))
        p.addLine(to: CGPoint(x: 88.19, y: 129.56))
        p.addLine(to: CGPoint(x: 88.25, y: 200))
        p.addLine(to: CGPoint(x: 82.5, y: 200))
        p.addLine(to: CGPoint(x: 76.75, y: 200))
        p.addLine(to: CGPoint(x: 76.75, y: 153.3))
        p.closeSubpath()
        p.move(to: CGPoint(x: 111.75, y: 129.9))
        p.addCurve(to: CGPoint(x: 111.9, y: 59.4), control1: CGPoint(x: 111.75, y: 91.34), control2: CGPoint(x: 111.82, y: 59.61))
        p.addCurve(to: CGPoint(x: 117.5, y: 59), control1: CGPoint(x: 112.03, y: 59.05), control2: CGPoint(x: 112.76, y: 59))
        p.addCurve(to: CGPoint(x: 123.22, y: 59.34), control1: CGPoint(x: 121.81, y: 59), control2: CGPoint(x: 123, y: 59.07))
        p.addCurve(to: CGPoint(x: 123.49, y: 76.65), control1: CGPoint(x: 123.43, y: 59.59), control2: CGPoint(x: 123.51, y: 64.28))
        p.addCurve(to: CGPoint(x: 123.93, y: 93.94), control1: CGPoint(x: 123.48, y: 92.66), control2: CGPoint(x: 123.5, y: 93.64))
        p.addCurve(to: CGPoint(x: 155.12, y: 94.19), control1: CGPoint(x: 124.29, y: 94.21), control2: CGPoint(x: 130.1, y: 94.25))
        p.addCurve(to: CGPoint(x: 186.88, y: 93.69), control1: CGPoint(x: 183.09, y: 94.11), control2: CGPoint(x: 185.97, y: 94.06))
        p.addCurve(to: CGPoint(x: 188.12, y: 93.26), control1: CGPoint(x: 187.43, y: 93.46), control2: CGPoint(x: 187.99, y: 93.27))
        p.addCurve(to: CGPoint(x: 188.3, y: 99.62), control1: CGPoint(x: 188.29, y: 93.25), control2: CGPoint(x: 188.35, y: 95.49))
        p.addLine(to: CGPoint(x: 188.23, y: 106))
        p.addLine(to: CGPoint(x: 156.01, y: 106))
        p.addCurve(to: CGPoint(x: 123.64, y: 106.23), control1: CGPoint(x: 136.42, y: 106), control2: CGPoint(x: 123.72, y: 106.09))
        p.addCurve(to: CGPoint(x: 123.5, y: 153.23), control1: CGPoint(x: 123.56, y: 106.36), control2: CGPoint(x: 123.49, y: 127.51))
        p.addLine(to: CGPoint(x: 123.5, y: 200))
        p.addLine(to: CGPoint(x: 117.63, y: 200))
        p.addLine(to: CGPoint(x: 111.75, y: 200))
        p.addLine(to: CGPoint(x: 111.75, y: 129.9))
        p.closeSubpath()
        p.move(to: CGPoint(x: 62.62, y: 46.84))
        p.addCurve(to: CGPoint(x: 55.25, y: 43.96), control1: CGPoint(x: 59.24, y: 46.11), control2: CGPoint(x: 57.49, y: 45.43))
        p.addCurve(to: CGPoint(x: 47.75, y: 32.96), control1: CGPoint(x: 51.31, y: 41.38), control2: CGPoint(x: 48.78, y: 37.67))
        p.addCurve(to: CGPoint(x: 47.74, y: 25.92), control1: CGPoint(x: 47.13, y: 30.08), control2: CGPoint(x: 47.12, y: 28.92))
        p.addCurve(to: CGPoint(x: 59.64, y: 12.63), control1: CGPoint(x: 49.05, y: 19.56), control2: CGPoint(x: 53.24, y: 14.87))
        p.addCurve(to: CGPoint(x: 65.12, y: 11.95), control1: CGPoint(x: 61.45, y: 12), control2: CGPoint(x: 61.93, y: 11.94))
        p.addCurve(to: CGPoint(x: 70.38, y: 12.5), control1: CGPoint(x: 68.01, y: 11.95), control2: CGPoint(x: 68.93, y: 12.05))
        p.addCurve(to: CGPoint(x: 80.8, y: 22.38), control1: CGPoint(x: 74.59, y: 13.82), control2: CGPoint(x: 77.44, y: 16.52))
        p.addCurve(to: CGPoint(x: 85.65, y: 32.81), control1: CGPoint(x: 82.15, y: 24.73), control2: CGPoint(x: 83.54, y: 27.72))
        p.addCurve(to: CGPoint(x: 86.62, y: 35.12), control1: CGPoint(x: 86, y: 33.67), control2: CGPoint(x: 86.44, y: 34.71))
        p.addCurve(to: CGPoint(x: 87.61, y: 37.62), control1: CGPoint(x: 86.79, y: 35.54), control2: CGPoint(x: 87.24, y: 36.66))
        p.addCurve(to: CGPoint(x: 88.64, y: 40.16), control1: CGPoint(x: 87.98, y: 38.59), control2: CGPoint(x: 88.45, y: 39.73))
        p.addCurve(to: CGPoint(x: 89, y: 41.12), control1: CGPoint(x: 88.84, y: 40.6), control2: CGPoint(x: 89, y: 41.03))
        p.addCurve(to: CGPoint(x: 89.35, y: 42.09), control1: CGPoint(x: 89, y: 41.22), control2: CGPoint(x: 89.16, y: 41.65))
        p.addCurve(to: CGPoint(x: 90.96, y: 46.41), control1: CGPoint(x: 90.68, y: 45.04), control2: CGPoint(x: 91.04, y: 46.01))
        p.addCurve(to: CGPoint(x: 77, y: 46.91), control1: CGPoint(x: 90.87, y: 46.86), control2: CGPoint(x: 90.28, y: 46.88))
        p.addCurve(to: CGPoint(x: 62.62, y: 46.84), control1: CGPoint(x: 69.37, y: 46.93), control2: CGPoint(x: 62.9, y: 46.9))
        p.closeSubpath()
        p.move(to: CGPoint(x: 109.09, y: 46.62))
        p.addCurve(to: CGPoint(x: 109.5, y: 44.92), control1: CGPoint(x: 109, y: 46.39), control2: CGPoint(x: 109.19, y: 45.63))
        p.addCurve(to: CGPoint(x: 110.5, y: 42.5), control1: CGPoint(x: 109.81, y: 44.21), control2: CGPoint(x: 110.26, y: 43.12))
        p.addCurve(to: CGPoint(x: 112.5, y: 37.5), control1: CGPoint(x: 111.06, y: 41.07), control2: CGPoint(x: 111.79, y: 39.25))
        p.addCurve(to: CGPoint(x: 113.56, y: 34.88), control1: CGPoint(x: 112.81, y: 36.74), control2: CGPoint(x: 113.28, y: 35.56))
        p.addCurve(to: CGPoint(x: 114.38, y: 32.88), control1: CGPoint(x: 113.83, y: 34.19), control2: CGPoint(x: 114.2, y: 33.29))
        p.addCurve(to: CGPoint(x: 115.5, y: 30.25), control1: CGPoint(x: 114.57, y: 32.46), control2: CGPoint(x: 115.07, y: 31.28))
        p.addCurve(to: CGPoint(x: 121.48, y: 18.83), control1: CGPoint(x: 117.07, y: 26.48), control2: CGPoint(x: 120.08, y: 20.73))
        p.addCurve(to: CGPoint(x: 129.44, y: 12.6), control1: CGPoint(x: 124.03, y: 15.36), control2: CGPoint(x: 126.18, y: 13.68))
        p.addCurve(to: CGPoint(x: 134.88, y: 11.95), control1: CGPoint(x: 131.14, y: 12.03), control2: CGPoint(x: 131.8, y: 11.96))
        p.addCurve(to: CGPoint(x: 140, y: 12.49), control1: CGPoint(x: 137.83, y: 11.94), control2: CGPoint(x: 138.63, y: 12.03))
        p.addCurve(to: CGPoint(x: 148.81, y: 18.29), control1: CGPoint(x: 143.57, y: 13.68), control2: CGPoint(x: 146.79, y: 15.81))
        p.addCurve(to: CGPoint(x: 152.25, y: 25.42), control1: CGPoint(x: 150.2, y: 19.99), control2: CGPoint(x: 151.7, y: 23.1))
        p.addCurve(to: CGPoint(x: 145.11, y: 43.81), control1: CGPoint(x: 153.89, y: 32.33), control2: CGPoint(x: 151.02, y: 39.73))
        p.addCurve(to: CGPoint(x: 139.75, y: 46.32), control1: CGPoint(x: 143.63, y: 44.83), control2: CGPoint(x: 142, y: 45.6))
        p.addCurve(to: CGPoint(x: 123.68, y: 46.93), control1: CGPoint(x: 138.2, y: 46.82), control2: CGPoint(x: 137.49, y: 46.84))
        p.addCurve(to: CGPoint(x: 109.09, y: 46.62), control1: CGPoint(x: 110.55, y: 47.01), control2: CGPoint(x: 109.23, y: 46.99))
        p.closeSubpath()
        return p
    }
}

// MARK: - Design tokens (lifted from moments.jsx · LBWinEntry)

private extension WinEntryView {
    // Button
    static let entrySize: CGFloat = 48           // width/height 48
    static let cornerRadius: CGFloat = 10         // borderRadius 10

    // Glyph — the SVG's native viewBox is 0...200; scaled down to this display
    // size at render time (design.md D-1 / D-2), matching the design gallery's
    // 29×29 (`moments.jsx` `LBWinEntry`, `width="29" height="29"`) exactly —
    // shared by both `.win` and `.activity` variants (rb-ios-winentry-icon-size-align-design).
    static let glyphSize: CGFloat = 29
    static let glyphOuterColor = Color(red: 0xF0 / 255.0, green: 0x32 / 255.0, blue: 0x46 / 255.0) // #F03246, hardcoded — NOT theme.accent

    // `.activity` background — `rgb(58 58 58 / 30%)` (design.md 1.4, moments.jsx
    // `LBWinEntry` variant="activity"). 58/255 ≈ 0.227.
    static let activityBackground = Color(white: 0.227, opacity: 0.3)

    // Bottom label — `rgba(55,60,68,0.8)` background (shared by both variants),
    // white text, fontSize 9, lineHeight 14px. Text differs per variant.
    static var winLabelText: String { ReferenceUIStrings.text("win_entry_label") }
    static var activityLabelText: String { ReferenceUIStrings.text("win_entry_activity_label") }
    static let labelFontSize: CGFloat = 9
    static let labelHeight: CGFloat = 14
    static let labelBackground = Color(white: 0.216, opacity: 0.8) // rgba(55,60,68,0.8) ≈ #373C44 @ 0.8

    // Accessibility labels (mirrors the design source's `aria-label`, design.md 1.7).
    static var winAccessibilityLabel: String { ReferenceUIStrings.text("win_entry_a11y") }
    static var activityAccessibilityLabel: String { ReferenceUIStrings.text("win_entry_activity_a11y") }
}

// MARK: - Deterministic demo data (previews + snapshot test)

public extension WinEntryView {

    /// A deterministic unclaimed-win set for previews / the snapshot test: two
    /// winners (a product award + a discount award), insertion-ordered, so a
    /// `count == 2` entry renders. Built ONLY from real public `LBWinner` /
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
