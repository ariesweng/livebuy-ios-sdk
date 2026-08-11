import SwiftUI
import Combine
import LivebuySDK
import LivebuyUI

// MARK: - WidgetModel — family-5 widget content observable snapshot bridge
//
// Spec: `reference-ui-rendering/spec.md` (family-5 widget surfaces:
//        carousel / video-shop grid / floating / minimized).
// Design: rb-ios-widget design.md §"渲染計畫" + §"守住的不變式" +
//          `design/templates/minimal/widgets.jsx` (LBPCarousel / LBPVideoShop) +
//          `sdk-components.jsx` (LBPFloatingWidget / LBPMinimizedWidget).
//
// This is the SKELETON for rb-ios-widget. It bridges the headless widget-content
// view-model exposed by `DefaultWidgetTemplate` (obtained via
// `LivebuyUI.widgetTemplate(for:)`) into a SwiftUI-observable snapshot that the
// four family-5 widget sub-views read. It is a read-only mirror — IDENTICAL in
// spirit to `MomentsModel` (family-4) / `PlayerShellModel` (family-1) /
// `FeedWinModel` (family-2) / `ProductSheetsModel` (family-3):
//
//   - It does NOT own a second copy of authoritative state — it republishes
//     SNAPSHOT VALUES taken from the template's own `private(set) public` read
//     (`content.current`: `videos` / `mode` / `currentPage` / `lastPage` /
//     `liveVideo` / `widgetColor` / `widgetBgcolor` / `productCard`) each time the
//     template notifies its registered change observers (design §"容器與 view-model 橋接").
//   - It does NOT add pixels and it does NOT add any accessor to `LivebuyUI`
//     (that would be a template-layer concern, out of scope here).
//   - It does NOT subscribe to the content view-model's internal `onMutation`
//     (that is a template-internal hook) — it observes ONLY the template's public
//     change notification, registered via `template.addObserver` (design §"守住的
//     不變式": 只讀呈現).
//   - It carries NO mutating interactions / forwarders. The widget's real intents
//     (card tap → open player / load-more pagination / floating close+expand) are
//     HOST-WIRED CONTAINER closures carried by `WidgetOverlayView`, NOT this model.
//     This model is a PURE read-only snapshot (do NOT invent template forwarders).
//   - `widgetColor` / `widgetBgcolor` are RAW PASSTHROUGH web-embed colors — THIS
//     MODEL carries them verbatim and MUST NOT interpret their semantics. The
//     interpretation lives one layer out, in the three widget SURFACES
//     (`ReferenceUIWidgetEmbedTheme.derive`, rb-ios-widget-embed-colors); the
//     global `ReferenceUIThemeResolver` still never sees them.
//   - `productCard` (`product_card`) is the SAME KIND of raw passthrough
//     (rb-ios-widget-product-card-modes): this model mirrors the wire string
//     VERBATIM — including `nil`, which means THE BACKEND SENT NOTHING and is a
//     DIFFERENT fact from the backend sending `"inside"`. Normalizing the value
//     (unknown / missing → `inside`) is `CarouselCardView`'s job via the single
//     pure entry point `LBProductCardMode.normalized(_:)`; this model MUST NOT
//     normalize, and the normalized value MUST NOT be written back here.
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

    /// Card-row data — core `LivebuyWidgetCore.videos` (read-only mirror). Drawn as a
    /// FIXED SMALL set in a PLAIN HStack / VStack by the carousel / grid surfaces
    /// (NEVER lazy / scroll — the `ImageRenderer` blank-render trap); the real
    /// scroll / pagination intent forwards to the container's host-wired closure.
    @Published public private(set) var videos: [LBVideoItem]

    /// Layout mode — `.carousel` / `.grid` / `.floating` / `.minimized`
    /// (`LBWidgetContentMode`). `.minimized` is the template-derived floating
    /// `isClosed == true` state. The container switches the active surface on this.
    @Published public private(set) var mode: LBWidgetContentMode

    /// Pagination cursor — core `LivebuyWidgetCore.currentPage`.
    @Published public private(set) var currentPage: Int

    /// Pagination last page — core `LivebuyWidgetCore.lastPage`. The grid surface's
    /// load-more footer compares `currentPage` vs `lastPage` (inclusive — Key
    /// Invariant: `current_page == last_page`) to decide「載入更多」vs「已顯示全部」.
    @Published public private(set) var lastPage: Int

    /// Floating live card — core `LivebuyWidgetCore.liveVideo`. The floating surface
    /// renders this single card; nil → render NOTHING (EmptyView).
    @Published public private(set) var liveVideo: LBVideoItem?

    /// Web-embed text color mode (`widget_color`) — RAW PASSTHROUGH. `1`=預設色彩,
    /// `2`=色彩反轉 (web renders `2` as `#ffffff` and `1` as no override); these are
    /// MODES, not color swatches. THIS layer MUST NOT interpret it — the three
    /// widget surfaces do, via `ReferenceUIWidgetEmbedTheme.derive`.
    @Published public private(set) var widgetColor: Int

    /// Web-embed background color (`widget_bgcolor`) — RAW PASSTHROUGH (mixed
    /// Int/String on wire, carried as `String?`; transparent is the EMPTY STRING
    /// `""`, never Int `1`). THIS layer MUST NOT interpret it — the three widget
    /// surfaces do, treating `""` / nil / unparseable alike as "leave it alone".
    @Published public private(set) var widgetBgcolor: String?

    /// Carousel card product-card display mode (`product_card`) — RAW PASSTHROUGH
    /// (backend domain `inside` / `below` / `hidden`, backend default `inside`).
    /// Mirrored VERBATIM: `nil` means the backend sent nothing (the field is absent
    /// on `/sdk/widget/live`, on the linetv branch, and before the first load) — NOT
    /// the same fact as `"inside"`, so this model deliberately does NOT substitute
    /// the backend default. The fallback (missing / unknown → `inside`) lives in
    /// `LBProductCardMode.normalized(_:)`, consumed by `CarouselCardView`.
    @Published public private(set) var productCard: String?

    // MARK: - Live binding

    /// The bound template, when constructed from a live widget. nil for demo /
    /// snapshot instances. Held weakly so this model never retains the template
    /// (the widget owns it; dependency stays one-way UI → core).
    private weak var template: DefaultWidgetTemplate?

    /// The removal token for this model's INDEPENDENT observer registration on the
    /// template (`ios-refui-widget-overlay-migrate-onchange-to-observer`). Each
    /// `WidgetModel` registers its OWN observer via `template.addObserver` and removes
    /// ONLY this token on deinit — it never chains / restores a single shared
    /// `onChange` var, so it is structurally impossible to wipe another observer's
    /// subscription (mirrors the family-1/2/3/4 player overlay models).
    private var observerToken: LBTemplateObserverToken?

    // MARK: - Live initializer (design §"容器與 view-model 橋接")

    /// Bridge a live `DefaultWidgetTemplate`: take an initial snapshot and register
    /// an INDEPENDENT change observer via `template.addObserver` so every videos
    /// update / mode change / page advance / liveVideo update / color update
    /// re-snapshots and republishes to the widget sub-views.
    ///
    /// The host obtains the template via `LivebuyUI.widgetTemplate(for:)` and passes
    /// it here. Returns a model whose published values mirror the template
    /// (read-only). This model keeps its OWN `LBTemplateObserverToken` and removes
    /// only that token on deinit — it never chains / clobbers a single shared
    /// `onChange` var, so other observers on the same template are unaffected.
    public convenience init(template: DefaultWidgetTemplate) {
        self.init(snapshotting: template)
        self.template = template
        self.observerToken = template.addObserver { [weak self] in
            self?.refresh(from: template)
        }
    }

    /// Take an immediate snapshot of a template (no subscription) — used by the
    /// live convenience init for the seed values.
    private convenience init(snapshotting t: DefaultWidgetTemplate) {
        let c = t.content.current
        // Hide in-app-unplayable lives (`type==2 && liveStatus==1 && liveurl==""`)
        // from the card list and the floating preview (rb-ios-widget-hide-urlless-live
        // / `widget-hide-urlless-live`). Applied ONLY on the live republish path —
        // the public memberwise init below stays unfiltered so demo / snapshot
        // fixtures render exactly as constructed (design D4).
        self.init(
            videos: WidgetVisibility.visibleVideos(c.videos),
            mode: c.mode,
            currentPage: c.currentPage,
            lastPage: c.lastPage,
            liveVideo: WidgetVisibility.visibleLive(c.liveVideo),
            widgetColor: c.widgetColor,
            widgetBgcolor: c.widgetBgcolor,
            productCard: c.productCard
        )
    }

    // MARK: - Memberwise / demo initializer (design §"容器與 view-model 橋接")

    /// Construct a deterministic instance WITHOUT a live widget — for the widget
    /// sub-views' previews and the per-surface snapshot tests. Every value defaults
    /// to the empty / at-attach seed (`videos: []`, `.carousel`, `currentPage: 0`,
    /// `lastPage: 1`, no live card, core color defaults `1` / `nil`, no
    /// `productCard`) so a zero-argument call yields a stable baseline that matches
    /// the freshly-attached template content (`LBWidgetContent.empty(mode: .carousel)`).
    public init(
        videos: [LBVideoItem] = [],
        mode: LBWidgetContentMode = .carousel,
        currentPage: Int = 0,
        lastPage: Int = 1,
        liveVideo: LBVideoItem? = nil,
        widgetColor: Int = 1,
        widgetBgcolor: String? = nil,
        productCard: String? = nil
    ) {
        self.videos = videos
        self.mode = mode
        self.currentPage = currentPage
        self.lastPage = lastPage
        self.liveVideo = liveVideo
        self.widgetColor = widgetColor
        self.widgetBgcolor = widgetBgcolor
        self.productCard = productCard
    }

    deinit {
        // Remove ONLY this model's own observer registration; other observers on the
        // same template are untouched (there is no single-`onChange`-var chain to
        // restore, so this can never clobber another observer's subscription).
        if let token = observerToken { template?.removeObserver(token) }
    }

    // MARK: - Re-snapshot on change (design §"容器與 view-model 橋接")

    /// Pull the latest values from the bound template's content snapshot into the
    /// published mirrors. Always on the main thread (the template dispatches its
    /// change notification on main; the live init only registers this observer from
    /// the main-thread `addObserver`). `objectWillChange` fires once per `@Published`
    /// write — acceptable for the skeleton; widget sub-views read final values within
    /// one runloop.
    private func refresh(from t: DefaultWidgetTemplate) {
        let c = t.content.current
        // Same in-app-unplayable-live hiding as the live seed init above
        // (rb-ios-widget-hide-urlless-live / `widget-hide-urlless-live`).
        videos = WidgetVisibility.visibleVideos(c.videos)
        mode = c.mode
        currentPage = c.currentPage
        lastPage = c.lastPage
        liveVideo = WidgetVisibility.visibleLive(c.liveVideo)
        widgetColor = c.widgetColor
        widgetBgcolor = c.widgetBgcolor
        productCard = c.productCard
    }
}
