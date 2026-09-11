import SwiftUI
import UIKit
import AVFoundation
import LivebuySDK
import LivebuyUI

// MARK: - CarouselCardView — family-5 shared 9:16 widget card primitive (LBPCarouselCard)
//
// Spec: `reference-ui-rendering/spec.md` (family-5 widget surfaces).
// Design: rb-ios-widget design.md §"渲染計畫" +
//          `design/templates/minimal/widgets.jsx` `LBPCarouselCard` (lines 135-226) +
//          `LBPCardProductOverlay` (107-131) / `LBPCardProductRow` (66-103).
//
// The single 9:16 thumbnail card shared by ALL four family-5 widget surfaces
// (carousel row, video-shop grid, floating live card, and — at a smaller scale —
// the minimized pill). It reproduces `LBPCarouselCard`'s structure:
//
//   • a 9:16 thumbnail placeholder (deterministic gradient chip — NO AsyncImage /
//     network fetch; the design's `<ProductMock>` becomes a `LinearGradient` +
//     monogram, mirroring `ProductDetailSheetView.productPhoto`),
//   • a KIND BADGE top-left:
//       - LIVE   → a red「LIVE」tag (pulse dot drawn statically) when `liveStatus`
//                  indicates live, optionally paired with a VIEWER-COUNT badge
//                  (see VIEWER COUNT BADGE below),
//       - VOD / UPCOMING → no kind badge (2026-09-04 design R33 removed the
//                  「▶ mm:ss」duration pill that used to occupy this slot for VOD;
//                  upcoming was already indicated by the centre `upcomingOverlay`,
//                  not a top-left badge).
//   • a PIN BADGE top-right (see PIN BADGE below) — independent of the kind badge;
//     any of LIVE / VOD / UPCOMING can carry it simultaneously,
//   • a PRODUCT CARD whose placement depends on `product_card` (see below) — drawn
//     from `LBVideoItem.goods` (`LBFeaturedGood`: product thumb + `goods.name` +
//     display price). The thumb binds `goods.pic` on the live runtime path (gradient
//     chip fallback); the price is de-duplicated via `displayPrice(_:)` so a
//     symbol-bearing wire value does not render a double currency,
//   • the `LBVideoItem.title` BELOW the thumbnail — gated by a `showTitle: Bool`
//     parameter (default `true`; `FloatingWidgetView` passes `false` — see
//     TITLE VISIBILITY below, rb-ios-floating-widget-hide-title).
//
// PIN BADGE (rb-ios-carousel-card-pin-viewers-duration-removal, design R33): a
// top-right thumbtack glyph gated by `LBVideoItem.pin == 1`, drawn via SF Symbol
// `pin.fill` (the design's inline SVG is FontAwesome `thumbtack`, a close visual
// match). This is a DIFFERENT glyph from `Glyphs/PinFillGlyph.swift` — that one is a
// hand-drawn map-pin BALLOON silhouette used by `ChatFeedView`'s pinned-MESSAGE
// banner (a different feature: pinned chat message, not pinned video). This card
// MUST NOT reuse or modify `PinFillGlyph.swift`.
//
// VIEWER COUNT BADGE (rb-ios-carousel-card-pin-viewers-duration-removal, design R33):
// a LIVE-only pill beside `liveTag` (person icon + `LBVideoItem.watchNum`, raw
// digits — no K-abbreviation), gated by `LBVideoItem.showPvNum == 1` (mirrors
// `PlayerHeaderBarView.viewerCountVisible`'s existing gating convention — pure
// presentation, no core / view-model change). Never shown for VOD / UPCOMING.
// As of rb-ios-live-entry-hide-viewer-count, display additionally requires
// `showViewerCount: Bool` (see VIEWER COUNT VISIBILITY FLAG below) — an
// independent AND-gate layered on top of this existing condition, not a
// replacement for it.
//
// VIEWER COUNT VISIBILITY FLAG (`showViewerCount`, iOS only, rb-ios-live-entry-
// hide-viewer-count): `showViewerCount: Bool` (default `true`) gates whether the
// viewer-count badge above may ever draw, on top of its existing `isLive &&
// item.showPvNum == 1` gate. Carousel row / video-shop grid / the two unaffected
// `FloatingWidgetView` consumers (`WidgetOverlayView`'s `.floating` content mode,
// `MinimalDesign.floatingPlayerCard`) MUST NOT pass this parameter, so they keep
// drawing the badge exactly as before this flag existed. `FloatingWidgetView`
// forwards its own same-named parameter straight through; `LivebuyLiveEntry`
// passes `showViewerCount: false` so its floating entry card never shows a
// viewer count, regardless of `showPvNum` / `watchNum`. Independent of
// `showTitle` / `productCard` — the three presentation axes never interact.
//
// PRODUCT-CARD MODES (rb-ios-widget-product-card-modes, design R14; the `below`
// placement was later reversed by design R17 / rb-ios-widget-product-card-below-slot-
// reposition; the colour scheme of BOTH modes was replaced by design R33 (2026-09-04)
// — `design/templates/minimal/widgets.jsx` `normalizeProductCardMode` /
// `LBPCardProductRow` / `LBPCardProductOverlay`). `POST /sdk/widget` carries a root
// `product_card` String (`inside` / `below` / `hidden`, backend default `inside`),
// raw-passed through core → `LBWidgetContent.productCard` → `WidgetModel.productCard`
// → this card's `productCard: String?` parameter:
//
//     inside (default)  a WHITE card overlay INSIDE the 9:16 thumbnail
//                       (`rgba(255,255,255,0.9)`, no border, 4pt corner radius,
//                       `#1a1a1a` product name, existing sale-color price token,
//                       44pt thumb — replaces the pre-R33 dark-glass treatment).
//                       `goods == nil` → the whole block is not drawn.
//     below             the product card moves OUTSIDE the thumbnail, landing UNDER
//                       THE TITLE — at the very bottom of the card. Same white-card
//                       vocabulary as `inside` (`rgba(255,255,255,0.9)`, no border,
//                       4pt corner radius, `#1a1a1a` name, sale-color price,
//                       36pt thumb) — replaces the pre-R33 `theme.surface.bgElev` +
//                       `stroke` treatment. `goods == nil` → an EQUAL-HEIGHT
//                       TRANSPARENT SPACER (fixed `belowRowHeight`) so cards in the
//                       same row / grid cell stay the same height; a POPULATED row
//                       no longer forces that fixed height (design R33 dropped the
//                       constraint — see EQUAL HEIGHT below).
//     hidden            no product card at all (neither overlay nor row, and NO
//                       spacer — every card in the surface is equally card-less).
//
// EQUAL HEIGHT (below mode, revised 2026-09-04 by design R33): only the `goods ==
// nil` TRANSPARENT SPACER uses the FIXED constant `belowRowHeight` (design
// `LB_BELOW_ROW_H = 44`). A POPULATED `below` row NO LONGER forces that height — it
// grows with its content (thumb + text), typically shorter than 44pt. This means a
// bound and an unbound `below` card in the same row/grid can now be different total
// heights — a deliberate, user-approved design decision (R33), not a regression.
//
// The LIVE tag (+ optional viewer badge) / pin badge / upcoming veil / title are
// IDENTICAL across all three product-card modes.
//
// FALLBACK IS THIS LAYER'S JOB: core deliberately does NOT substitute the backend
// default (`widget-decode-robustness` — `nil` means "the backend sent nothing",
// which is a different fact from `"inside"`), and neither does the view-model layer.
// `LBProductCardMode.normalized(_:)` is the SINGLE pure entry point that maps
// anything that is not exactly `"below"` / `"hidden"` (including `nil`, `""`,
// whitespace-padded and differently-cased spellings, and any unknown string) to
// `.inside`. It MUST NOT be duplicated in the view body, and the normalized value
// MUST NOT be written back into `WidgetModel` / `LBWidgetContent` / core.
//
// TITLE VISIBILITY (rb-ios-floating-widget-hide-title): `showTitle: Bool` (default `true`)
// gates whether `item.title` is drawn below the thumbnail. Carousel row / video-shop grid
// (the two `WidgetModel`-bound consumers) MUST NOT pass this parameter, so they keep the
// pre-existing byte-identical rendering. `FloatingWidgetView` passes `showTitle: false`:
// the design source for that surface, `sdk-components.jsx` `LBPFloatingWidget`, has no
// title element at all, so the title on the reused card was purely an artifact of reusing
// this primitive as the floating card's body — not something the design ever called for.
// `false` removes the title element from the view tree entirely (not a blank-space
// placeholder), so the card's intrinsic height shrinks by the title's height AND its
// leading spacing. Independent of `productCard` / the below-row equal-height rule — the
// two axes never interact.
//
// KIND MAPPING (three-way: LIVE → UPCOMING → VOD). The core `LBVideoItem` carries
// `liveStatus: Int` + `type: Int` + `publishAt: String` (UTC+8):
//     `liveStatus == 1`                          → LIVE tag (+ optional viewer badge).
//     `liveStatus == 0 && type == 2` (直播)       → UPCOMING (直播預告): dark veil + centre
//        && `publishAt` parses                     scheduled date + big time.
//     otherwise (incl. `type == 1` regular VOD,  → VOD: no kind badge (2026-09-04 design
//        `type == 3` replay, or unparseable publishAt)  R33 removed the duration pill this
//                                                  branch used to draw).
//
// WHY `type == 2` (not a future-`publishAt` heuristic): `liveStatus == 0` is shared by BOTH a
// regular VOD (`type == 1`, never a livestream) AND a scheduled live (`type == 2`, not yet
// started). Only `type == 2 && liveStatus == 0` is a「尚未開播的直播」= upcoming. The earlier
// future-`publishAt` heuristic flipped an upcoming card to VOD the moment its scheduled time
// PASSED (host running late) — rb-ios-widget-upcoming-persist fixes that: an upcoming card keeps
// showing the scheduled time AS LONG AS `liveStatus == 0 && type == 2`, regardless of clock time
// (and the detection no longer touches `Date()` → fully deterministic). `replay` (liveStatus==3)
// is excluded by `liveStatus == 0`.
//
// One-way data flow: this primitive reads ONLY its passed-in `item` + `theme` +
// `productCard`; it
// never reaches back into `WidgetModel` / `DefaultWidgetTemplate`. The tap exit is
// host-wired (`onTap`) — the card NEVER opens the player / calls core itself
// (design §"守住的不變式": 互動一律 host-wired exit 轉發). It renders correctly with
// `onTap` nil (so demo / snapshot tests construct it action-free).
//
// iOS-14-safe SwiftUI only. `VStack` / `HStack` / `ZStack` / `RoundedRectangle` /
// `LinearGradient` / `Text` / `Image(systemName:)` / `Button` / `.aspectRatio` are
// all iOS-13+. NO `AsyncImage` / `.task` / `.foregroundStyle` / `.tint`.

// MARK: - LBProductCardMode — the single fallback entry point (normalizeProductCardMode)

/// Where (and whether) the widget card draws its product card. The iOS counterpart
/// of the design's `LB_PRODUCT_CARD_MODES` + `normalizeProductCardMode`
/// (`design/templates/minimal/widgets.jsx`).
///
/// The wire value (`product_card`) is a raw passthrough `String?` all the way from
/// core; this enum is where it becomes a closed set, so the view body can `switch`
/// exhaustively and the compiler flags every unhandled site if the domain ever grows.
public enum LBProductCardMode: String {
    /// White card overlay INSIDE the 9:16 thumbnail (backend default, and the
    /// fallback for everything unrecognized). See `productOverlay(_:)`.
    case inside
    /// A surface-styled product row OUTSIDE the thumbnail, under the title (card bottom).
    case below
    /// No product card at all.
    case hidden

    /// THE ONLY place a raw `product_card` value becomes a mode. Mirrors the design's
    /// `normalizeProductCardMode(raw)` (`raw === 'below' || raw === 'hidden' ? raw :
    /// 'inside'`) EXACTLY — the comparison is strict, with no trimming and no case
    /// folding, so `" below "` / `"BELOW"` fall back to `.inside` just like any other
    /// unknown string. Being deliberately as strict as the design keeps the four
    /// platforms' fallback boundary identical precisely when the backend emits
    /// something malformed, which is when a divergence would be hardest to spot.
    ///
    /// `nil` (the backend sent nothing — absent key / JSON null / `/sdk/widget/live` /
    /// nothing loaded yet) also lands on `.inside`, WITHOUT that default ever being
    /// written back into the view-model (core's `nil` semantics are preserved).
    public static func normalized(_ raw: String?) -> LBProductCardMode {
        switch raw {
        case LBProductCardMode.below.rawValue: return .below
        case LBProductCardMode.hidden.rawValue: return .hidden
        default: return .inside
        }
    }
}

/// The shared family-5 widget card (`LBPCarouselCard`): a 9:16 thumbnail
/// placeholder + LIVE / VOD kind badge + a product card placed per `product_card`
/// (`inside` overlay / `below` row / `hidden`) + the title below. `onTap` is a
/// host-wired exit (the card never opens the player itself).
public struct CarouselCardView: View {

    /// The video this card renders (read-only — `cover` / `title` / `duration` /
    /// `liveStatus` / `goods`). Read-only; this layer never mutates / re-fetches.
    public let item: LBVideoItem

    /// The resolved reference-ui theme (FIRST positional-after-data argument; the
    /// card's title uses `theme.text`, badges / pin / viewer / product-card colors
    /// use FIXED design tokens per the design's literal color values).
    public let theme: ReferenceUITheme

    /// Card width (pt). Defaults to the design's `132`. The thumbnail height is
    /// derived 9:16. The minimized surface passes a smaller width (e.g. 96).
    public let width: CGFloat

    /// Runtime media gate. `false` (the default — every demo / snapshot / preview
    /// construction) → the thumbnail ALWAYS draws the deterministic placeholder
    /// chip (no `AVPlayer`, no async network fetch), so `ImageRenderer` snapshot
    /// baselines stay byte-identical. `true` (host runtime) → the thumbnail loads
    /// `preview` (animated) → `cover` (static) → placeholder. See spec
    /// `reference-ui-rendering` (family-5 widget card).
    public let live: Bool

    /// RAW `product_card` wire value (`WidgetModel.productCard`), carried verbatim —
    /// this card does NOT expect a pre-normalized value, so every call site is a plain
    /// hand-off and the fallback stays in ONE place (`productCardMode`). `nil` (the
    /// default, and what every existing call site / preview / snapshot passes) →
    /// `.inside` → pixels identical to before this parameter existed.
    public let productCard: String?

    /// Whether to draw the title below the thumbnail (`item.title`). **Default `true`**
    /// (carousel row / video-shop grid — the two `WidgetModel`-bound consumers — MUST NOT
    /// pass this parameter, so they keep drawing the title exactly as before this
    /// parameter existed). `false` (used by `FloatingWidgetView`, rb-ios-floating-widget-
    /// hide-title) means the title element does NOT exist in the view tree at all — it is
    /// NOT an empty-string / blank-space placeholder, and the card's intrinsic height
    /// shrinks accordingly (no fixed-height reservation): the design source for the
    /// floating surface, `sdk-components.jsx` `LBPFloatingWidget`, has no title element to
    /// begin with, so this flag lets that one consumer opt OUT of a feature the shared
    /// primitive draws by default — the same shape as the existing `productCard: String?`
    /// parameter (carousel/grid opt IN to a feature via a non-default value; here floating
    /// opts OUT via a non-default value). Independent of `productCard` — the two axes do
    /// not interact.
    public let showTitle: Bool

    /// Whether the LIVE-only viewer-count badge (`viewerCountBadge`) may ever draw
    /// (rb-ios-live-entry-hide-viewer-count). **Default `true`** — carousel row /
    /// video-shop grid, and the two `FloatingWidgetView` consumers that keep the
    /// existing behavior (`WidgetOverlayView`'s `.floating` content mode,
    /// `MinimalDesign.floatingPlayerCard`), **MUST NOT** pass this parameter, so
    /// they keep the badge's pre-existing `isLive && item.showPvNum == 1` gate as
    /// the sole condition. `false` (used by `FloatingWidgetView` when constructed
    /// by `LivebuyLiveEntry`) means the badge **MUST NOT** draw regardless of
    /// `showPvNum` / `watchNum` — an AND-gate layered on top of the existing
    /// condition, not a replacement for it. See VIEWER COUNT VISIBILITY FLAG above.
    public let showViewerCount: Bool

    /// Card tap → host-wired exit (→ host → core open player for `item.id`). nil for
    /// demo / snapshot instances — the card is inert. This layer NEVER opens the
    /// player / calls core simulate* itself.
    private let onTap: (() -> Void)?

    public init(
        item: LBVideoItem,
        theme: ReferenceUITheme,
        width: CGFloat = 132,
        live: Bool = false,
        productCard: String? = nil,
        showTitle: Bool = true,
        showViewerCount: Bool = true,
        onTap: (() -> Void)? = nil
    ) {
        self.item = item
        self.theme = theme
        self.width = width
        self.live = live
        self.productCard = productCard
        self.showTitle = showTitle
        self.showViewerCount = showViewerCount
        self.onTap = onTap
    }

    /// The resolved product-card mode. The ONE call of `LBProductCardMode.normalized(_:)`
    /// in this view — every branch below switches on this, never on the raw string.
    private var productCardMode: LBProductCardMode {
        LBProductCardMode.normalized(productCard)
    }

    /// Whether `item` is a LIVE card. `liveStatus == 1` → live (red LIVE tag).
    private var isLive: Bool { item.liveStatus == 1 }

    /// Whether `item` is an UPCOMING card (直播預告): a scheduled LIVE (`type == 2`) that has
    /// not started yet (`liveStatus == 0`) and whose `publishAt` parses (UTC+8) to a displayable
    /// time. Uses `type == 2` — NOT a future-`publishAt` heuristic — so the card keeps showing
    /// the scheduled time even after that time PASSES (host running late); a regular VOD
    /// (`type == 1`) stays VOD. Time-independent → no `Date()` (rb-ios-widget-upcoming-persist).
    private var isUpcoming: Bool {
        item.liveStatus == 0
            && item.type == 2
            && UpcomingCountdownView.parseUTC8(item.publishAt) != nil
    }

    public var body: some View {
        Button(action: { onTap?() }) {
            VStack(alignment: .leading, spacing: 8) {
                thumbnail
                // `showTitle` gate (rb-ios-floating-widget-hide-title): `true` (default,
                // carousel/grid) draws the title exactly as before this flag existed;
                // `false` (floating) omits the element entirely — a nil optional view
                // contributes no height AND no spacing (same pattern as `drawsBelowRow`
                // just below), so the card gets shorter rather than leaving a blank gap.
                if showTitle {
                    title
                }
                // `below` ONLY — the product card sits UNDER THE TITLE, at the very
                // bottom of the card (design R17, 2026-08-11: upstream reversed its own
                // 2026-08-05 decision, which had put this slot BETWEEN the thumbnail and
                // the title; `widgets.jsx` `LBPCarouselCard` now orders its children
                // thumbnail → title → `LBPCardProductRow`). `inside` / `hidden`
                // contribute nothing here, so the `VStack` lays out exactly as it did
                // before this mode existed (a nil optional view adds no spacing).
                if drawsBelowRow {
                    belowProductSlot
                }
            }
            .frame(width: width)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Mode-derived drawing decisions (exhaustive — no `default`)
    //
    // Both gates switch EXHAUSTIVELY over `LBProductCardMode`, so growing the domain
    // is a compile error here rather than a silently-unhandled mode. The raw wire
    // string is never compared outside `LBProductCardMode.normalized(_:)`.

    /// `inside` → the white product-card overlay is drawn inside the 9:16 thumbnail.
    private var drawsInsideOverlay: Bool {
        switch productCardMode {
        case .inside: return true
        case .below, .hidden: return false
        }
    }

    /// `below` → a product row (or its equal-height transparent spacer) is drawn
    /// under the title, at the bottom of the card (design R17).
    private var drawsBelowRow: Bool {
        switch productCardMode {
        case .below: return true
        case .inside, .hidden: return false
        }
    }

    // MARK: - Thumbnail (9:16, placeholder + kind badge + pin badge + product overlay)
    //
    // Mirrors LBPCarouselCard's thumbnail block: a 9:16 rounded media area with the
    // kind badge top-left, the pin badge top-right, and the white product-card
    // overlay anchored bottom.

    private var thumbnail: some View {
        ZStack(alignment: .topLeading) {
            // 9:16 media thumbnail. `live == false` (snapshot / demo) → always the
            // deterministic placeholder chip. `live == true` (runtime) → `preview`
            // (animated) → `cover` (static) → placeholder. See `mediaThumbnail`.
            mediaThumbnail

            // UPCOMING (直播預告): a full-bleed dark veil + centred「即將開播」+ a
            // 距開播 countdown (design's upcoming = dark mask + centre countdown).
            // VOD / UPCOMING draw no top-left kind badge at all (see kindBadge).
            if isUpcoming {
                upcomingOverlay
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier(LBAccessibilityID.cardUpcomingOverlay)
            }

            // Kind badge top-left: LIVE red tag (+ optional viewer-count badge).
            // VOD / UPCOMING draw nothing here (2026-09-04 design R33 removed the
            // VOD duration pill; upcoming was already indicated by the centre
            // `upcomingOverlay`, never by a top-left badge).
            kindBadge
                .padding(6)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(LBAccessibilityID.cardKindBadge)

            // Bottom white product-card overlay — `inside` mode only (`below` draws
            // the row outside the thumbnail, `hidden` draws nothing), and only when
            // goods != nil (an unbound card keeps a clean thumbnail).
            if drawsInsideOverlay, let goods = item.goods {
                VStack {
                    Spacer(minLength: 0)
                    productOverlay(goods)
                        .padding(.horizontal, 6)
                        .padding(.bottom, 6)
                }
            }
        }
        .frame(width: width, height: width * 16.0 / 9.0)
        // Pin badge top-right (rb-ios-carousel-card-pin-viewers-duration-removal,
        // design R33): `.overlay(_:alignment:)` (the iOS-13+ non-closure overload,
        // matching this codebase's existing convention — e.g. `MiniCartView`'s
        // `closeButton`) positions it independently of the ZStack's `.topLeading`
        // alignment used by `kindBadge` / `upcomingOverlay`. Independent of
        // `kindBadge` — any of LIVE / VOD / UPCOMING can carry it simultaneously.
        // `pinBadge` itself is an EmptyView when `item.pin != 1`, so this overlay
        // costs zero pixels when the video is not pinned.
        .overlay(pinBadge.padding(6), alignment: .topTrailing)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// The gated 9:16 media thumbnail. `live == false` → always the deterministic
    /// placeholder (snapshot-safe, no `AVPlayer` / network). `live == true` →
    /// `preview` (non-empty) animated loop → `cover` (non-empty) static still →
    /// placeholder (both empty). The placeholder sits behind the runtime media so a
    /// neutral chip shows while a still / first video frame loads, and empty-string
    /// `preview` / `cover` simply fall through (no broken image, no crash).
    @ViewBuilder
    private var mediaThumbnail: some View {
        if live, let url = previewURL {
            ZStack {
                coverPlaceholder
                LoopingVideoView(url: url)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(LBAccessibilityID.loopingPreview)
        } else if live, let url = coverURL {
            ZStack {
                coverPlaceholder
                RemoteStillImageView(url: url, contentMode: .scaleAspectFill)
            }
        } else {
            coverPlaceholder
        }
    }

    /// `item.preview` as a non-empty URL, or nil. Empty-string `preview` (common for
    /// LIVE items) → nil (absent), so the thumbnail falls through to `cover`.
    private var previewURL: URL? {
        let s = item.preview.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : URL(string: s)
    }

    /// `item.cover` as a non-empty URL, or nil. Empty-string `cover` → nil (absent),
    /// so the thumbnail falls through to the placeholder.
    private var coverURL: URL? {
        let s = item.cover.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : URL(string: s)
    }

    /// 9:16 deterministic cover placeholder — gradient + monogram of the title (no
    /// remote image; the both-empty / snapshot fallback). Mirrors the design's
    /// `<ProductMock>` rounded media chip.
    private var coverPlaceholder: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(hex: "#3A3A44") ?? .gray,
                    Color(hex: "#111118") ?? .black,
                ]),
                startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(Self.monogram(for: item.title))
                .font(.system(size: 28 * theme.fontScale, weight: .heavy))
                .foregroundColor(.white.opacity(0.85))
        }
    }

    // MARK: - Kind badge (LIVE tag + optional viewer-count badge — VOD/UPCOMING draw nothing)
    //
    // 2026-09-04 design R33 removed the VOD「▶ mm:ss」duration pill that used to occupy
    // this slot (rb-ios-carousel-card-pin-viewers-duration-removal). UPCOMING was
    // already indicated by the centred `upcomingOverlay`, never by a top-left badge —
    // so with the VOD branch gone, `isLive` is the ONLY case this view draws anything
    // for. Written as a single `if` (no `else`): `@ViewBuilder` implicitly returns
    // `EmptyView()` for the untaken branch, which is a more honest reflection of
    // "VOD / UPCOMING have no kind badge" than keeping two now-always-empty branches
    // around. `isUpcoming` itself (the `upcomingOverlay` trigger) is untouched.

    @ViewBuilder
    private var kindBadge: some View {
        if isLive {
            HStack(spacing: 6) {
                liveTag
                viewerCountBadge
            }
        }
    }

    // MARK: - Upcoming overlay (直播預告: design `LBPCarouselCard` upcoming — dark mask + date + time)

    /// Aligned to the design's `LBPCarouselCard` upcoming treatment: a `rgba(0,0,0,0.25)`
    /// dark mask over the thumbnail + a centred「scheduled DATE」(small) +「scheduled TIME」
    /// (big) — NO「即將開播」label and NO ticking「距開播」countdown. Date / time are pure
    /// string reformats of `publishAt` (shared with `UpcomingCountdownView`) → deterministic,
    /// no `Timer` → byte-stable baseline.
    private var upcomingOverlay: some View {
        ZStack {
            Color.black.opacity(0.25)
            VStack(spacing: 8) {
                let date = UpcomingCountdownView.scheduledDate(item.publishAt)
                if !date.isEmpty {
                    Text(date)
                        .font(.system(size: 11 * theme.fontScale, weight: .semibold))
                        .foregroundColor(.white)
                }
                Text(UpcomingCountdownView.scheduledTime(item.publishAt))
                    .font(.system(size: 26 * theme.fontScale, weight: .heavy).monospacedDigit())
                    .foregroundColor(.white)
            }
            .shadow(color: Color.black.opacity(0.55), radius: 4, x: 0, y: 2)
            .padding(6)
        }
    }

    /// LIVE red tag (LBPCarouselCard 180-192): a static pulse dot + 「LIVE」on the
    /// brand-red surface. The pulse animation is drawn statically (snapshot-safe).
    private var liveTag: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color.white)
                .frame(width: 4, height: 4)
            Text(Self.liveLabel)
                .font(.system(size: 10 * theme.fontScale, weight: .heavy))
                .foregroundColor(.white)
                .kerning(0.6)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Self.liveRed))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(LBAccessibilityID.cardLiveBadge)
    }

    // MARK: - Viewer-count badge (LIVE only, rb-ios-carousel-card-pin-viewers-duration-removal)

    /// Viewer-count pill beside `liveTag` (design `LBPCarouselCard` R33): a person
    /// icon + `LBVideoItem.watchNum` RAW digits (deliberately NOT the K-abbreviated
    /// `PlayerHeaderBarView.formatViewerCount` — the design shows the bare number, and
    /// that formatter belongs to a different family-1 component). Shown ⟺
    /// `showViewerCount && isLive && item.showPvNum == 1` (the `isLive &&
    /// item.showPvNum == 1` half mirrors `PlayerHeaderBarView.viewerCountVisible`'s
    /// existing gating convention — pure presentation, no core / view-model change;
    /// `showViewerCount` is an independent AND-gate layered on top,
    /// rb-ios-live-entry-hide-viewer-count — see VIEWER COUNT VISIBILITY FLAG in the
    /// file header doc comment). `EmptyView()` when the gate is false, so
    /// `kindBadge`'s `HStack { liveTag; viewerCountBadge }` costs zero extra pixels /
    /// spacing when there is no viewer count to show — pixel-identical to the badge
    /// being naturally absent via `showPvNum == 0`.
    @ViewBuilder
    private var viewerCountBadge: some View {
        if showViewerCount && isLive && item.showPvNum == 1 {
            HStack(spacing: 3) {
                Image(systemName: "person.fill")
                    .font(.system(size: 9, weight: .semibold))
                Text("\(item.watchNum)")
                    .font(.system(size: 10 * theme.fontScale, weight: .bold))
            }
            .foregroundColor(.white)
            .padding(.leading, 5)
            .padding(.trailing, 7)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 999)
                    .fill(Color.black.opacity(0.4)))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(LBAccessibilityID.cardViewerCountBadge)
        }
    }

    // MARK: - Pin badge (top-right, rb-ios-carousel-card-pin-viewers-duration-removal)

    /// Top-right「置頂」badge (design `LBPCarouselCard` R33): `LBVideoItem.pin == 1`
    /// gates a white thumbtack glyph, independent of `kindBadge` — LIVE / VOD /
    /// UPCOMING can all carry it simultaneously. SF Symbol `pin.fill` renders as a
    /// thumbtack (distinct from the `mappin.*` balloon family), a close visual match
    /// for the design's inline SVG (FontAwesome `thumbtack`). This is a DIFFERENT
    /// glyph from `Glyphs/PinFillGlyph.swift` (a hand-drawn map-pin BALLOON silhouette
    /// used by `ChatFeedView`'s pinned-MESSAGE banner — a different feature with a
    /// different shape) — this property MUST NOT reuse or modify that file.
    /// `EmptyView()` when `item.pin != 1`, so the `.overlay` at the `thumbnail` call
    /// site costs zero pixels for an unpinned video.
    @ViewBuilder
    private var pinBadge: some View {
        if item.pin == 1 {
            Image(systemName: "pin.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier(LBAccessibilityID.cardPinnedBadge)
        }
    }

    // MARK: - Bottom white product-card overlay (`inside` mode, goods != nil)

    /// White product-card overlay (`LBPCardProductOverlay`, design R33, 2026-09-04): a
    /// 44×44 product thumb + the product name (1-line, `#1a1a1a`) + the display price
    /// (existing sale-color token), on a `rgba(255,255,255,0.9)` surface with NO
    /// border, 4pt corner radius. Replaces the pre-R33 dark-glass + white-text
    /// treatment (same white-card vocabulary as `belowProductRow(_:)`). The thumb
    /// binds `goods.pic` on the `live == true` runtime path (gradient chip as the
    /// loading / empty fallback); `live == false` (snapshot / demo) keeps the gradient
    /// chip so baselines stay byte-identical. The price is produced by
    /// `displayPrice(_:)` (defensive prefix — no double currency).
    private func productOverlay(_ goods: LBFeaturedGood) -> some View {
        HStack(spacing: 6) {
            productThumb(goods, size: 44)

            VStack(alignment: .leading, spacing: 1) {
                Text(goods.name)
                    .font(.system(size: 10 * theme.fontScale, weight: .semibold))
                    .foregroundColor(Self.productCardTextColor)
                    .lineLimit(1)
                Text(Self.displayPrice(goods.price))
                    .font(.system(size: 10 * theme.fontScale, weight: .heavy))
                    .foregroundColor(Self.saleColor)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.trailing, 7)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Self.productCardBackground))
    }

    /// Square product thumb chip (`44` inside the `inside` overlay, `36` in the
    /// `below` row — design R33 enlarged both from their pre-R33 `24` / `32`).
    /// `live == true` + non-empty `goods.pic` → the remote product image
    /// (`RemoteStillImageView`, iOS-14-safe — NOT `AsyncImage`, `scaleAspectFill` so the
    /// image fills the chip edge-to-edge, no letterboxing — aligned with the
    /// in-player product cards' cover treatment, rb-ios-widget-carousel-card-image-cover),
    /// with the deterministic gradient chip behind it as the loading / pre-load
    /// fallback. `live == false` (snapshot / demo) or empty `pic` → the gradient chip
    /// alone, so snapshot baselines stay placeholder-only and byte-identical.
    @ViewBuilder
    private func productThumb(_ goods: LBFeaturedGood, size: CGFloat) -> some View {
        if live, let url = productPicURL(goods) {
            ZStack {
                thumbPlaceholder(size: size)
                RemoteStillImageView(url: url, contentMode: .scaleAspectFill)
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 5))
        } else {
            thumbPlaceholder(size: size)
        }
    }

    /// Deterministic gradient thumb chip (the design's `<ProductMock>` stand-in).
    private func thumbPlaceholder(size: CGFloat = 24) -> some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: [
                        ReferenceUIProductPlaceholderPalette.top,
                        ReferenceUIProductPlaceholderPalette.bottom,
                    ]),
                    startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
    }

    // MARK: - Card-bottom product row (`below` mode, LBPCardProductRow)

    /// The `below` slot — laid out UNDER THE TITLE, at the bottom of the card (design
    /// R17): the surface-styled product row, or — when the video has no featured good —
    /// an EQUAL-HEIGHT TRANSPARENT SPACER. The spacer (design's
    /// `aria-hidden` empty div) is what keeps cards in the same carousel row / grid
    /// cell the same height without drawing an empty frame. `Color.clear` with a fixed
    /// height, NOT a `Spacer()` (which would absorb the container's free space).
    /// **This spacer is the ONLY thing in `below` mode still pinned to
    /// `belowRowHeight`** — design R33 (2026-09-04) dropped the matching constraint
    /// on the POPULATED row (see `belowProductRow(_:)`), so a bound and an unbound
    /// `below` card can now be different total heights (accepted, R33).
    @ViewBuilder
    private var belowProductSlot: some View {
        if let goods = item.goods {
            belowProductRow(goods)
        } else {
            Color.clear.frame(height: Self.belowRowHeight)
        }
    }

    /// White product-card row (`LBPCardProductRow`, design R33, 2026-09-04): a 36×36
    /// product thumb + the product name (1-line, `#1a1a1a`) + the sale price + an
    /// optional struck-through original price, on a `rgba(255,255,255,0.9)` surface
    /// with NO border, 4pt corner radius — same white-card vocabulary as
    /// `productOverlay(_:)` (replaces the pre-R33 `theme.surface.bgElev` fill +
    /// `theme.surface.stroke` border treatment). **Height is NO LONGER the fixed
    /// `belowRowHeight` constant** — design R33 dropped that constraint for a
    /// POPULATED row (only the `goods == nil` spacer in `belowProductSlot` still uses
    /// it): this row grows with its content (thumb height + text block), typically
    /// shorter than 44pt. A bound and an unbound `below` card can therefore end up
    /// different total heights — a deliberate design decision, not a bug.
    private func belowProductRow(_ goods: LBFeaturedGood) -> some View {
        HStack(spacing: 7) {
            productThumb(goods, size: 36)

            VStack(alignment: .leading, spacing: 1) {
                Text(goods.name)
                    .font(.system(size: 11 * theme.fontScale, weight: .semibold))
                    .foregroundColor(Self.productCardTextColor)
                    .lineLimit(1)
                belowPriceLine(goods)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.trailing, 7)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Self.productCardBackground))
    }

    /// The `below` row's price line: sale price + optional struck-through original
    /// price, baseline-aligned like the design. Both run through the same
    /// `displayPrice(_:)` de-duplication; an empty `originalPrice` draws nothing.
    ///
    /// The sale price takes layout priority: at the design's 132pt card width the two
    /// prices together can exceed the text column, and the design (HTML) simply lets
    /// the line overflow. SwiftUI cannot overflow, so without a priority BOTH prices
    /// truncate to「NT$…」and the card shows no readable price at all. Prioritizing the
    /// sale price keeps the primary figure intact and lets the secondary struck-through
    /// original price absorb the squeeze instead.
    private func belowPriceLine(_ goods: LBFeaturedGood) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(Self.displayPrice(goods.price))
                .font(.system(size: 11 * theme.fontScale, weight: .heavy))
                .foregroundColor(Self.saleColor)
                .lineLimit(1)
                .layoutPriority(1)
            if let original = Self.strikePrice(goods.originalPrice) {
                Text(original)
                    .font(.system(size: 10 * theme.fontScale, weight: .semibold))
                    .foregroundColor(Self.textFaint)
                    .strikethrough()
                    .lineLimit(1)
            }
        }
    }

    /// `goods.pic` as a non-empty URL, or nil (empty string → absent). Mirrors the
    /// `coverURL` / `previewURL` guard so an empty `pic` falls through to the chip.
    private func productPicURL(_ goods: LBFeaturedGood) -> URL? {
        let s = goods.pic.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : URL(string: s)
    }

    // MARK: - Title (below thumbnail)

    /// The video title below the thumbnail (LBPCarouselCard 218-224), 1-line clamp,
    /// painted with `theme.text` (the card sits on the host surface, not the dark
    /// thumbnail). Gated by `showTitle` at the call site in `body` — this computed
    /// property itself is unconditional; when `showTitle == false` it is simply never
    /// referenced, so it is never built (rb-ios-floating-widget-hide-title).
    private var title: some View {
        Text(item.title)
            .font(.system(size: 12 * theme.fontScale, weight: .semibold))
            .foregroundColor(theme.text)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Helpers

    /// The display price string from the raw `LBFeaturedGood.price` (core raw
    /// passthrough). The production wire value already carries the currency symbol
    /// (e.g. `"NT$590"`), so prefixing again would render a double currency
    /// (`"NT$ NT$590"`). Defensive rule: trim → empty stays empty; a value that
    /// STARTS WITH A DIGIT (a bare number like `"880"` / `"2,480"`) gets the
    /// `"NT$ "` prefix (preserving the demo / bare-number fixtures); otherwise (a
    /// leading currency symbol / letter — the value already contains the currency)
    /// it is rendered VERBATIM. This layer does not interpret currency semantics
    /// beyond this de-duplication (core passthrough stays authoritative).
    static func displayPrice(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "" }
        return first.isNumber ? pricePrefix + trimmed : trimmed
    }

    /// The `below` row's struck-through ORIGINAL price, or nil when there is nothing
    /// to strike. Reuses `displayPrice(_:)` (same currency de-duplication), and maps
    /// the "trimmed to empty" case to nil so the caller draws no struck-through label
    /// at all rather than an empty one. Only the `below` row shows an original price —
    /// the `inside` overlay never has (design `LBPCardProductOverlay`).
    static func strikePrice(_ raw: String) -> String? {
        let shown = displayPrice(raw)
        return shown.isEmpty ? nil : shown
    }

    /// First non-whitespace character of a title, uppercased, for the placeholder
    /// monogram. Falls back to a play glyph stand-in when empty.
    static func monogram(for title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "▶" }
        return String(first).uppercased()
    }

    // MARK: - Decorative design tokens (literal widgets.jsx hex via Color(hex:))

    /// Brand-red LIVE tag surface (`#F03246`, LBPCarouselCard 185).
    static let liveRed = Color(hex: "#F03246") ?? .red

    /// White product-card surface (`rgba(255,255,255,0.9)`, design R33 2026-09-04),
    /// shared by BOTH `inside` (`productOverlay(_:)`) and `below`
    /// (`belowProductRow(_:)`) — the two modes were unified onto the same white-card
    /// vocabulary this design revision, replacing the pre-R33 dark-glass (`inside`)
    /// and `theme.surface.bgElev` + `stroke` (`below`) treatments (`productGlass` /
    /// `belowRowBackground` / `belowRowStroke` retired, no border in either mode now).
    static let productCardBackground = Color.white.opacity(0.9)
    /// Product-card name text color (`#1a1a1a`, design R33), shared by `inside` and
    /// `below` — replaces `inside`'s prior `.white` and `below`'s prior resolved
    /// `theme.text`.
    static let productCardTextColor = Color(hex: "#1a1a1a") ?? .black

    // `below` row / `inside` overlay shared price tokens. iOS `ReferenceUITheme` is a
    // 5-token thin palette with no surface / sale entries, so — following the existing
    // convention in `ProductListView` / `WinClaimModalView` / `NotifyRestockSheetView`
    // — the design's tokens are pinned here as LIGHT-MODE literals from
    // `design/brands/livebuy/tokens.jsx`.
    //
    // NOTE: `ProductListView.saleColor` carries an older `#E0334B`; the value below is
    // the one `tokens.jsx` currently defines for `theme.sale`. Converging the two is a
    // separate token-drift question and is NOT done here (it would move existing
    // family-3 baselines).

    /// Fixed height of `below` mode's no-goods TRANSPARENT SPACER ONLY (design
    /// `LB_BELOW_ROW_H = 44`). Design R33 (2026-09-04) dropped the matching constraint
    /// on the POPULATED `below` row (`belowProductRow(_:)` no longer pins its height to
    /// this constant — it grows with content instead), so a bound and an unbound
    /// `below` card can now be different total heights (accepted, R33).
    static let belowRowHeight: CGFloat = 44
    /// `theme.sale` — both `inside` and `below` product-card sale price (design R33
    /// unified `inside`'s prior plain `.white` price onto this same token).
    static let saleColor = Color(hex: "#F03246") ?? .red
    /// `theme.surface.textFaint` — the `below` row's struck-through original price.
    static let textFaint = Color(hex: "#9A9BA5") ?? Color.gray.opacity(0.5)

    // MARK: - Fixed presentation strings

    static let liveLabel = "LIVE"
    /// Default currency prefix, applied by `displayPrice(_:)` ONLY to bare-number
    /// values (a symbol-bearing wire value is rendered verbatim — no double currency).
    static let pricePrefix = "NT$ "
}

// MARK: - Deterministic demo data (previews + snapshot tests)
//
// Shared deterministic `LBVideoItem` fixtures so the family-5 surfaces' previews
// and snapshot tests render identical, stable cards without a live widget. All use
// the VERIFIED public `LBVideoItem` (18 params) + `LBFeaturedGood` (7 params) inits
// reachable from `LivebuyReferenceUI`. The surface agents (carousel / grid /
// floating / minimized) MUST reuse these so fixtures stay consistent.

public extension LBVideoItem {

    /// A deterministic demo `LBVideoItem`. `live` toggles the LIVE vs VOD kind
    /// (`liveStatus` 1 vs 0); `goods` non-nil draws the bottom product overlay.
    /// `upcoming` (with `live == false`) renders the UPCOMING (直播預告) treatment via
    /// `type == 2` (直播) + `liveStatus == 0` — rb-ios-widget-upcoming-persist. `type` is
    /// `2` for the live / upcoming kinds (直播) and `1` for the VOD kind (一般), so the kind
    /// detection (`liveStatus == 1` → LIVE; `liveStatus == 0 && type == 2` → UPCOMING;
    /// else → VOD) reproduces the prior baselines byte-identically.
    static func demo(
        id: String = "demo-vid-001",
        title: String = "週五美妝直播・新品開箱",
        live: Bool = false,
        upcoming: Bool = false,
        duration: Int = 754,
        goods: LBFeaturedGood? = .demo(),
        liveurl: String = "",
        pin: Int = 0,
        watchNum: Int = 0,
        showPvNum: Int = 0
    ) -> LBVideoItem {
        LBVideoItem(
            id: id,
            type: (upcoming || live) ? 2 : 1,
            title: title,
            sessionName: nil,
            cover: "",
            preview: "",
            duration: duration,
            publishAt: upcoming ? "2099-01-01 20:00:00" : "2026-06-06 20:00:00",
            watchNum: watchNum,
            pvNum: 0,
            liveStatus: live ? 1 : 0,
            pin: pin,
            showPvNum: showPvNum,
            liveurl: liveurl,
            playbackurl: "",
            previewTime: "",
            showStock: false,
            goods: goods)
    }
}

public extension LBFeaturedGood {

    /// A deterministic demo featured good (`LBFeaturedGood`). `price` is a raw
    /// `String`; a bare number (the default `"880"`) renders as「NT$ 880」via
    /// `displayPrice(_:)`. `pic` defaults to "" so demo / snapshot keep the gradient
    /// thumb chip (the `goods.pic` image binding is live-runtime-only).
    static func demo(
        name: String = "玫瑰精華水",
        price: String = "880"
    ) -> LBFeaturedGood {
        LBFeaturedGood(
            name: name,
            pic: "",
            price: price,
            originalPrice: "1180",
            soldOut: 0,
            stock: 12,
            status: 1)
    }
}

// MARK: - Runtime media helper views (live == true only)
//
// These load real media and are constructed ONLY on the `live == true` runtime path
// (never in snapshot / demo). They are iOS-14-safe (AVQueuePlayer / AVPlayerLooper /
// AVPlayerLayer / UIImageView), file-private to this card primitive.

// MARK: - BACKGROUND / OFF-SCREEN DECODE STOP (ios-refui-widget-preview-lifecycle-pause)
//
// iOS parity of the "widget preview half" of Android `android-refui-player-lifecycle-pause`
// (`LoopingVideoView` / media3 `ExoPlayer`) and Flutter `flutter-refui-widget-preview-lifecycle-pause`
// (`LoopingVideoView` / `video_player`). Previously `LoopingPlayerUIView` called `player.play()`
// UNCONDITIONALLY in `configure()` and only `pause()`d in `teardown()` (on `dismantleUIView`), with
// NO app-lifecycle observer and NO off-screen probe. The widget uses non-lazy `HStack` / `VStack`
// containers (golden determinism — the spec forbids `Lazy*` on the `ImageRenderer` path), so a card
// scrolled out of the viewport stays MOUNTED and keeps decoding. A list of N live previews therefore
// = N `AVPlayer` decoders still running when the card is off-screen — the same source Android measured
// as ~150% background CPU on the consumer app.
//
// Two gaps closed here:
//   (A) app background — a `UIApplication.didEnterBackgroundNotification` /
//       `willEnterForegroundNotification` observer (imperative, UIKit-level — NOT SwiftUI-rebuild
//       driven) sets the gate's `foreground` flag. `didEnterBackground` fires only on a REAL
//       background (not transient inactive), matching the existing codebase convention (LivebuyPlayer
//       auto-PiP, `LivebuyPlayer.swift`) and Android `ON_STOP`. iOS also tends to suspend
//       `AVPlayerLayer` render in the background on its own, so this axis is defensive parity.
//   (B) off-screen — a SwiftUI `GeometryReader` + `PreferenceKey` visibility probe (parity with
//       Android `onGloballyPositioned` / `boundsInWindow` and Flutter `VisibilityDetector`): a card
//       whose (global) frame no longer overlaps the screen bounds is off-screen → pause. This is the
//       real gap (a scrolled-out card stays mounted).
//
// Both signals fold into ONE unified `foreground && onScreen` gate (`PreviewPlaybackController`,
// edge-triggered, imperative — it calls `queuePlayer?.play()` / `.pause()` directly, it does NOT
// tear down / rebuild the player view). A single gate (rather than two independent observers) is
// deliberate: otherwise returning to the foreground would wake a card that is still scrolled
// off-screen (mirrors the Android / Flutter decision). Because the current desired state is applied
// via `gate.reapply()` once the player is (re)configured, a card that mounts while backgrounded /
// off-screen does NOT start decoding.
//
// "Tab-cover" (host keeps the home widget mounted and merely COVERS it with another route: the card
// stays laid-out, its global frame still overlaps the screen, the app stays active) is NOT detectable
// from the widget layer alone (z-order coverage is invisible to `GeometryReader`, and coverage does not
// background the app) — the same platform limit Android / Flutter recorded. It is closed by a THIRD gate
// axis `notCovered`, fed by the opt-in host bridge `LivebuyWidgetVisibility.setWidgetsCovered(_:)`
// (ios-refui-widget-host-visibility-pause, iOS parity of Android `android-refui-widget-host-visibility-pause`):
// the host declares when the widget-hosting screen is covered, and each mounted preview pauses. A host
// that does NOT opt in leaves `notCovered == true`, so the gate degrades to `foreground && onScreen`
// and behaviour is byte-identical to before this bridge existed — the residual gap still exists when
// the host does not opt in (covered detection is the host's responsibility, not claimed as self-sufficient).
// This preview is NEVER PiP content, so — like Flutter — no PiP guard is needed.

/// A control-free, looping, muted video view for the animated `preview` thumbnail. Wraps an
/// `AVPlayerLayer`-backed `UIView` (`LoopingPlayerUIView`, resizeAspectFill, clipped by the card's
/// 9:16 rounded frame) and adds the off-screen half of the play-gate: a `GeometryReader` +
/// `PreferenceKey` visibility probe forwards `onScreen` into the player view (the background half is
/// observed inside `LoopingPlayerUIView`). Constructed ONLY on the `live == true` runtime path (never
/// in snapshot / demo) so golden baselines are untouched. `init(url:)` is unchanged (all call sites —
/// `CarouselCardView`, `EndScreenView` — keep working).
struct LoopingVideoView: View {
    let url: URL

    /// Whether the card currently overlaps the screen. Seeded `true` (a just-mounted card is assumed
    /// visible until the probe reports otherwise); driven by the `GeometryReader` preference below.
    @State private var onScreen: Bool = true

    var body: some View {
        LoopingPlayerRepresentable(url: url, onScreen: onScreen)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: OnScreenPreferenceKey.self,
                        value: Self.isCardOnScreen(
                            cardFrame: geo.frame(in: .global),
                            screenBounds: UIScreen.main.bounds))
                }
            )
            .onPreferenceChange(OnScreenPreferenceKey.self) { self.onScreen = $0 }
    }

    /// Pure visibility test (unit-testable): a card is on-screen when its (global) frame overlaps the
    /// screen bounds. A zero-area frame (pre-layout) is treated as NOT on-screen. Mirrors Android's
    /// `boundsInWindow()` intersect-with-window and Flutter's `visibleFraction > 0`.
    static func isCardOnScreen(cardFrame: CGRect, screenBounds: CGRect) -> Bool {
        guard cardFrame.width > 0, cardFrame.height > 0 else { return false }
        return cardFrame.intersects(screenBounds)
    }
}

/// The off-screen visibility signal, folded so ANY visible fragment counts as on-screen.
private struct OnScreenPreferenceKey: PreferenceKey {
    static var defaultValue: Bool = true
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

/// The `UIViewRepresentable` that hosts `LoopingPlayerUIView` and forwards the `onScreen` axis into
/// it (the background axis is observed inside the UIView). Kept private — `LoopingVideoView` is the
/// public entry the card / end-screen construct.
private struct LoopingPlayerRepresentable: UIViewRepresentable {
    let url: URL
    let onScreen: Bool

    func makeUIView(context: Context) -> LoopingPlayerUIView {
        let view = LoopingPlayerUIView(url: url)
        view.setOnScreen(onScreen)
        return view
    }

    func updateUIView(_ uiView: LoopingPlayerUIView, context: Context) {
        uiView.update(url: url)
        uiView.setOnScreen(onScreen)
    }

    static func dismantleUIView(_ uiView: LoopingPlayerUIView, coordinator: ()) {
        uiView.teardown()
    }
}

final class LoopingPlayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    private var queuePlayer: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var currentURL: URL?

    /// The unified `foreground && onScreen` play-gate. `onPlay` / `onPause` drive the (nullable)
    /// `queuePlayer` directly — imperative, never a view teardown. Bound weakly so it survives
    /// player re-`configure`.
    private lazy var gate = PreviewPlaybackController(
        onPlay: { [weak self] in self?.queuePlayer?.play() },
        onPause: { [weak self] in self?.queuePlayer?.pause() })

    /// App-lifecycle observer tokens (background / foreground axis). Registered once, removed on
    /// `teardown` (dismantle) and `deinit`.
    private var lifecycleObservers: [NSObjectProtocol] = []

    /// The `LivebuyWidgetVisibility` subscription token (covered axis, ios-refui-widget-host-visibility-pause).
    /// Registered once in `init` (register replays the current covered level → seeds `notCovered` before
    /// the first `configure` reapply), unregistered on `teardown` (dismantle) and `deinit` alongside the
    /// lifecycle observers.
    private var visibilityToken: UUID?

    init(url: URL) {
        super.init(frame: .zero)
        backgroundColor = .black
        playerLayer.videoGravity = .resizeAspectFill
        // Seed the foreground axis from the current app state so a card that mounts while the app is
        // already backgrounded does NOT start decoding (`.inactive` counts as foreground — only a
        // real background flips it, matching the notification below).
        gate.setForeground(UIApplication.shared.applicationState != .background)
        registerLifecycleObservers()
        // Covered axis: subscribe to the opt-in host bridge. `register` immediately replays the current
        // covered level, so a card mounting DURING a covered period seeds `notCovered = false` (pauses)
        // before `configure`'s `reapply()`. Host that never opts in → covered stays false → notCovered
        // stays true → byte-identical prior behaviour.
        visibilityToken = LivebuyWidgetVisibility.shared.register { [weak self] covered in
            self?.gate.setNotCovered(!covered)
        }
        configure(url: url)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    func update(url: URL) {
        guard url != currentURL else { return }
        configure(url: url)
    }

    /// Off-screen axis: forwarded from the SwiftUI `GeometryReader` visibility probe. Edge-triggered
    /// inside the gate (redundant same-value sets are no-ops).
    func setOnScreen(_ onScreen: Bool) {
        gate.setOnScreen(onScreen)
    }

    private func registerLifecycleObservers() {
        let nc = NotificationCenter.default
        lifecycleObservers.append(nc.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) {
                [weak self] _ in self?.gate.setForeground(false)
            })
        lifecycleObservers.append(nc.addObserver(
            forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) {
                [weak self] _ in self?.gate.setForeground(true)
            })
    }

    private func configure(url: URL) {
        teardownPlayer()
        currentURL = url
        let player = AVQueuePlayer()
        player.isMuted = true
        player.actionAtItemEnd = .none
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        playerLayer.player = player
        queuePlayer = player
        // Apply the CURRENT gate decision instead of an unconditional `play()`: a card that mounts /
        // re-configures while backgrounded or off-screen must NOT start decoding. `reapply()` also
        // (re)plays a newly-built player when the card IS foreground + on-screen.
        gate.reapply()
    }

    /// Pause + release the player only (keeps the lifecycle observers, since `configure` reuses them).
    private func teardownPlayer() {
        queuePlayer?.pause()
        playerLayer.player = nil
        looper = nil
        queuePlayer = nil
        currentURL = nil
    }

    /// Full teardown (SwiftUI `dismantleUIView`): release the player AND drop the lifecycle observers.
    func teardown() {
        teardownPlayer()
        removeLifecycleObservers()
    }

    private func removeLifecycleObservers() {
        // Covered axis: drop the `LivebuyWidgetVisibility` subscription (independent of the lifecycle
        // observers below, and idempotent — a nil token is a no-op).
        if let token = visibilityToken {
            LivebuyWidgetVisibility.shared.unregister(token)
            visibilityToken = nil
        }
        guard !lifecycleObservers.isEmpty else { return }
        let nc = NotificationCenter.default
        lifecycleObservers.forEach { nc.removeObserver($0) }
        lifecycleObservers.removeAll()
    }

    deinit {
        removeLifecycleObservers()
    }
}

// MARK: - PreviewPlaybackController (unified foreground && onScreen && notCovered play-gate)
//
// A pure, framework-free state machine (no UIKit / AVFoundation import → unit-testable in isolation,
// mirroring Android's / Flutter's `PreviewPlaybackController`). The preview should play ONLY when the
// app is foreground AND the card is on-screen AND the widget-hosting screen is not covered by the host.
// The three axes fold into one `foreground && onScreen && notCovered` gate, applied edge-triggered so
// play / pause are not churned. Keeping ONE gate (rather than independent observers) means returning to
// the foreground / scrolling back never wakes a card that is still off-screen OR still covered
// (ios-refui-widget-host-visibility-pause: the `notCovered` axis is fed by the `LivebuyWidgetVisibility`
// opt-in host bridge and defaults to `true` = the prior two-axis behaviour). `reapply()` force-applies
// the current desired state once the underlying player is (re)configured (its earlier `onPlay` /
// `onPause` calls were meaningful only against a live player).
final class PreviewPlaybackController {

    /// Called (once, on the rising edge — or forced by `reapply`) when the preview SHOULD play.
    private let onPlay: () -> Void
    /// Called (once, on the falling edge — or forced by `reapply`) when the preview SHOULD pause.
    private let onPause: () -> Void

    private var foreground: Bool = true
    private var onScreen: Bool = true
    /// Third axis (ios-refui-widget-host-visibility-pause): whether the widget-hosting screen is NOT
    /// covered by another destination. `true` (the default) = not covered = the prior behaviour, so a
    /// host that never opts into `LivebuyWidgetVisibility` keeps a byte-identical `foreground && onScreen`
    /// gate. Fed by `LivebuyWidgetVisibility` (the host declares coverage the SDK cannot detect from the
    /// widget layer — z-order coverage is invisible to `GeometryReader`, and coverage does not background
    /// the app). Kept in the SAME single controller (not a separate observer) so returning to foreground /
    /// scrolling back never wakes a card that is still covered.
    private var notCovered: Bool = true

    /// The last applied decision (`nil` = never applied yet). Edge-trigger latch.
    private var applied: Bool?

    init(onPlay: @escaping () -> Void, onPause: @escaping () -> Void) {
        self.onPlay = onPlay
        self.onPause = onPause
    }

    /// Whether the preview should currently be playing — the three-axis AND (any axis false → pause).
    var shouldPlay: Bool { foreground && onScreen && notCovered }

    func setForeground(_ value: Bool) {
        guard foreground != value else { return }
        foreground = value
        apply()
    }

    func setOnScreen(_ value: Bool) {
        guard onScreen != value else { return }
        onScreen = value
        apply()
    }

    /// Covered axis: forwarded from the `LivebuyWidgetVisibility` opt-in host bridge (a listener passes
    /// `!covered` here). Edge-triggered inside the gate (redundant same-value sets are no-ops).
    func setNotCovered(_ value: Bool) {
        guard notCovered != value else { return }
        notCovered = value
        apply()
    }

    /// Force-(re)apply the current desired state. Used once the underlying player becomes (re)ready —
    /// its earlier `onPlay` / `onPause` callbacks acted on a now-replaced player, so the real state
    /// must be (re)issued to the live one.
    func reapply() {
        applied = nil
        apply()
    }

    private func apply() {
        let desired = shouldPlay
        guard desired != applied else { return }
        applied = desired
        if desired { onPlay() } else { onPause() }
    }
}

/// A minimal async still loader for the static `cover` thumbnail — a `UIImageView`
/// (scaleAspectFill, clipped) filled by a cancellable `URLSession` data task. Kept as
/// a `UIViewRepresentable` (not `AsyncImage`) to hold the iOS-14 floor without an
/// `@available` branch and to centralize the empty-string guard at the call site.
/// Process-wide decoded-image cache for reference-ui remote still images. The same
/// product / cover URL is used across carousel / grid / floating; without a cache
/// every appearance + every `template.reload()` re-fetches and re-decodes from
/// scratch (placeholder flicker). Mirrors the host's `RemoteImageCache`. iOS-14-safe.
enum ReferenceUIImageCache {
    static let shared = NSCache<NSURL, UIImage>()

    /// Decode `data` as an image and store it in `shared` under `url`. Returns the decoded
    /// image, or `nil` (no cache write) when `data` is missing / undecodable. SINGLE choke
    /// point for the decode+cache-write step — used by BOTH `RemoteStillImageView
    /// .Coordinator.load`'s network-completion path AND `ReferenceUIImagePrefetch.prefetch`
    /// (rb-ios-product-image-loading-polish), so the two call sites can never drift on
    /// decode/cache semantics. `internal` (not `private`) so `@testable import` test files can
    /// exercise it directly with in-memory `Data`, no network round trip needed.
    @discardableResult
    static func decodeAndStore(_ data: Data?, for url: URL) -> UIImage? {
        guard let data = data, let image = UIImage(data: data) else { return nil }
        shared.setObject(image, forKey: url as NSURL)
        return image
    }
}

/// Shared placeholder gradient tokens for PRODUCT PHOTO chips (loading / no-photo /
/// snapshot-deterministic state) — `CarouselCardView`'s widget product thumb,
/// `ProductZoomOverlayView`, `MiniCartView`, `ProductDetailSheetView`'s gallery placeholder.
/// Neutral grey (`rb-ios-product-image-loading-polish` — was a warm orange gradient;
/// user-reported it flashed distractingly on the mini-cart peek's first paint before the real
/// photo arrived). Both stops are DARKER than the corresponding old orange stops (`#FFD7A8`
/// L≈221.6 → `#C7C7CC` L≈199.5; `#E27D5A` L≈151.3 → `#8E8E93` L≈142.6, `L =
/// 0.299R+0.587G+0.114B`), so the existing white monogram text overlaid on 3 of the 4 call
/// sites keeps AT LEAST as much contrast as before — see `ProductImageLoadingPolishTests`.
/// `#C7C7CC` already appears elsewhere in this module (`LiveOverlayChromeView.swift`);
/// `#8E8E93` is iOS's well-known system grey. Deliberately EXCLUDES
/// `VideoInfoPanelView`'s shop-logo/`shopName` monogram chip, which happens to reuse the SAME
/// old orange pair but is a different semantic surface (merchant branding, not a product
/// photo) — left untouched by this change.
enum ReferenceUIProductPlaceholderPalette {
    static let topHex = "#C7C7CC"
    static let bottomHex = "#8E8E93"
    static var top: Color { Color(hex: topHex) ?? .gray }
    static var bottom: Color { Color(hex: bottomHex) ?? .gray }
}

/// A `UIImageView` that reports NO intrinsic content size. Plain `UIImageView`
/// reports `intrinsicContentSize == decoded image pixel size`; inside a SwiftUI
/// `UIViewRepresentable` hosted full-bleed (`.ignoresSafeArea()`, no explicit
/// `.frame`) that intrinsic size stretches the SwiftUI layout to the image's pixels
/// — overflowing the screen. Reporting `noIntrinsicMetric` makes the view take the
/// proposed size (the screen) instead. Fixed-frame call sites are unaffected.
final class FlexibleImageView: UIImageView {
    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
    }
}

struct RemoteStillImageView: UIViewRepresentable {
    let url: URL
    /// contentMode for the loaded image. Default `.scaleAspectFit` shows the COMPLETE image
    /// (no crop) — the widget card's cover / product thumb want the whole image visible. The
    /// Upcoming moment background passes `.scaleAspectFill` to fill the full screen.
    var contentMode: UIView.ContentMode = .scaleAspectFit
    /// Fires once per successful load with the decoded image's NATIVE SIZE IN POINTS
    /// (`UIImage.size` — already scale-corrected; do NOT divide by `UIScreen.main.scale` again,
    /// that would systematically shrink every reported size by the device's scale factor).
    /// Fired synchronously on a `ReferenceUIImageCache` cache hit, or on the main queue after a
    /// successful `URLSession` decode. Additive, defaults to `nil` — every EXISTING call site
    /// (none of which pass this) is byte-identical (rb-ios-product-detail-main-image-scale-down-
    /// letterbox).
    var onImageLoaded: ((CGSize) -> Void)? = nil

    /// Applies `image` to `imageView` with a short cross-dissolve fade (`rb-ios-product-image-
    /// loading-polish`, 150–200ms, default 180ms) — the NETWORK-completion path's transition.
    /// `UIView.transition(...)` (NOT SwiftUI's `.transition(.opacity)`, which does not apply to
    /// this `UIViewRepresentable`'s internal `UIImageView` content swap) is the idiomatic UIKit
    /// mechanism for animating an image-view content change. `internal` (not `private`) so it is
    /// directly unit-testable with a bare `UIImageView` — no network round trip needed. NOT used
    /// by the cache-hit path (`load`'s early-return branch below), which stays a synchronous,
    /// unanimated assignment.
    static func applyWithFade(_ image: UIImage, to imageView: UIImageView, duration: TimeInterval = 0.18) {
        UIView.transition(with: imageView, duration: duration, options: .transitionCrossDissolve) {
            imageView.image = image
        }
    }

    func makeUIView(context: Context) -> UIImageView {
        // `FlexibleImageView` reports NO intrinsic content size, so a full-bleed host
        // (the upcoming cover background uses `.ignoresSafeArea()` with NO explicit
        // `.frame`) is sized by the SwiftUI proposal (the screen), NOT by the decoded
        // image's pixel size. A plain `UIImageView` reports `intrinsicContentSize ==
        // image pixel size`, which stretched the enclosing `ZStack` wider than the
        // screen → the slim bottom bar's flex got an oversized width and its end
        // buttons (bag / like) were pushed off-screen. Fixed-frame call sites
        // (CarouselCardView's 24×24 / 9:16 thumbs) are unaffected — their `.frame`
        // overrides the (now absent) intrinsic size.
        let iv = FlexibleImageView()
        iv.contentMode = contentMode
        iv.clipsToBounds = true
        iv.setContentHuggingPriority(.defaultLow, for: .horizontal)
        iv.setContentHuggingPriority(.defaultLow, for: .vertical)
        iv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        iv.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        context.coordinator.load(url: url, into: iv, onImageLoaded: onImageLoaded)
        return iv
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {
        context.coordinator.load(url: url, into: uiView, onImageLoaded: onImageLoaded)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        private var task: URLSessionDataTask?
        private var loadedURL: URL?

        func load(url rawURL: URL, into imageView: UIImageView, onImageLoaded: ((CGSize) -> Void)? = nil) {
            // Single http→https upgrade point for ALL remote images (every call site routes
            // through RemoteStillImageView). A cleartext `http` pic would be blocked by iOS
            // ATS and never load → placeholder; the Livebuy host serves the same path over
            // TLS. https / non-http schemes pass through unchanged (ReferenceUIImageURL).
            let url = rawURL.lbHTTPSUpgraded
            guard url != loadedURL else { return }
            loadedURL = url
            task?.cancel()
            // Clear immediately so a RECYCLED cell never shows the previous product's
            // photo while the new one loads (URLSessionDataTask.cancel is best-effort).
            imageView.image = nil
            // Cache hit → no network / decode, no flicker. `imageView.image` is set synchronously
            // (imperative UIKit mutation, safe from any call context), but `onImageLoaded` is
            // deferred one run-loop tick via `DispatchQueue.main.async` — this callback mutates
            // SwiftUI `@State` (`loadedPhotoSizes`), and `load(url:into:onImageLoaded:)` runs
            // synchronously from `makeUIView`/`updateUIView`, which SwiftUI itself calls DURING an
            // active view-update pass. Mutating `@State` synchronously from inside that pass is
            // undefined behavior (Apple's own "Modifying state during view update" runtime
            // warning) — the write can silently fail to stick, which is exactly what caused the
            // `.detail` main image to stay wedged on the fixed-168pt crop placeholder forever even
            // though `onImageLoaded` reported the correct decoded size (rb-ios-product-detail-
            // main-image-scale-down-letterbox — this async defer restores the "never crop" fix on
            // the cache-hit path; the network-completion path below was already correctly async).
            if let cached = ReferenceUIImageCache.shared.object(forKey: url as NSURL) {
                imageView.image = cached
                DispatchQueue.main.async {
                    onImageLoaded?(cached.size)
                }
                return
            }
            let t = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                // Single decode+cache-write choke point, shared with `ReferenceUIImagePrefetch
                // .prefetch` (rb-ios-product-image-loading-polish) — the two paths can never
                // drift on decode/cache semantics.
                guard let image = ReferenceUIImageCache.decodeAndStore(data, for: url) else { return }
                DispatchQueue.main.async {
                    // Re-check currency: a late completion for a NOW-stale URL (the cell
                    // was recycled to a different product) MUST NOT overwrite the image.
                    guard self?.loadedURL == url else { return }
                    // Network-completion path fades in (rb-ios-product-image-loading-polish) —
                    // the cache-hit branch above stays a synchronous, unanimated assignment.
                    RemoteStillImageView.applyWithFade(image, to: imageView)
                    // `image.size` is already POINTS (scale-corrected) — do NOT divide by
                    // `UIScreen.main.scale` again (rb-ios-product-detail-main-image-scale-down-
                    // letterbox D1).
                    onImageLoaded?(image.size)
                }
            }
            task = t
            t.resume()
        }

        deinit { task?.cancel() }
    }
}

/// Fire-and-forget background prefetch (`rb-ios-product-image-loading-polish`) — call ahead of
/// a product entering the now-introducing / narrating window so its image is already decoded
/// and cached (`ReferenceUIImageCache.shared`) by the time `RemoteStillImageView.Coordinator
/// .load` needs it (cache-hit path — synchronous, no placeholder flash). Read-only cache warm;
/// NEVER touches any `UIImageView` / SwiftUI `@State`. `internal` (not `private`) so it — and
/// its dedicated test — can be called directly from `PlayerShellView` (a different file, same
/// module) and from test files via `@testable import`.
enum ReferenceUIImagePrefetch {
    /// URLs with an in-flight prefetch request, guarded by `lock` — the `URLSession` completion
    /// can fire on a background queue, and a caller (`PlayerShellView`) may invoke `prefetch`
    /// again for the SAME url before the first request completes (e.g. a repeated 5s products
    /// poll re-handing the same list) — dedup so that re-invocation is a cheap no-op, not a
    /// second network round trip.
    private static var inFlight = Set<URL>()
    private static let lock = NSLock()

    static func prefetch(url rawURL: URL) {
        // Same http→https upgrade point `Coordinator.load` uses, so the cache key this warms
        // is the SAME key a later `Coordinator.load` cache lookup will check.
        let url = rawURL.lbHTTPSUpgraded
        guard ReferenceUIImageCache.shared.object(forKey: url as NSURL) == nil else { return }
        lock.lock()
        guard !inFlight.contains(url) else { lock.unlock(); return }
        inFlight.insert(url)
        lock.unlock()
        let task = URLSession.shared.dataTask(with: url) { data, _, _ in
            _ = ReferenceUIImageCache.decodeAndStore(data, for: url)
            lock.lock()
            inFlight.remove(url)
            lock.unlock()
        }
        task.resume()
    }
}

#if DEBUG
struct CarouselCardView_Previews: PreviewProvider {
    static var previews: some View {
        let theme = ReferenceUIThemePalette.minimal
        Group {
            HStack(alignment: .top, spacing: 12) {
                // VOD card with a product overlay (no kind badge, 2026-09-04 R33).
                CarouselCardView(item: .demo(), theme: theme)
                    .previewDisplayName("vod + goods")
                // LIVE card (red LIVE tag + viewer-count badge).
                CarouselCardView(item: .demo(id: "demo-vid-002", title: "早春保養 LIVE", live: true,
                                             watchNum: 128, showPvNum: 1),
                                 theme: theme)
            }
            .frame(width: 320, height: 320)

            // product_card modes: `below` bound / `below` unbound (equal-height
            // transparent spacer) / `hidden`.
            HStack(alignment: .top, spacing: 12) {
                CarouselCardView(item: .demo(), theme: theme, productCard: "below")
                CarouselCardView(item: .demo(id: "demo-vid-003", goods: nil),
                                 theme: theme, productCard: "below")
                CarouselCardView(item: .demo(id: "demo-vid-004"), theme: theme,
                                 productCard: "hidden")
            }
            .frame(width: 460, height: 340)
            .previewDisplayName("product_card modes")

            // showTitle: false (rb-ios-floating-widget-hide-title) — the floating card's
            // shape: no title, shorter intrinsic height than the default (left) card.
            HStack(alignment: .top, spacing: 12) {
                CarouselCardView(item: .demo(id: "demo-vid-005", live: true), theme: theme)
                CarouselCardView(item: .demo(id: "demo-vid-006", live: true), theme: theme,
                                 showTitle: false)
            }
            .frame(width: 320, height: 320)
            .previewDisplayName("showTitle: true vs false")

            // pin badge (rb-ios-carousel-card-pin-viewers-duration-removal, design R33):
            // all three kinds can carry it simultaneously, independent of kindBadge.
            HStack(alignment: .top, spacing: 12) {
                CarouselCardView(item: .demo(id: "demo-vid-007", pin: 1), theme: theme)
                CarouselCardView(item: .demo(id: "demo-vid-008", title: "早春保養 LIVE", live: true,
                                             pin: 1, watchNum: 128, showPvNum: 1),
                                 theme: theme)
                CarouselCardView(item: .demo(id: "demo-vid-009", upcoming: true, pin: 1), theme: theme)
            }
            .frame(width: 460, height: 320)
            .previewDisplayName("pin badge: VOD / LIVE / upcoming")
        }
        .padding()
        .background(theme.background)
        .previewLayout(.sizeThatFits)
    }
}
#endif
