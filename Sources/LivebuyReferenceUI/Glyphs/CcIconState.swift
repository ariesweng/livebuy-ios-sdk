import Foundation

// MARK: - CcIconState — pure 3-state resolution for the CC (subtitle) pill
//
// Spec: `reference-ui-rendering/spec.md` (`rb-ios-cc-icon-availability-redesign`)
//
// Shared by `OperationRailView` (VOD side-rail `.subtitle` pill) and `LiveBottomBarView` (LIVE
// bottom bar's `chatClosed`-variant TRAILING CC toggle) — both resolve the SAME three-state icon
// from the SAME two existing booleans (`subtitleAvailable` / `subtitleEnabled`), so the mapping
// lives once here rather than being duplicated (and independently unit-tested) at each call
// site. Zero SwiftUI dependency — pure enum + pure functions (unit-test-discipline: 純函式抽出).

/// The three visual/interaction states the CC pill can be in. `.unavailable` is the NEW state
/// (design R42) — previously the pill was simply omitted when captions weren't available; now it
/// always renders, with this state driving a distinct fixed-grey glyph and swallowed taps.
enum CcIconState: Equatable {
    /// Captions available AND currently on — `CcGlyph(state: .on)`, active (white bg + accent
    /// glyph) fill.
    case on
    /// Captions available but currently off — `CcGlyph(state: .off)`, inactive (translucent-dark
    /// bg + white glyph) fill.
    case off
    /// No caption source at all — `CcUnavailableGlyph` (fixed grey, non-square), inactive fill.
    /// A tap in this state does NOT forward the subtitle-toggle intent (see
    /// `forwardsToggleTapIntent`) — it shows a transient tooltip instead.
    case unavailable

    /// Resolve the state from the two existing booleans — `subtitleAvailable` (is there a
    /// caption source at all; `items[].enabled` for `.subtitle` in `OperationRailView` / the new
    /// `LiveBottomBarView.subtitleAvailable` param) and `subtitleEnabled` (are captions currently
    /// turned on; `PlayerShellModel.subtitleEnabled`, already used by both call sites before this
    /// change). `subtitleAvailable == false` always wins regardless of `subtitleEnabled` — the
    /// template layer keeps them consistent (available==false implies enabled==false) but this
    /// resolver stays defensive rather than assuming that invariant holds.
    static func resolve(subtitleAvailable: Bool, subtitleEnabled: Bool) -> CcIconState {
        guard subtitleAvailable else { return .unavailable }
        return subtitleEnabled ? .on : .off
    }

    /// Whether a tap in this state SHOULD forward the subtitle-toggle intent
    /// (`onTapItem(.subtitle)` / `onToggleCC`). `false` only for `.unavailable` — there is
    /// nothing to toggle, so the tap instead shows `SubtitleUnavailableTooltip`.
    var forwardsToggleTapIntent: Bool {
        self != .unavailable
    }

    /// Whether this state wears the pill's "active" fill (white background + `theme.accent`
    /// glyph, `isActivePill` / `railBtn(icon, active, onClick)`). Only `.on` — `.off` and
    /// `.unavailable` both stay in the existing inactive (translucent-dark + white/grey glyph)
    /// style.
    var isActiveFill: Bool {
        self == .on
    }
}

// MARK: - Shared tooltip timing

/// Auto-dismiss timing for `SubtitleUnavailableTooltip`, shared by both call sites so the
/// duration is a single source of truth (and directly unit-testable) rather than a magic number
/// duplicated at each `DispatchQueue.main.asyncAfter` call site — mirrors
/// `PlayerShellView.likeGlowDurationMs`'s "pure duration, tested directly" precedent for
/// identically-shaped local timed UI state.
enum CcUnavailableTooltipTiming {
    /// Design `screens.jsx`'s `showCCUnavailableToast()` — 1.8s.
    static let autoDismissSeconds: TimeInterval = 1.8
}
