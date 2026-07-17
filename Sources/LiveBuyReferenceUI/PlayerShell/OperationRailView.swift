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
//     contact-merchant), each pill gated by its kind's `enabled` flag (a disabled
//     or absent kind is omitted — no dimmed slot). The view-model `items` ORDER
//     does NOT drive the visual order (it is a bottom-bar action set); see
//     `presentationOrder`. `goods` / `chat` / `like` / `guestNameEdit` / `more`
//     are NOT rail kinds (the bag is the separate `FloatingBagButtonView`; info is
//     the host-badge tap; like / nickname / chat are LIVE bottom-bar / not-in-VOD),
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

    /// Tap intent for a side-rail kind. The rail does NOT own the action — the
    /// shell / host forwards to the matching core `simulate*` (D-4). Default nil
    /// so demo / snapshot instances construct action-free.
    public let onTapItem: ((LBSideRailKind) -> Void)?

    public init(
        theme: ReferenceUITheme,
        items: [LBSideRailItem],
        bagCount: Int,
        heartBurstTick: Int,
        muted: Bool,
        onTapItem: ((LBSideRailKind) -> Void)? = nil
    ) {
        self.theme = theme
        self.items = items
        self.bagCount = bagCount
        self.heartBurstTick = heartBurstTick
        self.muted = muted
        self.onTapItem = onTapItem
    }

    // MARK: - Body

    /// Design-fixed presentation order for the VOD side rail (`LBPSideRail`,
    /// top→bottom): CC subtitle → share → contact merchant. The view-model `items`
    /// order is a bottom-bar action set (`DefaultPlayerChrome` doc) and NO LONGER
    /// drives the visual order; each kind is drawn only when its item exists and is
    /// `enabled` (design draws no dimmed slot — a disabled kind is simply omitted).
    /// The shopping bag is no longer a rail item — it is the separate floating
    /// `FloatingBagButtonView` (design `LBPBagButton`, anchored lower by the shell).
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

    /// Whether `kind` has an enabled item in `items` (design omits disabled kinds).
    private func isEnabled(_ kind: LBSideRailKind) -> Bool {
        items.first(where: { $0.kind == kind })?.enabled == true
    }

    /// A standard round pill (`LBPSideRail` `railBtn`): 40×40, fully-rounded,
    /// translucent dark fill, white glyph. `active` (white fill + accent glyph)
    /// is not currently fed for any kind, so pills render in the inactive style.
    private func pillButton(for kind: LBSideRailKind) -> some View {
        Button(action: { onTapItem?(kind) }) {
            ZStack {
                Circle()
                    .fill(Self.pillBackground)
                // Share uses the hand-drawn `ShareGlyph` (design `Icons.share` three-node share);
                // every other kind keeps its SF Symbol (rb-ios-share-icon-design-align).
                if kind == .share {
                    ShareGlyph(size: Self.pillGlyphSize, color: .white)
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
        case .subtitle:       return "captions.bubble"   // Icons.cc
        case .serviceLink:    return "bubble.left.fill"  // Icons.chat (聯繫商家)
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
            muted: true)
            .padding()
            .background(Color.black)
            .previewLayout(.sizeThatFits)
    }
}
#endif
