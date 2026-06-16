import SwiftUI
import Combine
import LiveBuySDK
import LiveBuyUI

// MARK: - WidgetModel — family-5 widget content observable snapshot bridge
//
// Spec: `reference-ui-rendering/spec.md` (family-5 widget surfaces:
//        carousel / video-shop grid / floating / minimized).
// Design: rb-ios-widget design.md §"渲染計畫" + §"守住的不變式" +
//          `design/templates/minimal/widgets.jsx` (LBPCarousel / LBPVideoShop /
//          LBPFloatingWidget) + `sdk-components.jsx` (LBPMinimizedWidget).
//
// This is the SKELETON for rb-ios-widget. It bridges the headless widget-content
// view-model exposed by `DefaultWidgetTemplate` (obtained via
// `LiveBuyUI.widgetTemplate(for:)`) into a SwiftUI-observable snapshot that the
// four family-5 widget sub-views read. It is a read-only mirror — IDENTICAL in
// spirit to `MomentsModel` (family-4) / `PlayerShellModel` (family-1) /
// `FeedWinModel` (family-2) / `ProductSheetsModel` (family-3):
//
//   - It does NOT own a second copy of authoritative state — it republishes
//     SNAPSHOT VALUES taken from the template's own `private(set) public` read
//     (`content.current`: `videos` / `mode` / `currentPage` / `lastPage` /
//     `liveVideo` / `widgetColor` / `widgetBgcolor`) each time the template fires
//     its single coalesced `onChange` (design §"容器與 view-model 橋接").
//   - It does NOT add pixels and it does NOT add any accessor to `LiveBuyUI`
//     (that would be a template-layer concern, out of scope here).
//   - It does NOT subscribe to the content view-model's internal `onMutation`
//     (that is a template-internal hook) — it observes ONLY the template's single
//     public `onChange` (design §"守住的不變式": 只讀呈現).
//   - It carries NO mutating interactions / forwarders. The widget's real intents
//     (card tap → open player / load-more pagination / floating close+expand) are
//     HOST-WIRED CONTAINER closures carried by `WidgetOverlayView`, NOT this model.
//     This model is a PURE read-only snapshot (do NOT invent template forwarders).
//   - `widgetColor` / `widgetBgcolor` are RAW PASSTHROUGH web-embed colors — this
//     model carries them verbatim and MUST NOT interpret their semantics (the
//     reference-ui native theme comes from `ReferenceUITheme` only; these are a
//     SEPARATE track — Key Invariant `widget_color` / `widget_bgcolor`).
//
// iOS-14-safe: `ObservableObject` + `@Published` are available from iOS 13, so no
// `@available` guard is needed here.

/// Observable snapshot of the family-5 widget content, republished from a live
/// `DefaultWidgetTemplate` (or constructed deterministically for demos / snapshot
/// tests via the memberwise initializer).
public final class WidgetModel: ObservableObject {

    // MARK: - Published widget-content snapshot
    //
    // The read-only mirror of `DefaultWidgetContent.current`. The four family-5
    // widget sub-views bind exactly the values they need (see `WidgetOverlayView`'s
    // SUB-VIEW INPUT PATTERN). All `private(set)` — the host / sub-views read; only
    // the live bridge (or the demo init) writes.

    /// Card-row data — core `LiveBuyWidgetCore.videos` (read-only mirror). Drawn as a
    /// FIXED SMALL set in a PLAIN HStack / VStack by the carousel / grid surfaces
    /// (NEVER lazy / scroll — the `ImageRenderer` blank-render trap); the real
    /// scroll / pagination intent forwards to the container's host-wired closure.
    @Published public private(set) var videos: [LBVideoItem]

    /// Layout mode — `.carousel` / `.grid` / `.floating` / `.minimized`
    /// (`LBWidgetContentMode`). `.minimized` is the template-derived floating
    /// `isClosed == true` state. The container switches the active surface on this.
    @Published public private(set) var mode: LBWidgetContentMode

    /// Pagination cursor — core `LiveBuyWidgetCore.currentPage`.
    @Published public private(set) var currentPage: Int

    /// Pagination last page — core `LiveBuyWidgetCore.lastPage`. The grid surface's
    /// load-more footer compares `currentPage` vs `lastPage` (inclusive — Key
    /// Invariant: `current_page == last_page`) to decide「載入更多」vs「已顯示全部」.
    @Published public private(set) var lastPage: Int

    /// Floating live card — core `LiveBuyWidgetCore.liveVideo`. The floating surface
    /// renders this single card; nil → render NOTHING (EmptyView).
    @Published public private(set) var liveVideo: LBVideoItem?

    /// Web-embed text color (`widget_color`) — RAW PASSTHROUGH (1=black / 2=white
    /// per web embed). This layer MUST NOT interpret it for the native theme (the
    /// theme comes from `ReferenceUITheme` only — they are independent tracks).
    @Published public private(set) var widgetColor: Int

    /// Web-embed background color (`widget_bgcolor`) — RAW PASSTHROUGH (mixed
    /// Int/String on wire, carried as `String?`). This layer MUST NOT interpret it.
    @Published public private(set) var widgetBgcolor: String?

    // MARK: - Live binding

    /// The bound template, when constructed from a live widget. nil for demo /
    /// snapshot instances. Held weakly so this model never retains the template
    /// (the widget owns it; dependency stays one-way UI → core).
    private weak var template: DefaultWidgetTemplate?

    /// The template's `onChange` we installed, so we can restore the previous one
    /// on deinit (we chain rather than clobber — same as the family-1/2/3/4 models).
    private var previousOnChange: (() -> Void)?

    // MARK: - Live initializer (design §"容器與 view-model 橋接")

    /// Bridge a live `DefaultWidgetTemplate`: take an initial snapshot and
    /// subscribe to its single coalesced `onChange` so every videos update / mode
    /// change / page advance / liveVideo update / color update re-snapshots and
    /// republishes to the widget sub-views.
    ///
    /// The host obtains the template via `LiveBuyUI.widgetTemplate(for:)` and passes
    /// it here. Returns a model whose published values mirror the template
    /// (read-only). The previous `onChange` (if any host already installed one) is
    /// chained, not replaced.
    public convenience init(template: DefaultWidgetTemplate) {
        self.init(snapshotting: template)
        self.template = template
        self.previousOnChange = template.onChange
        template.onChange = { [weak self] in
            self?.previousOnChange?()
            self?.refresh(from: template)
        }
    }

    /// Take an immediate snapshot of a template (no subscription) — used by the
    /// live convenience init for the seed values.
    private convenience init(snapshotting t: DefaultWidgetTemplate) {
        let c = t.content.current
        self.init(
            videos: c.videos,
            mode: c.mode,
            currentPage: c.currentPage,
            lastPage: c.lastPage,
            liveVideo: c.liveVideo,
            widgetColor: c.widgetColor,
            widgetBgcolor: c.widgetBgcolor
        )
    }

    // MARK: - Memberwise / demo initializer (design §"容器與 view-model 橋接")

    /// Construct a deterministic instance WITHOUT a live widget — for the widget
    /// sub-views' previews and the per-surface snapshot tests. Every value defaults
    /// to the empty / at-attach seed (`videos: []`, `.carousel`, `currentPage: 0`,
    /// `lastPage: 1`, no live card, core color defaults `1` / `nil`) so a
    /// zero-argument call yields a stable baseline that matches the freshly-attached
    /// template content (`LBWidgetContent.empty(mode: .carousel)`).
    public init(
        videos: [LBVideoItem] = [],
        mode: LBWidgetContentMode = .carousel,
        currentPage: Int = 0,
        lastPage: Int = 1,
        liveVideo: LBVideoItem? = nil,
        widgetColor: Int = 1,
        widgetBgcolor: String? = nil
    ) {
        self.videos = videos
        self.mode = mode
        self.currentPage = currentPage
        self.lastPage = lastPage
        self.liveVideo = liveVideo
        self.widgetColor = widgetColor
        self.widgetBgcolor = widgetBgcolor
    }

    deinit {
        // Restore the previous handler so a re-bound template is not left with a
        // dangling closure capturing this (now gone) model.
        template?.onChange = previousOnChange
    }

    // MARK: - Re-snapshot on change (design §"容器與 view-model 橋接")

    /// Pull the latest values from the bound template's content snapshot into the
    /// published mirrors. Always on the main thread (the template dispatches
    /// `onChange` on main; the live init only installs this from the main-thread
    /// `onChange`). `objectWillChange` fires once per `@Published` write —
    /// acceptable for the skeleton; widget sub-views read final values within one
    /// runloop.
    private func refresh(from t: DefaultWidgetTemplate) {
        let c = t.content.current
        videos = c.videos
        mode = c.mode
        currentPage = c.currentPage
        lastPage = c.lastPage
        liveVideo = c.liveVideo
        widgetColor = c.widgetColor
        widgetBgcolor = c.widgetBgcolor
    }
}
