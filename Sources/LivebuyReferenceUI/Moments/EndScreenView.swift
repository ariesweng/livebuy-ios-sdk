import SwiftUI
import LivebuySDK
import LivebuyUI

// MARK: - EndScreenView — family-4 player moment sub-view 2 (END / auto-next, LIVE-only)
//
// Spec: `reference-ui-rendering/spec.md` (family-4 moments, full-screen END moment)
// Design: rb-ios-moments design.md §2 +
//          `design/templates/minimal/moments.jsx` `LBPEndScreen` / `EndStage` /
//          `EndScreenArtboard` (design R41 / D7, commit `c480363ad`,
//          `docs/reference-ui/...` — see `rb-ios-endscreen-live-empty-state`).
//
// 2026-09 REDESIGN (`rb-ios-endscreen-live-empty-state`): EndScreen is now
// LIVE-ONLY and has exactly TWO variants — the previous 「熱門變體」(a card wall of
// hot recommendations, shown whenever `next` was empty) AND the older
// 「目前沒有推薦影片」bare-title fallback are BOTH RETIRED, replaced by ONE new empty
// state: a big「直播已結束」title + a「直播時長：HH:MM:SS」line + a full-width「查看
// 購物車」CTA. A VOD (non-live) video ending with no queued `next` no longer enters
// this view at ALL — the CONTAINER (`MomentsOverlayView`, via
// `shouldCloseInsteadOfEndScreen`) closes the player directly instead; that decision
// is made ONE LAYER UP, out of this view's scope (this view is never even
// constructed in that case). The countdown variant (`next` non-empty) is UNCHANGED
// by this redesign except for the shared scrim color (see VISUAL LANGUAGE below).
//
// It is the second of the family-4 moment sub-views composed by
// `MomentsOverlayView`, and it implements the agreed SUB-VIEW INPUT PATTERN
// documented verbatim in `MomentsOverlayView.swift`:
//
//   1. `theme: ReferenceUITheme`            — FIRST positional argument, always.
//   2. bound SNAPSHOT VALUES (BY VALUE from `MomentsModel`, never the model /
//      template):
//      • `countdown: LBEndScreenCountdown?` — non-nil ⇔ 倒數變體; `{ remain, total }`
//        drives the ring progress (`remain / total`). nil ⇔ 空狀態變體.
//      • `next: [LBNavItem]`                 — watch-next targets; `next.first` is the
//        倒數變體 preview card source (`cover` / `title?` / `shopName` /
//        `duration:Int`). Empty `next` also forces the 空狀態變體.
//      • `liveDuration: String`              — ALREADY-FORMATTED live-duration text
//        (e.g. `"01:23:45"`) for the 空狀態變體's「直播時長：」line. Empty (the
//        current production reality — no upstream data source is wired yet, see
//        design.md「Known limitation」) renders the design's documented fallback
//        `"--:--:--"`. This layer does NOT compute / derive it.
//   3. action closures (LAST, each `= nil`):
//      • `onWatchNext: (() -> Void)?`        — 倒數變體「立即觀看」CTA. Forwards to the
//        container's host-wired `onWatchNext` → host → core load(next videoId).
//        This layer NEVER loads / advances itself.
//      • `onCancel: (() -> Void)?`           — 倒數變體「取消」exit. Forwards to the
//        container's host-wired `onCancel` → host, which now CLOSES the whole
//        player session (the 熱門變體 fallback「取消」used to reveal no longer
//        exists — see `LivebuyPlayer.swift` `makeOverlayContext`'s `onCancel`
//        default: `cancelAutoNext()` + the SAME dismiss resolution `onDismiss`
//        uses). This layer only forwards the tap; it does NOT decide what closing
//        means.
//      • `onViewCart: (() -> Void)?`         — 空狀態變體「查看購物車」CTA. Forwards to
//        the container's host-wired `onViewCart` (wired by `PlayerOverlayRootView`
//        to the SAME `onOpenProductList` action the LIVE bottom bar's bag button
//        uses — there is no deeper "jump straight to the cart" seam available at
//        this assembly point; see design.md「onViewCart wiring」). This layer NEVER
//        opens the product list itself.
//
// VARIANT GATING (mirrors `LBPEndScreen`'s `isEmpty` — moments.jsx `EndStage`):
//   • 倒數變體 — `countdown != nil` AND `!next.isEmpty`: big `next.first` preview
//     card + a countdown RING (auto-advance-to-next) + 立即觀看 / 取消.
//   • 空狀態變體 — `countdown == nil` OR `next.isEmpty`: 「直播已結束」title +
//     「直播時長：…」line + a full-width「查看購物車」CTA (reuses the exact button
//     style `ProductListView.cartCTA` already established —
//     `CartFillGlyph` + `theme.cornerRadius` + `theme.accent` fill).
//
// One-way data flow: this sub-view reads ONLY its passed-in values; it never
// reaches back into `MomentsModel` / `DefaultPlayerTemplate`, holds NO second copy
// of countdown / next, and NEVER drives the auto-next countdown itself (core
// owns the tick — the ring is PURE PRESENTATION of the snapshot `remain` / `total`).
// It renders correctly with all actions nil (so demo / snapshot tests construct it
// action-free).
//
// VISUAL LANGUAGE: a full-bleed dark scrim — `rgba(50,50,50,0.64)`, NO blur
// (`rb-ios-endscreen-live-empty-state`; was `rgba(8,8,12,0.8)`, also never blurred
// on iOS — SwiftUI has no cheap backdrop-blur-over-video primitive, so this layer
// never attempted the design's separate `blur(2px)` — a pre-existing, unrelated
// gap) — with white text / glyphs (the moment composites over the ended video —
// design §2). This scrim is SHARED by BOTH variants (one `ZStack` layer under
// `body`), so this redesign changes the countdown variant's background too. The
// literal dark scrim + white-on-dark decorative colors are FIXED design colors
// lifted from `LBPEndScreen` via `Color(hex:)` (consistent with the family-2/3
// surfaces' surface-token approach); `theme.accent` paints the「立即觀看」/「查看
// 購物車」CTAs + the ring trim.
//
// iOS-14-safe SwiftUI only. `ZStack` / `VStack` / `HStack` / `Circle().trim` /
// `RoundedRectangle` / `Text` / `Button` / `Image(systemName:)` are all iOS-13+.
// No `.task` / `AsyncImage` / `NavigationStack` / `.foregroundStyle` / `.tint` —
// any >14 API would be guarded with `@available` / `if #available`, but none is
// reached here.
//
// ⚠️ NO ScrollView / LazyVStack / LazyHStack / LazyVGrid in rendered content — the
// reference-ui snapshot path (`ImageRenderer`) renders those BLANK (the verified
// family-3 lesson). Neither variant needs one any more (the 熱門 hstack is gone).

/// The family-4 full-screen END moment. In the 倒數變體 (`countdown != nil` &&
/// `!next.isEmpty`) it draws a big `next.first` preview card with a centered
/// countdown RING (`remain / total`) representing the auto-advance-to-next
/// countdown, plus 立即觀看 (`onWatchNext`) / 取消 (`onCancel`, now closes the whole
/// session — see `LivebuyPlayer.swift`). In the 空狀態變體 (`countdown == nil` ||
/// `next.isEmpty`) it draws a「直播已結束」title + a「直播時長：…」line + a
/// full-width「查看購物車」CTA (`onViewCart`). All actions are host-wired forwarders;
/// this layer never loads / advances / opens the cart itself.
public struct EndScreenView: View {

    /// The resolved reference-ui theme (FIRST positional argument, always).
    public let theme: ReferenceUITheme

    /// Auto-next countdown snapshot (`DefaultEndScreenState.countdown`). Non-nil ⇔
    /// 倒數變體; `{ remain, total }` drives the ring progress. Read-only.
    public let countdown: LBEndScreenCountdown?

    /// Watch-next targets (`DefaultEndScreenState.next`). `next.first` is the 倒數
    /// 變體 preview card source. Empty also forces the 空狀態變體. Read-only.
    public let next: [LBNavItem]

    /// ALREADY-FORMATTED live-duration text for the 空狀態變體's「直播時長：」line
    /// (e.g. `"01:23:45"`). Empty (default — the current production reality: no
    /// upstream signal is wired yet) renders the design's documented fallback
    /// `"--:--:--"` (`Self.liveDurationLine(_:)`). This layer does NOT compute /
    /// derive a duration itself. `rb-ios-endscreen-live-empty-state`.
    public let liveDuration: String

    /// Runtime media gate (mirrors `CarouselCardView.live`). `false` (the default —
    /// every demo / snapshot / preview construction) → the recommended / next-video
    /// cards ALWAYS draw the deterministic black placeholder (no `AVPlayer`, no async
    /// network fetch), so `ImageRenderer` snapshot baselines stay byte-identical.
    /// `true` (host runtime) → each card loads `preview` (animated) → `cover` (static)
    /// → placeholder, exactly like the widget card (`CarouselCardView.mediaThumbnail`).
    /// Wired by the container as `!paintsBackgroundPlaceholder` (the SAME flag the
    /// product sheets / start-screen surfaces use).
    public let live: Bool

    /// 倒數變體「立即觀看」CTA → host-wired `onWatchNext` → host → core load(next).
    /// nil for demo / snapshot instances — the CTA is inert (D §2). This layer NEVER
    /// loads / advances itself.
    private let onWatchNext: (() -> Void)?

    /// 倒數變體「取消」exit → host-wired `onCancel` → host, which now closes the
    /// whole player session (`LivebuyPlayer.swift` `makeOverlayContext`'s default:
    /// `player.cancelAutoNext()` + the SAME dismiss resolution `onDismiss` uses).
    /// nil for demo / snapshot instances. This layer only forwards the tap.
    private let onCancel: (() -> Void)?

    /// 空狀態變體「查看購物車」CTA → host-wired `onViewCart` → host (wired by
    /// `PlayerOverlayRootView` to the SAME `onOpenProductList` action the LIVE
    /// bottom bar's bag button uses). nil for demo / snapshot instances. This layer
    /// NEVER opens the product list itself.
    private let onViewCart: (() -> Void)?

    public init(
        theme: ReferenceUITheme,
        countdown: LBEndScreenCountdown?,
        next: [LBNavItem],
        liveDuration: String = "",
        live: Bool = false,
        onWatchNext: (() -> Void)? = nil,
        onCancel: (() -> Void)? = nil,
        onViewCart: (() -> Void)? = nil
    ) {
        self.theme = theme
        self.countdown = countdown
        self.next = next
        self.liveDuration = liveDuration
        self.live = live
        self.onWatchNext = onWatchNext
        self.onCancel = onCancel
        self.onViewCart = onViewCart
    }

    /// Whether the 倒數變體 is active — `countdown != nil` AND a preview target
    /// exists (mirrors `LBPEndScreen`'s `showCountdown`, moments.jsx `EndStage`).
    private var showCountdown: Bool {
        countdown != nil && !next.isEmpty
    }

    public var body: some View {
        ZStack {
            // Full-bleed dark scrim (LBPEndScreen `rgba(50,50,50,0.64)`, no blur —
            // rb-ios-endscreen-live-empty-state). Shared by BOTH variants. The moment
            // composites over the ended video — a fixed design color, not theme bg.
            Self.scrim
                .edgesIgnoringSafeArea(.all)

            if showCountdown {
                countdownVariant
            } else {
                emptyVariant
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(LBAccessibilityID.momentEnd)
    }

    // MARK: - 倒數變體 (preview card + ring + 立即觀看 / 取消)
    //
    // Mirrors `LBPEndScreen`'s `showCountdown` branch (moments.jsx 284-339):
    //   • 「影片結束」rule-flanked label.
    //   • a 150×(9:16) preview card of `next.first` with a centered countdown ring.
    //   • 「{remain} 秒後自動播放下一支」+ the next title + 「{shopName} · {duration}」.
    //   • 取消 (outline) / 立即觀看 (accent, play glyph) buttons.

    private var countdownVariant: some View {
        // next.first is guaranteed non-nil here (showCountdown gates on !next.isEmpty).
        let n0 = next.first
        let remain = countdown?.remain ?? 0
        return VStack(spacing: 20) {
            Spacer(minLength: 0)

            endedRule

            VStack(spacing: 14) {
                previewCard(remain: remain)
                if let n0 = n0 {
                    previewCaption(n0, remain: remain)
                }
            }

            countdownActions

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
    }

    /// 「— 影片結束 —」rule-flanked caption (LBPEndScreen 287-291).
    private var endedRule: some View {
        HStack(spacing: 8) {
            Rectangle().fill(Self.onDarkFaint).frame(width: 18, height: 1)
            Text(Self.endedLabel)
                .font(.system(size: 12 * theme.fontScale, weight: .semibold))
                .foregroundColor(Self.onDarkDim)
                .kerning(1)   // letterSpacing:1 — kerning is iOS-13+ (tracking is iOS-16+)
            Rectangle().fill(Self.onDarkFaint).frame(width: 18, height: 1)
        }
    }

    /// The 150×(9:16) preview card with the centered countdown ring (LBPEndScreen
    /// 295-314). The cover area is `live`-gated real media of `next.first` (preview loop
    /// → static cover → placeholder, mirroring the widget card); the ring + remaining
    /// seconds are drawn centered over a dark veil.
    private func previewCard(remain: Int) -> some View {
        ZStack {
            // 9:16 media of `next.first`: `live`-gated real cover / preview over the
            // black placeholder (mirrors CarouselCardView.mediaThumbnail). `live == false`
            // → placeholder only (snapshot byte-identical).
            previewMedia(next.first)
            // Dark veil over the cover (`rgba(0,0,0,0.4)`).
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.4))
            // Centered seek affordance hint behind the ring.
            countdownRing(remain: remain)
        }
        .frame(width: 150, height: 150 * 16.0 / 9.0)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.5), radius: 20, x: 0, y: 12)
    }

    /// The 16-radius black cover placeholder (the existing baseline fill) — the base
    /// layer of the countdown preview card, and the `live == false` / empty-URL fallback.
    private var previewCoverPlaceholder: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color.black)
    }

    /// Live-gated preview-card media of `next.first` — mirrors
    /// `CarouselCardView.mediaThumbnail`: `live` && `preview` → looping preview over the
    /// placeholder; else `live` && `cover` → static still over the placeholder; else the
    /// placeholder alone. Empty `preview` (the backend's current default) falls through
    /// to `cover`; empty `cover` falls through to the placeholder. `live == false` /
    /// `next.first == nil` → placeholder only (never constructs a runtime media view).
    @ViewBuilder
    private func previewMedia(_ n0: LBNavItem?) -> some View {
        if live, let n0 = n0, let url = Self.nonEmptyURL(n0.preview) {
            ZStack {
                previewCoverPlaceholder
                LoopingVideoView(url: url)
            }
        } else if live, let n0 = n0, let url = Self.nonEmptyURL(n0.cover) {
            ZStack {
                previewCoverPlaceholder
                RemoteStillImageView(url: url)
            }
        } else {
            previewCoverPlaceholder
        }
    }

    /// The auto-advance-to-next countdown RING (LBPEndScreen 298-313). Per the
    /// design recipe: a faint full track circle + an accent `trim(from: 0, to:
    /// remain/total)` arc rotated to start at 12 o'clock, with `remain` centered.
    /// The ring is PURE PRESENTATION of the snapshot — this layer never ticks it.
    private func countdownRing(remain: Int) -> some View {
        let total = countdown?.total ?? 0
        // progress = remain / max(total, 1) — clamped to [0, 1].
        let progress = CGFloat(remain) / CGFloat(max(total, 1))
        let clamped = min(max(progress, 0), 1)
        return ZStack {
            // Faint full track (`stroke rgba(255,255,255,0.28) 4`).
            Circle()
                .stroke(Self.ringTrack, lineWidth: 4)
            // Accent remaining arc (`stroke #fff 4 round`, rotated -90° to start top).
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(theme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            // Centered remaining seconds (`Inter 800 26`).
            Text("\(remain)")
                .font(.system(size: 26 * theme.fontScale, weight: .heavy))
                .foregroundColor(.white)
        }
        .frame(width: 72, height: 72)
    }

    /// Preview caption block (LBPEndScreen 315-322): the auto-play line, the next
    /// title (2-line clamp), and the「{shopName} · {duration}」meta line.
    private func previewCaption(_ n0: LBNavItem, remain: Int) -> some View {
        VStack(spacing: 5) {
            Text(String(format: Self.autoPlayLabel, remain))
                .font(.system(size: 12 * theme.fontScale))
                .foregroundColor(Self.onDarkDim)

            Text(n0.title ?? Self.untitledNext)
                .font(.system(size: 15 * theme.fontScale, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Text(metaLine(for: n0))
                .font(.system(size: 11.5 * theme.fontScale))
                .foregroundColor(Self.onDarkFaintText)
        }
        .frame(maxWidth: 280)
    }

    /// 「{shopName} · {mm:ss}」meta (LBPEndScreen 321). `LBNavItem.duration` is an
    /// `Int` (seconds) — formatted to `mm:ss` here (unlike `LBHotItem.duration`
    /// which is an already-formatted string).
    private func metaLine(for n0: LBNavItem) -> String {
        "\(n0.shopName) · \(Self.formatSeconds(n0.duration))"
    }

    /// 取消 (outline) / 立即觀看 (accent + play glyph) action row (LBPEndScreen 325-338).
    private var countdownActions: some View {
        HStack(spacing: 10) {
            // 取消 — translucent outline button.
            Button(action: { onCancel?() }) {
                Text(Self.cancelLabel)
                    .font(.system(size: 15 * theme.fontScale, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Self.onDarkFill)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Self.onDarkStroke, lineWidth: 1)))
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityIdentifier(LBAccessibilityID.momentEndCancel)

            // 立即觀看 — accent filled button with a play glyph.
            Button(action: { onWatchNext?() }) {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                    Text(Self.watchNextLabel)
                        .font(.system(size: 15 * theme.fontScale, weight: .bold))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(theme.accent))
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityIdentifier(LBAccessibilityID.momentEndWatch)
        }
        .frame(maxWidth: 320)
    }

    // MARK: - 空狀態變體 (「直播已結束」title + 直播時長 line + 查看購物車 CTA)
    //
    // Mirrors `LBPEndScreen`'s `isEmpty` branch (moments.jsx `EndStage`,
    // `rb-ios-endscreen-live-empty-state`, replacing the retired 熱門變體 card wall
    // AND the older bare-title fallback with ONE new empty state): a big title, a
    // live-duration line, and a full-width cart CTA — no recommendations, no
    // scroll, no per-item interaction.

    private var emptyVariant: some View {
        VStack(spacing: 36) {
            Spacer(minLength: 0)

            VStack(spacing: 14) {
                Text(Self.liveEndedTitle)
                    .font(.system(size: 30 * theme.fontScale, weight: .heavy))
                    .foregroundColor(.white)
                    .kerning(-0.2)

                Text(Self.liveDurationLine(liveDuration))
                    .font(.system(size: 15.5 * theme.fontScale))
                    .foregroundColor(Color.white.opacity(0.85))
            }
            .multilineTextAlignment(.center)
            .shadow(color: Color.black.opacity(0.4), radius: 10, x: 0, y: 2)

            viewCartButton

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 查看購物車 CTA (LBPEndScreen `EndStage`'s empty branch) — reuses the EXACT
    /// button style already established at `ProductListView.cartCTA` (`CartFillGlyph`
    /// + `theme.cornerRadius` + `theme.accent` fill), so this footer reads as the
    /// same cart affordance the product list already uses.
    private var viewCartButton: some View {
        Button(action: { onViewCart?() }) {
            HStack(spacing: 10) {
                CartFillGlyph(size: 20, color: .white)
                Text(Self.viewCartLabel)
                    .font(.system(size: 16 * theme.fontScale, weight: .bold))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: theme.cornerRadius)
                    .fill(theme.accent))
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier(LBAccessibilityID.momentEndViewCart)
    }

    // MARK: - Helpers

    /// The「直播時長：…」line (LBPEndScreen `EndStage`'s empty branch: `` `直播時長：${
    /// (liveInfo && liveInfo.duration) || '--:--:--'}` ``). Empty `duration` (the
    /// current production reality — no upstream signal is wired yet) renders the
    /// design's documented fallback `"--:--:--"`. Pure — no view state.
    static func liveDurationLine(_ duration: String) -> String {
        "\(liveDurationPrefix)\(duration.isEmpty ? fallbackDuration : duration)"
    }

    /// Format `Int` seconds → `mm:ss` (for `LBNavItem.duration`, which IS seconds —
    /// unlike `LBHotItem.duration` which is an already-formatted string).
    static func formatSeconds(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// A trimmed non-empty URL, or nil (empty string → absent). Mirrors
    /// `CarouselCardView.previewURL` / `coverURL`, so an empty `preview` (the backend's
    /// current default for `next[]`) falls through to `cover`, and an empty `cover`
    /// falls through to the black placeholder (no broken image, no crash).
    static func nonEmptyURL(_ raw: String) -> URL? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : URL(string: s)
    }

    // MARK: - Decorative design tokens (literal moments.jsx hex via Color(hex:))
    //
    // accent comes from the resolved theme; these are FIXED decorative colors lifted
    // verbatim from `LBPEndScreen` (the dark-scrim moment is white-on-dark
    // regardless of the host theme background — design §2). Kept consistent
    // with the family-2/3 surfaces' surface-token approach (Color(hex:) literals).

    /// Full-bleed scrim (`rgba(50,50,50,0.64)`, no blur — `rb-ios-endscreen-live-
    /// empty-state`; was `rgba(8,8,12,0.8)`).
    static let scrim = (Color(hex: "#323232") ?? Color.black).opacity(0.64)
    /// Faint on-dark rule line (`rgba(255,255,255,0.3)`).
    static let onDarkFaint = Color.white.opacity(0.3)
    /// Dim on-dark caption (`rgba(255,255,255,0.6)`).
    static let onDarkDim = Color.white.opacity(0.6)
    /// Fainter on-dark meta text (`rgba(255,255,255,0.5)`).
    static let onDarkFaintText = Color.white.opacity(0.5)
    /// Translucent on-dark fill (button / pill `rgba(255,255,255,0.12)`).
    static let onDarkFill = Color.white.opacity(0.12)
    /// Translucent on-dark outline (`rgba(255,255,255,0.28)`).
    static let onDarkStroke = Color.white.opacity(0.28)
    /// Ring track (`rgba(255,255,255,0.28)`).
    static let ringTrack = Color.white.opacity(0.28)

    // MARK: - Fixed localized copy (static presentation strings)

    static let endedLabel = "影片結束"
    static let liveEndedTitle = "直播已結束"
    static let liveDurationPrefix = "直播時長："
    static let fallbackDuration = "--:--:--"
    static let autoPlayLabel = "%d 秒後自動播放下一支"
    static let untitledNext = "下一支影片"
    static let cancelLabel = "取消"
    static let watchNextLabel = "立即觀看"
    static let viewCartLabel = "查看購物車"
}

// MARK: - Deterministic demo seed (previews + snapshot tests)
//
// Deterministic END moments (倒數變體 + 空狀態變體) so previews / the snapshot test
// render the moment's "happy path" without a live player. Built via the skeleton's
// documented demo recipe (`MomentsModel.demoNavItem` /
// `LBEndScreenCountdown(remain:total:)` — VERIFIED public inits reachable from
// `LivebuyReferenceUI`).

public extension EndScreenView {

    /// A deterministic 倒數變體 demo: an active countdown (`remain 3 / total 5`) + one
    /// watch-next preview target, action-free. Mirrors `MomentsModel.demoEndCountdown`'s
    /// fixture.
    static func demoCountdown(theme: ReferenceUITheme) -> EndScreenView {
        EndScreenView(
            theme: theme,
            countdown: LBEndScreenCountdown(remain: 3, total: 5),
            next: [MomentsModel.demoNavItem()])
    }

    /// A deterministic 空狀態變體 demo (`rb-ios-endscreen-live-empty-state`): NO
    /// countdown, empty watch-next, NO `liveDuration` — renders the design's
    /// documented「--:--:--」fallback (the current production reality: no upstream
    /// live-duration signal is wired yet).
    static func demoEmpty(theme: ReferenceUITheme) -> EndScreenView {
        EndScreenView(
            theme: theme,
            countdown: nil,
            next: [])
    }

    /// A deterministic 空狀態變體 demo WITH a populated `liveDuration`, exercising the
    /// non-fallback rendering path of「直播時長：…」.
    static func demoEmptyWithDuration(theme: ReferenceUITheme, liveDuration: String = "01:23:45") -> EndScreenView {
        EndScreenView(
            theme: theme,
            countdown: nil,
            next: [],
            liveDuration: liveDuration)
    }
}

#if DEBUG
struct EndScreenView_Previews: PreviewProvider {
    static var previews: some View {
        let theme = ReferenceUIThemePalette.minimal
        Group {
            // 倒數變體 — preview card + countdown ring + 立即觀看 / 取消.
            EndScreenView.demoCountdown(theme: theme)
                .previewDisplayName("countdown · ring + preview")

            // 空狀態變體 —「直播已結束」title + 直播時長 (fallback) + 查看購物車 CTA.
            EndScreenView.demoEmpty(theme: theme)
                .previewDisplayName("empty · fallback duration")

            // 空狀態變體 — with a populated liveDuration.
            EndScreenView.demoEmptyWithDuration(theme: theme)
                .previewDisplayName("empty · populated duration")
        }
        .frame(width: 393, height: 852)
        .previewLayout(.sizeThatFits)
    }
}
#endif
