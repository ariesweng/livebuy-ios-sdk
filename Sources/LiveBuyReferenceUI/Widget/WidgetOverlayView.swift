import SwiftUI
import LiveBuySDK
import LiveBuyUI

// MARK: - WidgetOverlayView — family-5 widget container (SKELETON)
//
// Spec: `reference-ui-rendering/spec.md` (family-5 widget surfaces).
// Design: rb-ios-widget design.md §"渲染計畫" + §"守住的不變式" +
//          `design/templates/minimal/widgets.jsx` (LBPCarousel / LBPVideoShop /
//          LBPFloatingWidget) + `sdk-components.jsx` (LBPMinimizedWidget).
//
// The top-level family-5 container. It reads a `WidgetModel` (republished from a
// live `DefaultWidgetTemplate` or constructed deterministically) and renders the
// ONE widget surface selected by `model.mode`, mirroring `MomentsOverlayView`
// (family-4) / `FeedWinOverlayView` (family-2) / `ProductSheetsOverlayView`
// (family-3):
//
//   .carousel  → CarouselView        (LBPCarousel — header + horizontal card row)
//   .grid      → VideoShopGridView   (LBPVideoShop — 2-col grid + load-more footer)
//   .floating  → FloatingWidgetView  (LBPFloatingWidget — single live card + close)
//   .minimized → MinimizedWidgetView (LBPMinimizedWidget — minimized pill)
//
// MODE IS MUTUALLY EXCLUSIVE — exactly ONE surface shows, chosen by `model.mode`
// (which is the template-derived `LBWidgetContentMode`; `.minimized` is the
// floating `isClosed == true` state). There is NO priority stack here (unlike
// family-4's moment priority) — the mode is authoritative.
//
// ─────────────────────────────────────────────────────────────────────────────
// HOST-WIRED ACTION CLOSURES (design §"守住的不變式": host-wired exit)
// ─────────────────────────────────────────────────────────────────────────────
// All widget interactions are HOST-WIRED CONTAINER closures — this layer NEVER
// calls core `widget.simulateCardTap` / `simulateClose` / `requestLoadMore` or any
// template intent directly. The host wires them to the core / template exits it
// owns, e.g.:
//   • onTapVideo(item) → host → core open player for `item.id`
//                        (carousel / grid card tap, floating live-card tap).
//   • onClose          → host → core floating-close (floating / minimized close).
//   • onExpand         → host → core re-open the floating widget (minimized tap).
//   • onLoadMore       → host → `widgetTemplate.requestLoadMore()` (grid footer).
//
// Each closure is nil-defaulted, so the container renders correctly action-free
// (demo / snapshot tests construct it without host wiring); a nil closure means the
// corresponding interaction is inert. This layer NEVER opens the player / loads /
// closes itself (design §"守住的不變式": 互動一律 host-wired exit 轉發).
//
// This is the SKELETON: it owns the mode switch + a `WidgetModel` + the resolved
// `ReferenceUITheme` + the host-wired action closures, and composes the four
// surface sub-views BY TYPE NAME. The four surface TYPES are produced by the
// parallel surface agents that run after this skeleton — see the "SUB-VIEW INPUT
// PATTERN" contract below, which every surface agent MUST implement verbatim so the
// container's call sites match.
//
// Until all four widget surface sub-views exist, this file will not compile on its
// own — that is expected (the surface agents land the types). The whole
// LiveBuyReferenceUI target compiles together (SPM globs the directory), so the
// container referencing not-yet-written surface views is fine — they are created in
// the next phase before any build.
//
// iOS-14-safe: `ZStack` / `switch` in a `@ViewBuilder` are all iOS-13+; no
// `@available` guard needed here. Any surface that reaches for a >14 API must guard
// it inside its own sub-view (design §"守住的不變式": iOS-14 樓地板).
//
// ⚠️ NO ScrollView / LazyVStack / LazyHStack / LazyVGrid anywhere in rendered
// content — `ImageRenderer` renders them BLANK (the family-3 lesson). The carousel
// row and the video-shop grid MUST be drawn as a FIXED SMALL set in plain
// HStack / VStack; the real scroll / pagination intent forwards to `onLoadMore`.
//
// ─────────────────────────────────────────────────────────────────────────────
// SUB-VIEW INPUT PATTERN — the contract the 4 parallel surface agents MUST follow
// ─────────────────────────────────────────────────────────────────────────────
//
// Concretely, the four surface agents implement EXACTLY these initializers (frozen
// API — the container's call sites below depend on them verbatim):
//
//   CarouselView(
//       model: WidgetModel,
//       theme: ReferenceUITheme,
//       title: String = "精選影片",
//       subtitle: String? = nil,
//       cardWidth: CGFloat = 132,
//       onTapVideo: ((LBVideoItem) -> Void)? = nil)
//
//   VideoShopGridView(
//       model: WidgetModel,
//       theme: ReferenceUITheme,
//       live: Bool = false,
//       hostScrollable: Bool = false,        // rb-ios-widget-host-scroll
//       containerWidth: CGFloat = 393,       // rb-ios-widget-host-scroll
//       onTapVideo: ((LBVideoItem) -> Void)? = nil,
//       onLoadMore: (() -> Void)? = nil)
//
//   FloatingWidgetView(
//       video: LBVideoItem?,                 // nil → render NOTHING (EmptyView)
//       theme: ReferenceUITheme,
//       width: CGFloat = 132,
//       onTap: ((LBVideoItem) -> Void)? = nil,
//       onClose: (() -> Void)? = nil)
//
//   MinimizedWidgetView(
//       theme: ReferenceUITheme,
//       isLive: Bool = false,
//       onExpand: (() -> Void)? = nil,
//       onClose: (() -> Void)? = nil)
//
// Rules every surface agent honours:
//   • A surface reads ONLY its passed-in `model` / values — it MUST NOT reach back
//     into `DefaultWidgetTemplate` or hold a second copy of state (one-way data
//     flow). It MUST NOT interpret `widgetColor` / `widgetBgcolor` for the native
//     theme (those are a SEPARATE raw-passthrough track — theme comes ONLY from
//     `ReferenceUITheme`).
//   • Card / live-card tap → `onTapVideo(item)` (forwarded host-wired). Floating /
//     minimized close → `onClose`. Minimized tap → `onExpand`. Grid bottom →
//     `onLoadMore`. NO core simulate* / template intent calls here.
//   • Each surface renders correctly with all actions nil (so demo / snapshot tests
//     construct it action-free).
//   • iOS-14-safe SwiftUI only; any >14 API guarded with `@available` /
//     `if #available`. ⚠️ NO ScrollView / Lazy* in rendered content (the carousel
//     row + the grid especially — plain HStack / VStack, fixed small set; real
//     scroll / pagination forwards to `onLoadMore`).
//
// HOST-SCROLL EMBEDDING (rb-ios-widget-host-scroll):
//   • GRID — this container forwards `hostScrollable` / `containerWidth` (both
//     defaulted: `false` / `393`) to `VideoShopGridView` in the `.grid` branch.
//     The host wraps the WHOLE container (or the grid surface directly) in its
//     own vertical `ScrollView`; with `hostScrollable: true` the grid renders
//     ALL videos at intrinsic height (no `GeometryReader` root / no card cap).
//   • CAROUSEL — host-embed does NOT go through this container: the carousel's
//     scrollable form needs the header FIXED OUTSIDE the host's horizontal
//     scroll container, which this single-view mode switch cannot express. The
//     host composes the decomposed sub-surfaces directly instead:
//
//       VStack(alignment: .leading, spacing: 0) {
//           CarouselHeaderView(theme: theme, title: "精選影片", onSeeMore: { ... })
//           ScrollView(.horizontal, showsIndicators: false) {   // host-owned
//               CarouselRowView(model: model, theme: theme, live: true,
//                               onTapVideo: { ... })             // ALL videos
//           }
//       }
//
//     The `.carousel` branch below keeps the unchanged windowed `CarouselView`.
// ─────────────────────────────────────────────────────────────────────────────

/// The family-5 widget container. Renders the ONE widget surface selected by
/// `model.mode` (carousel / grid / floating / minimized, mutually exclusive);
/// reads a `WidgetModel` (republished from a live `DefaultWidgetTemplate` or
/// constructed deterministically) and paints with the resolved `ReferenceUITheme`.
/// All widget actions are host-wired container closures (no core simulate* /
/// template intents are called here).
public struct WidgetOverlayView: View {

    /// The republished, read-only widget content snapshot.
    @ObservedObject public var model: WidgetModel

    /// The resolved reference-ui theme.
    public let theme: ReferenceUITheme

    /// Runtime media gate forwarded to the card-bearing surfaces (carousel / grid /
    /// floating). `false` (default — demo / snapshot) → placeholder thumbnails
    /// (baselines unchanged); `true` (host runtime) → cards render `preview → cover →
    /// placeholder`. The minimized pill (no `LBVideoItem`) is unaffected.
    public let live: Bool

    /// HOST-SCROLL EMBEDDING opt-in, forwarded to `VideoShopGridView` in the `.grid`
    /// branch ONLY (rb-ios-widget-host-scroll; the carousel's host-embed composes
    /// `CarouselHeaderView` + a host-owned `ScrollView` + `CarouselRowView` directly,
    /// not through this container — see the header comment). Default `false` keeps
    /// every surface's rendering unchanged.
    public let hostScrollable: Bool

    /// The host's embed width (pt) forwarded with `hostScrollable` to the grid
    /// surface; used only when `hostScrollable == true`. Defaults to the
    /// reference-ui 393pt canvas.
    public let containerWidth: CGFloat

    // MARK: - Host-wired action closures (design §"守住的不變式": host-wired exit)
    //
    // Each nil-defaulted; a nil closure means an inert interaction (demo / snapshot
    // tests construct the container action-free). This layer NEVER opens the player
    // / loads / closes itself.

    /// Card / live-card tap → host → core open player for `item.id`.
    private let onTapVideo: ((LBVideoItem) -> Void)?
    /// Floating / minimized close → host → core floating-close.
    private let onClose: (() -> Void)?
    /// Minimized pill tap → host → core re-open the floating widget.
    private let onExpand: (() -> Void)?
    /// Grid load-more footer → host → `widgetTemplate.requestLoadMore()`.
    private let onLoadMore: (() -> Void)?

    public init(
        model: WidgetModel,
        theme: ReferenceUITheme,
        live: Bool = false,
        hostScrollable: Bool = false,
        containerWidth: CGFloat = 393,
        onTapVideo: ((LBVideoItem) -> Void)? = nil,
        onClose: (() -> Void)? = nil,
        onExpand: (() -> Void)? = nil,
        onLoadMore: (() -> Void)? = nil
    ) {
        self.model = model
        self.theme = theme
        self.live = live
        self.hostScrollable = hostScrollable
        self.containerWidth = containerWidth
        self.onTapVideo = onTapVideo
        self.onClose = onClose
        self.onExpand = onExpand
        self.onLoadMore = onLoadMore
    }

    public var body: some View {
        // Mutually-exclusive surface, chosen by the template-derived mode.
        ZStack {
            activeSurface
        }
    }

    /// Host-wired `onTapVideo` wrapped to redirect external-platform lives
    /// (external-live-watch): a live whose `liveurl` host is an external platform
    /// (Facebook) opens out to that platform instead of the in-app player, so the
    /// host's `onTapVideo` is NOT invoked for it. Non-external lives forward to
    /// `onTapVideo` unchanged. Computed once and used by every surface below.
    private var routedTapVideo: (LBVideoItem) -> Void {
        externalLiveAwareTap(onTapVideo)
    }

    /// The single active widget surface for `model.mode`. Mutually exclusive — the
    /// mode is authoritative (no priority stack).
    @ViewBuilder
    private var activeSurface: some View {
        switch model.mode {
        case .carousel:
            // LBPCarousel — header + horizontal card row (FIXED SMALL set; real
            // scroll forwards to the host).
            CarouselView(
                model: model,
                theme: theme,
                live: live,
                onTapVideo: { item in routedTapVideo(item) })

        case .grid:
            // LBPVideoShop — 2-col grid + load-more footer. Forwards the host-scroll
            // embedding opt-in (defaults keep the windowed rendering unchanged).
            VideoShopGridView(
                model: model,
                theme: theme,
                live: live,
                hostScrollable: hostScrollable,
                containerWidth: containerWidth,
                onTapVideo: { item in routedTapVideo(item) },
                onLoadMore: { onLoadMore?() })

        case .floating:
            // LBPFloatingWidget — single live card + close. nil video → EmptyView
            // (the surface itself renders NOTHING for a nil `video`).
            FloatingWidgetView(
                video: model.liveVideo,
                theme: theme,
                live: live,
                onTap: { item in routedTapVideo(item) },
                onClose: { onClose?() })

        case .minimized:
            // LBPMinimizedWidget — minimized pill (floating isClosed). Tap →
            // onExpand; close → onClose. `isLive` reflects whether a live card is
            // available behind the minimized pill.
            MinimizedWidgetView(
                theme: theme,
                isLive: model.liveVideo?.liveStatus == 1,
                onExpand: { onExpand?() },
                onClose: { onClose?() })
        }
    }
}
