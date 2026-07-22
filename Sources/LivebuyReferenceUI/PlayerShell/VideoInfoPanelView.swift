import SwiftUI
import LivebuySDK
import LivebuyUI

// MARK: - VideoInfoPanelView — family-1 player-shell surface 3 (info / notice panel)
//
// Spec: `reference-ui-rendering/spec.md` (family-1 player-shell, surface 3)
// Design: rb-ios-player-shell design.md D-2 #3 (`LBPBottomSheet`) +
//          `design/templates/minimal/screens.jsx` `VideoInfoSheet` +
//          `design/templates/minimal/sdk-components.jsx` `LBPBottomSheet` / `LBPSheetHeader`.
//
// The bottom-sheet info/notice panel. It is the third of the four family-1
// surface sub-views composed by `PlayerShellView`, and it implements the agreed
// SUB-VIEW INPUT PATTERN documented in `PlayerShellView.swift`:
//
//   1. `theme: ReferenceUITheme`            — FIRST positional argument.
//   2. bound SNAPSHOT VALUES               — `info: LBInfoTabState`,
//      `activeTab: LBInfoPanelTab`, `canOpenNotice: Bool`,
//      `systemNotice: String`, `notice: String`, plus the PRESENTATION flag
//      `live: Bool` (live-runtime image gate, NOT a view-model field — see its
//      doc comment) — all passed BY VALUE.
//   3. action closure (LAST, `= nil`)      — `onSelectTab: ((LBInfoPanelTab) -> Void)?`
//                                             which the host wires to the
//                                             template's `selectInfoTab` intent.
//
// This sub-view reads ONLY its passed-in values; it never reaches back into
// `PlayerShellModel` / `DefaultPlayerTemplate` (one-way data flow, D-1 / D-4).
//
// Two-tab panel (mirrors `VideoInfoSheet` + the spec's `LBInfoPanelTab`):
//   • 影片詳情 (`.info`)  — ALWAYS selectable. Shows publishAt / title /
//                            shopIntro, a divider, then a shop row (logo +
//                            shopName + subscribe affordance bound to
//                            `info.isSubscribed`).
//   • 公告     (`.notice`) — selectable ONLY when `canOpenNotice == true`.
//                            When un-selectable it is drawn as a DISABLED
//                            affordance (dimmed, non-tappable) and the tap is a
//                            no-op — the template's `selectTab(.notice)` is
//                            itself a no-op in that case, so we never request it.
//
// iOS-14-safe SwiftUI only. `VStack` / `HStack` / `ZStack` / `Text` / `Button` /
// `Divider` / `Color` are all iOS-13+; `RoundedRectangle` corner-specific masking
// for the sheet top is done with a manual iOS-14-safe rounded-corner shape. No
// `.task` / `AsyncImage` / `NavigationStack` / `.foregroundStyle` / `.tint`.

/// The family-1 bottom-sheet info/notice panel. Renders a two-tab panel: an
/// always-available 影片詳情 (info) tab and a 公告 (notice) tab that is a disabled
/// affordance when `canOpenNotice == false`.
public struct VideoInfoPanelView: View {

    /// The resolved reference-ui theme (FIRST positional argument, always).
    public let theme: ReferenceUITheme

    /// Info-tab snapshot (`DefaultInfoTab.current`). Read-only.
    public let info: LBInfoTabState
    /// Currently selected tab (`DefaultInfoTab.activeTab`). Read-only.
    public let activeTab: LBInfoPanelTab
    /// Whether the 公告 (notice) tab is selectable (`DefaultNoticeTab.canOpen`).
    public let canOpenNotice: Bool
    /// System notice text (`DefaultNoticeTab.systemNotice`).
    public let systemNotice: String
    /// Shop / video notice text (`DefaultNoticeTab.notice`).
    public let notice: String

    /// Live-runtime image gate (same convention as `PlayerHeaderBarView.live` and
    /// `CarouselCardView.live`). A by-value presentation flag (default `false`, NOT an
    /// info-tab view-model field): `PlayerShellView` feeds `!paintsBackgroundPlaceholder`
    /// — the SAME expression the header avatar uses — so the shop row loads the real
    /// `info.shopLogo` ONLY when the shell sits over a real video surface (runtime).
    /// `false` (demo / snapshot / preview / `ImageRenderer` path) → the shop row stays the
    /// deterministic gradient monogram chip so the baseline never touches the network.
    ///
    /// ⚠️ NAMING TRAP: this is the live-RUNTIME IMAGE gate, **not** the LIVE broadcast
    /// state (`isLive`). `VideoInfoPanelView` has no `isLive` concept, so there is no
    /// clash here — but note that `PlayerHeaderBarView.demo(live:)`'s `live:` argument
    /// means `isLive` (LIVE chrome), an entirely different thing. Do not conflate the two
    /// when mirroring this to Android / RN / Flutter.
    public let live: Bool

    /// Host-wired tab-switch intent. The shell forwards
    /// `model.selectInfoTab(tab)`. nil for demo / snapshot instances — the panel
    /// renders correctly action-free.
    private let onSelectTab: ((LBInfoPanelTab) -> Void)?

    /// Footer「前往商城首頁」intent (design `VideoInfoSheet` primary CTA). Host wires
    /// it to the storefront open-intent. nil → button renders but is inert (demo /
    /// snapshot).
    private let onOpenStorefront: (() -> Void)?

    /// Footer「與商家一對一對話」intent (design `VideoInfoSheet` ghost CTA). Host wires
    /// it to the service-link / customer-service open-intent. nil → inert.
    private let onContactMerchant: (() -> Void)?

    /// Host-wired header close-icon tap → close the panel. The shell forwards this to
    /// `infoPanelPresented = false` (rb-ios-sheet-header-close-unify — VideoInfoPanel previously
    /// had NO explicit close icon, only drag / scrim / host-badge re-tap). nil → tap is a no-op.
    private let onClose: (() -> Void)?

    /// Host-wired 訂閱 pill tap → 走 core 既有訂閱路徑（`PlayerShellModel.toggleSubscribe`
    /// → template → `performSubscribe` → `toggleSubscribe`）。已登入 → 訂閱 / 取消訂閱 API；
    /// 未登入 → core emit `AUTH_REQUIRED`，host 攔截跳登入（videoinfo-subscribe-pill-wire-refui）。
    /// nil → demo / snapshot 時 pill 仍渲染但點擊 no-op。
    private let onSubscribe: (() -> Void)?

    public init(
        theme: ReferenceUITheme,
        info: LBInfoTabState,
        activeTab: LBInfoPanelTab,
        canOpenNotice: Bool,
        systemNotice: String,
        notice: String,
        live: Bool = false,
        onSelectTab: ((LBInfoPanelTab) -> Void)? = nil,
        onOpenStorefront: (() -> Void)? = nil,
        onContactMerchant: (() -> Void)? = nil,
        onClose: (() -> Void)? = nil,
        onSubscribe: (() -> Void)? = nil
    ) {
        self.theme = theme
        self.info = info
        self.activeTab = activeTab
        self.canOpenNotice = canOpenNotice
        self.systemNotice = systemNotice
        self.notice = notice
        self.live = live
        self.onSelectTab = onSelectTab
        self.onOpenStorefront = onOpenStorefront
        self.onContactMerchant = onContactMerchant
        self.onClose = onClose
        self.onSubscribe = onSubscribe
    }

    public var body: some View {
        // Content only — the shared `.lbBottomSheet` presenter (SheetKit) draws the grab
        // handle + `theme.background` + `TopRoundedRectangle(20)` + shadow + dim scrim +
        // drag-to-dismiss (sheetkit-foundation). The leaf carries just the panel content.
        // Pinned header (標題 + 分頁列) + scrollable content body + pinned footer, within the
        // ½-screen cap (rb-ios-sheet-pinned-header-footer): a long 簡介 / 公告 scrolls between the
        // pinned tab bar and the pinned footer action.
        LBSheetScaffold {
            VStack(spacing: 0) {
                sheetHeader
                tabBar
                Divider().background(Self.stroke)
            }
        } bodyContent: {
            content
        } footer: {
            footer
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(LBAccessibilityID.infoPanel)
    }

    // MARK: - Sheet header (LBPSheetHeader — centered title + trailing close)
    //
    // Centered title with a trailing close icon overlaid (rb-ios-sheet-header-close-unify):
    // VideoInfoPanel previously had NO explicit close icon — only drag / scrim / host-badge
    // re-tap. The shared `SheetHeaderCloseButton` (transparent, aligned to ProductListView /
    // design) is now the fourth legal close entry, wired by the shell to `infoPanelPresented =
    // false`. The centered title is preserved (close overlays the header trailing).

    private var sheetHeader: some View {
        ZStack {
            Text(Self.panelTitle)
                .font(.system(size: 15 * theme.fontScale, weight: .bold))
                .foregroundColor(theme.text)
                .frame(maxWidth: .infinity, alignment: .center)

            HStack {
                Spacer(minLength: 0)
                SheetHeaderCloseButton(theme: theme, onTap: onClose)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 14)
    }

    // MARK: - Tab bar (VideoInfoSheet tab row — active = accent + 2pt underline)

    private var tabBar: some View {
        HStack(spacing: 24) {
            tab(.info, title: Self.infoTabTitle, enabled: true)
            tab(.notice, title: Self.noticeTabTitle, enabled: canOpenNotice)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
    }

    /// One tab label. `enabled == false` (notice tab when un-openable) → dimmed,
    /// non-tappable disabled affordance; the tap is a no-op.
    private func tab(_ tab: LBInfoPanelTab, title: String, enabled: Bool) -> some View {
        let isActive = (activeTab == tab) && enabled
        let underline = isActive ? theme.accent : Color.clear
        // Active → accent; disabled → very dim; inactive-enabled → mid dim.
        let labelColor: Color = isActive
            ? theme.accent
            : (enabled ? Self.textDim : Self.textDisabled)

        return Button(action: {
            guard enabled else { return }          // disabled affordance: no-op
            onSelectTab?(tab)
        }) {
            HStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 13 * theme.fontScale, weight: .bold))
                    .foregroundColor(labelColor)
                // Disabled 公告 tab → "· 無" suffix (mirrors the design's tabBtn).
                if tab == .notice && !enabled {
                    Text(Self.noticeNoneSuffix)
                        .font(.system(size: 10 * theme.fontScale, weight: .medium))
                        .foregroundColor(Self.textDisabled)
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 10)
            .overlay(
                Rectangle()
                    .fill(underline)
                    .frame(height: 2),
                alignment: .bottom
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!enabled)
        .accessibilityIdentifier(tab == .info ? LBAccessibilityID.infoTabDetail : LBAccessibilityID.infoTabNotice)
    }

    // MARK: - Content (info-tab vs notice-tab)

    @ViewBuilder
    private var content: some View {
        switch activeTab {
        case .info:
            infoContent
        case .notice:
            noticeContent
        }
    }

    // MARK: Info tab (VideoInfoSheet body)

    private var infoContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // publishAt — small dim caption.
            if !info.publishAt.isEmpty {
                Text(info.publishAt)
                    .font(.system(size: 12 * theme.fontScale))
                    .foregroundColor(Self.textDim)
            }

            // title — primary heading.
            if !info.title.isEmpty {
                Text(info.title)
                    .font(.system(size: 17 * theme.fontScale, weight: .bold))
                    .foregroundColor(theme.text)
                    .padding(.top, 6)
            }

            // shopIntro — dim body copy.
            if !info.shopIntro.isEmpty {
                Text(info.shopIntro)
                    .font(.system(size: 13 * theme.fontScale))
                    .foregroundColor(Self.textDim)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }

            // hairline divider.
            Rectangle()
                .fill(Self.stroke)
                .frame(height: 1)
                .padding(.vertical, 18)

            shopRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 18)
    }

    /// Shop row — circular shop logo + shopName + 「這裡是 …」 subline +
    /// subscribe affordance bound to `info.isSubscribed`.
    ///
    /// The logo chip is drawn as TWO STACKED LAYERS, mirroring `PlayerHeaderBarView.avatar`
    /// (which already paints this very same `shopLogo` at the top of the shell):
    ///
    ///   • BOTTOM (always drawn) — the deterministic gradient + monogram chip. It is NOT a
    ///     "host can swap this out" placeholder any more: it IS the loading state, the
    ///     load-failure state, the no-logo state and the snapshot/demo state.
    ///   • TOP (conditional)     — the REAL remote logo via the iOS-14-safe
    ///     `RemoteStillImageView` (no `AsyncImage` — iOS 15+, banned in this package).
    ///
    /// Overlay — NOT `if / else`: `RemoteStillImageView` paints NO pixels while the image is
    /// still downloading and none at all when it fails, so an `else`-only placeholder would
    /// flash a transparent hole in both cases. Stacking makes the chip cover both for free,
    /// which is why this change needs zero error UI / spinner / extra placeholder asset.
    private var shopRow: some View {
        HStack(spacing: 12) {
            ZStack {
                // Bottom layer — deterministic gradient + monogram (loading / failure /
                // no-logo / snapshot placeholder). Unchanged from before this change.
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(hex: "#FFD7A8") ?? .orange,
                        Color(hex: "#E27D5A") ?? .orange,
                    ]),
                    startPoint: .topLeading, endPoint: .bottomTrailing)
                Text(Self.monogram(for: info.shopName))
                    .font(.system(size: 12 * theme.fontScale, weight: .bold))
                    .foregroundColor(.white)

                // Top layer — the REAL shop logo, gated by the single resolver predicate.
                // `.scaleAspectFill` is EXPLICIT (the primitive defaults to `.scaleAspectFit`,
                // which would letterbox a non-square mark inside the circle) and matches
                // `PlayerHeaderBarView.avatar`.
                if let url = Self.resolvedShopLogoURL(live: live, urlString: info.shopLogo) {
                    RemoteStillImageView(url: url, contentMode: .scaleAspectFill)
                        .clipShape(Circle())
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                if !info.shopName.isEmpty {
                    Text(info.shopName)
                        .font(.system(size: 14 * theme.fontScale, weight: .semibold))
                        .foregroundColor(theme.text)
                    Text("\(Self.shopSublinePrefix)\(info.shopName)")
                        .font(.system(size: 12 * theme.fontScale))
                        .foregroundColor(Self.textDim)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            subscribePill
        }
    }

    /// Subscribe affordance — outlined accent pill. The label reflects
    /// `info.isSubscribed` (already-subscribed vs subscribe). Tappable: wrapped in a
    /// `Button` firing `onSubscribe` → `PlayerShellModel.toggleSubscribe()` → core
    /// (logged-in → subscribe API; NOT-logged-in → core emits `AUTH_REQUIRED` and the
    /// host shows login). Same entry as the header avatar subscribe badge
    /// (videoinfo-subscribe-pill-wire-refui). Appearance is UNCHANGED — `PlainButtonStyle`
    /// keeps the exact pill layout so snapshot baselines stay byte-identical.
    private var subscribePill: some View {
        Button(action: { onSubscribe?() }) {
            Text(info.isSubscribed ? Self.subscribedLabel : Self.subscribeLabel)
                .font(.system(size: 13 * theme.fontScale, weight: .bold))
                .foregroundColor(info.isSubscribed ? Self.textDim : theme.accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .overlay(
                    RoundedRectangle(cornerRadius: 999)
                        .stroke(info.isSubscribed ? Self.strokeStrong : theme.accent, lineWidth: 1)
                )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: Notice tab (公告 content)

    @ViewBuilder
    private var noticeContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if hasNoticeText {
                // 系統公告 — textFaint dot + textDim heading (mirrors design announceBlock).
                if !systemNotice.isEmpty {
                    announceBlock(
                        label: Self.systemNoticeLabel,
                        labelColor: Self.textDim,
                        dotColor: Self.textDisabled,
                        text: systemNotice)
                }
                // Hairline divider only when BOTH sections are present.
                if !systemNotice.isEmpty && !notice.isEmpty {
                    Rectangle()
                        .fill(Self.stroke)
                        .frame(height: 1)
                        .padding(.vertical, 18)
                }
                // 商城公告 — accent dot + accent heading.
                if !notice.isEmpty {
                    announceBlock(
                        label: Self.mallNoticeLabel,
                        labelColor: theme.accent,
                        dotColor: theme.accent,
                        text: notice)
                }
            } else {
                // Disabled / empty affordance — dim placeholder copy.
                Text(Self.noticeEmptyPlaceholder)
                    .font(.system(size: 13 * theme.fontScale))
                    .foregroundColor(Self.textDisabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 18)
    }

    /// One announcement block — a dot + heading (系統 vs 商城 differ by color) then
    /// the body text (always `theme.text`). Mirrors the design's `announceBlock`.
    private func announceBlock(
        label: String,
        labelColor: Color,
        dotColor: Color,
        text: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 6, height: 6)
                Text(label)
                    .font(.system(size: 13 * theme.fontScale, weight: .bold))
                    .foregroundColor(labelColor)
            }
            Text(text)
                .font(.system(size: 13 * theme.fontScale))
                .foregroundColor(theme.text)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var hasNoticeText: Bool {
        !systemNotice.isEmpty || !notice.isEmpty
    }

    // MARK: - Footer CTAs (VideoInfoSheet bottom buttons — present on BOTH tabs)

    /// The two bottom action buttons the design pins below the tab content
    /// regardless of tab (`screens.jsx` `VideoInfoSheet`): a primary「前往商城首頁」and
    /// a ghost「與商家一對一對話」. Stacked full-width (gap 10, padding `0 18 18`). Each
    /// forwards its host-wired intent and is inert (but still drawn) when nil.
    private var footer: some View {
        VStack(spacing: 10) {
            footerButton(title: Self.storefrontLabel, systemImage: "house.fill",
                         kind: .primary, action: onOpenStorefront)
            footerButton(title: Self.contactLabel, systemImage: "message.fill",
                         kind: .ghost, action: onContactMerchant)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
    }

    private enum FooterButtonKind { case primary, ghost }

    /// One full-width footer button mirroring the design `LBPButton` (radius 12,
    /// 14pt vertical padding, 15pt / weight-700 label, icon + label, gap 8). Primary
    /// = accent fill + white; ghost = sunken fill + theme text.
    private func footerButton(
        title: String, systemImage: String, kind: FooterButtonKind, action: (() -> Void)?
    ) -> some View {
        let bg: Color = (kind == .primary) ? theme.accent : Self.bgSunken
        let fg: Color = (kind == .primary) ? .white : theme.text
        return Button(action: { action?() }) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(fg)
                Text(title)
                    .font(.system(size: 15 * theme.fontScale, weight: .bold))
                    .foregroundColor(fg)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 12).fill(bg))
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier(kind == .primary ? LBAccessibilityID.infoPanelHome : LBAccessibilityID.infoFooterContact)
    }

    // MARK: - Decorative design tokens (literal minimal hex via Color(hex:))
    //
    // accent / text / background come from the resolved theme (above). These are
    // FIXED decorative colors lifted verbatim from `screens.jsx` `theme.surface.*`
    // (dim text / hairline strokes) — design-literal, not theme-resolved.

    /// `theme.surface.textDim` (secondary / caption text).
    static let textDim = Color(hex: "#6B6775") ?? Color.gray
    /// A further-dimmed disabled affordance color.
    static let textDisabled = Color(hex: "#B6B2BE") ?? Color.gray.opacity(0.5)
    /// `theme.surface.stroke` (hairline divider).
    static let stroke = Color(hex: "#ECEAF0") ?? Color.gray.opacity(0.2)
    /// `theme.surface.strokeStrong` (grab handle / stronger hairline).
    static let strokeStrong = Color(hex: "#D8D5DE") ?? Color.gray.opacity(0.35)

    // MARK: - Fixed localized copy (static presentation strings)

    static let panelTitle = "點播間說明"
    static let infoTabTitle = "影片詳情"
    static let noticeTabTitle = "公告"
    static let noticeNoneSuffix = "· 無"
    static let systemNoticeLabel = "系統公告"
    static let mallNoticeLabel = "商城公告"
    static let subscribeLabel = "訂閱通知"
    static let subscribedLabel = "已訂閱"
    static let shopSublinePrefix = "這裡是 "
    static let noticeEmptyPlaceholder = "目前沒有公告"
    static let storefrontLabel = "前往商城首頁"
    static let contactLabel = "與商家一對一對話"

    /// `theme.surface.bgSunken` (#F4F4F6) — ghost button fill (design `LBPButton`).
    static let bgSunken = Color(hex: "#F4F4F6") ?? Color.gray.opacity(0.08)

    // MARK: - Shop-logo gate (pure, zero-render, deterministically unit-testable)

    /// Resolves the shop row's REAL logo URL, or `nil` when the gradient monogram chip is
    /// the final presentation. Pure and render-free, so the whole gate is covered by plain
    /// unit tests on any Simulator with no network and no snapshot.
    ///
    /// Degradation ladder (mirrored verbatim by the Android / RN / Flutter siblings):
    ///   1. `live == false`             → nil. Demo / snapshot / preview / non-runtime paths
    ///                                    NEVER load an image, so baselines stay deterministic.
    ///   2. `urlString` trims to empty  → nil. No logo → the chip IS the answer.
    ///   3. otherwise                   → `URL(string:)` built from the TRIMMED string;
    ///                                    unparseable → nil (no crash, no force-unwrap).
    ///
    /// Trimming is used for the emptiness verdict AND for URL construction only — this
    /// function never mutates what it stores anywhere, it just answers "which URL, if any".
    ///
    /// STRUCTURAL COUPLING (do not undo): `shopRow`'s overlay condition MUST be expressed
    /// as `if let url = resolvedShopLogoURL(live:urlString:)`. It MUST NOT re-derive an
    /// equivalent check inline (`if live, !info.shopLogo.isEmpty, let url = URL(...)`).
    /// Same discipline as the product-photo resolver's "validity == drawability": once the
    /// verdict and the drawing each own a copy of the logic they eventually diverge, and
    /// unit tests of this function would then prove nothing about what is actually drawn.
    ///
    /// ⚠️ `live` here is the live-RUNTIME IMAGE gate, not the LIVE broadcast state
    /// (`isLive`) — see the `live` property's doc comment.
    static func resolvedShopLogoURL(live: Bool, urlString: String) -> URL? {
        guard live else { return nil }
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }

    /// Test-only hook exposing the SAME `shopRow` subtree `body` renders, so unit tests can
    /// make STRUCTURAL assertions on it (does a `RemoteStillImageView` node exist, and does
    /// it carry the expected URL). This closes the gap the pure-function tests cannot reach:
    /// `resolvedShopLogoURL` staying correct while `shopRow` was never wired to
    /// `info.shopLogo` at all. MUST NOT be called from production code, and MUST keep
    /// returning the very same `shopRow` (never a parallel copy — a copy would decouple the
    /// assertion target from what is actually drawn).
    var shopRowForTesting: some View { shopRow }

    /// Up-to-3-char monogram from the shop name (deterministic, pure).
    static func monogram(for shopName: String) -> String {
        let trimmed = shopName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "LB" }
        return String(trimmed.prefix(3)).uppercased()
    }
}

// MARK: - Deterministic demo seed (previews + snapshot tests)
//
// A fully-populated info-tab snapshot + notice texts so previews / the snapshot
// test render the panel's "happy path" deterministically (no live player).

public extension VideoInfoPanelView {

    /// A deterministic demo info-tab snapshot (mirrors `LB_DEMO` in screens.jsx:
    /// a 點播 show with title / publishAt / shop / intro, not subscribed).
    static var demoInfo: LBInfoTabState {
        LBInfoTabState(
            title: "夏日通勤彩妝 LIVE 精選",
            publishAt: "點播影片 · Feb 04, 2026",
            shopName: "BeautyToYou",
            shopIntro: "這場直播主推夏日通勤彩妝。整理出 8 款熱銷商品,觀眾可一邊看示範一邊下單,精選色號限時 5 折。",
            shopLogo: "",
            isSubscribed: false)
    }

    /// Deterministic demo system-notice copy.
    static let demoSystemNotice = "系統公告:本場次將於 21:00 開始,敬請準時收看。"
    /// Deterministic demo shop-notice copy.
    static let demoNotice = "本場直播限定:單筆滿 NT$999 免運,結帳輸入折扣碼 LIVE5 享 5 折。"

    /// A deterministic demo panel on the info tab (notice openable).
    static func demo(theme: ReferenceUITheme) -> VideoInfoPanelView {
        VideoInfoPanelView(
            theme: theme,
            info: demoInfo,
            activeTab: .info,
            canOpenNotice: true,
            systemNotice: demoSystemNotice,
            notice: demoNotice)
    }
}

#if DEBUG
struct VideoInfoPanelView_Previews: PreviewProvider {
    static var previews: some View {
        let theme = ReferenceUIThemePalette.minimal
        Group {
            // Info tab, notice openable.
            VideoInfoPanelView.demo(theme: theme)
                .previewDisplayName("info tab")

            // Notice tab, with content.
            VideoInfoPanelView(
                theme: theme,
                info: VideoInfoPanelView.demoInfo,
                activeTab: .notice,
                canOpenNotice: true,
                systemNotice: VideoInfoPanelView.demoSystemNotice,
                notice: VideoInfoPanelView.demoNotice)
                .previewDisplayName("notice tab")

            // Notice tab UN-selectable → disabled affordance.
            VideoInfoPanelView(
                theme: theme,
                info: VideoInfoPanelView.demoInfo,
                activeTab: .info,
                canOpenNotice: false,
                systemNotice: "",
                notice: "")
                .previewDisplayName("notice disabled")
        }
        .frame(width: 393, height: 520)
        .previewLayout(.sizeThatFits)
    }
}
#endif
