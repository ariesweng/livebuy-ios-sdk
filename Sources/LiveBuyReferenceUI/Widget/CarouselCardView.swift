import SwiftUI
import UIKit
import AVFoundation
import LiveBuySDK
import LiveBuyUI

// MARK: - CarouselCardView — family-5 shared 9:16 widget card primitive (LBPCarouselCard)
//
// Spec: `reference-ui-rendering/spec.md` (family-5 widget surfaces).
// Design: rb-ios-widget design.md §"渲染計畫" +
//          `design/templates/minimal/widgets.jsx` `LBPCarouselCard` (lines 54-160).
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
//                  indicates live,
//       - VOD    → a「▶ mm:ss」duration pill (from `LBVideoItem.duration` seconds,
//                  formatted) otherwise,
//   • a BOTTOM dark-glass product overlay (product thumb + `goods.name` + display
//     price) when `goods != nil` (`LBVideoItem.goods` — `LBFeaturedGood`). The thumb
//     binds `goods.pic` on the live runtime path (gradient chip fallback); the price
//     is de-duplicated via `displayPrice(_:)` so a symbol-bearing wire value does not
//     render a double currency,
//   • the `LBVideoItem.title` BELOW the thumbnail.
//
// KIND MAPPING (three-way: LIVE → UPCOMING → VOD). The core `LBVideoItem` carries
// `liveStatus: Int` + `type: Int` + `publishAt: String` (UTC+8):
//     `liveStatus == 1`                          → LIVE tag (no duration pill).
//     `liveStatus == 0 && type == 2` (直播)       → UPCOMING (直播預告): dark veil + centre
//        && `publishAt` parses                     scheduled date + big time.
//     otherwise (incl. `type == 1` regular VOD,  → VOD (duration pill from `duration` seconds).
//        `type == 3` replay, or unparseable publishAt)
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
// One-way data flow: this primitive reads ONLY its passed-in `item` + `theme`; it
// never reaches back into `WidgetModel` / `DefaultWidgetTemplate`. The tap exit is
// host-wired (`onTap`) — the card NEVER opens the player / calls core itself
// (design §"守住的不變式": 互動一律 host-wired exit 轉發). It renders correctly with
// `onTap` nil (so demo / snapshot tests construct it action-free).
//
// iOS-14-safe SwiftUI only. `VStack` / `HStack` / `ZStack` / `RoundedRectangle` /
// `LinearGradient` / `Text` / `Image(systemName:)` / `Button` / `.aspectRatio` are
// all iOS-13+. NO `AsyncImage` / `.task` / `.foregroundStyle` / `.tint`.

/// The shared family-5 widget card (`LBPCarouselCard`): a 9:16 thumbnail
/// placeholder + LIVE / VOD kind badge + an optional bottom dark-glass product
/// overlay + the title below. `onTap` is a host-wired exit (the card never opens
/// the player itself).
public struct CarouselCardView: View {

    /// The video this card renders (read-only — `cover` / `title` / `duration` /
    /// `liveStatus` / `goods`). Read-only; this layer never mutates / re-fetches.
    public let item: LBVideoItem

    /// The resolved reference-ui theme (FIRST positional-after-data argument; the
    /// card's title uses `theme.text`, badges use FIXED design colors per the
    /// design's dark-glass treatment).
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

    /// Card tap → host-wired exit (→ host → core open player for `item.id`). nil for
    /// demo / snapshot instances — the card is inert. This layer NEVER opens the
    /// player / calls core simulate* itself.
    private let onTap: (() -> Void)?

    public init(
        item: LBVideoItem,
        theme: ReferenceUITheme,
        width: CGFloat = 132,
        live: Bool = false,
        onTap: (() -> Void)? = nil
    ) {
        self.item = item
        self.theme = theme
        self.width = width
        self.live = live
        self.onTap = onTap
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
                title
            }
            .frame(width: width)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Thumbnail (9:16, placeholder + kind badge + product overlay)
    //
    // Mirrors LBPCarouselCard's thumbnail block (widgets.jsx 63-150): a 9:16
    // rounded media area with the kind badge top-left and the dark-glass product
    // overlay anchored bottom.

    private var thumbnail: some View {
        ZStack(alignment: .topLeading) {
            // 9:16 media thumbnail. `live == false` (snapshot / demo) → always the
            // deterministic placeholder chip. `live == true` (runtime) → `preview`
            // (animated) → `cover` (static) → placeholder. See `mediaThumbnail`.
            mediaThumbnail

            // UPCOMING (直播預告): a full-bleed dark veil + centred「即將開播」+ a
            // 距開播 countdown (design's upcoming = dark mask + centre countdown).
            // Replaces the VOD duration pill (kindBadge returns EmptyView for upcoming).
            if isUpcoming {
                upcomingOverlay
            }

            // Kind badge top-left: LIVE red tag, else VOD「▶ mm:ss」duration pill
            // (EmptyView for upcoming — the centre overlay is the indicator).
            kindBadge
                .padding(6)

            // Bottom dark-glass product overlay (only when goods != nil).
            if let goods = item.goods {
                VStack {
                    Spacer(minLength: 0)
                    productOverlay(goods)
                        .padding(.horizontal, 6)
                        .padding(.bottom, 6)
                }
            }
        }
        .frame(width: width, height: width * 16.0 / 9.0)
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
        } else if live, let url = coverURL {
            ZStack {
                coverPlaceholder
                RemoteStillImageView(url: url)
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

    // MARK: - Kind badge (LIVE tag / VOD duration pill)

    @ViewBuilder
    private var kindBadge: some View {
        if isLive {
            liveTag
        } else if isUpcoming {
            // Upcoming is indicated by the centred `upcomingOverlay`, not a top-left pill.
            EmptyView()
        } else {
            durationPill
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

    /// LIVE red tag (LBPCarouselCard 97-108): a static pulse dot + 「LIVE」on the
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
    }

    /// VOD「▶ mm:ss」duration pill (LBPCarouselCard 110-124) over a translucent
    /// dark capsule. `LBVideoItem.duration` is `Int` SECONDS — formatted to `mm:ss`.
    private var durationPill: some View {
        HStack(spacing: 4) {
            Image(systemName: "play.fill")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.white)
            Text(Self.formatSeconds(item.duration))
                .font(.system(size: 10 * theme.fontScale, weight: .semibold))
                .foregroundColor(.white)
        }
        .padding(.leading, 4)
        .padding(.trailing, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 999)
                .fill(Color.black.opacity(0.55)))
    }

    // MARK: - Bottom dark-glass product overlay (goods != nil)

    /// Dark-glass product overlay (LBPCarouselCard 126-149): a 24×24 product thumb +
    /// the product name (1-line) + the display price, on a translucent dark surface.
    /// The thumb binds `goods.pic` on the `live == true` runtime path (gradient chip
    /// as the loading / empty fallback); `live == false` (snapshot / demo) keeps the
    /// gradient chip so baselines stay byte-identical. The price is produced by
    /// `displayPrice(_:)` (defensive prefix — no double currency).
    private func productOverlay(_ goods: LBFeaturedGood) -> some View {
        HStack(spacing: 6) {
            productThumb(goods)

            VStack(alignment: .leading, spacing: 1) {
                Text(goods.name)
                    .font(.system(size: 10 * theme.fontScale, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(Self.displayPrice(goods.price))
                    .font(.system(size: 10 * theme.fontScale, weight: .heavy))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Self.productGlass)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.5)))
    }

    /// 24×24 product thumb chip. `live == true` + non-empty `goods.pic` → the remote
    /// product image (`RemoteStillImageView`, iOS-14-safe — NOT `AsyncImage`,
    /// `scaleAspectFit` so the COMPLETE product image is visible), with the
    /// deterministic gradient chip behind it as the loading / pre-load fallback.
    /// `live == false` (snapshot / demo) or empty `pic` → the gradient chip alone, so
    /// snapshot baselines stay placeholder-only and byte-identical.
    @ViewBuilder
    private func productThumb(_ goods: LBFeaturedGood) -> some View {
        if live, let url = productPicURL(goods) {
            ZStack {
                thumbPlaceholder
                RemoteStillImageView(url: url)
            }
            .frame(width: 24, height: 24)
            .clipShape(RoundedRectangle(cornerRadius: 5))
        } else {
            thumbPlaceholder
        }
    }

    /// Deterministic gradient thumb chip (the design's `<ProductMock>` stand-in).
    private var thumbPlaceholder: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(hex: "#FFD7A8") ?? .orange,
                        Color(hex: "#E27D5A") ?? .orange,
                    ]),
                    startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 24, height: 24)
    }

    /// `goods.pic` as a non-empty URL, or nil (empty string → absent). Mirrors the
    /// `coverURL` / `previewURL` guard so an empty `pic` falls through to the chip.
    private func productPicURL(_ goods: LBFeaturedGood) -> URL? {
        let s = goods.pic.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : URL(string: s)
    }

    // MARK: - Title (below thumbnail)

    /// The video title below the thumbnail (LBPCarouselCard 152-157), 1-line clamp,
    /// painted with `theme.text` (the card sits on the host surface, not the dark
    /// thumbnail).
    private var title: some View {
        Text(item.title)
            .font(.system(size: 12 * theme.fontScale, weight: .semibold))
            .foregroundColor(theme.text)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Helpers

    /// Format `Int` seconds → zero-padded `mm:ss` (`08:02`), or `hh:mm:ss`
    /// (`01:24:36`) when ≥ 1h, for `LBVideoItem.duration` (which IS seconds). Mirrors
    /// the design's `LB_CAROUSEL_DEMO` / `LB_SHOP_POOL` duration copy (`00:28` /
    /// `08:42` / `01:24:36`) — minutes are always 2-digit; long replays carry an hours
    /// component (so `5076s` reads `01:24:36`, not `84:36`).
    static func formatSeconds(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        if h > 0 {
            return String(format: "%02d:%02d:%02d", h, m, sec)
        }
        return String(format: "%02d:%02d", m, sec)
    }

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

    /// First non-whitespace character of a title, uppercased, for the placeholder
    /// monogram. Falls back to a play glyph stand-in when empty.
    static func monogram(for title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "▶" }
        return String(first).uppercased()
    }

    // MARK: - Decorative design tokens (literal widgets.jsx hex via Color(hex:))

    /// Brand-red LIVE tag surface (`#F03246`, LBPCarouselCard 102).
    static let liveRed = Color(hex: "#F03246") ?? .red
    /// Dark-glass product overlay surface (`rgba(20,20,24,0.78)`, LBPCarouselCard 130).
    static let productGlass = (Color(hex: "#141418") ?? .black).opacity(0.78)

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
// reachable from `LiveBuyReferenceUI`. The surface agents (carousel / grid /
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
        liveurl: String = ""
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
            watchNum: 0,
            pvNum: 0,
            liveStatus: live ? 1 : 0,
            pin: 0,
            showPvNum: 0,
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

/// A control-free, looping, muted video view for the animated `preview` thumbnail —
/// an `AVPlayerLayer`-backed `UIView` (resizeAspectFill, clipped by the card's 9:16
/// rounded frame). Created lazily and torn down on disappear to bound resource use.
struct LoopingVideoView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> LoopingPlayerUIView {
        LoopingPlayerUIView(url: url)
    }

    func updateUIView(_ uiView: LoopingPlayerUIView, context: Context) {
        uiView.update(url: url)
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

    init(url: URL) {
        super.init(frame: .zero)
        backgroundColor = .black
        playerLayer.videoGravity = .resizeAspectFill
        configure(url: url)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    func update(url: URL) {
        guard url != currentURL else { return }
        configure(url: url)
    }

    private func configure(url: URL) {
        teardown()
        currentURL = url
        let player = AVQueuePlayer()
        player.isMuted = true
        player.actionAtItemEnd = .none
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        playerLayer.player = player
        queuePlayer = player
        player.play()
    }

    func teardown() {
        queuePlayer?.pause()
        playerLayer.player = nil
        looper = nil
        queuePlayer = nil
        currentURL = nil
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
        context.coordinator.load(url: url, into: iv)
        return iv
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {
        context.coordinator.load(url: url, into: uiView)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        private var task: URLSessionDataTask?
        private var loadedURL: URL?

        func load(url: URL, into imageView: UIImageView) {
            guard url != loadedURL else { return }
            loadedURL = url
            task?.cancel()
            // Clear immediately so a RECYCLED cell never shows the previous product's
            // photo while the new one loads (URLSessionDataTask.cancel is best-effort).
            imageView.image = nil
            // Cache hit → no network / decode, no flicker.
            if let cached = ReferenceUIImageCache.shared.object(forKey: url as NSURL) {
                imageView.image = cached
                return
            }
            let t = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let data = data, let image = UIImage(data: data) else { return }
                ReferenceUIImageCache.shared.setObject(image, forKey: url as NSURL)
                DispatchQueue.main.async {
                    // Re-check currency: a late completion for a NOW-stale URL (the cell
                    // was recycled to a different product) MUST NOT overwrite the image.
                    guard self?.loadedURL == url else { return }
                    imageView.image = image
                }
            }
            task = t
            t.resume()
        }

        deinit { task?.cancel() }
    }
}

#if DEBUG
struct CarouselCardView_Previews: PreviewProvider {
    static var previews: some View {
        let theme = ReferenceUIThemePalette.minimal
        HStack(alignment: .top, spacing: 12) {
            // VOD card with a product overlay (duration pill).
            CarouselCardView(item: .demo(), theme: theme)
                .previewDisplayName("vod + goods")
            // LIVE card (red LIVE tag).
            CarouselCardView(item: .demo(id: "demo-vid-002", title: "早春保養 LIVE", live: true),
                             theme: theme)
        }
        .padding()
        .frame(width: 320, height: 320)
        .previewLayout(.sizeThatFits)
    }
}
#endif
