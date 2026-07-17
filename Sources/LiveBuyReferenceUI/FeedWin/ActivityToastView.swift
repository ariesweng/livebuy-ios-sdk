import SwiftUI
import LivebuySDK
import LivebuyUI

// MARK: - ActivityToastView — family-2 activity-notification toast (LBActivityToast)
//
// Spec: `reference-ui-rendering/spec.md` § "活動通知 toast（聊天室上方，iOS reference-ui）"
// Design: rb-ios-activity-toast design.md D-1 / D-2 / D-3 (`design/templates/minimal/
// moments.jsx` `LBActivityToast`, 2026-07-03 export — 呈現位置改版).
//
// Group② 炒氣氛提示（進場 / 選購 / 搶購 / 中獎）no longer renders inline in the merged
// chat-feed stream (`ChatFeedView` now filters `.activity` items out of its rows — see
// `ChatFeedView.visibleItems`). This view surfaces them instead as a transient toast above
// the chat feed: only the QUEUE'S NEWEST `.activity` item is shown, sliding in → holding for
// ~2.6s → sliding out. It reads the SAME `items` snapshot `ChatFeedView` receives (no new
// data plumbing, no core/view-model change) and reuses `LBActivityLineRow`'s existing
// tier-styled visuals verbatim — only the PRESENTATION LOCATION changed.
//
// Unlike `CartToastView` (a PURE presentation view whose timer/visibility is owned by its
// container, `ProductSheetsOverlayView`), this view owns its OWN transient state — mirroring
// `moments.jsx`'s `LBActivityToast`, which is itself a self-contained component with its own
// `useState`/`useEffect`/`setTimeout` (unlike `LBPCartToast`, which is driven externally by
// `screens.jsx`). It needs to inspect `items` itself to decide "is the latest activity item
// actually a NEW one", so there is no single external boolean/token to be handed instead.
//
// iOS-14-safe: `.transition` / `.onChange(of:)` / `withAnimation` / `DispatchWorkItem` are
// all iOS-13/14-safe SwiftUI / Foundation APIs.

/// The activity-notification toast: shows the newest `.activity(tier:)` feed item above the
/// chat feed, sliding in, holding ~2.6s, then sliding out. Idle (no activity item shown) →
/// renders zero pixels and zero height (design D-3 — an intentional trade-off vs. the
/// design's constant 26pt reserved slot, made to keep existing snapshot baselines that do
/// not exercise `.activity` items byte-identical; see design.md D-3).
public struct ActivityToastView: View {

    /// The resolved reference-ui theme (FIRST positional argument, always).
    public let theme: ReferenceUITheme

    /// The SAME merged-feed snapshot `ChatFeedView` renders rows from (`FeedWinModel
    /// .feedItems` / `.feedHistory`). This view derives its OWN slice (the latest `.activity`
    /// item) — it MUST NOT be handed a pre-filtered array (single source of truth: `items`).
    public let items: [LBFeedItem]

    /// The activity item currently shown (or about to slide out). `nil` → nothing to paint.
    @State private var shown: LBFeedItem?
    /// Whether `shown` is in its "settled visible" pose (drives the slide transition).
    @State private var visible: Bool = false
    /// The pending auto-dismiss work, cancelled + re-scheduled whenever a genuinely new
    /// activity item supersedes the one currently shown (mirrors `CartToastView`'s
    /// `showCartToast()` timer skeleton).
    @State private var dismissWork: DispatchWorkItem?

    public init(theme: ReferenceUITheme, items: [LBFeedItem]) {
        self.theme = theme
        self.items = items
    }

    public var body: some View {
        ZStack(alignment: .leading) {
            if let shown = shown, visible {
                LBActivityLineRow(theme: theme, text: shown.text, tier: shown.tier ?? .join)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .allowsHitTesting(false)
        .accessibilityIdentifier(LBAccessibilityID.activityToast)
        .onAppear { present(latest: ActivityToastTrigger.latestActivity(in: items)) }
        .onChange(of: items) { newItems in
            present(latest: ActivityToastTrigger.latestActivity(in: newItems))
        }
    }

    /// Present `latest` if (and only if) it genuinely differs from what is currently shown
    /// (`ActivityToastTrigger.shouldPresent`, design D-1). Cancels + reschedules the ~2.6s
    /// auto-dismiss timer on every genuine (re)trigger.
    private func present(latest: LBFeedItem?) {
        guard ActivityToastTrigger.shouldPresent(latest: latest, shown: shown) else { return }
        dismissWork?.cancel()
        shown = latest
        withAnimation(Self.presentAnimation) { visible = true }
        let work = DispatchWorkItem {
            withAnimation(Self.dismissAnimation) { visible = false }
        }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.displayDuration, execute: work)
    }

    /// Hold duration before auto-dismiss (`moments.jsx` `setTimeout(…, 2600)`).
    static let displayDuration: TimeInterval = 2.6
    /// Slide-in spring, approximating the design's `cubic-bezier(0.2,0.9,0.3,1.2)` pop-in.
    static let presentAnimation = Animation.spring(response: 0.36, dampingFraction: 0.78)
    /// Slide-out ease, approximating the design's plain opacity/translate fade.
    static let dismissAnimation = Animation.easeOut(duration: 0.32)
}

// MARK: - ActivityToastTrigger — pure "is this a new activity item" decision (design D-1)
//
// Extracted so the dedupe logic (the only non-trivial decision this view makes) is unit
// testable independent of SwiftUI state/animation timing (docs/unit-test-discipline.md).

enum ActivityToastTrigger {

    /// The queue's newest `.activity(tier:)` item in `items` (oldest → newest order,
    /// unchanged from the merged feed), or `nil` when there is none. Pure — no side effects.
    static func latestActivity(in items: [LBFeedItem]) -> LBFeedItem? {
        items.last(where: { $0.isActivity })
    }

    /// Whether `latest` should (re)trigger the toast, given the item `shown` right now (`nil`
    /// if nothing has been shown yet). `LBFeedItem` is `Equatable` (kind / text / winner),
    /// so two items are "the same" only when every field matches — a strict superset of
    /// `moments.jsx`'s `_k ?? text` fallback key (see design.md D-1). Pure — no side effects.
    static func shouldPresent(latest: LBFeedItem?, shown: LBFeedItem?) -> Bool {
        guard let latest = latest else { return false }
        return latest != shown
    }
}

#if DEBUG
struct ActivityToastView_Previews: PreviewProvider {
    static var previews: some View {
        ActivityToastView(
            theme: ReferenceUIThemePalette.minimal,
            items: [LBFeedItem(kind: .activity(tier: .purchase), text: "Mia 購買了「絲絨唇釉 #04 焦糖」")])
            .padding()
            .background(Color.black)
            .previewLayout(.sizeThatFits)
    }
}
#endif
