import SwiftUI
import LivebuySDK
import LivebuyUI

// MARK: - FloatingWidgetView — family-5 widget surface 3 (LBPFloatingWidget)
//
// Spec: `reference-ui-rendering/spec.md` (family-5 widget surfaces).
// Design: rb-ios-widget design.md §"渲染計畫" +
//          `design/templates/minimal/sdk-components.jsx` `LBPFloatingWidget`
//          (lines 590-710) — the CURRENT canonical definition. A same-named
//          carousel-card component used to live in `widgets.jsx`; it was REMOVED on
//          2026-06-09 (`design/contract/claude-design-sync.md` §2 R5), so nothing here
//          may cite `widgets.jsx` for this component.
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
//      render NOTHING (`EmptyView`). The container passes `model.liveVideo`, which may
//      be nil before a live stream. DESIGN BASIS: `widgets.jsx:426-436` (the R5 guard
//      comment) — "招攬入口只在「有直播」時由 host 掛載（等同舊 `video=null 不渲染` 語意）".
//      NOT the literal `if (!video) return null`: that line belonged to the REMOVED
//      carousel-card variant. The current canonical `LBPFloatingWidget` has NO `video`
//      prop at all; its early-return is `if (!shown) return null` (sdk-components.jsx
//      655), which gates the ENTRANCE DELAY, not the presence of a video.
//      NOTE this does NOT re-open `widgets.jsx` as a design source: those lines carry
//      ZERO visual / geometric properties (they are a component-migration + mount-
//      semantics note). The STYLING source remains ONLY `sdk-components.jsx` 590-710.
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
// LIVE TREATMENT: the design's live-vs-not treatment is a caller-supplied `isLive`
// prop (sdk-components.jsx 591) — the component never derives it. The core
// `LBVideoItem` is a read-only value carrying only `liveStatus: Int`, and the reused
// `CarouselCardView.isLive` keys on `liveStatus == 1`. We pass `video` STRAIGHT
// THROUGH to the card (we never build a live-forced copy — `LBVideoItem` is immutable
// and we must not mutate the host's model). The card therefore reads LIVE iff
// `video.liveStatus == 1`; in practice the container only routes a genuine live stream
// (`WidgetModel.liveVideo`) into this surface, so it reads LIVE. A non-live `liveVideo`
// would render the VOD duration pill instead — an accepted approximation. The
// kind-mapping is documented in `CarouselCardView.swift`; the floating surface honours
// it (NO separate upcoming/replay handling).
//
// TITLE SUPPRESSION (rb-ios-floating-widget-hide-title): the reused `CarouselCardView` is
// constructed with `showTitle: false`, so this surface does NOT draw a title below its
// thumbnail. The design source `sdk-components.jsx` `LBPFloatingWidget` (590-712) has no
// title element at all — the reused card's title (drawn by default for the carousel /
// video-shop grid consumers) was purely an artifact of reusing `CarouselCardView` as this
// surface's body, not something the design ever called for. Suppressing it is therefore a
// design-alignment fix, not a new deviation. The card's intrinsic height shrinks
// accordingly (no fixed-height reservation for the missing title) — this surface never
// relied on a fixed card height to begin with (`productCard` already varies it: `below`
// mode, unused here, grows it by 44pt).
//
// CLOSE-TAP ISOLATION (sdk-components.jsx 695-696 `e.stopPropagation()`): the close
// button is a SEPARATE `Button` overlaid on top of the card. SwiftUI hit-testing
// routes the tap to the front-most interactive view, so a tap on the close fires ONLY
// `onClose` and never the card's `onTap`. The card tap is wired through
// `CarouselCardView`'s own `onTap` (its whole-card `Button`), so the two exits stay
// cleanly separated without a custom gesture.
//
// One-way data flow: this surface reads ONLY its passed-in `video` + `theme`; it
// never reaches back into `WidgetModel` / `DefaultWidgetTemplate`, holds NO second
// copy of state, and NEVER opens the player / closes itself. It renders correctly
// with `onTap` / `onClose` nil (so demo / snapshot tests construct it action-free).
// It MUST NOT interpret `widgetColor` / `widgetBgcolor` — theme comes ONLY from the
// caller-supplied `ReferenceUITheme`. This is a DELIBERATE exclusion, not an
// oversight: the three embedded widget surfaces (`CarouselView` /
// `ScrollableCarouselView` / `VideoShopGridView`) DO interpret those two via
// `ReferenceUIWidgetEmbedTheme.derive` (rb-ios-widget-embed-colors), but this
// floating card is a standalone overlay on the host's own screen — same reasoning
// that already keeps `product_card` out of it.
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
    /// NOTHING (`EmptyView`), per the design's R5 guard note (`widgets.jsx:426-436`).
    /// Read-only.
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

    /// Whether the reused card's LIVE-only viewer-count badge may draw, forwarded
    /// verbatim to `CarouselCardView`'s same-named parameter
    /// (rb-ios-live-entry-hide-viewer-count). **Default `true`** — this surface's
    /// OTHER two consumers, `WidgetOverlayView`'s `.floating` content mode and
    /// `MinimalDesign.floatingPlayerCard` (the collapsible player's minimized
    /// floating card), **MUST NOT** pass this parameter, so their viewer-count
    /// badge keeps its pre-existing `isLive && item.showPvNum == 1` gate as the
    /// sole condition — byte-identical to before this parameter existed. The THIRD
    /// consumer, `LivebuyLiveEntry` (`Container/LivebuyLiveEntry.swift`), passes
    /// `showViewerCount: false` so its「現正直播」entry card never shows a viewer
    /// count. This is the ONLY per-caller difference on this surface: `showTitle`
    /// stays hardcoded `false` for ALL three consumers (see the doc comment on the
    /// `CarouselCardView(...)` call in `window(_:)` below), because `showViewerCount`
    /// is genuinely caller-specific while `showTitle` is not.
    public let showViewerCount: Bool

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
        showViewerCount: Bool = true,
        onTap: ((LBVideoItem) -> Void)? = nil,
        onClose: (() -> Void)? = nil
    ) {
        self.video = video
        self.theme = theme
        self.width = width
        self.live = live
        self.showViewerCount = showViewerCount
        self.onTap = onTap
        self.onClose = onClose
    }

    public var body: some View {
        // video == nil → render NOTHING (design R5 guard note, widgets.jsx 426-436).
        if let video = video {
            window(video)
        } else {
            EmptyView()
        }
    }

    // MARK: - Floating window (reused card + top-right close button)
    //
    // Mirrors `LBPFloatingWidget` (sdk-components.jsx 657-708): a `position: relative`
    // box of the reused `LBPCarouselCard` (whole-window tap → videoTap) with a
    // `drop-shadow`, plus a round close button anchored INSIDE the frame's top-right
    // corner at `top: 4, right: 4` (sdk-components.jsx 698).

    private func window(_ video: LBVideoItem) -> some View {
        ZStack(alignment: .topTrailing) {
            // Reuse the shared 9:16 card primitive (DO NOT re-draw a card). Its own
            // whole-card `Button` carries the videoTap exit → forward the bound `video`.
            //
            // NO `productCard:` here, deliberately: the floating card is fed by
            // `/sdk/widget/live`, whose response does NOT carry `product_card`, and
            // this surface binds a bare `LBVideoItem` rather than a `WidgetModel`.
            // Leaving the parameter at its default keeps the floating card on the
            // `inside` overlay (rb-ios-widget-product-card-modes).
            //
            // NO title here, deliberately (rb-ios-floating-widget-hide-title): the design
            // source `sdk-components.jsx` `LBPFloatingWidget` (590-712) has no title
            // element at all — the reused card's title was purely an artifact of reusing
            // `CarouselCardView` as this surface's body, never something the design asked
            // for. `showTitle: false` removes the element from the view tree (the card's
            // intrinsic height shrinks accordingly — see `CarouselCardView`'s TITLE
            // VISIBILITY doc comment), aligning this surface with the design rather than
            // introducing a new deviation.
            // showViewerCount forwards verbatim (rb-ios-live-entry-hide-viewer-count):
            // this surface's own `showViewerCount` parameter defaults to `true`, so a
            // caller that does not pass it (WidgetOverlayView / MinimalDesign) draws
            // the viewer-count badge exactly as before this parameter existed; only
            // `LivebuyLiveEntry` sets it `false`.
            CarouselCardView(
                item: video,
                theme: theme,
                width: width,
                live: live,
                showTitle: false,
                showViewerCount: showViewerCount,
                onTap: { onTap?(video) })

            // Top-right round close button (floating-only). A SEPARATE front-most
            // `Button` — a tap here fires ONLY `onClose`, never the card's `onTap`
            // (design `e.stopPropagation()`). It sits INSIDE the card frame, 4pt from
            // the top and trailing edges (design `top: 4, right: 4`) — the `.padding(4)`
            // plus the `.topTrailing` alignment IS that inset. It does NOT change the
            // window's measured size: the button lays out at 20 + 4*2 = 28pt, far
            // smaller than the card, so the `ZStack` is still sized by the card alone.
            closeButton
                .padding(4)
        }
        // drop-shadow(0 8px 24px rgba(0,0,0,0.28)) — the floating window lifts off the
        // host content.
        .shadow(color: Self.windowShadow, radius: 12, x: 0, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(LBAccessibilityID.floatingWidget)
    }

    /// Top-right round close button (`sdk-components.jsx` `LBPFloatingWidget`): a
    /// `rgba(0,0,0,0.55)` circle with a white ✕ glyph. Forwards `onClose` only.
    ///
    /// **Enlarged 2026-09-03 (design R32)**: 20×20 (icon 9pt) → 28×28 (icon 12pt) — a pure
    /// visual bump, no behavior change. The design's OWN literal values moved 20×20/icon-11px
    /// → 28×28/icon-14px, but SF/`.font(size:)` pt is not a 1:1 stand-in for the design's SVG
    /// px (this button's ORIGINAL 9pt was already smaller than the design's then-11px for
    /// exactly that reason — see the git history / `rb-ios-live-replay-more-menu-and-video-
    /// info-live-copy` design.md). 12pt is a considered pt choice for the new 28pt circle
    /// (scaling the button's own linear growth, 20→28 = ×1.4, onto the prior 9pt glyph ≈
    /// 12.6pt), not a literal transcription of the design's 14px — verified against a render
    /// rather than assumed.
    ///
    /// NO border and NO shadow of its own — the design has neither (`border: 'none'`,
    /// no `box-shadow` on the button; the window's own drop-shadow is separate and
    /// stays). Both used to exist here because the button was pushed OUTSIDE the card
    /// frame, where its backdrop was the host page's arbitrary (possibly white)
    /// content; inside the frame the backdrop is always the 9:16 thumbnail, and the
    /// white glyph carries the contrast — the same vocabulary every other dark chrome
    /// disc in this layer uses. Identical to `MinimizedWidgetView.closeButton`, which
    /// renders this same design element.
    private var closeButton: some View {
        Button(action: { onClose?() }) {
            ZStack {
                Circle()
                    .fill(Self.closeGlass)
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
            }
            .frame(width: 28, height: 28)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier(LBAccessibilityID.floatingClose)
    }

    // MARK: - Decorative design tokens (literal sdk-components.jsx values)
    //
    // theme is passed through to the card; these are FIXED decorative colors lifted
    // from `sdk-components.jsx` `LBPFloatingWidget` (the close button + window shadow
    // are the same regardless of the host theme — design's standalone floating
    // chrome), kept consistent with the family-2/3/4 surfaces' surface-token approach.

    /// Close-button surface (`rgba(0,0,0,0.55)`, `LBPFloatingWidget` 699).
    ///
    /// The design pairs that fill with `backdropFilter: 'blur(6px)'`, which this layer
    /// does NOT implement: SwiftUI's counterpart `.ultraThinMaterial` is iOS-15+ and
    /// this package targets iOS 14+. Every `rgba(…)` "glass" in this layer is drawn as
    /// a plain translucent fill for that reason (see `MiniCartView`,
    /// `MinimizedWidgetView`) — a KNOWN, deliberate gap, not an oversight.
    static let closeGlass = Color.black.opacity(0.55)
    /// Floating window drop-shadow (`LBPFloatingWidget` 668).
    ///
    /// NOTE the value diverges from the design's current `rgba(0,0,0,0.35)`: this 0.28
    /// predates the design's own revision and is left as-is deliberately —
    /// `rb-ios-floating-close-button-design-align` scoped itself to the CLOSE BUTTON,
    /// so the window shadow was not re-aligned. Unrelated to the blur gap above.
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
