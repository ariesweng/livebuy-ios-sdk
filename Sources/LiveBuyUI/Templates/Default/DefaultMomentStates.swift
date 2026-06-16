import LiveBuySDK

// MARK: - DefaultMomentStates — five player "moment" host-bindable view-models
//
// Spec: `ui-template-foundation/spec.md`
//   § "Default Template Player Moment-State 暴露"
// Design: expose-player-moment-state-template design.md D1–D8.
//
// Behaviour / view-model layer ONLY (no pixels). core stays headless: it owns the
// player state machine, the `/sdk/video` + `/sdk/video/goods` polls, subtitle /
// subscribe / mute. These models MAP the core's `LBPlayerMomentState` (delivered
// via `onMomentStateChange`) + the player state (`onStateChange`) + the player
// mute flag into host-bindable read surfaces so the host can draw `moments.jsx`'s
// StartScreen / EndScreen / ProductOverlay / PlayerHeader / SubtitleTrack.
//
// Each model mirrors `DefaultErrorState` / `DefaultActivityFeed`: PUBLIC read
// surface (`private(set) public var`), an INTERNAL coalesced `onMutation` hook
// (the host observes the owning template's single `onChange`, never the model),
// and INTERNAL `handle*` mutators that DIFF-then-notify (fire `onMutation` exactly
// once per REAL change — never on an unchanged re-feed, e.g. the 5s products poll).

// MARK: - 1. StartScreen — `{ phase }`

/// Splash lifecycle phase for `LBPStartScreen`. The host picks which splash
/// variant (or none) to draw; `done` dismisses the splash.
public enum LBStartScreenPhase: Equatable {
    case loading
    case splash
    case buffering
    case done
}

/// Upcoming（直播預告）等待開播 view-model. Mapped from the canonical player state
/// `"awaitingLive"` (core `live_status == 0`) + `channel.publishAt`（開播時間）。Host /
/// reference-ui bind this to render the「等待開播倒數」surface. The datetime parse /
/// countdown is a reference-ui presentation concern — this layer passes `publish_at`
/// through verbatim. Diff-then-notify.
public final class DefaultUpcomingState {

    /// Whether the player is awaiting a not-yet-started live (直播預告).
    private(set) public var active: Bool = false
    /// Whether the UPCOMING video's opening video (intro MP4 preroll, `channel.start`)
    /// is currently playing — `true` ⟺ canonical state `"startScreenPlaying"` AND there
    /// is an opening video AND the channel is upcoming (`liveStatus == 0` + future
    /// `publishAt`). reference-ui reads this to wear the LIVE chrome during an upcoming
    /// video's intro (a VOD's intro keeps `introPlaying == false` → VOD chrome). Distinct
    /// from `active` (the awaiting-live countdown, which plays NO video).
    private(set) public var introPlaying: Bool = false
    /// Scheduled start (`channel.publishAt` / backend `publish_at`), passed through
    /// verbatim; empty when not upcoming.
    private(set) public var scheduledStartAt: String = ""
    /// Video cover URL (`channel.cover`), passed through verbatim (template MUST NOT load
    /// the image); reference-ui renders it as the await-live countdown background (matching
    /// the widget card). Empty when not upcoming / no cover.
    private(set) public var cover: String = ""

    var onMutation: (() -> Void)?

    init() {}

    /// Feed the upcoming state. Diff-then-notify: same values re-feed is a no-op.
    func handle(active: Bool, introPlaying: Bool, scheduledStartAt: String, cover: String) {
        guard active != self.active
            || introPlaying != self.introPlaying
            || scheduledStartAt != self.scheduledStartAt
            || cover != self.cover else { return }
        self.active = active
        self.introPlaying = introPlaying
        self.scheduledStartAt = scheduledStartAt
        self.cover = cover
        onMutation?()
    }
}

/// StartScreen phase view-model. Mapped from the canonical player state +
/// `channel.start` presence (D2); core owns the state machine, the template owns
/// the splash mapping.
public final class DefaultStartScreenState {

    private(set) public var phase: LBStartScreenPhase = .loading

    var onMutation: (() -> Void)?

    init() {}

    /// Map a canonical player state → splash phase. `startScreenPlaying` maps to
    /// `.splash` ONLY when `hasStart` (channel.start / startUrl non-empty) — with
    /// no opening MP4 it goes straight loading → done (never splash). Diff-then-
    /// notify: same phase re-feed is a no-op.
    func handlePhase(canonicalState: String, hasStart: Bool) {
        let next: LBStartScreenPhase
        switch canonicalState {
        case "loading":            next = .loading
        case "startScreenPlaying": next = hasStart ? .splash : .done
        case "buffering":          next = .buffering
        default:                   next = .done   // playing / paused / ended / endScreenShown / …
        }
        guard next != phase else { return }
        phase = next
        onMutation?()
    }
}

// MARK: - 2. EndScreen — `{ next, hot, countdown? }`

/// Auto-next countdown snapshot for the `LBPEndScreen` 圓環倒數. `total` is the
/// `remain` captured at the instant the countdown went active; held constant while
/// `remain` decrements per tick.
public struct LBEndScreenCountdown: Equatable {
    public let remain: Int
    public let total: Int
    public init(remain: Int, total: Int) {
        self.remain = remain
        self.total = total
    }
}

/// EndScreen view-model. `next` / `hot` stay exposed even when `countdown == nil`
/// (host draws the 熱門 variant). `countdown` is non-nil ONLY while core drives the
/// auto-next countdown AND `next` is non-empty (D3).
public final class DefaultEndScreenState {

    private(set) public var next: [LBNavItem] = []
    private(set) public var hot: [LBHotItem] = []
    private(set) public var countdown: LBEndScreenCountdown?

    /// Template-owned `total`, captured at the inactive→active transition; reset to
    /// nil when the countdown goes inactive (D3 — 倒數秒數本身屬 UI).
    private var capturedTotal: Int?

    var onMutation: (() -> Void)?

    init() {}

    /// Ingest one moment-state end-screen snapshot. Diff-then-notify on the
    /// (next ids, hot ids, countdown) tuple.
    func handleMoment(next: [LBNavItem], hot: [LBHotItem],
                      countdownActive: Bool, remain: Int) {
        let total = resolveTotal(active: countdownActive, remain: remain)
        let newCountdown = (countdownActive && !next.isEmpty)
            ? LBEndScreenCountdown(remain: remain, total: total ?? remain)
            : nil
        let changed = next.map(\.id) != self.next.map(\.id)
            || hot.map(\.id) != self.hot.map(\.id)
            || newCountdown != countdown
        guard changed else { return }
        self.next = next
        self.hot = hot
        self.countdown = newCountdown
        onMutation?()
    }

    /// Capture `total` at the inactive→active edge; hold it while active; drop it
    /// once inactive so the next activation re-captures.
    private func resolveTotal(active: Bool, remain: Int) -> Int? {
        guard active else { capturedTotal = nil; return nil }
        if capturedTotal == nil { capturedTotal = remain }
        return capturedTotal
    }
}

// MARK: - 3. ProductOverlay — `{ products, activeProduct }`

/// ProductOverlay view-model. SNAPSHOT of the core products + the single
/// `narrate_status == 2` active product (nil when none). Core pre-computes the
/// active item; the template does NOT scan or re-poll (D4).
public final class DefaultProductOverlayState {

    private(set) public var products: [LBProduct] = []
    private(set) public var activeProduct: LBProduct?

    /// The currently-introducing product's id (= `activeProduct?.id`; LIVE
    /// `narrate_status == 2`, nil when none). The reference-ui product LIST draws
    /// the「介紹中」banner on the row whose id matches this. Pure computed.
    public var introducingProductId: String? { activeProduct?.id }

    /// `products` with the currently-introducing product (`activeProduct`) moved
    /// to the FRONT, preserving the relative order of the rest. When there is no
    /// active product (VOD / nothing introducing) this equals `products` unchanged.
    /// Pure computed (no second state). The reference-ui product LIST binds THIS so
    /// the introducing item sorts first — ORDERING is a data-layer responsibility;
    /// reference-ui MUST NOT re-sort (aligns `screens.jsx` `ProductListSheet`：介紹中排第一).
    public var productsIntroducingFirst: [LBProduct] {
        guard let id = activeProduct?.id,
              let idx = products.firstIndex(where: { $0.id == id }) else { return products }
        var ordered = products
        let item = ordered.remove(at: idx)
        ordered.insert(item, at: 0)
        return ordered
    }

    var onMutation: (() -> Void)?

    init() {}

    /// DIFF by product id array + active id (LBProduct is NOT Equatable, mirror
    /// `DefaultActivityFeed` comparing `winner.id`). An unchanged 5s refresh MUST
    /// NOT re-notify.
    func handleProducts(_ products: [LBProduct], active: LBProduct?) {
        let changed = products.map(\.id) != self.products.map(\.id)
            || active?.id != activeProduct?.id
        guard changed else { return }
        self.products = products
        self.activeProduct = active
        onMutation?()
    }
}

// MARK: - 4. PlayerHeader — `{ isSubscribed, viewerCount, muted }`

/// PlayerHeader view-model for `LBPHostBadge` + `LBLiveTopBar` / `LBPTopBar`.
/// `isSubscribed` / `viewerCount` are sourced from momentState; `muted` from the
/// player mute flag (momentState does NOT carry muted — see the iOS mute wiring
/// gap in the change notes). The top-bar chrome fields (`title` / `hostName` /
/// `shopLogo` / `shareUrl`) are STATIC values read from the public `channel` once
/// loaded (player-chrome-template D3); they coexist with the dynamic mirrors and
/// MUST NOT be re-stored in `LBPlayerMomentState`. Each field diff-then-notify.
public final class DefaultPlayerHeaderState {

    private(set) public var isSubscribed: Bool = false
    private(set) public var viewerCount: Int = 0
    private(set) public var muted: Bool = false  // unmuted by default (sound on; Player States)
    /// LIVE vs VOD flag — `channel.liveStatus == 1`. Host reads this to branch the
    /// top-bar chrome (LIVE pill / viewer count / 直播限定 chrome only when live;
    /// plain top bar for VOD). Channel-derived (fed by `ingestChannel`); default
    /// `false` (neutral/VOD) pre-channel. NOT in `LBPlayerMomentState` (single source).
    private(set) public var isLive: Bool = false

    // MARK: - Top-bar chrome (player-chrome-template D3) — from public `channel`
    /// Host pill 標題 — `channel.title`.
    private(set) public var title: String = ""
    /// Host pill 副標 / 主持人 / 商城名 — `channel.shop.name`.
    private(set) public var hostName: String = ""
    /// Host pill / top-bar logo — `channel.shop.logo`.
    private(set) public var shopLogo: String = ""
    /// Share action context — `channel.share_url`.
    private(set) public var shareUrl: String = ""

    var onMutation: (() -> Void)?

    init() {}

    /// momentState-sourced fields (live subscribe mirror + pv_num).
    func handleHeader(isSubscribed: Bool, viewerCount: Int) {
        guard isSubscribed != self.isSubscribed || viewerCount != self.viewerCount else { return }
        self.isSubscribed = isSubscribed
        self.viewerCount = viewerCount
        onMutation?()
    }

    /// Separate mute source (auto-muted seed at attach; flips on first unmute).
    func handleMuted(_ muted: Bool) {
        guard muted != self.muted else { return }
        self.muted = muted
        onMutation?()
    }

    /// LIVE/VOD flag from the public `channel` (`liveStatus == 1`). Diff-then-notify;
    /// re-feeding the same value is a no-op. Fed inside `ingestChannel`'s coalescing
    /// batch so a single channel ingest fires `onMutation` at most once.
    func handleLive(_ isLive: Bool) {
        guard isLive != self.isLive else { return }
        self.isLive = isLive
        onMutation?()
    }

    /// Top-bar chrome from the public `channel` (read once loaded; idempotent —
    /// re-feeding identical values is a no-op). Diff-then-notify on the 4-field
    /// tuple so a single channel load fires `onMutation` at most once.
    func handleHeaderChrome(title: String, hostName: String, shopLogo: String, shareUrl: String) {
        guard title != self.title || hostName != self.hostName
            || shopLogo != self.shopLogo || shareUrl != self.shareUrl else { return }
        self.title = title
        self.hostName = hostName
        self.shopLogo = shopLogo
        self.shareUrl = shareUrl
        onMutation?()
    }
}

// MARK: - 4a-nav. PlayerNavigation — prev/next adjacent video targets (swipe-navigate-template)

/// Read-only navigation view-model exposing the previous / next adjacent video ids,
/// derived from the public core `channel.prev.first?.id` / `channel.next.first?.id`
/// (`LBNavItem.id`). Fed by `DefaultPlayerTemplate.ingestChannel`; consumed by the
/// reference-ui vertical-swipe-to-switch-video gesture (a separate reference-ui change)
/// and the template's `navigateToPrev()` / `navigateToNext()` forwarders. Diff-then-
/// notify so a channel re-ingest with identical adjacency is a no-op. The ids are NOT
/// re-stored anywhere else — they live only in the core channel until ingested here
/// (single source).
public final class DefaultPlayerNavigation {

    /// Previous video id (`channel.prev.first?.id`), or nil when there is no previous.
    private(set) public var prevVideoId: String?
    /// Next video id (`channel.next.first?.id`), or nil when there is no next.
    private(set) public var nextVideoId: String?

    var onMutation: (() -> Void)?

    init() {}

    /// Ingest the channel-derived adjacency. Diff-then-notify: fires `onMutation`
    /// exactly once iff either id actually changed (a re-ingest of the same pair is a
    /// no-op).
    func ingest(prevVideoId: String?, nextVideoId: String?) {
        guard prevVideoId != self.prevVideoId || nextVideoId != self.nextVideoId else { return }
        self.prevVideoId = prevVideoId
        self.nextVideoId = nextVideoId
        onMutation?()
    }
}

// MARK: - 4b. PlaybackProgress — VOD `{ position, duration, isPlaying, isReplay }`

/// Read-only VOD playback-progress view-model, fed from the core's dedicated
/// `onPlaybackProgressChange` channel (NOT momentState). Drives the reference-ui VOD
/// progress bar / timestamp / play-pause. Diff-then-notify so a 1 Hz tick fires
/// `onMutation` only when a field actually changes.
public final class DefaultPlaybackProgressState {

    private(set) public var position: Double = 0
    private(set) public var duration: Double = 0
    private(set) public var isPlaying: Bool = false
    private(set) public var isReplay: Bool = false

    var onMutation: (() -> Void)?

    init() {}

    func handle(position: Double, duration: Double, isPlaying: Bool, isReplay: Bool) {
        guard position != self.position || duration != self.duration
            || isPlaying != self.isPlaying || isReplay != self.isReplay else { return }
        self.position = position
        self.duration = duration
        self.isPlaying = isPlaying
        self.isReplay = isReplay
        onMutation?()
    }
}

// MARK: - 5. SubtitleTrack — `{ available, enabled }`

/// SubtitleTrack view-model. `available` = `is_subtitle` / `subtitle_url`;
/// `enabled` = current toggle state. Diff-then-notify.
public final class DefaultSubtitleState {

    private(set) public var available: Bool = false
    private(set) public var enabled: Bool = false

    var onMutation: (() -> Void)?

    init() {}

    func handle(available: Bool, enabled: Bool) {
        guard available != self.available || enabled != self.enabled else { return }
        self.available = available
        self.enabled = enabled
        onMutation?()
    }
}
