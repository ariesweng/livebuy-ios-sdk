import SwiftUI
import LivebuySDK
import LivebuyUI

// MARK: - LiveActivitySheetView — family-2 抽獎活動參加彈窗（rb-ios-live-activity-sheet）
//
// Spec: `reference-ui-rendering/spec.md`
//   § "LivebuyReferenceUI 渲染抽獎活動參加彈窗，綁 DefaultActiveEvent（iOS）"
// Design: `design/templates/minimal/moments.jsx` `LBActivitySheet` +
//         rb-ios-live-activity-sheet design.md D2 / D3 / D4 / D5.
//
// This is family-2's fourth surface: a CENTERED MODAL (scrim + card, full-bleed
// overlay — same presentation convention as `WinClaimModalView`), opened by the
// `.activity` variant of `WinEntryView`, bound to `DefaultActiveEvent.currentActivity`
// (`live-activity-entry-template`, already applied — this file only READS its
// exposed public surface).
//
// ─────────────────────────────────────────────────────────────────────────────
// SINGLE-STAGE, NOT a `WinClaimModalView` four-stage clone (design.md D3;
// updated by `rb-ios-activity-sheet-cta-repeatable`)
// ─────────────────────────────────────────────────────────────────────────────
// `WinClaimModalView` runs `claim → confirmSubmit/confirmClose → submitting →
// done/fail` because the win-claim submit has an ASYNCHRONOUS backend result to
// wait for. Joining an activity (`joinCurrentActivity()` → `EVENT_JOIN_INTENT`) is
// FIRE-AND-FORGET — core never reports success/failure for it (see
// `live-activity-entry-template` design.md D3). This view carries NO UI-local
// state at all — the CTA is a stateless, repeatable dispatch: it always reads
// "立即參加" and always fires `onJoin?()` on tap, with nothing to reconcile
// against and nothing to gate a second (or third, or Nth) tap on
// (`rb-ios-activity-sheet-cta-repeatable` — the previous single `@State private
// var joined` boolean has been removed; not even ONE piece of local state is
// needed anymore). Do NOT grow this into a `WinClaimModalView`-shaped type — the
// two flows are shaped differently for a real reason (async result vs. none) and
// forcing them to share code would drag `WinClaimModalView`'s unrelated
// four-stage concerns into review here.
//
// ─────────────────────────────────────────────────────────────────────────────
// SUB-VIEW INPUT PATTERN (mirrors `WinClaimModalView` / `WinEntryView`)
// ─────────────────────────────────────────────────────────────────────────────
//   1. `theme: ReferenceUITheme`  — FIRST positional argument.
//   2. `activity: LBActiveEvent`  — the bound snapshot value, passed BY VALUE from
//      the container (`FeedWinOverlayView` guards non-nil via `model.currentActivity`
//      before mounting this view — see that file's §3.3).
//   3. action closures (trailing, each `= nil`) — `onClose` (scrim tap → container
//      clears its presentation state), `onJoin` (CTA tap → container forwards to
//      `FeedWinModel.joinCurrentActivity()` → `DefaultPlayerTemplate
//      .joinCurrentActivity()`).
//
// This sub-view reads ONLY its passed-in `activity` value — it NEVER reaches back
// into `FeedWinModel` / `DefaultPlayerTemplate`, and it does NOT call any
// `LivebuySDK` API directly (join goes out via `onJoin`, entirely host/container
// wired). All actions `nil` still renders correctly (demo / snapshot construct
// action-free).
//
// iOS-14-safe SwiftUI only (`GeometryReader` / `ZStack` / `VStack` / `Text` /
// `Button` / `RoundedRectangle` / `Circle` are all iOS 13+). No `ScrollView` (the
// centered modal convention forbids scrolling containers, same as
// `WinClaimModalView`), no `.task` / `AsyncImage` / `NavigationStack` /
// `.foregroundStyle` / `.tint`.

/// The single-stage 抽獎活動參加彈窗 for one `LBActiveEvent`. Mirrors
/// `WinClaimModalView`'s centered scrim + card presentation, but carries NO
/// UI-local state at all (`rb-ios-activity-sheet-cta-repeatable`) — there is no
/// submitting / result stage because joining an activity has no asynchronous
/// outcome to wait for, and the CTA itself is a stateless, repeatable dispatch.
public struct LiveActivitySheetView: View {
    /// Observed so a runtime language switch re-renders this view's localized copy
    /// (`rb-ios-i18n-string-table`; see `ReferenceUILanguage`).
    @ObservedObject var l10n = ReferenceUILanguage.shared

    // MARK: - Inputs (documented sub-view input pattern)

    /// The resolved reference-ui theme (FIRST positional argument, always).
    public let theme: ReferenceUITheme

    /// The activity this sheet presents (`DefaultActiveEvent.currentActivity`,
    /// caller-guaranteed non-nil — see `FeedWinOverlayView`'s container-level
    /// guard). Read-only; this view never mutates it.
    public let activity: LBActiveEvent

    /// Close intent (scrim tap). The design source's `LBActivitySheet` scrim is
    /// UNCONDITIONALLY clickable (`onClick={onClose}`, no stage gate — unlike
    /// `WinClaimModalView`'s scrim, which only closes on the `done` stage because
    /// that flow has interaction friction to protect). Default `nil` so demo /
    /// snapshot instances construct action-free.
    private let onClose: (() -> Void)?

    /// Join intent (CTA tap — repeatable, fires on every tap with no lock-out
    /// state, `rb-ios-activity-sheet-cta-repeatable`). The container forwards
    /// this to `FeedWinModel.joinCurrentActivity()`. Default `nil`.
    private let onJoin: (() -> Void)?

    /// Total number of concurrently ongoing activities
    /// (`activity-sheet-pagination-reference-ui-ios`). Default `1` — the existing
    /// single-activity baseline is byte-identical when this default is used (no
    /// pagination dots drawn, swipe gesture is inert). Mirrors
    /// `WinClaimModalView.pageCount`.
    public let pageCount: Int

    /// The index into the (container-held) activities list this sheet currently
    /// presents. Default `0`. This view does NOT hold the `activities` array
    /// itself — `activity:` above is already the container-resolved snapshot for
    /// this index (design.md D3); `pageIndex` is used ONLY for the pagination dots
    /// / swipe target-page math.
    public let pageIndex: Int

    /// Page-change intent (swipe or dot tap), carrying the target index. The
    /// container forwards this to `DefaultActiveEvent.setActivityPageIndex(_:)`.
    /// Default `nil`.
    private let onPage: ((Int) -> Void)?

    public init(
        theme: ReferenceUITheme,
        activity: LBActiveEvent,
        onClose: (() -> Void)? = nil,
        onJoin: (() -> Void)? = nil,
        pageCount: Int = 1,
        pageIndex: Int = 0,
        onPage: ((Int) -> Void)? = nil
    ) {
        self.theme = theme
        self.activity = activity
        self.onClose = onClose
        self.onJoin = onJoin
        self.pageCount = pageCount
        self.pageIndex = pageIndex
        self.onPage = onPage
    }

    // MARK: - Body

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                scrim
                card(containerWidth: geo.size.width)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            // 分頁手勢（activity-sheet-pagination-reference-ui-ios）——掛在整張彈窗
            // （scrim + 卡）上，對齊 `WinClaimModalView.pageSwipeGesture` 既有作法與設計稿
            // 把 swipe handler 綁在最外層 wrapper 的行為。
            .gesture(pageSwipeGesture)
        }
    }

    // MARK: - Pagination (activity-sheet-pagination-reference-ui-ios)

    /// The target page index for a completed horizontal drag, or `nil` if the
    /// drag should NOT change the page (below threshold, `pageCount <= 1`, or the
    /// clamped target equals the current page — already at a boundary). Direction
    /// + threshold + boundary clamp are all baked into the return value, mirroring
    /// `WinClaimModalView.clampedPage` + `attemptPage`'s combined inert logic —
    /// pure, no Combine/SwiftUI dependency, independently unit-testable.
    static func activitySheetSwipeTargetPage(
        totalDragWidth: CGFloat,
        threshold: CGFloat,
        pageIndex: Int,
        pageCount: Int
    ) -> Int? {
        guard pageCount > 1, abs(totalDragWidth) >= threshold else { return nil }
        let delta = totalDragWidth < 0 ? 1 : -1
        guard pageIndex + delta >= 0, pageIndex + delta < pageCount else { return nil }
        return pageIndex + delta
    }

    /// Horizontal drag threshold (aligns with `WinClaimModalView.pageSwipeThreshold`
    /// / design source `Math.abs(dx) < 40`).
    static let pageSwipeThreshold: CGFloat = 40

    private var pageSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 16)
            .onEnded { value in
                guard let target = Self.activitySheetSwipeTargetPage(
                    totalDragWidth: value.translation.width,
                    threshold: Self.pageSwipeThreshold,
                    pageIndex: pageIndex,
                    pageCount: pageCount) else { return }
                onPage?(target)
            }
    }

    /// 分頁圓點列——每頁一顆、`6×6pt`，目前頁 `theme.accent` 填色、其餘中性色
    /// （對齊 `WinClaimModalView.paginationDots` 既有視覺與 `LBActivitySheet` 設計稿）。
    /// 點擊任一顆直接呼叫 `onPage(該索引)`（索引本身由 `ForEach(0..<pageCount)` 保證合法，
    /// 不需要再經過 `activitySheetSwipeTargetPage` 的邊界夾制）。
    private var paginationDots: some View {
        HStack(spacing: 5) {
            ForEach(0..<pageCount, id: \.self) { i in
                Circle()
                    .fill(i == pageIndex ? theme.accent : Self.dotInactive)
                    .frame(width: 6, height: 6)
                    .contentShape(Rectangle().inset(by: -4))
                    .onTapGesture { onPage?(i) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(LBAccessibilityID.activitySheetPaginationDots)
    }

    // MARK: - Scrim (unconditionally clickable → onClose, design.md D3 / source `LBActivitySheet`)

    private var scrim: some View {
        Self.scrimColor
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { onClose?() }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(LBAccessibilityID.activitySheetScrim)
    }

    // MARK: - Card (84% width, capped 320pt — same cap as `WinClaimModalView`)

    private func card(containerWidth: CGFloat) -> some View {
        let width = Self.cardWidth(containerWidth: containerWidth)
        return ZStack(alignment: .top) {
            VStack(spacing: 14) {
                titleText
                prizeNameText
                keywordText
                ctaButton
                // 分頁圓點（activity-sheet-pagination-reference-ui-ios）——只在
                // `pageCount > 1` 時畫，對齊設計稿只在 CTA 之後、footer 之前渲染。
                if pageCount > 1 {
                    paginationDots
                }
                footer
            }
            .padding(.top, 46)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .frame(width: width)
            .background(theme.background)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: Color.black.opacity(0.35), radius: 32, x: 0, y: 24)

            // The trophy badge floats OUTSIDE the clipped card (top: -30 in the
            // design source) — same two-layer ZStack technique as
            // `WinClaimModalView.cardShell` (an inner clipped layer + an outer
            // unclipped layer for the badge), for the same reason: a badge placed
            // INSIDE the clipped card would be cut off by `clipShape`.
            badge
                .offset(y: -30)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(LBAccessibilityID.activitySheet)
    }

    /// Card width — design source `width: '84%', maxWidth: 320` (same rule as
    /// `WinClaimModalView.cardWidth`).
    static func cardWidth(containerWidth: CGFloat) -> CGFloat {
        min(containerWidth * 0.84, 320)
    }

    // MARK: - Content

    private var titleText: some View {
        Text(activity.title)
            .font(.system(size: 20 * theme.fontScale, weight: .heavy))
            .foregroundColor(theme.text)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// 獎品名稱 — `activity.award.first?.name`（空值退回空字串，design.md /
    /// spec.md 明確容忍空 award 陣列，不是 fallback 佔位文案）。
    private var prizeNameText: some View {
        Text(activity.award.first?.name ?? "")
            .font(.system(size: 15 * theme.fontScale, weight: .semibold))
            .foregroundColor(theme.text)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// 「留言關鍵字【{keyword}】即可參加抽獎！」— accent 色文字（design source 固定格式，
    /// `keyword` 為空時仍照格式呈現空括號，忠實反映 `activity.keyword ?? ""`，不臆測替代文案）。
    private var keywordText: some View {
        Text(Self.keywordLabel(keyword: activity.keyword ?? ""))
            .font(.system(size: 14 * theme.fontScale, weight: .bold))
            .foregroundColor(theme.accent)
            .multilineTextAlignment(.center)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Pure: the keyword call-to-action string (design source's fixed format).
    static func keywordLabel(keyword: String) -> String {
        ReferenceUIStrings.text("activity_keyword_cta", ["keyword": keyword])
    }

    /// CTA tap dispatch — `rb-ios-activity-sheet-cta-repeatable`: unconditionally
    /// forwards to `onJoin?()`, every single time it's called, with no gating or
    /// state mutation. Extracted as a one-line `self`-touching dispatch method
    /// (mirrors `WinClaimModalView.handleFooterTermsTap()` / `.handleScrimTap()`)
    /// so a test can call it directly, repeatedly, without rendering the view.
    func handleCtaTap() { onJoin?() }

    /// 「立即參加」CTA — 按下即呼叫 `handleCtaTap()`（`rb-ios-activity-sheet-cta-repeatable`：
    /// fire-and-forget，無非同步結果可等，CTA 恆可點擊、每次按下皆各自獨立觸發，MUST NOT
    /// 因先前任一次點擊而鎖定 / 改變文案或背景色）。
    private var ctaButton: some View {
        Button(action: handleCtaTap) {
            Text(Self.joinLabel)
                .font(.system(size: 16 * theme.fontScale, weight: .heavy))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(theme.accent))
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.top, 4)
        .accessibilityIdentifier(LBAccessibilityID.activitySheetCta)
    }

    /// footer「使用條款｜隱私政策」— 純文字版面，未接任何連結 / action（連結目標未定案，
    /// 沿用 `WinClaimModalView` 舊有「先留版面、不接實際連結」的既有作法；本 change 的
    /// props 清單本身也不帶 footer 連結 callback，見 tasks.md 2.2）。
    private var footer: some View {
        HStack(spacing: 0) {
            Text(Self.footerTerms)
            Text(" | ").opacity(0.5)
            Text(Self.footerPrivacy)
        }
        .font(.system(size: 12.5 * theme.fontScale, weight: .medium))
        .foregroundColor(Self.textDim)
    }

    // MARK: - Badge (60pt, 浮出卡頂外 — accent 填色 + 白底圓形 + 4pt surface-bg 描邊)
    //
    // design.md / spec.md: 重用 `WinEntryGiftGlyph`，但這裡是 accent 填色（NOT `.win`
    // 入口的硬寫死 `#F03246`）、白底圓形（NOT `WinClaimModalView.giftBadge` 的 accent
    // 漸層底）—— 對齊 design 原始碼 `LBActivitySheet` 的 `giftSvg(30, accent)` 畫在白底圓上。

    private var badge: some View {
        let scale: CGFloat = 30 / 200
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        return ZStack {
            Circle()
                .fill(Color.white)
            ZStack {
                WinEntryGiftGlyph.outlinePath()
                    .applying(transform)
                    .fill(theme.accent, style: FillStyle(eoFill: true))
                WinEntryGiftGlyph.innerPath()
                    .applying(transform)
                    .fill(Color.white, style: FillStyle(eoFill: true))
            }
            .frame(width: 30, height: 30)
        }
        .frame(width: 60, height: 60)
        .overlay(Circle().stroke(theme.background, lineWidth: 4))
        .shadow(color: Color.black.opacity(0.2), radius: 11, x: 0, y: 8)
    }

    // MARK: - Design tokens (design-literal, mirrors `WinClaimModalView`'s convention)

    static let scrimColor = Color.black.opacity(0.6)
    /// `theme.surface.textDim`（footer 次要文字，與 `WinClaimModalView.textDim` 同一色值）。
    static let textDim = Color(hex: "#6B6775") ?? Color.gray
    /// 分頁圓點非目前頁色（對齊 `WinClaimModalView.dotInactive` 同一色值 / 設計稿
    /// `S.border || '#D8DBE0'`）。
    static let dotInactive = Color(hex: "#D8DBE0") ?? Color.gray.opacity(0.3)

    static var joinLabel: String { ReferenceUIStrings.text("common_join_now") }
    static var footerTerms: String { ReferenceUIStrings.text("common_terms") }
    static var footerPrivacy: String { ReferenceUIStrings.text("common_privacy") }
}

// `rb-ios-activity-sheet-cta-repeatable`: this view no longer carries any
// `@State` — the previous `makeSeededForTesting(theme:activity:joined:)` test /
// preview seed existed solely to pre-set the (now removed) `joined` boolean, so
// it has been removed too. Test code that needs an instance (snapshot tests
// included) MUST use the public `LiveActivitySheetView(theme:activity:...)`
// initializer directly — there is no longer any hidden state to seed.
