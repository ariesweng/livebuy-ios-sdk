import SwiftUI
import LivebuySDK
import LivebuyUI

// MARK: - MomentsOverlayView — family-4 player moment container (SKELETON)
//
// Spec: `reference-ui-rendering/spec.md` (family-4 moments: end / error / upcoming-countdown)
// Design: rb-ios-moments design.md §1 (start) / §2 (end) / §3 (error) +
//          §"CRITICAL 渲染約束" + §"Family boundary".
//
// The top-level family-4 container (this is the design's `MomentsView` role; the
// file/type name is `MomentsOverlayView` to read as a full-screen overlay
// composited over the player, mirroring `FeedWinOverlayView` /
// `ProductSheetsOverlayView`). It is a FULL-SCREEN container that conditionally
// shows the single ACTIVE player-lifecycle moment over the video area:
//
//   1. ErrorScreenView  — terminal error screen   (design §3, `LBPErrorScreen`)
//   2. EndScreenView    — auto-next countdown ring + watch-next + 熱門推薦
//                          (design §2, `LBPEndScreen` + `LBPHotCard`)
//
// The start lifecycle (loading / buffering / splash) is NO LONGER a moment — it is a
// player-shell surface (`StartScreenView` reading `PlayerShellModel.startPhase`),
// composed by the container, not here (rb-ios-start-screen-out-of-moments).
//
// ─────────────────────────────────────────────────────────────────────────────
// MOMENT PRIORITY (mutually exclusive — at most ONE moment is on screen)
// ─────────────────────────────────────────────────────────────────────────────
// The container shows the HIGHEST-priority active moment and nothing else:
//
//   1. error  != nil                         → ErrorScreenView   (HIGHEST)
//   2. else countdown != nil                 → EndScreenView     (倒數變體)
//   3. else                                  → nothing (stable playback)
//
// NOTE — the END moment's TWO variants: the container shows EndScreenView when
// `countdown != nil` (the 倒數 variant, design §2). The 熱門 variant (`countdown ==
// nil` or `next` empty) is governed BY the sub-view itself once shown; the
// SKELETON gates EndScreenView on `countdown != nil` only (the 熱門-only end
// screen with no countdown is a follow-up gating refinement for the end-screen
// surface agent — the sub-view always accepts `hot` so it can render either
// variant). Error always wins.
//
// PRESENTATION MODEL — these are FULL-SCREEN moments, NOT `.sheet(item:)`
// presentations (unlike family-2's claim sheet / family-3's detail sheet). The
// container draws the active moment as a full-bleed `ZStack` layer; there is no
// local `@State` presentation binding (the model snapshot drives which moment is
// active).
//
// ─────────────────────────────────────────────────────────────────────────────
// HOST-WIRED ACTION CLOSURES (design §"守住的不變式": host-wired exit)
// ─────────────────────────────────────────────────────────────────────────────
// UNLIKE family-2/3, there is NO public template / player moment INTENT to forward
// to (no `skip` / `retry` / `watchNext` / `pickHot` / `cancel` / `dismiss` on
// `DefaultPlayerTemplate`). So the moment actions are HOST-WIRED CONTAINER closures
// — EXACTLY like family-3's `onProductTap` (the open is the host's / core's job,
// not this layer's). The host wires them to the core player exits it owns, e.g.:
//   • onWatchNext  → host → core load(next videoId) / watch-next exit
//   • onPickHot    → host → core load(hot.id) (switch to the tapped hot video)
//   • onCancel     → host → dismiss the end screen / stay
//   • onRetry      → host → core re-load (retry is core's job — SDK auto-retries
//                    3×/3s; this layer ONLY forwards the CTA tap, never retries)
//   • onDismiss    → host → dismiss the error / end screen / player
//
// Every closure is nil-defaulted, so the container renders correctly action-free
// (demo / snapshot tests construct it without host wiring); a nil closure means
// the corresponding CTA is inert. This layer NEVER calls core skip / retry / load
// itself (design §"守住的不變式": 互動一律 host-wired exit 轉發).
//
// This is the SKELETON: it owns the layout + a `MomentsModel` + the resolved
// `ReferenceUITheme` + the host-wired action closures, and composes the three
// moment sub-views BY TYPE NAME. The three sub-view TYPES are produced by the
// three parallel surface agents that run after this skeleton — see the "SUB-VIEW
// INPUT PATTERN" contract below, which every surface agent MUST implement verbatim
// so the container's call sites match.
//
// Until all three moment sub-views exist, this file will not compile on its own —
// that is expected (the surface agents land the types). The container's job is to
// FIX the layout + the call-site shape + the demo construction recipe so the
// parallel agents converge.
//
// iOS-14-safe: `ZStack` / `VStack` / `HStack` / `Spacer` / manual padding are all
// iOS-13+; no `@available` guard needed here. Any surface that reaches for a >14
// API must guard it inside its own sub-view (design §"守住的不變式": iOS-14 樓地板).
//
// ⚠️ NO ScrollView / LazyVStack / LazyHStack / LazyVGrid anywhere in rendered
// content — `ImageRenderer` renders them BLANK (the family-3 lesson). The
// EndScreen 熱門 list MUST be a PLAIN `HStack`/`VStack` of a FIXED SMALL set.
//
// ─────────────────────────────────────────────────────────────────────────────
// SUB-VIEW INPUT PATTERN — the contract the 3 parallel surface agents MUST follow
// ─────────────────────────────────────────────────────────────────────────────
//
// Every family-4 moment sub-view is a `public struct …: View` whose initializer
// takes, IN THIS ORDER (identical convention to family-1 / family-2 / family-3):
//
//   1. `theme: ReferenceUITheme`            — the resolved reference-ui theme
//                                             (FIRST positional argument, always).
//   2. its bound SNAPSHOT VALUE(S)          — the read-only state it renders,
//                                             passed BY VALUE from MomentsModel
//                                             (never the model, never the template).
//   3. optional action closures            — trailing, each defaulting to `nil`
//                                             (`onX: (() -> Void)? = nil`, etc.).
//                                             The container does NOT own actions;
//                                             they forward to the host-wired
//                                             container closures (NO template
//                                             forwarders exist for moments).
//
// Concretely, the moment surface agents implement EXACTLY these initializers:
//
//   EndScreenView(
//       theme: ReferenceUITheme,
//       countdown: LBEndScreenCountdown?,           // non-nil → 倒數變體
//       next: [LBNavItem],                          // watch-next targets (next.first = preview)
//       liveDuration: String = "",                  // 空狀態變體「直播時長：」line (formatted)
//       onWatchNext: (() -> Void)? = nil,           // → onWatchNext (host-wired)
//       onCancel: (() -> Void)? = nil,              // → onCancel    (host-wired; now CLOSES)
//       onViewCart: (() -> Void)? = nil)            // → onViewCart  (host-wired)
//
//   ErrorScreenView(
//       theme: ReferenceUITheme,
//       error: LBPlayerErrorState,                  // non-optional (container gates on non-nil)
//       onRetry: (() -> Void)? = nil,               // → onRetry   (host-wired; shown only for .stream)
//       onDismiss: (() -> Void)? = nil)             // → onDismiss (host-wired)
//
// Rules every surface agent honours:
//   • FIRST positional arg is `theme:`. Snapshot values are passed BY VALUE.
//   • Action closures are LAST, each `… = nil` (the container passes the host-wired
//     closure or omits it). A moment sub-view MUST render correctly with all
//     actions nil (so demo / snapshot tests construct it action-free).
//   • A moment sub-view reads ONLY its passed-in values — it MUST NOT reach back
//     into MomentsModel or DefaultPlayerTemplate (one-way data flow). It MUST NOT
//     hold a second copy of phase / countdown / error, MUST NOT re-classify
//     `LBError` (kind is pre-classified), MUST NOT drive the countdown / skip /
//     retry itself (core owns those — design §"守住的不變式": 只讀呈現).
//   • `EndScreenView` 倒數變體 (`countdown != nil` && !next.isEmpty): SVG-style
//     ring (progress = `countdown.remain / countdown.total`, centre `remain`) +
//     `next.first` preview card + `onWatchNext` / `onCancel`（取消現在會關閉整個
//     session）. 空狀態變體 (`countdown == nil` || `next` empty, LIVE ONLY —
//     `rb-ios-endscreen-live-empty-state`)：「直播已結束」title +「直播時長：…」line
//     + 全寬「查看購物車」CTA (`onViewCart`)。舊「熱門變體」卡牆已退役——`LBHotItem` /
//     `onPickHot` 不再轉發給這個 sub-view（`MomentsOverlayView.onPickHot` 為了 wire
//     相容仍留在本容器自己的 init 上，但現在未使用 / inert，見下方）。
//   • `ErrorScreenView` 依 `kind` 切換人話文案 (NO raw code): `.stream`「播放發生
//     問題」(重試 onRetry + 返回 onDismiss) / `.notFound`「找不到影片」(僅 onDismiss,
//     no retry) / `.outdated`「請更新版本」(前往更新 / onDismiss, no retry). `phase`
//     is always `.failed`. retry is core's job — the CTA only FORWARDS onRetry.
//   • iOS-14-safe SwiftUI only; any >14 API guarded with `@available` /
//     `if #available` inside the sub-view. ⚠️ NO ScrollView / Lazy* in rendered
//     content.
// ─────────────────────────────────────────────────────────────────────────────
//
// ─────────────────────────────────────────────────────────────────────────────
// EndScreen IS NOW LIVE-ONLY (`rb-ios-endscreen-live-empty-state`)
// ─────────────────────────────────────────────────────────────────────────────
// A VOD (non-live) video ending with NO queued `next` no longer shows the END
// moment at all — the RETIRED 熱門變體 used to fill that gap; without it there is
// nothing meaningful to show, so the player CLOSES directly instead. THIS
// CONTAINER decides that (the `isLiveChannel` input below + the pure function
// `shouldCloseInsteadOfEndScreen`), NOT `EndScreenView` — `EndScreenView` is never
// even constructed for that case. A VOD ending WITH a queued `next` is UNCHANGED /
// out of scope (this path does not currently occur — see design.md).
// `isLiveChannel` is DISTINCT from `live` above: `live` gates whether the
// end-screen preview card loads REAL media vs. a placeholder; `isLiveChannel` is
// the channel's LIVE-vs-VOD classification (mirrors `PlayerShellModel.isLive`,
// threaded in by the container as its own reactive `isLiveMode` mirror — see
// `MinimalDesign.swift`). Do not conflate the two.
// ─────────────────────────────────────────────────────────────────────────────

/// The family-4 full-screen player moment container. Conditionally shows the
/// single ACTIVE player-lifecycle moment (error > end-countdown, mutually
/// exclusive) over the video area; reads a `MomentsModel` (republished from a live
/// `DefaultPlayerTemplate` or constructed deterministically) and paints with the
/// resolved `ReferenceUITheme`. All moment actions are host-wired container
/// closures (no template moment intents exist).
public struct MomentsOverlayView: View {

    /// The republished, read-only player moment snapshot.
    @ObservedObject public var model: MomentsModel

    /// The resolved reference-ui theme.
    public let theme: ReferenceUITheme

    /// Runtime media gate threaded into `EndScreenView` (default `false` → snapshot /
    /// demo construct action-free with placeholder-only cards). `true` (host runtime) →
    /// the end-screen next-video preview card loads real `cover` / `preview` media.
    /// Wired by the container as `!paintsBackgroundPlaceholder` (the SAME flag the
    /// product sheets / start-screen surfaces use). NOT the channel's live/VOD status
    /// — see `isLiveChannel` below; do not conflate the two.
    public let live: Bool

    /// The channel's LIVE-vs-VOD classification (mirrors `PlayerShellModel.isLive`).
    /// Drives `shouldCloseInsteadOfEndScreen` (`rb-ios-endscreen-live-empty-state`):
    /// EndScreen is now LIVE-ONLY, so a VOD (`false`) ending with no queued `next`
    /// closes the player instead of showing the end moment. Threaded by the
    /// container from its own reactive `isLiveMode` mirror (see `MinimalDesign.swift`
    /// `PlayerOverlayRootView`) — NOT from `model` (this container does not own a
    /// live/VOD signal of its own; `MomentsModel` has none). DISTINCT from `live`
    /// above (media-loading gate); do not conflate the two.
    public let isLiveChannel: Bool

    // MARK: - Host-wired action closures (design §"守住的不變式": host-wired exit)
    //
    // No template / player moment INTENT exists to forward to — these are wired
    // by the HOST to the core player exits it owns (skipStart / load(next) /
    // re-load / dismiss / open product list). Each nil-defaulted; a nil closure
    // means an inert CTA (demo / snapshot tests construct the container action-free).

    /// End-screen「立即觀看」→ host → core load(next videoId).
    private let onWatchNext: (() -> Void)?
    /// RETIRED consumer (`rb-ios-endscreen-live-empty-state`): the 熱門變體 card wall
    /// `EndScreenView` used to render this against no longer exists, so this closure
    /// is no longer forwarded to `EndScreenView`. Kept on this container's own init
    /// for WIRE STABILITY (the upstream `LivebuyPlayerConfig.onPickHot` seam and its
    /// `PlayerOverlayContext` / `ReferenceUIDesign` threading are NOT touched by this
    /// change — out of scope, see design.md) — a host that still sets it keeps
    /// compiling, the closure is simply never invoked from here any more.
    private let onPickHot: ((LBHotItem) -> Void)?
    /// End-screen「取消」exit → host, which now CLOSES the whole player session
    /// (`LivebuyPlayer.swift` `makeOverlayContext`'s default `onCancel`: `player
    /// .cancelAutoNext()` + the SAME dismiss resolution `onDismiss` uses). This
    /// container only forwards the tap.
    private let onCancel: (() -> Void)?
    /// Error-screen「重試」→ host → core re-load. retry is core's job (auto 3×/3s);
    /// this layer ONLY forwards the CTA tap, NEVER retries / loads itself.
    private let onRetry: (() -> Void)?
    /// Error / end-screen「返回」/「關閉」→ host → dismiss the moment / player. ALSO
    /// fired (via `.onChange` below) when `shouldCloseInsteadOfEndScreen` flips true
    /// (VOD ends with no `next` — closes instead of entering the end moment).
    private let onDismiss: (() -> Void)?
    /// End-screen 空狀態變體「查看購物車」CTA → host (wired by `PlayerOverlayRootView`
    /// to the SAME `onOpenProductList` action the LIVE bottom bar's bag button uses).
    /// `rb-ios-endscreen-live-empty-state`.
    private let onViewCart: (() -> Void)?

    public init(
        model: MomentsModel,
        theme: ReferenceUITheme,
        live: Bool = false,
        isLiveChannel: Bool,
        onWatchNext: (() -> Void)? = nil,
        onPickHot: ((LBHotItem) -> Void)? = nil,
        onCancel: (() -> Void)? = nil,
        onRetry: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil,
        onViewCart: (() -> Void)? = nil
    ) {
        self.model = model
        self.theme = theme
        self.live = live
        self.isLiveChannel = isLiveChannel
        self.onWatchNext = onWatchNext
        self.onPickHot = onPickHot
        self.onCancel = onCancel
        self.onRetry = onRetry
        self.onDismiss = onDismiss
        self.onViewCart = onViewCart
    }

    public var body: some View {
        // Full-screen container. At most ONE moment is shown, by priority:
        // error (highest) > end-countdown > start (not .done) > nothing.
        ZStack {
            activeMoment
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(LBAccessibilityID.momentRoot)
        // VOD ends with no queued `next` (`shouldCloseForVodNoNext` flips true) →
        // close the player instead of leaving the (unrendered) end moment up.
        // `.onChange` only fires on a genuine transition (never on initial mount),
        // which matches this container's real lifecycle: it is mounted once per
        // player session, BEFORE `endScreenVisible` can ever be true, so the
        // transition is always observed (rb-ios-endscreen-live-empty-state).
        .onChange(of: shouldCloseForVodNoNext) { shouldClose in
            if shouldClose { onDismiss?() }
        }
    }

    /// Whether the CURRENT snapshot should close the player instead of entering the
    /// end moment at all — the end-screen gate (`countdown != nil || endScreenVisible`)
    /// is active AND `Self.shouldCloseInsteadOfEndScreen` says so. Drives BOTH
    /// `activeMoment`'s branch (never construct `EndScreenView` in this case) and the
    /// `.onChange`-driven `onDismiss` side effect in `body` above.
    private var shouldCloseForVodNoNext: Bool {
        (model.countdown != nil || model.endScreenVisible)
            && Self.shouldCloseInsteadOfEndScreen(isLiveChannel: isLiveChannel, next: model.next)
    }

    /// The single active moment by priority, or `EmptyView` for stable playback.
    /// Mutually exclusive — error wins, then the auto-next countdown end screen.
    @ViewBuilder
    private var activeMoment: some View {
        if let error = model.error {
            // 1. Terminal error — HIGHEST priority. Non-optional inside (gated here).
            ErrorScreenView(
                theme: theme,
                error: error,
                onRetry: { onRetry?() },
                onDismiss: { onDismiss?() })
        } else if model.countdown != nil || model.endScreenVisible {
            if shouldCloseForVodNoNext {
                // VOD ended with no `next` — EndScreen is LIVE-ONLY
                // (rb-ios-endscreen-live-empty-state): nothing meaningful to show.
                // `body`'s `.onChange` closes the player; render nothing here.
                EmptyView()
            } else {
                // 2. End screen. countdown != nil → 倒數變體 (auto-next). countdown ==
                //    nil && endScreenVisible → 空狀態變體（「直播已結束」+ 直播時長 +
                //    查看購物車 CTA，LIVE-only；VOD-with-no-next never reaches here}.
                EndScreenView(
                    theme: theme,
                    countdown: model.countdown,
                    next: model.next,
                    live: live,
                    onWatchNext: { onWatchNext?() },
                    onCancel: { onCancel?() },
                    onViewCart: { onViewCart?() })
            }
        } else {
            // 3. Stable playback — no moment overlay. The start lifecycle (loading /
            //    buffering / splash) is NO LONGER a moment: it is composed by the
            //    container as a PLAYER-SHELL start-lifecycle surface (reading
            //    `PlayerShellModel.startPhase`), not here (rb-ios-start-screen-out-of-moments).
            EmptyView()
        }
    }

    /// Test-only read window onto `activeMoment` (`*ForTesting` naming per
    /// `docs/unit-test-discipline.md` — mirrors the established `iconClusterForTesting`
    /// precedent, `PlayerHeaderBarView`). Lets a Mirror-reflection test confirm which
    /// branch renders WITHOUT touching `UIViewRepresentable.makeUIView` / actual
    /// rendering.
    var activeMomentForTesting: some View { activeMoment }

    // MARK: - Pure decision (internal-testability)

    /// Whether the end moment should be REPLACED by a direct player close
    /// (`rb-ios-endscreen-live-empty-state`): EndScreen is LIVE-ONLY, so a VOD
    /// (`isLiveChannel == false`) ending with no queued `next` has nothing meaningful
    /// to show — the 熱門變體 fallback that used to fill this gap is retired. A LIVE
    /// channel (`isLiveChannel == true`) with empty `next` is UNCHANGED — it renders
    /// `EndScreenView`'s 空狀態變體. A VOD ending WITH a queued `next` is also
    /// UNCHANGED / out of scope (this path does not currently occur — see design.md).
    /// Pure — no view state, no I/O. Mirrors `resolvedEnableDirectCloseButton`'s shape
    /// (`LivebuyPlayerPresenter.swift`).
    static func shouldCloseInsteadOfEndScreen(isLiveChannel: Bool, next: [LBNavItem]) -> Bool {
        !isLiveChannel && next.isEmpty
    }
}

// MARK: - Deterministic demo construction recipe (previews + snapshot tests)
//
// VERIFIED CONSTRUCTION PATHS — the 3 parallel surface agents MUST use these so
// the demo / snapshot fixtures stay consistent and COMPILE. All inits below were
// VERIFIED against the real public sources:
//
//   • LBEndScreenCountdown(remain: Int, total: Int)  (DefaultMomentStates.swift) —
//     PUBLIC memberwise init. Ring progress = `remain / total`. e.g.
//     `LBEndScreenCountdown(remain: 3, total: 5)`.
//   • LBNavItem(id: String, cover: String, title: String?, duration: Int,
//       shopName: String)  (LBModels.swift) — PUBLIC init. NOTE `title` is OPTIONAL
//     `String?` and `duration` is an `Int` (seconds). e.g.
//     `LBNavItem(id: "v-002", cover: "", title: "下一支・週五美妝直播",
//                duration: 1830, shopName: "Aurora 美妝")`.
//   • LBHotItem(id: String, cover: String, title: String, duration: String)
//       (LBModels.swift) — PUBLIC init. NOTE `duration` is a STRING already
//     FORMATTED (e.g. `"38:36"`, NOT seconds) — render verbatim. e.g.
//     `LBHotItem(id: "h-001", cover: "", title: "夏日裸妝教學", duration: "38:36")`.
//   • LBPlayerErrorState(kind: LBPlayerErrorKind, phase: LBPlayerErrorPhase)
//       (DefaultErrorState.swift) — PUBLIC init. `kind`: `.stream` / `.notFound` /
//     `.outdated`; `phase`: `.failed` (the only case). e.g.
//     `LBPlayerErrorState(kind: .stream, phase: .failed)`.
//
// All five live in `LivebuySDK` / `LivebuyUI` with PUBLIC inits reachable from
// `LivebuyReferenceUI`, so the deterministic snapshot path needs NO live player —
// the `MomentsModel` memberwise init stores these values directly.

public extension MomentsModel {

    // MARK: End-moment demo fixtures
    //
    // NOTE: the start lifecycle (loading / buffering / splash) is no longer a moment —
    // its demo / snapshot fixtures live with the player-shell surface
    // (`StartScreenView.demo(phase:)`), not here (rb-ios-start-screen-out-of-moments).

    /// A deterministic watch-next target (`next.first` preview card source).
    /// `title` is OPTIONAL `String?`; `duration` is an `Int` (seconds).
    static func demoNavItem(
        id: String = "demo-vid-next-001",
        title: String? = "下一支・週五美妝直播",
        duration: Int = 1830
    ) -> LBNavItem {
        LBNavItem(
            id: id,
            cover: "",
            title: title,
            duration: duration,
            shopName: "Aurora 美妝旗艦")
    }

    /// A demo END moment in the 倒數變體: an active countdown (`remain 3 / total 5`)
    /// + one watch-next preview target. The end-screen surface agent uses this for
    /// the countdown-ring + preview-card fixture. `hot` defaults to `[]` — `MomentsModel
    /// .hot` remains populated from the live template (unchanged, template layer),
    /// but is no longer consumed by `EndScreenView` (`rb-ios-endscreen-live-empty-state`
    /// retired the 熱門變體 it used to feed), so this demo fixture no longer bothers
    /// seeding it.
    static var demoEndCountdown: MomentsModel {
        MomentsModel(
            countdown: LBEndScreenCountdown(remain: 3, total: 5),
            next: [demoNavItem()])
    }

    // MARK: Error-moment demo fixtures

    /// A demo ERROR moment — `.stream`「播放發生問題」(重試 + 返回). Default kind.
    static func demoError(kind: LBPlayerErrorKind = .stream) -> MomentsModel {
        MomentsModel(error: LBPlayerErrorState(kind: kind, phase: .failed))
    }

    /// `.notFound`「找不到影片」(僅返回, no retry).
    static var demoErrorNotFound: MomentsModel { demoError(kind: .notFound) }

    /// `.outdated`「請更新版本」(前往更新 / 關閉, no retry).
    static var demoErrorOutdated: MomentsModel { demoError(kind: .outdated) }
}
