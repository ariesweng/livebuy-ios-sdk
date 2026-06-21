import SwiftUI
import LiveBuySDK
import LiveBuyUI

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
//       hot: [LBHotItem],                           // 熱門變體 set (FIXED SMALL — plain HStack/VStack)
//       onWatchNext: (() -> Void)? = nil,           // → onWatchNext (host-wired)
//       onPickHot: ((LBHotItem) -> Void)? = nil,    // → onPickHot   (host-wired)
//       onCancel: (() -> Void)? = nil)              // → onCancel    (host-wired)
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
//     `next.first` preview card + `onWatchNext` / `onCancel`. 熱門變體 (`countdown
//     == nil` || `next` empty): `hot` as `LBHotCard`s in a PLAIN `HStack`/`VStack`
//     FIXED SMALL set (e.g. first N) + `onPickHot`. `hot[].duration` is an
//     ALREADY-FORMATTED string (`"38:36"`), NOT seconds — render verbatim.
//   • `ErrorScreenView` 依 `kind` 切換人話文案 (NO raw code): `.stream`「播放發生
//     問題」(重試 onRetry + 返回 onDismiss) / `.notFound`「找不到影片」(僅 onDismiss,
//     no retry) / `.outdated`「請更新版本」(前往更新 / onDismiss, no retry). `phase`
//     is always `.failed`. retry is core's job — the CTA only FORWARDS onRetry.
//   • iOS-14-safe SwiftUI only; any >14 API guarded with `@available` /
//     `if #available` inside the sub-view. ⚠️ NO ScrollView / Lazy* in rendered
//     content (the 熱門 list especially — plain HStack/VStack, fixed small set).
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

    // MARK: - Host-wired action closures (design §"守住的不變式": host-wired exit)
    //
    // No template / player moment INTENT exists to forward to — these are wired
    // by the HOST to the core player exits it owns (skipStart / load(next) /
    // load(hot.id) / re-load / dismiss). Each nil-defaulted; a nil closure means
    // an inert CTA (demo / snapshot tests construct the container action-free).

    /// End-screen「立即觀看」→ host → core load(next videoId).
    private let onWatchNext: (() -> Void)?
    /// End-screen 熱門卡片 tap → host → core load(hot.id) (switch to that video).
    private let onPickHot: ((LBHotItem) -> Void)?
    /// End-screen「取消」/「換一批」exit → host.
    private let onCancel: (() -> Void)?
    /// Error-screen「重試」→ host → core re-load. retry is core's job (auto 3×/3s);
    /// this layer ONLY forwards the CTA tap, NEVER retries / loads itself.
    private let onRetry: (() -> Void)?
    /// Error / end-screen「返回」/「關閉」→ host → dismiss the moment / player.
    private let onDismiss: (() -> Void)?

    public init(
        model: MomentsModel,
        theme: ReferenceUITheme,
        onWatchNext: (() -> Void)? = nil,
        onPickHot: ((LBHotItem) -> Void)? = nil,
        onCancel: (() -> Void)? = nil,
        onRetry: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.model = model
        self.theme = theme
        self.onWatchNext = onWatchNext
        self.onPickHot = onPickHot
        self.onCancel = onCancel
        self.onRetry = onRetry
        self.onDismiss = onDismiss
    }

    public var body: some View {
        // Full-screen container. At most ONE moment is shown, by priority:
        // error (highest) > end-countdown > start (not .done) > nothing.
        ZStack {
            activeMoment
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(LBAccessibilityID.momentRoot)
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
            // 2. End screen. countdown != nil → 倒數變體 (auto-next). countdown == nil &&
            //    endScreenVisible → no-countdown「直播已結束」variant (live ended with no
            //    next: hot recommendations if any, else just the title). `hot` is passed
            //    so the sub-view renders the 熱門 variant; `endScreenVisible` gates the title.
            EndScreenView(
                theme: theme,
                countdown: model.countdown,
                next: model.next,
                hot: model.hot,
                liveEnded: model.endScreenVisible && model.countdown == nil,
                onWatchNext: { onWatchNext?() },
                onPickHot: { hot in onPickHot?(hot) },
                onCancel: { onCancel?() })
        } else {
            // 3. Stable playback — no moment overlay. The start lifecycle (loading /
            //    buffering / splash) is NO LONGER a moment: it is composed by the
            //    container as a PLAYER-SHELL start-lifecycle surface (reading
            //    `PlayerShellModel.startPhase`), not here (rb-ios-start-screen-out-of-moments).
            EmptyView()
        }
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
// All five live in `LiveBuySDK` / `LiveBuyUI` with PUBLIC inits reachable from
// `LiveBuyReferenceUI`, so the deterministic snapshot path needs NO live player —
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

    /// A deterministic 熱門 card. `duration` is an ALREADY-FORMATTED STRING
    /// (`"38:36"`), NOT seconds — render verbatim.
    static func demoHotItem(
        id: String = "demo-vid-hot-001",
        title: String = "夏日裸妝教學・10 分鐘上手",
        duration: String = "38:36"
    ) -> LBHotItem {
        LBHotItem(
            id: id,
            cover: "",
            title: title,
            duration: duration)
    }

    /// A demo END moment in the 倒數變體: an active countdown (`remain 3 / total 5`)
    /// + one watch-next preview target + a small 熱門 set. The end-screen surface
    /// agent uses this for the countdown-ring + preview-card fixture.
    static var demoEndCountdown: MomentsModel {
        MomentsModel(
            countdown: LBEndScreenCountdown(remain: 3, total: 5),
            next: [demoNavItem()],
            hot: demoHotSet)
    }

    /// A demo END moment in the 熱門變體: NO countdown, watch-next empty, a FIXED
    /// SMALL 熱門 set (3 cards) for the `LBHotCard` row/grid. The end-screen surface
    /// agent uses this for the 熱門-list fixture (PLAIN HStack/VStack, NOT lazy).
    static var demoEndHotOnly: MomentsModel {
        MomentsModel(
            countdown: nil,
            next: [],
            hot: demoHotSet)
    }

    /// A FIXED SMALL 熱門 set (3 cards) — deterministic, snapshot-stable. Keep it
    /// small (the 熱門 list is a PLAIN HStack/VStack of a fixed N, NEVER lazy/scroll).
    static var demoHotSet: [LBHotItem] {
        [
            demoHotItem(id: "demo-vid-hot-001", title: "夏日裸妝教學・10 分鐘上手", duration: "38:36"),
            demoHotItem(id: "demo-vid-hot-002", title: "辦公室通勤妝・防脫妝技巧", duration: "12:08"),
            demoHotItem(id: "demo-vid-hot-003", title: "新品開箱・霧面唇釉全色號", duration: "07:45")
        ]
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
