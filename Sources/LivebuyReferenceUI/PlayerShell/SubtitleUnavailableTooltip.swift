import SwiftUI

// MARK: - SubtitleUnavailableTooltip — transient "no caption source" explanation bubble
//
// Spec: `reference-ui-rendering/spec.md` (`rb-ios-cc-icon-availability-redesign`)
// Design: `design/templates/minimal/sdk-components.jsx` `LBPTooltip` (design R42, 2026-09-10) —
// a small dark bubble + triangle arrow, `show` / `text` / `placement: 'top' | 'left'`. First (and
// currently only) caller is the CC (subtitle) pill's `.unavailable` state, at both
// `OperationRailView` (VOD side-rail, `placement: .left` — the bubble sits to the LEFT of the
// button, arrow pointing right into it, mirroring the rail's trailing-edge anchor) and
// `LiveBottomBarView` (LIVE bottom bar, `placement: .top` — the bubble sits ABOVE the button,
// arrow pointing down into it).
//
// Purely local presentation: `show` is driven by the CALLER's own local `@State` (a timer that
// flips it back to `false` after `CcUnavailableTooltipTiming.autoDismissSeconds`) — this view
// itself holds no state and has no host callback. `pointerEvents: none` in the design maps to
// `.allowsHitTesting(false)` here (the bubble is purely explanatory chrome, never a tap target).
//
// iOS-14-safe SwiftUI only: `ZStack` / `Text` / `Path` / `.fill` / `.cornerRadius` /
// `.transition` are all iOS-13+.

/// A small dark tooltip bubble with a triangle arrow, shown transiently to explain why the CC
/// (subtitle) pill is inert (`CcIconState.unavailable`). Purely presentational — `show` /
/// `placement` / `text` are the caller's own local state; this view has no callback.
public struct SubtitleUnavailableTooltip: View {

    /// Where the bubble sits relative to the button it explains.
    public enum Placement: Equatable {
        /// Bubble ABOVE the button, arrow pointing down — used by the LIVE bottom bar (a
        /// horizontal row anchored to the bottom edge, so the tooltip opens upward).
        case top
        /// Bubble to the LEFT of the button, arrow pointing right — used by the VOD side-rail (a
        /// vertical stack anchored to the trailing edge, so the tooltip opens leftward, away from
        /// the screen edge).
        case left
    }

    /// Design-literal copy (`screens.jsx` `showCCUnavailableToast`), shared by both call sites —
    /// exposed as the default so callers don't need to repeat the literal string.
    public static let defaultText = "未提供字幕/隱藏式輔助字幕"

    public let show: Bool
    public let placement: Placement
    public let text: String

    /// Internal reference-ui wiring — NOT something a host sets. Extra `.top`-placement-only
    /// horizontal offset applied to the arrow ALONE (`rb-ios-cc-tooltip-arrow-anchor-fix`), on
    /// top of whatever `.offset(x:)` a caller applies to this whole view for the viewport clamp
    /// (`clampedTopOffsetX`). See `arrowCompensationOffsetX(bubbleShift:)`'s doc comment for why
    /// this cancels the clamp shift out for the arrow specifically. Defaults to `0` so every
    /// existing/simple call site (`show:placement:text:` labeled construction — `OperationRailView`,
    /// the `#if DEBUG` preview) keeps compiling and rendering byte-identical, and `.left`
    /// placement never reads this value.
    public var arrowOffsetX: CGFloat = 0

    public init(
        show: Bool,
        placement: Placement,
        text: String = SubtitleUnavailableTooltip.defaultText,
        arrowOffsetX: CGFloat = 0
    ) {
        self.show = show
        self.placement = placement
        self.text = text
        self.arrowOffsetX = arrowOffsetX
    }

    public var body: some View {
        if show {
            bubble(arrowOffsetX: arrowOffsetX)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    // MARK: - Bubble

    /// `arrowOffsetX` (`rb-ios-cc-tooltip-arrow-anchor-fix`) is consumed ONLY by the `.top`
    /// branch's `arrow` node — `.left`'s `arrow` node is completely unchanged and never reads
    /// it, matching this fix's Flutter/`arrowOffset` sibling (top-only compensation).
    private func bubble(arrowOffsetX: CGFloat) -> some View {
        Group {
            switch placement {
            case .top:
                VStack(spacing: 0) {
                    bubbleLabel
                    arrow
                        .offset(x: arrowOffsetX)
                }
            case .left:
                HStack(spacing: 0) {
                    bubbleLabel
                    arrow
                }
            }
        }
    }

    private var bubbleLabel: some View {
        Text(text)
            .font(.system(size: Self.fontSize, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, Self.hPadding)
            .padding(.vertical, Self.vPadding)
            .fixedSize()
            .background(
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .fill(Self.bubbleColor)
            )
    }

    private var arrow: some View {
        let size = placement.arrowSize
        return TooltipArrowShape(placement: placement)
            .fill(Self.bubbleColor)
            .frame(width: size.width, height: size.height)
    }
}

// MARK: - Outside positioning (`rb-ios-cc-tooltip-position-fix`)
//
// BUG this section fixes (confirmed by reading the two call sites, 2026-09-10): both
// `OperationRailView.subtitlePillButton` and `LiveBottomBarView.ccToggleButton` used to wrap
// this tooltip in a bare `ZStack { button; tooltip }` with NO alignment override and NO
// `.offset()` — the bubble rendered dead-CENTERED on top of the button it explains, instead of
// to its LEFT (`.left`) / ABOVE (`.top`) per design. `Placement`'s cases have only ever
// controlled the bubble's OWN internal layout (`bubble` above — label+arrow orientation), never
// its position relative to the button; this section is what a caller now uses to fix that.
//
// Call-site usage (`.overlay(_:alignment:)`, the plain-View iOS-13+ overload — NOT the
// iOS-15+ closure-based `overlay(alignment:content:)`, matching this file's
// iOS-14-safe-SwiftUI constraint):
//
//   button.overlay(
//       SubtitleUnavailableTooltip(show: ..., placement: placement).positionedOutsideButton(),
//       alignment: placement.overlayAlignment
//   )
//
// `.overlay` (unlike a raw `ZStack`) does NOT let the tooltip influence the BUTTON's own
// reported size to its parent (`VStack` / `HStack`) — the rail / bottom bar's layout does not
// shift when the tooltip appears or disappears, matching the design's CSS
// `position: absolute` (the tooltip is floating chrome, not a participant in the layout flow).

extension SubtitleUnavailableTooltip {
    /// Gap (points) between the bubble+arrow's facing edge and the button it explains, once
    /// pushed outside via `positionedOutsideButton()`. Design-literal constant — both call
    /// sites resolve to the SAME value: `sdk-components.jsx` `LBPTooltip` `right: 49` on
    /// `LBPSideRail`'s 40pt-wide button (49 − 40 = 9), and `live-chrome.jsx`'s CC button
    /// `bottom: 45` on `LBLiveBottomBar`'s 36pt-tall button (45 − 36 = 9).
    static let outsideGap: CGFloat = 9

    /// Pushes this tooltip fully OUTSIDE the button it is `.overlay`'d onto (see the MARK
    /// above), `outsideGap` points from its facing edge — `.left` moves it left (vertically
    /// centered, for free, via `Alignment.leading`'s `.center` vertical component); `.top`
    /// moves it up (horizontally centered, for free, via `Alignment.top`'s `.center` horizontal
    /// component). Computes the shift from the tooltip's OWN measured `ViewDimensions`, so it
    /// stays correct regardless of text length / Dynamic Type — no hardcoded pixel width. MUST
    /// be paired with `.overlay(_:alignment: placement.overlayAlignment)` at the call site;
    /// this modifier alone only supplies the alignment-guide override.
    ///
    /// Applies BOTH the `.leading` and `.top` guide overrides UNCONDITIONALLY (gated internally
    /// by `placement == .left` / `placement == .top`), rather than branching with an
    /// `@ViewBuilder switch` over `placement` to pick ONE of the two `.alignmentGuide(...)`
    /// calls. This is deliberate, not stylistic: a `switch`/`if` over `placement` here compiles
    /// to `_ConditionalContent<A, B>` (SwiftUI's type for "one of two possible view types"), and
    /// empirically `_ConditionalContent` does NOT forward a branch's custom `alignmentGuide`
    /// override to an enclosing `.overlay(_:alignment:)`'s placement computation — the overlay
    /// silently fell back to the un-overridden default guide (dead-centered on the button, the
    /// very bug this change fixes) even though each branch's `.alignmentGuide` call was
    /// individually correct. Confirmed via a minimal, isolated repro before landing this fix.
    /// Applying both guides unconditionally on `self` (never branching the MODIFIER CHAIN
    /// itself, only the CGFloat each closure computes) sidesteps `_ConditionalContent` entirely
    /// — a single concrete `ModifiedContent<ModifiedContent<Self, _>, _>` chain every time — and
    /// is harmless for the "other" axis: `.overlay(alignment: .leading)` (used for `.left`) only
    /// ever queries the vertical `.center` guide, never `.top`, and vice versa for `.top`'s
    /// `.center` horizontal guide, so the inactive branch's `d[.leading]` / `d[.top]` passthrough
    /// (the same value the guide would have defaulted to unmodified) is simply never consulted.
    func positionedOutsideButton() -> some View {
        self
            .alignmentGuide(.leading) { d in
                placement == .left ? d[.trailing] + Self.outsideGap : d[HorizontalAlignment.leading]
            }
            .alignmentGuide(.top) { d in
                placement == .top ? d[.bottom] + Self.outsideGap : d[VerticalAlignment.top]
            }
    }
}

extension SubtitleUnavailableTooltip.Placement {
    /// The `.overlay(_:alignment:)` anchor matching this placement — pairs with
    /// `positionedOutsideButton()` at the call site (see the MARK above). `.left` → `.leading`,
    /// `.top` → `.top`; each `Alignment`'s "other axis" component is `.center`, which is
    /// exactly the centering the design specifies (`top: 50%` / `left: 50%` + a `translate` in
    /// the CSS). Pure — safe to unit test directly (`Alignment` is `Equatable`).
    var overlayAlignment: Alignment {
        switch self {
        case .left: return .leading
        case .top: return .top
        }
    }
}

// MARK: - Viewport clamp (`rb-ios-cc-tooltip-viewport-clamp`)
//
// BUG this section fixes (confirmed by reading `LiveBottomBarView.ccToggleButton` — the CC
// button sits near the bar's TRAILING edge by construction, the row packs bag → comment-area →
// leading-slot → CC → like left-to-right — and by reading the Android/Flutter/RN siblings'
// already-shipped fixes for the identical overflow, 2026-09-10): `positionedOutsideButton()`
// above centers the `.top`-placement bubble horizontally on its anchor "for free" via
// `Alignment.top`'s `.center` horizontal component, with NO awareness of how close that anchor
// sits to the viewport's edge. A ~180pt-wide bubble centered on a 36pt anchor near the screen's
// right edge overflows past it — the user-reported "回放會超出螢幕、指向靠右顯示" symptom.
// `.left` placement (`OperationRailView`'s VOD side-rail CC pill) is UNAFFECTED and NOT touched
// by this section — it pushes the bubble INWARD (toward screen center, away from the
// right-docked rail) and has no observed overflow, exactly like Android's `TooltipPlacement.Left`
// / Flutter's `left` placement / RN's `placement="left"` siblings, none of which this change's
// counterparts touch either.
//
// This mirrors the fix Android (`CcAvailability.kt`'s `clampTooltipTopX`), Flutter
// (`cc_tooltip_layout.dart`'s `clampCcTooltipCenterX`), and RN (`CcTooltip.tsx`'s
// `ccTooltipHorizontalClampDelta`) already landed for their own `Top`/`top` branches — this is
// the iOS parity fix, LAYERED ON TOP of `rb-ios-cc-tooltip-position-fix`'s outside-positioning
// (this section does NOT replace `positionedOutsideButton()` — the call site chains BOTH:
// `.positionedOutsideButton().offset(x: clampedTopOffsetX(...))`).
//
// `clampedTopOffsetX` itself takes plain `CGFloat`s — no UIKit/SwiftUI dependency — so it is
// directly unit-testable (mirrors the Android/Flutter/RN pure-function siblings). The CALL SITE
// (`LiveBottomBarView.ccToggleButton`) measures `anchorCenterX` / `bubbleWidth` / `viewportWidth`
// via `GeometryReader` + `PreferenceKey` (the same idiom `LoopingVideoView`/`CarouselCardView`
// already ship in this package) and supplies them here.

extension SubtitleUnavailableTooltip {
    /// Minimum breathing room (points) kept between the `.top`-placement bubble's left/right
    /// edges and the viewport when `clampedTopOffsetX` has to clamp — a DIFFERENT concept from
    /// `outsideGap` (the fixed gap between the bubble and its own anchor BUTTON, along the
    /// placement axis; unaffected by this constant). `8pt` matches the Android (`8.dp`) / Flutter
    /// (`edgeMargin: 8`, default) / RN (`MIN_EDGE_MARGIN = 8`) siblings — an engineering safety
    /// margin, not a value lifted from `design/`.
    static let viewportEdgeMargin: CGFloat = 8

    /// PURE FUNCTION: the extra horizontal `.offset(x:)` delta (points) to layer on top of the
    /// already-centered `.top`-placement position (`positionedOutsideButton()`), so the bubble's
    /// left/right edges stay within `[minMargin, viewportWidth - minMargin]` of the viewport.
    /// Mirrors Android's `clampTooltipTopX` / Flutter's `clampCcTooltipCenterX` / RN's
    /// `ccTooltipHorizontalClampDelta` (`rb-ios-cc-tooltip-viewport-clamp`).
    ///
    /// `anchorCenterX` / `bubbleWidth` / `viewportWidth` MUST all be in the SAME coordinate
    /// space. The call site uses a NAMED `GeometryReader` coordinate space anchored to
    /// `LiveBottomBarView`'s own root (`ccTooltipViewportSpace`) — deliberately NOT
    /// `UIScreen.main.bounds` / `.global` window coordinates, which are unavailable inside the
    /// isolated `ImageRenderer`-based snapshot harness (`ReferenceUISnapshotHelper.render` never
    /// attaches the rendered view to a real `UIWindow`) and would make this clamp's behavior
    /// depend on WHICH simulator model runs the test — this package's snapshot baselines are
    /// deliberately simulator-independent (fixed frame sizes only). Using the bar's own measured
    /// width instead keeps the clamp deterministic at any canvas size; in production the bar
    /// spans the full device width (`.frame(maxWidth: .infinity)` inside a full-screen player),
    /// so this is not a behavior compromise, only an implementation choice.
    ///
    /// `bubbleWidth <= 0` OR `viewportWidth <= 0` means "not yet measured" — the very first
    /// render (before either `GeometryReader` has ever reported real geometry), OR the isolated
    /// `ccToggleButtonForTesting(tooltipVisible:)` test accessor (which renders `ccToggleButton`'s
    /// subtree alone, never `body`'s viewport-width probe) — this MUST return `0` (no additional
    /// shift; the prior always-centered `positionedOutsideButton()` position stands unclamped)
    /// rather than clamp against bogus zero geometry. A later re-render (once real geometry is
    /// known) applies the real clamp; the tooltip only ever appears after a tap, so this brief
    /// unclamped-then-corrected window is not user-visible as a flash (same reasoning Android's
    /// own two-pass `onGloballyPositioned` correction documents).
    ///
    /// A `viewportWidth` narrower than `2 * minMargin + bubbleWidth` would otherwise invert the
    /// valid `[minLeft, maxLeft]` range; taking `min`/`max` of the two candidate bounds (mirrors
    /// Android's `coerceIn(minOf(...), maxOf(...))`) degrades to the narrower edge instead of
    /// producing a nonsensical delta.
    static func clampedTopOffsetX(
        anchorCenterX: CGFloat,
        bubbleWidth: CGFloat,
        viewportWidth: CGFloat,
        minMargin: CGFloat = SubtitleUnavailableTooltip.viewportEdgeMargin
    ) -> CGFloat {
        guard bubbleWidth > 0, viewportWidth > 0 else { return 0 }
        let idealLeft = anchorCenterX - bubbleWidth / 2
        let minLeft = minMargin
        let maxLeft = viewportWidth - minMargin - bubbleWidth
        let lo = min(minLeft, maxLeft)
        let hi = max(minLeft, maxLeft)
        let clampedLeft = min(max(idealLeft, lo), hi)
        return clampedLeft - idealLeft
    }
}

// MARK: - Arrow anchor fix (`rb-ios-cc-tooltip-arrow-anchor-fix`)
//
// BUG this fixes (confirmed by reading `bubble`'s `.top` branch — `VStack(spacing: 0) {
// bubbleLabel; arrow }` — and `LiveBottomBarView.ccToggleButton`'s call site, 2026-09-10):
// `clampedTopOffsetX` above returns a delta that the call site applies via `.offset(x:)` to the
// ENTIRE tooltip view (bubble + arrow together, since both live inside the SAME `VStack`). The
// arrow's horizontal position inside that `VStack` is purely relative to the bubble's own center
// (SwiftUI centers a `VStack`'s children on the cross axis by default) — it has no awareness of
// the button's true anchor position. Once the clamp engages (`clampOffsetX != 0`), bubble and
// arrow move together as one rigid group and the arrow tip drifts away from the real CC button by
// exactly `clampOffsetX` points — the "箭頭指錯方向" symptom. This mirrors the bug Flutter's sibling
// change (`rb-flutter-cc-tooltip-arrow-anchor-fix`, archived 2026-09-10) already fixed for its own
// platform, via the identical `arrowCompensationOffset` pattern ported here.

extension SubtitleUnavailableTooltip {
    /// PURE FUNCTION: the extra horizontal `.offset(x:)` delta (points) to apply to the arrow
    /// ALONE — on top of the bubble's own `clampedTopOffsetX` shift — so the arrow's absolute
    /// screen X stays pinned to the button's true (unclamped) anchor center, regardless of how
    /// far the bubble body was nudged for the viewport clamp.
    ///
    /// The call site applies BOTH offsets: `.offset(x: bubbleShift)` on the whole tooltip view
    /// (existing, unchanged — see `clampedTopOffsetX`'s doc comment) and, additionally,
    /// `.offset(x: arrowCompensationOffsetX(bubbleShift:))` on the `arrow` node alone, RELATIVE
    /// to that already-shifted group. The two cancel out in screen space: `+bubbleShift` (outer,
    /// moves bubble+arrow together) plus `-bubbleShift` (inner, moves the arrow back), net `0`
    /// relative to the arrow's pre-clamp position — i.e. the arrow tip stays exactly where it
    /// always was (`positionedOutsideButton()`'s un-clamped, centered placement). The bubble
    /// label only ever receives the outer `+bubbleShift`, so its existing (correct) clamp
    /// behavior is completely unaffected by this function.
    ///
    /// `bubbleShift == 0` (the common case — clamp did not engage, including every existing
    /// fixed-frame snapshot baseline) MUST return `0`, keeping rendering byte-identical to before
    /// this fix. Deliberately a trivial negation (not a re-derivation of the anchor from
    /// scratch) — the call site already knows exactly what shift it applied to the bubble; the
    /// compensation is by construction its exact inverse, and both values originate from the
    /// SAME `clampedTopOffsetX(...)` result computed once per render, so there is no risk of the
    /// two diverging.
    static func arrowCompensationOffsetX(bubbleShift: CGFloat) -> CGFloat {
        -bubbleShift
    }
}

// MARK: - Design tokens (lifted from `sdk-components.jsx` `LBPTooltip`)

private extension SubtitleUnavailableTooltip {
    /// `rgba(0,0,0,0.9)`.
    static let bubbleColor = Color.black.opacity(0.9)
    static let cornerRadius: CGFloat = 5
    static let hPadding: CGFloat = 9
    static let vPadding: CGFloat = 5
    static let fontSize: CGFloat = 12.5
}

private extension SubtitleUnavailableTooltip.Placement {
    /// Arrow box size — 10pt across the bubble edge, 5pt deep, oriented per placement.
    var arrowSize: CGSize {
        switch self {
        case .top: return CGSize(width: 10, height: 5)
        case .left: return CGSize(width: 5, height: 10)
        }
    }
}

// MARK: - Arrow shape

/// A small filled triangle pointing INTO the button the bubble explains: down for `.top`
/// (bubble above the button), right for `.left` (bubble to the left of the button).
private struct TooltipArrowShape: Shape {
    let placement: SubtitleUnavailableTooltip.Placement

    func path(in rect: CGRect) -> Path {
        Path { p in
            switch placement {
            case .top:
                // Flat edge along the top (touching the bubble), apex pointing down.
                p.move(to: CGPoint(x: rect.minX, y: rect.minY))
                p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
                p.closeSubpath()
            case .left:
                // Flat edge along the left (touching the bubble), apex pointing right.
                p.move(to: CGPoint(x: rect.minX, y: rect.minY))
                p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
                p.closeSubpath()
            }
        }
    }
}

// MARK: - Preview (deterministic demo)

#if DEBUG
struct SubtitleUnavailableTooltip_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black
            VStack(spacing: 40) {
                SubtitleUnavailableTooltip(show: true, placement: .top)
                SubtitleUnavailableTooltip(show: true, placement: .left)
            }
        }
        .frame(width: 240, height: 160)
        .previewLayout(.sizeThatFits)
    }
}
#endif
