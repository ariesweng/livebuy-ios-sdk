import SwiftUI
import LivebuySDK
import LivebuyUI

// MARK: - LiveMoreSheetView — LIVE bottom bar「更多」(⋯) collapsible menu (design R32)
//
// Spec: `reference-ui-rendering/spec.md`
//   § "LivebuyReferenceUI 渲染 LIVE 底部 bar「更多」選單，綁 LiveBottomBarView.onMore"
// Change: rb-ios-live-replay-more-menu-and-video-info-live-copy.
//   Design source: `design/templates/minimal/screens.jsx` `LBPPlayerScreen`'s
//   `effectiveState === 'live_more'` block (lines 699-722) — a `LBPBottomSheet` with a
//   4-slot equal-width action row: 「分享」(`Icons.shareFill`, → `share`) + 「客服」
//   (`Icons.contact`, → `contact_merchant`) + TWO `visibility: hidden` placeholder slots
//   (upstream drew 4 equal-width columns but only wired 2 handlers — a known upstream dead
//   column, not a local omission; see design.md).
//
// Opened from `LiveBottomBarView`'s new `onMore` closure — that bar renders the「更多」
// trigger ONLY in its `chatClosed` (finished-live-replay) variant, in the LEADING slot
// (nickname's old position — `LiveBottomBarView.leadingSlotKind`), where Share moves OUT of
// the bar and INTO this sheet (the bar's TRAILING slot shows a restored CC toggle instead —
// `LiveBottomBarView.trailingActionKind`, 2026-09-03 correction round).
//
// Both real actions reuse EXISTING host seams — no new view-model / core exit:
//   • 分享 → the SAME `onShare` intent `LiveBottomBarView`'s own (now-hidden-in-this-variant)
//     share button would have forwarded (container wires it to `presentChannelShare` /
//     `model.performShare()`, unchanged).
//   • 客服 → the SAME「聯絡商家」confirm-modal flow the side-rail service-link tap and
//     `VideoInfoPanelView`'s footer「與商家一對一對話」already use (`contactMerchantPresented`
//     + `ContactMerchantModalView`, unchanged — see `PlayerShellView`).
//
// One-way data flow (mirrors LiveBottomBarView / OperationRailView): pure presentation, no
// view-model reads, no `simulate*` calls. The two placeholder slots are PERMANENTLY
// unwired (nil action, hidden — not merely disabled) — they mirror the design's own dead
// columns, not a local gap to eventually fill; a future upstream export that wires them
// would need its own change.
//
// iOS-14-safe SwiftUI only: `VStack` / `HStack` / `ZStack` / `Circle` / `Button` +
// `PlainButtonStyle` are all iOS-13+. No `ScrollView` / `Lazy*`.

/// The LIVE bottom bar's「更多」(⋯) collapsible menu: a 4-column equal-width action row
/// (分享 + 客服 + 2 hidden placeholders), presented as sheet CONTENT via the shared
/// `.lbBottomSheet` presenter (SheetKit draws the scrim + grab handle + card chrome).
public struct LiveMoreSheetView: View {
    /// Observed so a runtime language switch re-renders this view's localized copy
    /// (`rb-ios-i18n-string-table`; see `ReferenceUILanguage`).
    @ObservedObject var l10n = ReferenceUILanguage.shared

    /// The resolved reference-ui theme (FIRST positional argument, always).
    public let theme: ReferenceUITheme

    /// 分享 tap → host-wired share intent (mirrors `LiveBottomBarView.onShare`). nil → inert.
    private let onShare: (() -> Void)?
    /// 客服 tap → host-wired「聯絡商家」confirm-modal intent (mirrors
    /// `VideoInfoPanelView.onContactMerchant` / the side-rail service-link tap). nil → inert.
    private let onContact: (() -> Void)?

    public init(
        theme: ReferenceUITheme,
        onShare: (() -> Void)? = nil,
        onContact: (() -> Void)? = nil
    ) {
        self.theme = theme
        self.onShare = onShare
        self.onContact = onContact
    }

    public var body: some View {
        // Content only — the shared `.lbBottomSheet` presenter (SheetKit) draws the grab
        // handle + `theme.background` + `TopRoundedRectangle(20)` + shadow + dim scrim +
        // drag-to-dismiss. No header / footer split (unlike VideoInfoPanel / product
        // sheets) — this sheet is a single content row, so both are `EmptyView()`.
        LBSheetScaffold {
            EmptyView()
        } bodyContent: {
            HStack(spacing: Self.columnGap) {
                actionColumn(
                    label: Self.shareLabel, action: onShare,
                    accessibilityID: LBAccessibilityID.liveMoreShare
                ) { fg in ShareFillGlyph(size: Self.iconSize, color: fg) }

                actionColumn(
                    label: Self.contactLabel, action: onContact,
                    accessibilityID: LBAccessibilityID.liveMoreContact
                ) { fg in ContactGlyph(size: Self.iconSize, color: fg) }

                // Two hidden placeholder columns (design `visibility: hidden` — reserved
                // width, no visible affordance, never tappable). Mirrors the design's own
                // 2 unwired slots verbatim (design.md "Non-Goals").
                placeholderColumn
                placeholderColumn
            }
            .padding(.horizontal, Self.horizontalPadding)
            .padding(.vertical, Self.verticalPadding)
        } footer: {
            EmptyView()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(LBAccessibilityID.liveMoreSheet)
    }

    /// One tappable action column: a 40×40 translucent-grey circle icon + a 12pt label
    /// underneath, `Self.columnWidth`-wide. `action == nil` renders correctly (demo /
    /// snapshot) — the column still draws, tap is a no-op.
    private func actionColumn<Glyph: View>(
        label: String, action: (() -> Void)?, accessibilityID: String,
        @ViewBuilder icon: (Color) -> Glyph
    ) -> some View {
        Button(action: { action?() }) {
            VStack(spacing: 8) {
                ZStack {
                    Circle().fill(Self.slotBackground)
                    icon(theme.text)
                }
                .frame(width: Self.iconSlotSize, height: Self.iconSlotSize)
                Text(label)
                    .font(.system(size: 12 * theme.fontScale))
                    .foregroundColor(theme.text)
            }
            .frame(width: Self.columnWidth)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier(accessibilityID)
    }

    /// A width-reserving but INVISIBLE column (design `visibility: hidden` — occupies the
    /// same equal-width slot as the two real columns so the row stays evenly spaced, but
    /// draws nothing and is never tappable). `.hidden()` keeps layout space (unlike
    /// conditionally not building the view at all), matching CSS `visibility: hidden`
    /// exactly — distinct from `opacity(0)`, which would still be hit-testable.
    private var placeholderColumn: some View {
        VStack(spacing: 8) {
            Circle().frame(width: Self.iconSlotSize, height: Self.iconSlotSize)
            Text(" ").font(.system(size: 12 * theme.fontScale))
        }
        .frame(width: Self.columnWidth)
        .hidden()
        .allowsHitTesting(false)
    }

    // MARK: - Design tokens (lifted from `screens.jsx` `live_more` block)

    static let columnGap: CGFloat = 20            // gap: 20
    static let horizontalPadding: CGFloat = 18    // padding: '20px 18px'
    static let verticalPadding: CGFloat = 20
    static let columnWidth: CGFloat = 64          // width: 64
    static let iconSlotSize: CGFloat = 40         // width/height: 40
    static let iconSize: CGFloat = 20             // Icons.* size 20
    /// `rgba(204,204,204,0.8)` icon-slot backdrop.
    static let slotBackground = Color(.sRGB, red: 204 / 255, green: 204 / 255, blue: 204 / 255, opacity: 0.8)

    // MARK: - Localized copy (reference-ui string table, `ReferenceUIStrings`)

    static var shareLabel: String { ReferenceUIStrings.text("common_share") }
    static var contactLabel: String { ReferenceUIStrings.text("live_more_contact") }
}

// MARK: - Preview (deterministic demo)

#if DEBUG
struct LiveMoreSheetView_Previews: PreviewProvider {
    static var previews: some View {
        Color.black
            .lbBottomSheet(theme: ReferenceUIThemePalette.minimal, isPresented: .constant(true)) {
                LiveMoreSheetView(theme: ReferenceUIThemePalette.minimal)
            }
            .environment(\.lbSheetHeightUncapped, true)
            .previewLayout(.fixed(width: 393, height: 300))
    }
}
#endif
