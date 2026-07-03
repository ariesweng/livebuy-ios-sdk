import LiveBuySDK

// MARK: - DefaultWidgetContent — Widget content host-bindable view-model
//
// Spec: `ui-template-foundation/spec.md` (widget-content-template)
//   § "Default Template Widget 內容 view-model 暴露"
//   § "Default Template Host 取得 widget template 實例介面"
//   § "Default Template Bindable State 變更通知" (MODIFIED — widget content folded in)
// Design: design.md D2 / D3 / D4 / D5 / D6.
//
// Behaviour / view-model layer ONLY (no pixels). core stays headless: it owns the
// `LiveBuyWidgetCore` state (`videos` / `mode` / `currentPage` / `lastPage` /
// `liveVideo` / `isClosed`), the `loadFirstPage` / `requestLoadMore` fetch, and
// the `POST /sdk/widget` flow. This model MIRRORS core `LiveBuyWidgetCore`'s existing
// read-only public state into a host-bindable snapshot so the host / reference-ui
// can draw `widgets.jsx` (`LBPCarousel` / `LBPCarouselCard` / `LBPVideoShop` /
// `LBPFloatingWidget` / `LBPMinimizedWidget`). The template renders NOTHING.
//
// D2 — single source of truth stays in core `LiveBuyWidgetCore` (and the
//       `widget-bridge-color-core` snapshot for colors). This model does NOT hold
//       a second copy of the data — it re-reads core on every `refresh`.

/// Host-bindable widget layout mode. `carousel` / `grid` / `floating` map 1:1 to
/// core `WidgetMode`; `minimized` is a TEMPLATE-DERIVED state (core floating
/// `isClosed == true`), aligned to the design's `LBPMinimizedWidget`. core has NO
/// `minimized` enum value (D3) — it is derived here, never added to core.
public enum LBWidgetContentMode: Equatable {
    case carousel
    case grid
    case floating
    case minimized
}

/// One host-bindable widget-content snapshot. Mirrors core `LiveBuyWidgetCore` plus
/// the `widget-bridge-color-core` web-embed colors (raw passthrough — the
/// template MUST NOT interpret the color semantics, D4).
public struct LBWidgetContent: Equatable {
    /// Card-row data — core `LiveBuyWidgetCore.videos` (read-only mirror).
    public let videos: [LBVideoItem]
    /// Layout mode — `carousel` / `grid` / `floating` from core `WidgetMode`;
    /// `minimized` derived from floating `isClosed == true` (D3).
    public let mode: LBWidgetContentMode
    /// Pagination cursor — core `LiveBuyWidgetCore.currentPage`.
    public let currentPage: Int
    /// Pagination last page — core `LiveBuyWidgetCore.lastPage`.
    public let lastPage: Int
    /// Floating live card — core `LiveBuyWidgetCore.liveVideo`.
    public let liveVideo: LBVideoItem?
    /// Web-embed text color (`widget_color`) — `widget-bridge-color-core` raw
    /// passthrough (1=black / 2=white per web embed; template does NOT interpret).
    /// Fallback `1` when absent (core DTO default).
    public let widgetColor: Int
    /// Web-embed background color (`widget_bgcolor`) — `widget-bridge-color-core`
    /// raw passthrough (mixed Int/String on wire; template does NOT interpret).
    /// Fallback `nil` when absent (core DTO default).
    public let widgetBgcolor: String?

    public init(videos: [LBVideoItem], mode: LBWidgetContentMode,
                currentPage: Int, lastPage: Int, liveVideo: LBVideoItem?,
                widgetColor: Int, widgetBgcolor: String?) {
        self.videos = videos
        self.mode = mode
        self.currentPage = currentPage
        self.lastPage = lastPage
        self.liveVideo = liveVideo
        self.widgetColor = widgetColor
        self.widgetBgcolor = widgetBgcolor
    }

    /// The empty / not-loaded default snapshot (core defaults: `currentPage = 0`,
    /// `lastPage = 1`, `widgetColor = 1`, `widgetBgcolor = nil`). Mode is supplied
    /// since it depends on the widget's configured `WidgetMode`.
    static func empty(mode: LBWidgetContentMode) -> LBWidgetContent {
        LBWidgetContent(videos: [], mode: mode, currentPage: 0, lastPage: 1,
                        liveVideo: nil, widgetColor: 1, widgetBgcolor: nil)
    }

    /// Per-video diff signature for the snapshot equality guard. Beyond the stable
    /// `id` it includes every DISPLAY-AFFECTING field that can change mid-session so a
    /// refresh that changes only what the card renders still counts as "changed":
    ///   • `liveStatus` (預告 0 / 直播 1 / 回放 3) + `type` + `liveurl` — the latter two
    ///     drive `widget-hide-urlless-live` visibility;
    ///   • `cover` + `preview` + `title` — the card's thumbnail media + title text
    ///     (all widget cells reuse `CarouselCardView`);
    ///   • the product-overlay display fields (`goods.name` / `goods.pic` / `goods.price`)
    ///     via `goodsDiffSignature` (nil-safe — `goods` is `Optional`).
    /// Comparing only `id` + status fields (the prior behaviour) made a refresh that
    /// keeps the same `id` but swaps `cover` (backend renames the cover URL), `title`,
    /// or the featured product look "unchanged", so `onChange` never fired and the card
    /// stayed on the stale image until a reopen (widget-content-diff-refresh /
    /// widget-content-diff-include-cover). Pure for unit testing.
    static func videoDiffSignature(_ v: LBVideoItem) -> String {
        "\(v.id)|\(v.liveStatus)|\(v.type)|\(v.liveurl)|\(v.cover)|\(v.preview)|\(v.title)|\(goodsDiffSignature(v.goods))"
    }

    /// Diff signature for the card's featured-product overlay (`LBVideoItem.goods` —
    /// `LBFeaturedGood?`). `nil` (no overlay rendered) → the sentinel `"-"`, so a
    /// product appearing / disappearing (nil ↔ non-nil) always differs; otherwise the
    /// DISPLAYED fields the overlay draws (`name` / `pic` / `price`). Pure for unit
    /// testing. `originalPrice` / `soldOut` / `stock` / `status` are intentionally
    /// excluded — the widget card does not render them.
    static func goodsDiffSignature(_ g: LBFeaturedGood?) -> String {
        guard let g = g else { return "-" }
        return "\(g.name)|\(g.pic)|\(g.price)"
    }

    /// `Equatable` is hand-rolled because core `LBVideoItem` is NOT `Equatable`
    /// (it is a Mapper-produced model). Two snapshots are equal when the scalar
    /// fields match AND the video / live-card DIFF SIGNATURE (id + liveStatus + type +
    /// liveurl + cover + preview + title + 商品名稱/圖片/價格) is the same — so ANY change
    /// the card renders (live status flipping, a swapped cover / preview / title, or an
    /// updated featured product) always makes the snapshot unequal and fires `onChange`
    /// (diff-then-notify). Covering the DISPLAY fields is what keeps a pure cover /
    /// title / price update from being swallowed by the diff.
    public static func == (lhs: LBWidgetContent, rhs: LBWidgetContent) -> Bool {
        lhs.mode == rhs.mode
            && lhs.currentPage == rhs.currentPage
            && lhs.lastPage == rhs.lastPage
            && lhs.widgetColor == rhs.widgetColor
            && lhs.widgetBgcolor == rhs.widgetBgcolor
            && lhs.liveVideo.map(videoDiffSignature) == rhs.liveVideo.map(videoDiffSignature)
            && lhs.videos.map(videoDiffSignature) == rhs.videos.map(videoDiffSignature)
    }
}

/// Maps a core `LiveBuyWidgetCore` into a host-bindable widget-content snapshot. The
/// owning `DefaultWidgetTemplate` feeds it `refresh(from:)` (on attach + whenever
/// core load / loadMore / floating-close changes state); the host reads `current`
/// and observes the template's `onChange`.
///
/// `current` is publicly READABLE (host consumes the snapshot); the constructor
/// and `refresh(from:)` feed method stay `internal` (the host does NOT build the
/// model or feed core state — it only consumes), per the spec's "內部接線不對
/// host 公開".
public final class DefaultWidgetContent {

    /// Current host-bindable widget-content snapshot. Starts empty (core defaults)
    /// until the first `refresh`.
    private(set) public var current: LBWidgetContent

    /// Internal coalesced "widget-content mutated" hook → owning template's single
    /// host-facing `onChange`. NOT public (host observes via `onChange`).
    var onMutation: (() -> Void)?

    init(mode: WidgetMode) {
        self.current = LBWidgetContent.empty(mode: Self.mode(from: mode, isClosed: false))
    }

    /// Re-read the core `LiveBuyWidgetCore`'s existing public read-only state into a
    /// fresh snapshot (D2 — no second copy; the snapshot is rebuilt each time).
    /// Notifies ONLY when the snapshot actually changed (diff-then-notify), so a
    /// no-op core callback never fires a spurious onChange.
    ///
    /// Colors come from `widget-bridge-color-core`'s host-readable exits on the
    /// widget instance (`widget.widgetColor` / `widget.widgetBgcolor`); when that
    /// dependency is absent the widget instance still carries the core DTO
    /// defaults (`1` / `nil`), so this never throws (D4 / R5).
    func refresh(from widget: LiveBuyWidgetCore) {
        let next = LBWidgetContent(
            videos: widget.videos,
            mode: Self.mode(from: widget.mode, isClosed: widget.isClosed),
            currentPage: widget.currentPage,
            lastPage: widget.lastPage,
            liveVideo: widget.liveVideo,
            widgetColor: widget.widgetColor,
            widgetBgcolor: widget.widgetBgcolor)
        guard next != current else { return }
        current = next
        onMutation?()
    }

    /// Pure derivation: core `WidgetMode` + floating `isClosed` → host-bindable
    /// mode (D3). `floating` + `isClosed == true` → `minimized`; everything else
    /// maps 1:1. Never throws / never breaks the state model (unknown combos fall
    /// back to the corresponding core mode).
    static func mode(from coreMode: WidgetMode, isClosed: Bool) -> LBWidgetContentMode {
        switch coreMode {
        case .carousel: return .carousel
        case .grid:     return .grid
        case .floating: return isClosed ? .minimized : .floating
        }
    }
}
