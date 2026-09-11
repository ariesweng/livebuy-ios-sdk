import SwiftUI
import LivebuySDK
import LivebuyUI

// MARK: - OperationRailView — family-1 player-shell surface 2 (side rail)
//
// Spec: `reference-ui-rendering/spec.md` (family-1 player-shell, surface 2)
// Design: rb-ios-player-shell design.md D-2 #2.
//   Design source: `design/templates/minimal/sdk-components.jsx`
//     · `LBPSideRail`   (right-side vertical pill stack)
//     · `LBPBagButton`  (floating bag affordance + cart badge)
//     · `LBPHeartBurst` (floating hearts, played off a like)
//
// The trailing side-rail. It binds the `DefaultOperationRail` SNAPSHOT VALUES
// republished by `PlayerShellModel` (`items: [LBSideRailItem]` + `bagCount` +
// `heartBurstTick` + `muted`) and paints:
//
//   • a FIXED design-ordered pill stack (top→bottom: CC subtitle → share →
//     contact-merchant). `.share`/`.serviceLink` are each gated by their kind's
//     `enabled` flag (a disabled or absent kind is omitted — no dimmed slot).
//     `.subtitle` (CC) is the ONE exception (`rb-ios-cc-icon-availability-
//     redesign`): it ALWAYS renders, using `enabled` (`subtitleAvailable`) only to
//     pick which of its 3 icon states (`CcIconState`) to draw — see
//     `showsRailPill(kind:items:)`. The view-model `items` ORDER does NOT drive
//     the visual order (it is a bottom-bar action set); see `presentationOrder`.
//     `goods` / `chat` / `like` / `guestNameEdit` / `more` are NOT rail kinds (the
//     bag is the separate `FloatingBagButtonView`; info is the host-badge tap;
//     like / nickname / chat are LIVE bottom-bar / not-in-VOD),
//   • a heart burst that replays every time `heartBurstTick` INCREASES.
//
// `bagCount` / `muted` are carried for the documented init shape but are no longer
// rendered by the rail (the bag moved to `FloatingBagButtonView`, composed by the
// shell at a lower anchor).
//
// One-way data flow (D-1/D-4): this view reads ONLY its passed-in values; it
// never reaches back into `PlayerShellModel` / `DefaultPlayerTemplate`, and it
// does NOT call any core `simulate*`. Taps surface a single `onTapItem` intent
// (each kind), which the shell / host wires to the matching core exit.
//
// iOS-14-safe SwiftUI only (D-7): `ZStack` / `VStack` / `ForEach` / `Circle` /
// `withAnimation` are all iOS-13+. The like glyph fill animation uses the
// iOS-13+ `Image(systemName:)` + `.opacity` / `.offset` / `.scaleEffect`
// modifiers (no `.task` / `AsyncImage` / `.foregroundStyle` / `.tint`).

/// The family-1 trailing side-rail surface. Renders only the enabled
/// `LBSideRailItem`s as themed round pills (goods as the larger bag button with
/// a cart badge), and replays a heart burst each time `heartBurstTick` increases.
public struct OperationRailView: View {

    // MARK: - Inputs (sub-view input pattern: theme, snapshot values, action)

    /// The resolved reference-ui theme (FIRST positional argument, always).
    public let theme: ReferenceUITheme

    /// Ordered side-rail action items. Only `enabled` items are drawn.
    public let items: [LBSideRailItem]

    /// Shopping-bag badge count. `> 0` → draw the badge on the goods button.
    public let bagCount: Int

    /// Monotonic heart-burst tick. Observe its INCREASE to replay the burst.
    public let heartBurstTick: Int

    /// Mute gesture state (shared with the header). Currently informational for
    /// the rail; carried so the surface matches the documented initializer shape.
    public let muted: Bool

    /// Whether the subtitle (CC) track is currently enabled (`PlayerShellModel.subtitleEnabled`,
    /// `DefaultPlaybackProgressState`-derived — NOT a `DefaultOperationRail` field, shared the
    /// same way `muted` is shared with the header). Drives the `.subtitle` pill's `active` fill
    /// state (`isActivePill`, rb-ios-cc-icon-active-fill-state) — white background + accent glyph
    /// when `true`, matching the design's `railBtn(icon, ccOn, onCC)`.
    public let subtitleEnabled: Bool

    /// Tap intent for a side-rail kind. The rail does NOT own the action — the
    /// shell / host forwards to the matching core `simulate*` (D-4). Default nil
    /// so demo / snapshot instances construct action-free.
    public let onTapItem: ((LBSideRailKind) -> Void)?

    /// Local, presentation-only UI state: whether the CC pill's `.unavailable`-state transient
    /// tooltip (`SubtitleUnavailableTooltip`) is currently shown (`rb-ios-cc-icon-availability-
    /// redesign`). NOT part of the public init shape — mirrors `PlayerShellView.liveLiked`'s
    /// identically-shaped local timed UI state (set `true` on tap, reset `false` after
    /// `CcUnavailableTooltipTiming.autoDismissSeconds` via `showSubtitleTooltipTransiently()`).
    @State private var subtitleTooltipVisible = false

    public init(
        theme: ReferenceUITheme,
        items: [LBSideRailItem],
        bagCount: Int,
        heartBurstTick: Int,
        muted: Bool,
        subtitleEnabled: Bool,
        onTapItem: ((LBSideRailKind) -> Void)? = nil
    ) {
        self.theme = theme
        self.items = items
        self.bagCount = bagCount
        self.heartBurstTick = heartBurstTick
        self.muted = muted
        self.subtitleEnabled = subtitleEnabled
        self.onTapItem = onTapItem
    }

    // MARK: - Body

    /// Design-fixed presentation order for the VOD side rail (`LBPSideRail`,
    /// top→bottom): CC subtitle → share → contact merchant. The view-model `items`
    /// order is a bottom-bar action set (`DefaultPlayerChrome` doc) and NO LONGER
    /// drives the visual order. `.share`/`.serviceLink` are drawn only when their item
    /// exists and is `enabled` (design draws no dimmed slot — a disabled kind is simply
    /// omitted); `.subtitle` ALWAYS draws (`showsRailPill`, `rb-ios-cc-icon-availability-
    /// redesign`) — see `isEnabled(_:)`. The shopping bag is no longer a rail item — it
    /// is the separate floating `FloatingBagButtonView` (design `LBPBagButton`, anchored
    /// lower by the shell).
    static let presentationOrder: [LBSideRailKind] = [.subtitle, .share, .serviceLink]

    public var body: some View {
        // `LBPSideRail` is a bottom-anchored vertical stack on the trailing edge;
        // the heart burst (`LBPHeartBurst`) floats over the rail's lower region. The burst
        // is the shared `HeartBurstView` driven by the core `heartBurstTick`
        // (rb-ios-live-bottom-heart-burst — same component the LIVE bottom bar now uses).
        ZStack(alignment: .bottomTrailing) {
            HeartBurstView(tick: heartBurstTick, color: theme.accent, glyphSize: Self.heartGlyphSize)
                .padding(.trailing, Self.heartTrailingInset)
                .padding(.bottom, Self.heartBottomInset)

            VStack(spacing: Self.railGap) {
                // Fixed design order, each gated by its kind's `enabled` flag.
                ForEach(Self.presentationOrder.indices, id: \.self) { idx in
                    let kind = Self.presentationOrder[idx]
                    if isEnabled(kind) {
                        pillButton(for: kind)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(LBAccessibilityID.operationRail)
    }

    // MARK: - Rail items

    /// PURE FUNCTION: whether `kind` should render at all (`rb-ios-cc-icon-availability-
    /// redesign`). `.subtitle` (CC) ALWAYS renders now — it no longer disappears when
    /// unavailable; its `enabled` flag (`subtitleAvailable`) only selects which of the 3 icon
    /// states `subtitleGlyph(for:)` draws (`.on` / `.off` / `.unavailable`), via `CcIconState`.
    /// `.share` / `.serviceLink` keep the ORIGINAL "enabled == false → omit, no dimmed slot"
    /// rule unchanged. Extracted as a static pure function (docs/unit-test-discipline 純函式
    /// 抽出) so the "always renders" behavior is directly unit-testable — `body`'s `ForEach`
    /// wraps this decision in a way `Mirror`-based structural tests cannot see into (see
    /// `pillButtonForTesting`'s doc comment).
    static func showsRailPill(kind: LBSideRailKind, items: [LBSideRailItem]) -> Bool {
        if kind == .subtitle { return true }
        return items.first(where: { $0.kind == kind })?.enabled == true
    }

    /// Whether `kind` should render (`.share`/`.serviceLink` enabled-gate; `.subtitle` always —
    /// see `showsRailPill`).
    private func isEnabled(_ kind: LBSideRailKind) -> Bool {
        Self.showsRailPill(kind: kind, items: items)
    }

    /// PURE FUNCTION: whether `items` carries an available `.subtitle` source
    /// (`subtitleAvailable`). Missing `.subtitle` entry defaults to `false` — a defensive
    /// default, not a production path (`DefaultOperationRail` always includes a `.subtitle`
    /// entry; only its `enabled` value varies).
    static func subtitleAvailable(items: [LBSideRailItem]) -> Bool {
        items.first(where: { $0.kind == .subtitle })?.enabled == true
    }

    /// PURE FUNCTION: resolves the CC pill's 3-state icon from `items`' `.subtitle` entry
    /// (`subtitleAvailable`) + the caller-supplied `subtitleEnabled` (`rb-ios-cc-icon-
    /// availability-redesign`).
    static func ccState(items: [LBSideRailItem], subtitleEnabled: Bool) -> CcIconState {
        CcIconState.resolve(subtitleAvailable: Self.subtitleAvailable(items: items), subtitleEnabled: subtitleEnabled)
    }

    /// A standard round pill (`LBPSideRail` `railBtn`): 40×40, fully-rounded. `.subtitle` is
    /// special-cased into `subtitlePillButton` (3-state icon + tap-routing + tooltip overlay,
    /// `rb-ios-cc-icon-availability-redesign`); every other kind (only `.share`/`.serviceLink`
    /// are actually drawn by the aligned VOD rail — see `presentationOrder`) keeps the ORIGINAL,
    /// unaffected inactive-only styling via `standardPillButton`. `@ViewBuilder` so the two
    /// branches compose directly into the value tree (no `AnyView` type-erasure box — an opaque
    /// erasure boundary would hide `subtitlePillButton`'s glyph/tooltip nodes from the existing
    /// `Mirror`-based structural tests, exactly the pitfall `LiveBottomBarView.trailingAction`'s
    /// own `@ViewBuilder` switch already avoids).
    @ViewBuilder
    private func pillButton(for kind: LBSideRailKind) -> some View {
        if kind == .subtitle {
            subtitlePillButton(tooltipVisible: subtitleTooltipVisible)
        } else {
            standardPillButton(for: kind)
        }
    }

    /// `.share` / `.serviceLink` (and, defensively, every other non-`.subtitle` kind): always
    /// the inactive translucent-dark fill (`isActivePill` is `false` for all of these — see its
    /// doc comment), white glyph. Byte-identical to this file's pre-`rb-ios-cc-icon-availability-
    /// redesign` behavior for these kinds.
    private func standardPillButton(for kind: LBSideRailKind) -> some View {
        Button(action: { onTapItem?(kind) }) {
            ZStack {
                Circle().fill(Self.pillBackground)
                // Share uses the hand-drawn `ShareGlyph` (design `Icons.share` three-node share);
                // serviceLink uses the hand-drawn `ContactGlyph` (design `Icons.contact` dual
                // speech-bubble + question-mark, rb-ios-icon-parity); every other kind keeps its
                // SF Symbol (rb-ios-share-icon-design-align). The aligned VOD rail only ever
                // draws `.share`/`.serviceLink` here (`.subtitle` is handled by
                // `subtitlePillButton`, not this function — see `presentationOrder`), so the
                // `else` branch below is unreachable in production but kept total for the wider
                // view-model kind set.
                if kind == .share {
                    ShareGlyph(size: Self.pillGlyphSize, color: .white)
                } else if kind == .serviceLink {
                    ContactGlyph(size: Self.pillGlyphSize, color: .white)
                } else {
                    Image(systemName: Self.symbolName(for: kind))
                        .font(.system(size: Self.pillGlyphSize, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .frame(width: Self.pillSize, height: Self.pillSize)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier(Self.accessibilityID(for: kind))
    }

    /// `.subtitle` (CC): 3-state icon (`CcIconState`, `rb-ios-cc-icon-availability-redesign`) —
    /// `.on`/`.off` draw `CcGlyph(state:)`, `.unavailable` draws `CcUnavailableGlyph` (fixed
    /// grey, non-square). Fill state follows `isActivePill` (white bg + accent glyph only for
    /// `.on`). A tap forwards `onTapItem(.subtitle)` for `.on`/`.off`; for `.unavailable` it
    /// swallows the tap and shows `SubtitleUnavailableTooltip` instead
    /// (`handleSubtitleTap(state:)`), auto-dismissing after
    /// `CcUnavailableTooltipTiming.autoDismissSeconds`. ALWAYS rendered (`showsRailPill`) —
    /// unlike the pre-redesign behavior where `enabled == false` omitted this pill entirely.
    ///
    /// Takes `tooltipVisible` as a parameter (rather than reading `subtitleTooltipVisible`
    /// directly) so `subtitlePillButtonForTesting(tooltipVisible:)` below can force the tooltip
    /// visible without simulating a real tap + timer (`rb-ios-cc-tooltip-position-fix`). The
    /// tooltip is attached via `.overlay(_:alignment:)` (NOT a raw `ZStack`) so it does NOT
    /// influence the button's own reported size to the rail's `VStack` — see
    /// `SubtitleUnavailableTooltip.positionedOutsideButton()`'s doc comment.
    private func subtitlePillButton(tooltipVisible: Bool) -> some View {
        let available = Self.subtitleAvailable(items: items)
        let state = Self.ccState(items: items, subtitleEnabled: subtitleEnabled)
        let active = Self.isActivePill(kind: .subtitle, subtitleAvailable: available, subtitleEnabled: subtitleEnabled)
        let placement = SubtitleUnavailableTooltip.Placement.left
        return Button(action: { handleSubtitleTap(state: state) }) {
            ZStack {
                Circle().fill(active ? Color.white : Self.pillBackground)
                subtitleGlyph(for: state)
            }
            .frame(width: Self.pillSize, height: Self.pillSize)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier(Self.accessibilityID(for: .subtitle))
        .overlay(
            SubtitleUnavailableTooltip(show: tooltipVisible, placement: placement)
                .positionedOutsideButton(),
            alignment: placement.overlayAlignment
        )
    }

    /// TEST-ONLY: renders the `.subtitle` pill with the tooltip forced to a given visibility,
    /// bypassing the private `subtitleTooltipVisible` timed state (`rb-ios-cc-tooltip-position-
    /// fix`) — mirrors `pillButtonForTesting(for:)`'s established precedent. Lets
    /// structural/snapshot tests assert the tooltip's actual OUTSIDE-the-button layout position
    /// without needing to simulate a real button tap + `CcUnavailableTooltipTiming` timer.
    func subtitlePillButtonForTesting(tooltipVisible: Bool) -> some View {
        subtitlePillButton(tooltipVisible: tooltipVisible)
    }

    /// The `.subtitle` pill's glyph for a given `CcIconState` — `@ViewBuilder` so the 3-way
    /// switch composes directly (no `AnyView`), matching `subtitlePillButton`'s reasoning.
    @ViewBuilder
    private func subtitleGlyph(for state: CcIconState) -> some View {
        switch state {
        case .on:
            CcGlyph(size: Self.pillGlyphSize, color: theme.accent, state: .on)
        case .off:
            CcGlyph(size: Self.pillGlyphSize, color: .white, state: .off)
        case .unavailable:
            CcUnavailableGlyph(size: Self.pillGlyphSize)
        }
    }

    /// Routes a `.subtitle` pill tap: `.on`/`.off` forward the existing toggle intent
    /// unchanged; `.unavailable` shows the transient tooltip instead
    /// (`rb-ios-cc-icon-availability-redesign`).
    private func handleSubtitleTap(state: CcIconState) {
        if state.forwardsToggleTapIntent {
            onTapItem?(.subtitle)
        } else {
            showSubtitleTooltipTransiently()
        }
    }

    /// Shows `subtitleTooltipVisible` and schedules its own reset — mirrors
    /// `PlayerShellView`'s established `liveLiked` + `DispatchQueue.main.asyncAfter` self-reset
    /// pattern for identically-shaped local timed UI state.
    private func showSubtitleTooltipTransiently() {
        subtitleTooltipVisible = true
        DispatchQueue.main.asyncAfter(deadline: .now() + CcUnavailableTooltipTiming.autoDismissSeconds) {
            subtitleTooltipVisible = false
        }
    }

    /// PURE FUNCTION: which pills wear the design's "active" fill (white background + accent
    /// glyph, `LBPSideRail` `railBtn(icon, active, onClick)`, `design/templates/minimal/
    /// sdk-components.jsx:766-786`). Only `.subtitle` (CC) currently binds `active` to a real
    /// state — `subtitleAvailable && subtitleEnabled` (`rb-ios-cc-icon-availability-redesign`,
    /// MODIFIED: previously just `subtitleEnabled`, not considering availability) — `.share` /
    /// `.serviceLink` are hardwired `active == false` in the design (`railBtn(<Icons.share.../>,
    /// false, onShare)` / `railBtn(<Icons.contact.../>, false, onContact)`) and stay in the
    /// inactive style regardless of any state. No side effects — safe to unit test directly.
    static func isActivePill(kind: LBSideRailKind, subtitleAvailable: Bool, subtitleEnabled: Bool) -> Bool {
        kind == .subtitle && subtitleAvailable && subtitleEnabled
    }

    /// TEST-ONLY: exposes the exact per-kind pill subtree `pillButton(for:)` renders (including
    /// which glyph it draws), so structural tests can confirm e.g. the `.subtitle` pill draws
    /// `CcGlyph` (not an SF Symbol `Image`) without going through `ForEach` — a plain `Mirror`
    /// walk over `body` cannot see into `ForEach`'s per-element closure output, only into value
    /// trees SwiftUI compiles directly (`Group { if ... }` branches, etc.). Mirrors the
    /// established `PlayerHeaderBarView.iconClusterForTesting` precedent.
    func pillButtonForTesting(for kind: LBSideRailKind) -> some View { pillButton(for: kind) }

    /// Maps a rail `kind` to its E2E `accessibilityIdentifier` (registry constant).
    /// Only `.subtitle` / `.share` / `.serviceLink` are drawn by the aligned VOD rail
    /// (`presentationOrder`); the rest map to their matching registry id for
    /// exhaustiveness should they ever be drawn (`.more` has no dedicated rail id →
    /// reuses the rail-container id, but it is never drawn by this rail).
    static func accessibilityID(for kind: LBSideRailKind) -> String {
        switch kind {
        case .subtitle:      return LBAccessibilityID.railSubtitle
        case .share:         return LBAccessibilityID.railShare
        case .serviceLink:   return LBAccessibilityID.railService
        case .goods:         return LBAccessibilityID.railGoods
        case .chat:          return LBAccessibilityID.railComment
        case .like:          return LBAccessibilityID.railLike
        case .guestNameEdit: return LBAccessibilityID.livePersonEdit
        case .more:          return LBAccessibilityID.operationRail
        }
    }

    // MARK: - Kind → SF Symbol mapping
    //
    // The aligned VOD `LBPSideRail` draws only cc / share / contact (chat bubble);
    // the view-model carries the wider reachable kind set (it is a bottom-bar action
    // set), so the mapping stays total. Each kind maps to the SF Symbol that matches
    // its design glyph intent (bag is now the separate `FloatingBagButtonView`).

    static func symbolName(for kind: LBSideRailKind) -> String {
        switch kind {
        case .goods:          return "bag"               // FloatingBagButtonView
        case .chat:           return "bubble.left.fill"  // Icons.chat
        case .like:           return "heart.fill"        // Icons.heartFill
        case .share:          return "square.and.arrow.up" // unused for .share — pillButton draws ShareGlyph (Icons.share)
        case .subtitle:       return "captions.bubble"   // unused for .subtitle — pillButton draws CcGlyph (Icons.cc)
        case .serviceLink:    return "bubble.left.fill"  // unused for .serviceLink — pillButton draws ContactGlyph (Icons.contact)
        case .guestNameEdit:  return "pencil"            // edit display name
        case .more:           return "ellipsis"          // more menu
        }
    }
}

// MARK: - Design tokens (lifted from sdk-components.jsx)

private extension OperationRailView {
    // LBPSideRail
    static let railGap: CGFloat = 10           // flex gap between pills
    static let pillSize: CGFloat = 40          // 40×40 round pill
    static let pillGlyphSize: CGFloat = 18     // Icons size 18
    /// `rgba(20,20,24,0.55)` — the translucent dark pill fill.
    static let pillBackground = Color(.sRGB, red: 20 / 255, green: 20 / 255, blue: 24 / 255, opacity: 0.55)

    // LBPHeartBurst — anchor for the shared `HeartBurstView` (fly-up / jitter tokens live there).
    static let heartGlyphSize: CGFloat = 26    // Icons.heartFill size 26
    static let heartTrailingInset: CGFloat = 6 // design right:28 relative to rail (right:10) → ~18 over rail; trimmed for the rail frame
    static let heartBottomInset: CGFloat = 8   // design bottom:70 floats just above the rail base
}

// MARK: - Preview (deterministic demo)

#if DEBUG
struct OperationRailView_Previews: PreviewProvider {
    static var previews: some View {
        OperationRailView(
            theme: ReferenceUIThemePalette.minimal,
            items: PlayerShellModel.defaultRailItems,
            bagCount: 3,
            heartBurstTick: 0,
            muted: true,
            subtitleEnabled: false)
            .padding()
            .background(Color.black)
            .previewLayout(.sizeThatFits)
    }
}
#endif
