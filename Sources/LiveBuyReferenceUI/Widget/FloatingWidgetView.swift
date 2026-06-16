import SwiftUI
import LiveBuySDK
import LiveBuyUI

// MARK: - FloatingWidgetView — family-5 widget surface 3 (LBPFloatingWidget)
//
// Spec: `reference-ui-rendering/spec.md` (family-5 widget surfaces).
// Design: rb-ios-widget design.md §"渲染計畫" +
//          `design/templates/minimal/widgets.jsx` `LBPFloatingWidget` (lines 374-419).
//
// The standalone 懸浮直播預覽視窗 (`LBWidgetContentMode.floating`): a self-contained,
// dismissible floating window that previews a single LIVE stream. Unlike the
// carousel / video-shop surfaces (which embed many videos in a host page), this is
// instantiated standalone by 3rd-party hosts and floats over their own content. It
// REUSES the shared `CarouselCardView` primitive for the 9:16 live thumbnail (so the
// brand language matches the carousel / grid cards), and overlays a top-right round
// close button (floating-only).
//
// SUB-VIEW INPUT PATTERN (frozen — `WidgetOverlayView.swift` calls this verbatim):
//   1. `video: LBVideoItem?`            — the single floating preview video. When nil,
//      render NOTHING (`EmptyView`) — EXACTLY like the design `if (!video) return null`
//      (the container passes `model.liveVideo`, which may be nil before a live stream).
//   2. `theme: ReferenceUITheme`        — the resolved reference-ui theme (passed
//      straight through to the reused `CarouselCardView`).
//   3. `width: CGFloat = 132`           — the floating window width (design default 132).
//   4. action closures (LAST, each `= nil`):
//      • `onTap: ((LBVideoItem) -> Void)?`  — whole-window tap → `onTap(video)`
//        (canonical `videoTap`). Host-wired exit → host → core open player for the
//        live `video.id`. This layer NEVER opens the player itself.
//      • `onClose: (() -> Void)?`           — top-right close button → `onClose`
//        (canonical `close`, floating-only). Host owns re-mount; this layer just
//        forwards the dismiss intent. The close tap MUST NOT also fire `onTap`.
//
// LIVE TREATMENT: the design always treats the floating preview as a LIVE card
// visually (design line 378-379 `kind: video.kind || 'live'`). The core `LBVideoItem`
// is a read-only value carrying only `liveStatus: Int`, and the reused
// `CarouselCardView.isLive` keys on `liveStatus == 1`. We pass `video` STRAIGHT
// THROUGH to the card (we never build a live-forced copy — `LBVideoItem` is immutable
// and we must not mutate the host's model). The card therefore reads LIVE iff
// `video.liveStatus == 1`; in practice the container only routes a genuine live stream
// (`WidgetModel.liveVideo`) into this surface, so it reads LIVE. A non-live `liveVideo`
// would render the VOD duration pill instead — an accepted approximation. The
// kind-mapping is documented in `CarouselCardView.swift`; the floating surface honours
// it (NO separate upcoming/replay handling).
//
// CLOSE-TAP ISOLATION (design line 401 `e.stopPropagation()`): the close button is a
// SEPARATE `Button` overlaid on top of the card. SwiftUI hit-testing routes the tap
// to the front-most interactive view, so a tap on the close button fires ONLY
// `onClose` and never the card's `onTap`. The card tap is wired through
// `CarouselCardView`'s own `onTap` (its whole-card `Button`), so the two exits stay
// cleanly separated without a custom gesture.
//
// One-way data flow: this surface reads ONLY its passed-in `video` + `theme`; it
// never reaches back into `WidgetModel` / `DefaultWidgetTemplate`, holds NO second
// copy of state, and NEVER opens the player / closes itself. It renders correctly
// with `onTap` / `onClose` nil (so demo / snapshot tests construct it action-free).
// It MUST NOT interpret `widgetColor` / `widgetBgcolor` (a separate raw-passthrough
// track — theme comes ONLY from `ReferenceUITheme`).
//
// iOS-14-safe SwiftUI only. `ZStack` / `Button` / `Circle` / `Image(systemName:)` /
// `.shadow` are all iOS-13+. NO `ScrollView` / `Lazy*` (a single card in a `ZStack`),
// NO `AsyncImage` / `.task` (the reused card draws a deterministic placeholder chip),
// NO `.foregroundStyle` / `.tint`.

/// The family-5 standalone floating live-preview window (`LBPFloatingWidget`). When
/// `video == nil` it renders NOTHING (`EmptyView`). When non-nil it draws ONE reused
/// `CarouselCardView` (the live preview) with a top-right round close button overlay.
/// Whole-window tap → `onTap(video)`; close button → `onClose` (the close tap never
/// also fires `onTap`). All exits are host-wired; this layer never opens / closes
/// itself.
public struct FloatingWidgetView: View {

    /// The single floating preview video (`WidgetModel.liveVideo`). nil → render
    /// NOTHING (`EmptyView`), mirroring the design `if (!video) return null`. Read-only.
    public let video: LBVideoItem?

    /// The resolved reference-ui theme — passed straight through to the reused
    /// `CarouselCardView`. (FIRST positional-after-data argument.)
    public let theme: ReferenceUITheme

    /// Floating window width (pt). Defaults to the design's `132`; the reused card's
    /// 9:16 thumbnail height is derived from it.
    public let width: CGFloat

    /// Runtime media gate, passed straight through to the reused `CarouselCardView`.
    /// `false` (default — demo / snapshot) → placeholder chip (golden baselines
    /// unchanged); `true` (host runtime) → the card renders `preview → cover →
    /// placeholder`. See spec `reference-ui-rendering` (family-5).
    public let live: Bool

    /// Whole-window tap → host-wired `onTap(video)` → host → core open player for the
    /// live `video.id` (canonical `videoTap`). nil for demo / snapshot instances —
    /// the window is inert. This layer NEVER opens the player itself.
    private let onTap: ((LBVideoItem) -> Void)?

    /// Top-right close button → host-wired `onClose` (canonical `close`, floating-only).
    /// Host owns re-mount. nil for demo / snapshot instances. The close tap MUST NOT
    /// also fire `onTap` (separate front-most `Button` — SwiftUI hit-testing isolates it).
    private let onClose: (() -> Void)?

    public init(
        video: LBVideoItem?,
        theme: ReferenceUITheme,
        width: CGFloat = 132,
        live: Bool = false,
        onTap: ((LBVideoItem) -> Void)? = nil,
        onClose: (() -> Void)? = nil
    ) {
        self.video = video
        self.theme = theme
        self.width = width
        self.live = live
        self.onTap = onTap
        self.onClose = onClose
    }

    public var body: some View {
        // video == nil → render NOTHING (design `if (!video) return null`).
        if let video = video {
            window(video)
        } else {
            EmptyView()
        }
    }

    // MARK: - Floating window (reused card + top-right close button)
    //
    // Mirrors `LBPFloatingWidget` (widgets.jsx 381-417): a `position: relative` box of
    // the reused `LBPCarouselCard` (whole-window tap → videoTap) with a `drop-shadow`,
    // plus a top-right round close button anchored at `top: -8, right: -8`.

    private func window(_ video: LBVideoItem) -> some View {
        ZStack(alignment: .topTrailing) {
            // Reuse the shared 9:16 card primitive (DO NOT re-draw a card). Its own
            // whole-card `Button` carries the videoTap exit → forward the bound `video`.
            CarouselCardView(
                item: video,
                theme: theme,
                width: width,
                live: live,
                onTap: { onTap?(video) })

            // Top-right round close button (floating-only). A SEPARATE front-most
            // `Button` — a tap here fires ONLY `onClose`, never the card's `onTap`
            // (design `e.stopPropagation()`). Nudged outward (top/right -8) over the
            // card corner, like the design.
            closeButton
                .offset(x: 8, y: -8)
        }
        // drop-shadow(0 8px 24px rgba(0,0,0,0.28)) — the floating window lifts off the
        // host content.
        .shadow(color: Self.windowShadow, radius: 12, x: 0, y: 8)
    }

    /// Top-right round close button (LBPFloatingWidget 398-416): a 24×24 dark-glass
    /// circle with a white ✕ glyph. Forwards `onClose` only.
    private var closeButton: some View {
        Button(action: { onClose?() }) {
            ZStack {
                Circle()
                    .fill(Self.closeGlass)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.18), lineWidth: 0.5))
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
            }
            .frame(width: 24, height: 24)
            .shadow(color: Color.black.opacity(0.35), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Decorative design tokens (literal widgets.jsx values)
    //
    // theme is passed through to the card; these are FIXED decorative colors lifted
    // verbatim from `LBPFloatingWidget` (the close button + window shadow are the
    // same regardless of the host theme — design's standalone floating chrome), kept
    // consistent with the family-2/3/4 surfaces' `Color(hex:)` surface-token approach.

    /// Close-button dark glass surface (`rgba(20,20,24,0.88)`, LBPFloatingWidget 406).
    static let closeGlass = (Color(hex: "#141418") ?? Color.black).opacity(0.88)
    /// Floating window drop-shadow (`rgba(0,0,0,0.28)`, LBPFloatingWidget 386).
    static let windowShadow = Color.black.opacity(0.28)
}

// MARK: - Deterministic demo seed (previews + snapshot test)
//
// A deterministic LIVE floating preview so the preview / the snapshot test render the
// floating window's "happy path" without a live widget. Reuses the SHARED
// `LBVideoItem.demo(...)` / `LBFeaturedGood.demo(...)` fixtures added in
// `CarouselCardView.swift` so the floating card stays visually consistent with the
// other family-5 surfaces.

public extension FloatingWidgetView {

    /// A deterministic LIVE floating preview demo: one `live: true` video with a
    /// product overlay, action-free. The reused `CarouselCardView` renders it with the
    /// red LIVE tag.
    static func demoLive(theme: ReferenceUITheme) -> FloatingWidgetView {
        FloatingWidgetView(
            video: .demo(
                id: "demo-floating-001",
                title: "限時直播・現正開賣",
                live: true,
                goods: .demo()),
            theme: theme)
    }
}

#if DEBUG
struct FloatingWidgetView_Previews: PreviewProvider {
    static var previews: some View {
        let theme = ReferenceUIThemePalette.minimal
        Group {
            // LIVE floating preview — reused card (red LIVE tag) + close button.
            FloatingWidgetView.demoLive(theme: theme)
                .previewDisplayName("floating · live preview")

            // nil video → renders NOTHING (EmptyView).
            FloatingWidgetView(video: nil, theme: theme)
                .previewDisplayName("floating · nil (empty)")
        }
        .padding(40)
        .frame(width: 240, height: 360)
        .previewLayout(.sizeThatFits)
    }
}
#endif
