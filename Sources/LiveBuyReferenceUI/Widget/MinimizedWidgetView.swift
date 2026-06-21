import SwiftUI
import LiveBuySDK
import LiveBuyUI

// MARK: - MinimizedWidgetView — family-5 widget surface 4 (LBPMinimizedWidget)
//
// Spec: `reference-ui-rendering/spec.md` (family-5 widget surfaces:
//        carousel / video-shop grid / floating / minimized).
// Design: rb-ios-widget design.md §"渲染計畫" +
//          `design/templates/minimal/sdk-components.jsx` `LBPMinimizedWidget`
//          (lines 459-546).
//
// The MINIMIZED widget surface: a small ~96pt-wide 9:16 floating pill the SDK
// collapses to (the design's PiP-style corner widget). It maps to
// `LBWidgetContentMode.minimized` (the template-derived floating `isClosed == true`
// state) and is the fourth of the four family-5 widget sub-views the container
// (`WidgetOverlayView`) switches on. It implements the FROZEN initializer
// documented verbatim in `WidgetOverlayView.swift`'s SUB-VIEW INPUT PATTERN:
//
//     MinimizedWidgetView(
//         theme: ReferenceUITheme,
//         isLive: Bool = false,
//         onExpand: (() -> Void)? = nil,
//         onClose: (() -> Void)? = nil)
//
// SELF-CONTAINED (no WidgetModel): unlike the carousel / grid surfaces, the
// minimized pill takes NO `WidgetModel` — it is a tiny chrome affordance with only
// a single derived bound field, `isLive` (the container/host derives it from
// `model.liveVideo?.liveStatus == 1`, i.e. mode == `.minimized` with a live card
// behind it). So this view binds ONLY `isLive`; it reads no other view-model state
// and holds NO copy of model state (one-way data flow preserved).
//
// STRUCTURE (mirrors `LBPMinimizedWidget`, sdk-components.jsx 503-544):
//   • a 96pt-wide 9:16 rounded (12) pill with a soft drop shadow + a 1px white
//     hairline (`0 0 0 1px rgba(255,255,255,0.08)`),
//   • a deterministic dark cover placeholder (the design's `<VideoBG>` — NO
//     AsyncImage / network fetch; a gradient + monogram chip, mirroring
//     `CarouselCardView.coverPlaceholder` / `ProductDetailSheetView.productPhoto`),
//   • a top-left LIVE red tag (`#F03246`, static pulse dot) ONLY when `isLive`,
//   • a top-right round close affordance (`rgba(0,0,0,0.55)` + close glyph),
//   • a bottom centered drag-handle hint (24×3 pill, `rgba(255,255,255,0.4)`).
//
// HOST-WIRED EXITS (design §"守住的不變式": 互動一律 host-wired exit 轉發):
//   • BODY tap   → `onExpand` → host → core re-open the floating widget (the design
//                  restores the player to full screen on a no-drag tap, line 499).
//   • CLOSE tap  → `onClose`  → host → core floating-close.
//   The design's grip-DRAG-to-reposition (pointer math, lines 460-501) is a host /
//   PiP-window concern, NOT pixel rendering — this layer renders the pill at a fixed
//   position and forwards only tap / close (NO drag re-positioning, NO core
//   simulate* / template intents). Renders correctly with both actions nil (so demo
//   / snapshot tests construct it action-free).
//
// `widget_color` / `widget_bgcolor` are NOT consulted here — the theme comes ONLY
// from `ReferenceUITheme` (those two are a SEPARATE raw-passthrough track).
//
// iOS-14-safe SwiftUI only. `ZStack` / `VStack` / `RoundedRectangle` / `Circle` /
// `LinearGradient` / `Text` / `Button` / `Image(systemName:)` / `.shadow` are all
// iOS-13+. NO `AsyncImage` / `.task` / ScrollView / Lazy* / `.foregroundStyle` /
// `.tint`. (The whole pill is a tiny fixed chrome — no scroll content at all.)

/// The family-5 MINIMIZED widget pill (`LBPMinimizedWidget`): a small ~96pt 9:16
/// floating placeholder pill with an optional LIVE tag, a close affordance, and a
/// drag-handle hint. Body tap → `onExpand`; close → `onClose`. Self-contained (no
/// `WidgetModel`) — it binds only the derived `isLive` flag and never reaches back
/// into the model / template.
public struct MinimizedWidgetView: View {

    /// The resolved reference-ui theme (FIRST positional argument, always). The
    /// minimized pill is white-on-dark chrome (fixed design colors for the cover /
    /// LIVE tag / close), so `theme` is consulted only for `fontScale` consistency —
    /// it is NOT used to interpret `widget_color` / `widget_bgcolor`.
    public let theme: ReferenceUITheme

    /// Whether a LIVE card sits behind the minimized pill — the SINGLE bound field
    /// (the container/host derives it from `model.liveVideo?.liveStatus == 1`). When
    /// true, the top-left LIVE red tag is drawn (design `isLive` prop, line 519).
    public let isLive: Bool

    /// BODY tap → host-wired `onExpand` → host → core re-open the floating widget
    /// (the design restores full screen on a no-drag tap). nil for demo / snapshot
    /// instances — the pill is inert. This layer NEVER re-opens / calls core itself.
    private let onExpand: (() -> Void)?

    /// CLOSE tap → host-wired `onClose` → host → core floating-close. nil for demo /
    /// snapshot instances. This layer NEVER closes / calls core itself.
    private let onClose: (() -> Void)?

    public init(
        theme: ReferenceUITheme,
        isLive: Bool = false,
        onExpand: (() -> Void)? = nil,
        onClose: (() -> Void)? = nil
    ) {
        self.theme = theme
        self.isLive = isLive
        self.onExpand = onExpand
        self.onClose = onClose
    }

    public var body: some View {
        // BODY tap restores the player (no-drag tap → onExpand, design line 499).
        Button(action: { onExpand?() }) {
            pill
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier(LBAccessibilityID.minimizedExpand)
    }

    // MARK: - The 96pt 9:16 pill (cover + LIVE tag + close + drag handle)
    //
    // Mirrors `LBPMinimizedWidget`'s outer pill (sdk-components.jsx 503-544): a
    // fixed 96-wide 9:16 rounded media area, the LIVE tag top-left (when isLive),
    // the close button top-right, and the drag-handle hint centered at the bottom.

    private var pill: some View {
        ZStack {
            // Deterministic dark cover placeholder (`<VideoBG>`) — gradient + monogram
            // chip, NO network / AsyncImage (consistent with CarouselCardView).
            coverPlaceholder

            // LIVE red tag top-left (only when a live card is behind the pill).
            if isLive {
                VStack {
                    HStack {
                        liveTag
                        Spacer(minLength: 0)
                    }
                    Spacer(minLength: 0)
                }
                .padding(6)
            }

            // Close affordance top-right → onClose.
            VStack {
                HStack {
                    Spacer(minLength: 0)
                    closeButton
                }
                Spacer(minLength: 0)
            }
            .padding(4)

            // Centered drag-handle hint at the bottom (pure decoration — the real
            // grip-drag is a host / PiP-window concern, not rendered here).
            VStack {
                Spacer(minLength: 0)
                dragHandle
                    .padding(.bottom, 4)
            }
        }
        .frame(width: Self.pillWidth, height: Self.pillWidth * 16.0 / 9.0)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            // 1px white hairline (`0 0 0 1px rgba(255,255,255,0.08)`, line 514).
            RoundedRectangle(cornerRadius: 12)
                .stroke(Self.hairline, lineWidth: 1))
        .shadow(color: Self.shadow, radius: 12, x: 0, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(LBAccessibilityID.minimizedWidget)
    }

    /// 9:16 deterministic dark cover placeholder (the design's `<VideoBG>`) — a
    /// gradient + a play-glyph monogram (no remote image). Mirrors
    /// `CarouselCardView.coverPlaceholder`.
    private var coverPlaceholder: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(hex: "#3A3A44") ?? .gray,
                    Color(hex: "#111118") ?? .black,
                ]),
                startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "play.fill")
                .font(.system(size: 18 * theme.fontScale, weight: .heavy))
                .foregroundColor(.white.opacity(0.85))
        }
    }

    // MARK: - LIVE tag (top-left, isLive only)

    /// LIVE red tag (`LBPMinimizedWidget` 519-529): a static pulse dot + 「LIVE」on
    /// the brand-red surface (`#F03246`). The pulse animation is drawn statically
    /// (snapshot-safe). Reuses the same `#F03246` red as `CarouselCardView.liveRed`.
    private var liveTag: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(Color.white)
                .frame(width: 3, height: 3)
            Text(Self.liveLabel)
                .font(.system(size: 9 * theme.fontScale, weight: .heavy))
                .foregroundColor(.white)
                .kerning(0.5)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(CarouselCardView.liveRed))
    }

    // MARK: - Close affordance (top-right → onClose)

    /// Top-right round close button (`LBPMinimizedWidget` 530-538): a 20×20
    /// translucent-dark circle (`rgba(0,0,0,0.55)`) + a close (×) glyph. Tap →
    /// host-wired `onClose`. Stops the body tap from also firing by being its own
    /// `Button` (SwiftUI routes the inner button hit first).
    private var closeButton: some View {
        Button(action: { onClose?() }) {
            ZStack {
                Circle().fill(Color.black.opacity(0.55))
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
            }
            .frame(width: 20, height: 20)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier(LBAccessibilityID.minimizedClose)
    }

    // MARK: - Drag-handle hint (bottom center, decorative)

    /// The bottom-centered drag-handle hint (`LBPMinimizedWidget` 540-543): a 24×3
    /// rounded pill (`rgba(255,255,255,0.4)`). Pure decoration — the real grip-drag
    /// reposition is host / PiP-window logic, NOT rendered at this layer.
    private var dragHandle: some View {
        RoundedRectangle(cornerRadius: 99)
            .fill(Color.white.opacity(0.4))
            .frame(width: 24, height: 3)
    }

    // MARK: - Decorative design tokens (literal sdk-components.jsx values)

    /// Pill width (pt) — the design's fixed `width: 96` (line 512).
    static let pillWidth: CGFloat = 96
    /// 1px white hairline (`0 0 0 1px rgba(255,255,255,0.08)`, line 514).
    static let hairline = Color.white.opacity(0.08)
    /// Soft drop shadow (`0 8px 24px rgba(0,0,0,0.35)`, line 514).
    static let shadow = Color.black.opacity(0.35)

    // MARK: - Fixed presentation strings

    static let liveLabel = "LIVE"
}

#if DEBUG
struct MinimizedWidgetView_Previews: PreviewProvider {
    static var previews: some View {
        let theme = ReferenceUIThemePalette.minimal
        HStack(alignment: .top, spacing: 24) {
            // LIVE variant — top-left red LIVE tag.
            MinimizedWidgetView(theme: theme, isLive: true)
                .previewDisplayName("minimized · live")
            // VOD variant — no LIVE tag.
            MinimizedWidgetView(theme: theme, isLive: false)
                .previewDisplayName("minimized · vod")
        }
        .padding(40)
        .frame(width: 320, height: 280)
        .background(Color(white: 0.92))
        .previewLayout(.sizeThatFits)
    }
}
#endif
