import LiveBuySDK

// MARK: - DefaultNoticeTab — VideoInfoPanel 公告分頁 open-state
//
// Spec: `ui-template-foundation/spec.md`
//   § "Default Template VideoInfoPanel 公告分頁 open-state 行為"
// Design: design.md D4.
//
// Behaviour / view-model layer ONLY (no pixels). core stays headless: it owns the
// `sys_notice` / `notice` data on `LBChannel` and the "公告分頁任一不為空才開放"
// contract. This model holds a snapshot of the two texts + an explicit `isOpen`,
// and DERIVES `canOpen` (either text non-empty), so the host can draw the panel.

/// One host-bindable notice-tab snapshot. `canOpen` is DERIVED (never stored
/// separately) so it can never drift from the texts.
public struct LBNoticeTabState: Equatable {
    /// Whether the panel may open at all — `true` iff either text is non-empty.
    public let canOpen: Bool
    /// Whether the panel is currently expanded (only ever true when `canOpen`).
    public let isOpen: Bool
    /// System notice text (`sys_notice`).
    public let systemNotice: String
    /// Shop / video notice text (`notice`).
    public let notice: String

    public init(canOpen: Bool, isOpen: Bool, systemNotice: String, notice: String) {
        self.canOpen = canOpen
        self.isOpen = isOpen
        self.systemNotice = systemNotice
        self.notice = notice
    }
}

/// Maps the core's `sys_notice` / `notice` channel data into a host-bindable
/// notice-tab open-state. The owning template injects the latest texts (from
/// `channel`) and the host toggles `isOpen` via `openNoticeTab` / `closeNoticeTab`.
public final class DefaultNoticeTab {

    private(set) public var systemNotice: String = ""
    private(set) public var notice: String = ""
    private(set) public var isOpen: Bool = false

    /// Internal coalesced "notice-tab mutated" hook → owning template's single
    /// host-facing `onChange`. NOT public.
    var onMutation: (() -> Void)?

    public init() {}

    /// DERIVED: the panel may open iff either notice text is non-empty (aligns with
    /// core "公告分頁任一不為空才開放"). Never stored — always computed from texts.
    public var canOpen: Bool { !systemNotice.isEmpty || !notice.isEmpty }

    /// Host-bindable snapshot.
    public var current: LBNoticeTabState {
        LBNoticeTabState(canOpen: canOpen, isOpen: isOpen,
                         systemNotice: systemNotice, notice: notice)
    }

    /// Inject the latest notice texts (from `channel`). If the texts change such
    /// that the panel becomes un-openable while open, `isOpen` is forced false (no
    /// illegal "open but not openable" state, D4). Notifies iff anything changed.
    func injectNotices(systemNotice: String, notice: String) {
        guard systemNotice != self.systemNotice || notice != self.notice else { return }
        self.systemNotice = systemNotice
        self.notice = notice
        if !canOpen { isOpen = false }
        onMutation?()
    }

    /// Host opens the panel — only honoured when `canOpen` (un-openable → no-op).
    public func openNoticeTab() {
        guard canOpen, !isOpen else { return }
        isOpen = true
        onMutation?()
    }

    /// Host closes the panel.
    public func closeNoticeTab() {
        guard isOpen else { return }
        isOpen = false
        onMutation?()
    }
}
