import SwiftUI
import Combine
import LiveBuySDK
import LiveBuyUI

// MARK: - MomentsModel — family-4 player moment-state observable snapshot bridge
//
// Spec: `reference-ui-rendering/spec.md` (family-4 moments: end / error / upcoming-countdown)
// Design: rb-ios-moments design.md §"渲染計畫" + §"守住的不變式".
//
// This is the SKELETON for rb-ios-moments. It bridges the headless template
// view-models exposed by `DefaultPlayerTemplate` (obtained via
// `LiveBuyUI.playerTemplate(for:)`) into a SwiftUI-observable snapshot that the
// three family-4 full-screen moment sub-views read. It is a read-only mirror —
// IDENTICAL pattern to `PlayerShellModel` (family-1) / `FeedWinModel` (family-2) /
// `ProductSheetsModel` (family-3):
//
//   - It does NOT own a second copy of authoritative state — it republishes
//     SNAPSHOT VALUES taken from the template's own `private(set) public` reads
//     (`endScreen.countdown` / `endScreen.hot` / `endScreen.next` /
//     `errorState.current` / `upcoming.*`) each time the template fires its
//     single coalesced `onChange` (design §"容器與 view-model 橋接"). The start
//     lifecycle (`startScreen.phase`) is NO LONGER mirrored here — it is a
//     player-shell concern (`PlayerShellModel.startPhase`).
//   - It does NOT add pixels and it does NOT add any accessor to `LiveBuyUI`
//     (that would be a template-layer concern, out of scope here).
//   - It does NOT subscribe to each moment model's internal `onMutation` (that is
//     a template-internal hook); it observes ONLY the template's single public
//     `onChange` (design §"守住的不變式": 只讀呈現).
//   - It carries NO mutating interactions / forwarders. UNLIKE family-2/3 there is
//     NO public template / player moment intent for skip / retry / watch-next /
//     pick-hot / cancel / dismiss to forward to. The design states the moment
//     actions are HOST-WIRED CONTAINER closures (like family-3's `onProductTap`),
//     NOT template methods — so this model is a PURE read-only snapshot. The
//     container (`MomentsOverlayView`) carries the host-wired exits; this model
//     does NOT (do NOT invent template forwarders — none exist for moments).
//
// iOS-14-safe: `ObservableObject` + `@Published` are available from iOS 13, so
// no `@available` guard is needed here.

/// Observable snapshot of the family-4 player moment state, republished from a
/// live `DefaultPlayerTemplate` (or constructed deterministically for demos /
/// snapshot tests via the memberwise initializer).
public final class MomentsModel: ObservableObject {

    // MARK: - Published surface snapshots
    //
    // Each group is the read-only value set ONE family-4 moment sub-view needs.
    // The grouping mirrors the three moments so a sub-view binds exactly the
    // snapshot values it needs (see the documented sub-view input pattern in
    // MomentsOverlayView.swift).

    // NOTE: the start lifecycle (loading / buffering / splash) is NO LONGER a moment.
    // It moved to the player shell (`PlayerShellModel.startPhase`) and is composed by the
    // container as a player-shell start-lifecycle surface (rb-ios-start-screen-out-of-moments).
    // `MomentsModel` carries only the end / error / upcoming-countdown surfaces.

    // -- Surface 1: EndScreenView ← auto-next countdown + next + hot (design §2) -

    /// Auto-next countdown snapshot (`DefaultEndScreenState.countdown`); non-nil
    /// ONLY while core drives the auto-next countdown AND `next` is non-empty
    /// (`countdown != nil` ⇔ 倒數變體, nil ⇔ 熱門變體). `{ remain, total }` —
    /// ring progress = `remain / total`. The container shows the end moment when
    /// `countdown != nil` (else the hot variant is governed by the sub-view).
    @Published public private(set) var countdown: LBEndScreenCountdown?
    /// Watch-next targets (`DefaultEndScreenState.next`). The 倒數變體 preview card
    /// reads `next.first` (`cover` / `title?` / `shopName` / `duration:Int`).
    @Published public private(set) var next: [LBNavItem]
    /// 熱門推薦 set (`DefaultEndScreenState.hot`). Rendered as a FIXED SMALL set in
    /// a PLAIN `HStack`/`VStack` (NEVER lazy/scroll — see the no-Lazy constraint).
    /// `duration` is an ALREADY-FORMATTED string (e.g. `"38:36"`, NOT seconds).
    @Published public private(set) var hot: [LBHotItem]

    /// Whether the end screen should be shown at all (`DefaultEndScreenState.endScreenVisible`,
    /// mirrors core `endScreenShown`). True on live_end REGARDLESS of next/hot. The container
    /// shows the end moment when `countdown != nil || endScreenVisible`; when `countdown == nil`
    /// && `endScreenVisible`, EndScreenView renders the no-countdown「直播已結束」variant
    /// (end-screen-no-countdown #6c).
    @Published public private(set) var endScreenVisible: Bool

    // -- Surface 2: ErrorScreenView ← terminal error snapshot (design §3) -------

    /// Terminal player error snapshot (`DefaultErrorState.current`); nil when the
    /// player is not in `error`. `{ kind, phase }` — `phase` is always `.failed`
    /// (core does not expose `.retrying`). `kind` (`.stream` / `.notFound` /
    /// `.outdated`) is ALREADY classified by the template; this layer MUST NOT
    /// re-classify `LBError`. The container shows the error moment (HIGHEST
    /// priority) when `error != nil`.
    @Published public private(set) var error: LBPlayerErrorState?

    // -- Surface 3: UpcomingCountdownView ← 直播預告等待開播（DefaultUpcomingState）-----

    /// Whether the player is awaiting a not-yet-started live (`DefaultUpcomingState.active`).
    /// The container shows the upcoming-countdown moment (after error, before start) when true.
    @Published public private(set) var upcomingActive: Bool
    /// Scheduled start (`DefaultUpcomingState.scheduledStartAt` / backend `publish_at`),
    /// passed through verbatim; the countdown surface parses it for display.
    @Published public private(set) var upcomingStartAt: String
    /// Video cover URL (`DefaultUpcomingState.cover` / backend `channel.cover`); the
    /// upcoming moment renders it as its background (design `LBLiveUpcomingOverlay`).
    @Published public private(set) var upcomingCover: String

    // MARK: - Live binding

    /// The bound template, when constructed from a live player. nil for demo /
    /// snapshot instances. Held weakly so this model never retains the template
    /// (the player VC owns it; dependency stays one-way UI → core).
    private weak var template: DefaultPlayerTemplate?

    /// The template's `onChange` we installed, so we can restore the previous one
    /// on deinit (we chain rather than clobber — same as the family-1/2/3 models).
    private var previousOnChange: (() -> Void)?

    // MARK: - Live initializer (design §"容器與 view-model 橋接")

    /// Bridge a live `DefaultPlayerTemplate`: take an initial snapshot and
    /// subscribe to its single coalesced `onChange` so every start-phase change /
    /// end-screen countdown advance / next / hot update / error record / clear
    /// re-snapshots and republishes to the moment sub-views.
    ///
    /// The host obtains the template via `LiveBuyUI.playerTemplate(for:)` and
    /// passes it here. Returns a model whose published values mirror the template
    /// (read-only). The previous `onChange` (if any host already installed one) is
    /// chained, not replaced.
    public convenience init(template: DefaultPlayerTemplate) {
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
    private convenience init(snapshotting t: DefaultPlayerTemplate) {
        self.init(
            countdown: t.endScreen.countdown,
            next: t.endScreen.next,
            hot: t.endScreen.hot,
            endScreenVisible: t.endScreen.endScreenVisible,
            error: t.errorState.current,
            upcomingActive: t.upcoming.active,
            upcomingStartAt: t.upcoming.scheduledStartAt,
            upcomingCover: t.upcoming.cover
        )
    }

    // MARK: - Memberwise / demo initializer (design §"容器與 view-model 橋接")

    /// Construct a deterministic instance WITHOUT a live player — for the moment
    /// sub-views' previews and the per-surface snapshot tests. Every value defaults
    /// to the at-attach seed (no countdown, no next / hot, no error) so a
    /// zero-argument call yields a stable baseline that matches the freshly-
    /// constructed template models:
    ///   • `DefaultEndScreenState.countdown` == nil, `next` / `hot` == [].
    ///   • `DefaultErrorState.current` == nil.
    public init(
        countdown: LBEndScreenCountdown? = nil,
        next: [LBNavItem] = [],
        hot: [LBHotItem] = [],
        endScreenVisible: Bool = false,
        error: LBPlayerErrorState? = nil,
        upcomingActive: Bool = false,
        upcomingStartAt: String = "",
        upcomingCover: String = ""
    ) {
        self.countdown = countdown
        self.next = next
        self.hot = hot
        self.endScreenVisible = endScreenVisible
        self.error = error
        self.upcomingActive = upcomingActive
        self.upcomingStartAt = upcomingStartAt
        self.upcomingCover = upcomingCover
    }

    deinit {
        // Restore the previous handler so a re-bound template is not left with a
        // dangling closure capturing this (now gone) model.
        template?.onChange = previousOnChange
    }

    // MARK: - Re-snapshot on change (design §"容器與 view-model 橋接")

    /// Pull the latest values from the bound template into the published mirrors.
    /// Always on the main thread (the template dispatches `onChange` on main; the
    /// live init only installs this from the main-thread `onChange`). `objectWill
    /// Change` fires once per `@Published` write — acceptable for the skeleton;
    /// moment sub-views read final values within one runloop.
    private func refresh(from t: DefaultPlayerTemplate) {
        countdown = t.endScreen.countdown
        next = t.endScreen.next
        hot = t.endScreen.hot
        endScreenVisible = t.endScreen.endScreenVisible
        error = t.errorState.current
        upcomingActive = t.upcoming.active
        upcomingStartAt = t.upcoming.scheduledStartAt
        upcomingCover = t.upcoming.cover
    }
}
