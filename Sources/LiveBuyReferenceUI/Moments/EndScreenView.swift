import SwiftUI
import LivebuySDK
import LivebuyUI

// MARK: - EndScreenView — family-4 player moment sub-view 2 (END / auto-next)
//
// Spec: `reference-ui-rendering/spec.md` (family-4 moments, full-screen END moment)
// Design: rb-ios-moments design.md §2 +
//          `design/templates/minimal/moments.jsx` `LBPEndScreen` (lines 266-364) +
//          `LBPHotCard` (226-264).
//
// The full-screen END moment shown when the video finishes. It is the second of
// the three family-4 moment sub-views composed by `MomentsOverlayView`, and it
// implements the agreed SUB-VIEW INPUT PATTERN documented verbatim in
// `MomentsOverlayView.swift`:
//
//   1. `theme: ReferenceUITheme`            — FIRST positional argument, always.
//   2. bound SNAPSHOT VALUES (BY VALUE from `MomentsModel`, never the model /
//      template):
//      • `countdown: LBEndScreenCountdown?` — non-nil ⇔ 倒數變體; `{ remain, total }`
//        drives the ring progress (`remain / total`). nil ⇔ 熱門變體.
//      • `next: [LBNavItem]`                 — watch-next targets; `next.first` is the
//        倒數變體 preview card source (`cover` / `title?` / `shopName` /
//        `duration:Int`). Empty `next` also forces the 熱門變體.
//      • `hot: [LBHotItem]`                  — 熱門變體 set; rendered as `LBPHotCard`s
//        in a PLAIN `HStack`/`VStack` FIXED SMALL set (`cover` / `title` /
//        `duration:String` already-formatted). NEVER lazy / scroll.
//   3. action closures (LAST, each `= nil`):
//      • `onWatchNext: (() -> Void)?`        — 倒數變體「立即觀看」CTA. Forwards to the
//        container's host-wired `onWatchNext` → host → core load(next videoId).
//        This layer NEVER loads / advances itself.
//      • `onPickHot: ((LBHotItem) -> Void)?` — 熱門變體 card tap. Forwards the tapped
//        `LBHotItem` to the container's host-wired `onPickHot` → host → core
//        load(hot.id). This layer NEVER switches videos itself.
//      • `onCancel: (() -> Void)?`           — 倒數變體「取消」exit. Forwards to the
//        container's host-wired `onCancel` → host (dismiss / stay).
//
// VARIANT GATING (mirrors `LBPEndScreen`'s `showCountdown` — moments.jsx line 268):
//   • 倒數變體 — `countdown != nil` AND `!next.isEmpty`: big `next.first` preview
//     card + a countdown RING (auto-advance-to-next) + 立即觀看 / 取消.
//   • 熱門變體 — `countdown == nil` OR `next.isEmpty`: 為你推薦 header + a PLAIN
//     `HStack` row of `LBPHotCard`s, each tap → `onPickHot`.
//
// One-way data flow: this sub-view reads ONLY its passed-in values; it never
// reaches back into `MomentsModel` / `DefaultPlayerTemplate`, holds NO second copy
// of countdown / next / hot, and NEVER drives the auto-next countdown itself (core
// owns the tick — the ring is PURE PRESENTATION of the snapshot `remain` / `total`).
// It renders correctly with all actions nil (so demo / snapshot tests construct it
// action-free).
//
// VISUAL LANGUAGE: a full-bleed dark scrim (`rgba(8,8,12,0.8)`) with white text /
// glyphs (the moment composites over the ended video — design §2). The literal dark
// scrim + white-on-dark decorative colors are FIXED design colors lifted from
// `LBPEndScreen` via `Color(hex:)` (consistent with the family-2/3 surfaces'
// surface-token approach); `theme.accent` paints the「立即觀看」CTA + the ring trim.
//
// iOS-14-safe SwiftUI only. `ZStack` / `VStack` / `HStack` / `Circle().trim` /
// `RoundedRectangle` / `Text` / `Button` / `Image(systemName:)` are all iOS-13+.
// No `.task` / `AsyncImage` / `NavigationStack` / `.foregroundStyle` / `.tint` —
// any >14 API would be guarded with `@available` / `if #available`, but none is
// reached here.
//
// ⚠️ NO ScrollView / LazyVStack / LazyHStack / LazyVGrid in rendered content — the
// reference-ui snapshot path (`ImageRenderer`) renders those BLANK (the verified
// family-3 lesson). The 熱門 list is a PLAIN `HStack` of a FIXED SMALL set.

/// The family-4 full-screen END moment. In the 倒數變體 (`countdown != nil` &&
/// `!next.isEmpty`) it draws a big `next.first` preview card with a centered
/// countdown RING (`remain / total`) representing the auto-advance-to-next
/// countdown, plus 立即觀看 (`onWatchNext`) / 取消 (`onCancel`). In the 熱門變體
/// (`countdown == nil` || `next.isEmpty`) it draws a 為你推薦 header + a PLAIN
/// `HStack` of `LBPHotCard`s (`onPickHot`). All actions are host-wired forwarders;
/// this layer never loads / advances / picks itself.
public struct EndScreenView: View {

    /// The resolved reference-ui theme (FIRST positional argument, always).
    public let theme: ReferenceUITheme

    /// Auto-next countdown snapshot (`DefaultEndScreenState.countdown`). Non-nil ⇔
    /// 倒數變體; `{ remain, total }` drives the ring progress. Read-only.
    public let countdown: LBEndScreenCountdown?

    /// Watch-next targets (`DefaultEndScreenState.next`). `next.first` is the 倒數
    /// 變體 preview card source. Empty also forces the 熱門變體. Read-only.
    public let next: [LBNavItem]

    /// 熱門推薦 set (`DefaultEndScreenState.hot`). Rendered as a FIXED SMALL PLAIN
    /// `HStack` of `LBPHotCard`s. `duration` is an ALREADY-FORMATTED string. Read-only.
    public let hot: [LBHotItem]

    /// Whether this is the no-countdown LIVE-ENDED state (`endScreenVisible && countdown == nil`,
    /// i.e. live ended with no next). Adds the「直播已結束」rule-flanked title above the 熱門
    /// header (D2 / end-screen-no-countdown #6c). Default `false` → existing 熱門變體 demos /
    /// snapshots render unchanged. No countdown, no auto-advance.
    public let liveEnded: Bool

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

    /// 熱門變體 card tap → host-wired `onPickHot(item)` → host → core load(hot.id).
    /// nil for demo / snapshot instances. This layer NEVER switches videos itself.
    private let onPickHot: ((LBHotItem) -> Void)?

    /// 倒數變體「取消」exit → host-wired `onCancel` → host (dismiss / stay). nil for
    /// demo / snapshot instances.
    private let onCancel: (() -> Void)?

    /// LOCAL presentation-only 熱門推薦 window index (page). Purely a view-state cursor
    /// over `hot` for the「換一批」pill — it slides the FIXED SMALL set to the next page
    /// of `maxHotCards` recommendations WITHOUT loading / switching any video. Default
    /// `0` → shows `hot.prefix(maxHotCards)` (the existing behavior → baseline
    /// byte-identical). NOT part of `init` — never bound from the view-model / core.
    @State private var hotPage: Int = 0

    public init(
        theme: ReferenceUITheme,
        countdown: LBEndScreenCountdown?,
        next: [LBNavItem],
        hot: [LBHotItem],
        liveEnded: Bool = false,
        live: Bool = false,
        onWatchNext: (() -> Void)? = nil,
        onPickHot: ((LBHotItem) -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        self.theme = theme
        self.countdown = countdown
        self.next = next
        self.hot = hot
        self.liveEnded = liveEnded
        self.live = live
        self.onWatchNext = onWatchNext
        self.onPickHot = onPickHot
        self.onCancel = onCancel
    }

    /// Whether the 倒數變體 is active — `countdown != nil` AND a preview target
    /// exists (mirrors `LBPEndScreen`'s `showCountdown`, moments.jsx line 268).
    private var showCountdown: Bool {
        countdown != nil && !next.isEmpty
    }

    public var body: some View {
        ZStack {
            // Full-bleed dark scrim (LBPEndScreen `rgba(8,8,12,0.8)`). The moment
            // composites over the ended video — a fixed design color, not theme bg.
            Self.scrim
                .edgesIgnoringSafeArea(.all)

            if showCountdown {
                countdownVariant
            } else {
                hotVariant
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

    /// Live-gated preview-card media of `next.first` — mirrors `hotMedia` /
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

    // MARK: - 熱門變體 (為你推薦 header + PLAIN HStack of LBPHotCards)
    //
    // Mirrors `LBPEndScreen`'s 熱門 branch (moments.jsx 340-361): a「為你推薦」title
    // + a「換一批」pill, then the `hot` cards. The design uses a 2-col grid in a
    // scroll; the reference-ui surface renders a FIXED SMALL set (`maxHotCards` = 3)
    // in a PLAIN `HStack` (NEVER lazy / scroll — `ImageRenderer` renders those blank).
    //
    // 「換一批」= LOCAL RECOMMENDATION-WINDOW ROLL (NOT a video open). The backend
    // `hot` list has no upper bound (often > 3) and is fetched once at channel load;
    // core has NO refetch-hot API and the backend has NO reshuffle endpoint. So the
    // pill rolls a purely-presentational window (`hotPage`) over the already-loaded
    // `hot` — showing the next page of `maxHotCards` recommendations — and MUST NOT
    // load / switch any video. The design's pill is a refresh-arrow no-op stub
    // (`moments.jsx:295-306`, demo wires `onPickHot={() => {}}`, `:957` — it never
    // opened a video); all four reference-ui platforms previously mis-forwarded it to
    // `onPickHot(hot.first)` (a four-platform proxy bug — Android / RN / Flutter are
    // each a follow-up). Only the 熱門卡 itself opens a video (`onPickHot(item)`); the
    // pill is now decoupled from it. When `hot.count <= 3` (a single page, nothing to
    // roll) the pill is INERT (its action no-ops via a `pageCount > 1` guard) — kept
    // rendered UNCHANGED so the baseline stays byte-identical. (Not `.disabled()`: that
    // dims the pill in the `ImageRenderer` snapshot path; not hidden: that removes it.)

    private var hotVariant: some View {
        VStack(spacing: 0) {
            // D2 (end-screen-no-countdown): live ended with no next → 「直播已結束」收尾標題
            // (rule-flanked, like the countdown variant's「影片結束」) above 為你推薦.
            if liveEnded {
                liveEndedRule
                    .padding(.bottom, 14)
            }
            hotHeader
            hotRow
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// 「— 直播已結束 —」rule-flanked caption for the no-countdown live-ended end screen
    /// (D2). Mirrors `endedRule` but with the live-ended copy (design moments.jsx 熱門變體).
    private var liveEndedRule: some View {
        HStack(spacing: 8) {
            Rectangle().fill(Self.onDarkFaint).frame(width: 18, height: 1)
            Text(Self.liveEndedLabel)
                .font(.system(size: 12 * theme.fontScale, weight: .semibold))
                .foregroundColor(Self.onDarkDim)
                .kerning(1)
            Rectangle().fill(Self.onDarkFaint).frame(width: 18, height: 1)
        }
        .frame(maxWidth: .infinity)
    }

    /// 為你推薦 title + 換一批 pill (LBPEndScreen 343-355). The「換一批」pill is a LOCAL
    /// recommendation-window roll — it advances `hotPage` to the next page of
    /// `maxHotCards` cards over the already-loaded `hot`, and NEVER opens / switches a
    /// video (it does NOT call `onPickHot`). Inert (no-op via a `pageCount > 1` guard)
    /// when there is only one page (`pageCount <= 1`, i.e. `hot.count <= 3`), kept
    /// rendered UNCHANGED so the baseline stays byte-identical (not `.disabled()`,
    /// which dims the pill in the snapshot path).
    private var hotHeader: some View {
        HStack {
            Text(Self.recommendTitle)
                .font(.system(size: 18 * theme.fontScale, weight: .heavy))
                .foregroundColor(.white)
            Spacer(minLength: 0)
            Button(action: {
                // LOCAL window roll ONLY — advance to the next page of recommendations.
                // No `onPickHot`, no `player.load` — the pill NEVER opens a video.
                // Single page (`pageCount <= 1`, i.e. hot.count <= 3) → INERT no-op
                // (nothing to roll → avoids the invalid interaction). Implemented as a
                // guard rather than `.disabled()` because `.disabled()` DIMS the pill in
                // the `ImageRenderer` snapshot path (verified — it changed the
                // `end-screen-live-ended-hot` / `-no-hot` baselines), and the pill must
                // stay byte-identical to the existing baseline.
                guard pageCount > 1 else { return }
                hotPage = (hotPage + 1) % pageCount
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                    Text(Self.shuffleLabel)
                        .font(.system(size: 12 * theme.fontScale, weight: .semibold))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 999)
                        .fill(Self.onDarkFill))
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityIdentifier(LBAccessibilityID.momentEndReshuffle)
        }
        .padding(.bottom, 12)
    }

    /// A PLAIN `HStack` of `LBPHotCard`s — a FIXED SMALL set (first N), NEVER a
    /// lazy / scroll container (the `ImageRenderer` blank-render trap). Each card
    /// taps to `onPickHot(item)`.
    @ViewBuilder
    private var hotRow: some View {
        if hot.isEmpty {
            // Empty-state line (no hot recommendations).
            HStack {
                Spacer(minLength: 0)
                Text(Self.emptyHotLabel)
                    .font(.system(size: 13 * theme.fontScale))
                    .foregroundColor(Self.onDarkFaintText)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 40)
        } else {
            HStack(alignment: .top, spacing: 12) {
                ForEach(Array(hotCards.enumerated()), id: \.element.id) { index, item in
                    hotCard(item)
                        .accessibilityIdentifier(LBAccessibilityID.momentHotCard(index))
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(LBAccessibilityID.momentEndHotRow)
        }
    }

    /// The FIXED SMALL hot set actually rendered — the current `hotPage` window of
    /// `maxHotCards` cards over `hot` (a PLAIN `HStack`, bounded, snapshot-stable).
    /// `hotPage == 0` (the default) ⇒ `hot.prefix(maxHotCards)` (existing behavior →
    /// baseline byte-identical).
    private var hotCards: [LBHotItem] {
        Self.hotWindow(hot, page: hotPage)
    }

    /// Number of `maxHotCards`-sized recommendation pages over `hot` (ceil division).
    /// `1` (or `0` when empty) ⇒ nothing to roll ⇒ the「換一批」pill is disabled.
    private var pageCount: Int {
        Self.pageCount(forHotCount: hot.count)
    }

    /// One 熱門卡 (LBPHotCard, moments.jsx 226-264): a 9:16 cover with a duration
    /// pill (top-left) + a centered play affordance, then a 2-line title. `duration`
    /// is rendered VERBATIM (it is an already-formatted string, NOT seconds). The cover
    /// area is `live`-gated real media (preview loop → static cover → placeholder).
    private func hotCard(_ item: LBHotItem) -> some View {
        Button(action: { onPickHot?(item) }) {
            VStack(alignment: .leading, spacing: 7) {
                ZStack(alignment: .topLeading) {
                    // 9:16 media: `live`-gated real cover / preview over the black
                    // placeholder (mirrors CarouselCardView.mediaThumbnail). `live == false`
                    // → placeholder only (snapshot byte-identical).
                    hotMedia(item)
                    // Centered play affordance (`rgba(0,0,0,0.5)` circle + play glyph).
                    centeredPlay
                    // Duration pill (top-left, monospace, `rgba(0,0,0,0.55)`).
                    durationPill(item.duration)
                        .padding(6)
                }
                .aspectRatio(9.0 / 16.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Text(item.title)
                    .font(.system(size: 12 * theme.fontScale, weight: .semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .frame(maxWidth: .infinity)
    }

    /// The 12-radius black cover placeholder (the existing baseline fill) — the base
    /// layer of a hot card thumbnail, and the `live == false` / empty-URL fallback.
    private var hotCoverPlaceholder: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.black)
    }

    /// Live-gated hot-card media — mirrors `previewMedia` /
    /// `CarouselCardView.mediaThumbnail`: `live` && `preview` → looping preview over the
    /// placeholder; else `live` && `cover` → static still over the placeholder; else the
    /// placeholder alone. Empty `preview` (the backend's current default) falls through
    /// to `cover`; empty `cover` falls through to the placeholder. `live == false` →
    /// placeholder only (never constructs a runtime media view → snapshot byte-identical).
    @ViewBuilder
    private func hotMedia(_ item: LBHotItem) -> some View {
        if live, let url = Self.nonEmptyURL(item.preview) {
            ZStack {
                hotCoverPlaceholder
                LoopingVideoView(url: url)
            }
        } else if live, let url = Self.nonEmptyURL(item.cover) {
            ZStack {
                hotCoverPlaceholder
                RemoteStillImageView(url: url)
            }
        } else {
            hotCoverPlaceholder
        }
    }

    /// Centered play affordance over a hot card cover (LBPHotCard 242-249).
    private var centeredPlay: some View {
        ZStack {
            Circle().fill(Color.black.opacity(0.5))
            Image(systemName: "play.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
        }
        .frame(width: 32, height: 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Duration pill (LBPHotCard 232-241) — play glyph + the verbatim duration
    /// string over a translucent dark capsule.
    private func durationPill(_ duration: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "play.fill")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.white)
            Text(duration)
                .font(.system(size: 10 * theme.fontScale, weight: .semibold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 999)
                .fill(Color.black.opacity(0.55)))
    }

    // MARK: - Helpers

    /// Number of `maxHotCards`-sized recommendation pages over `hotCount` items (ceil
    /// division). `hotCount <= 0 → 0`; otherwise `ceil(hotCount / maxHotCards)`
    /// (e.g. 3 → 1, 4 → 2, 6 → 2, 7 → 3). Pure — no view state.
    static func pageCount(forHotCount count: Int) -> Int {
        guard count > 0 else { return 0 }
        return (count + maxHotCards - 1) / maxHotCards
    }

    /// The `maxHotCards`-sized window of `hot` at `page` (the「換一批」recommendation
    /// window). `page == 0` (or any out-of-range / negative `page`) SAFELY falls back
    /// to `Array(hot.prefix(maxHotCards))` — the existing behavior → baseline
    /// byte-identical; otherwise `hot[page*maxHotCards ..< min(+maxHotCards, count)]`.
    /// Pure — never crashes on a stale / out-of-range `page`.
    static func hotWindow(_ hot: [LBHotItem], page: Int) -> [LBHotItem] {
        let start = page * maxHotCards
        guard page > 0, start < hot.count else {
            return Array(hot.prefix(maxHotCards))
        }
        return Array(hot[start ..< min(start + maxHotCards, hot.count)])
    }

    /// Format `Int` seconds → `mm:ss` (for `LBNavItem.duration`, which IS seconds —
    /// unlike `LBHotItem.duration` which is an already-formatted string).
    static func formatSeconds(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// A trimmed non-empty URL, or nil (empty string → absent). Mirrors
    /// `CarouselCardView.previewURL` / `coverURL`, so an empty `preview` (the backend's
    /// current default for `hot[]` / `next[]`) falls through to `cover`, and an empty
    /// `cover` falls through to the black placeholder (no broken image, no crash).
    static func nonEmptyURL(_ raw: String) -> URL? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : URL(string: s)
    }

    // MARK: - Decorative design tokens (literal moments.jsx hex via Color(hex:))
    //
    // accent comes from the resolved theme; these are FIXED decorative colors lifted
    // verbatim from `LBPEndScreen` / `LBPHotCard` (the dark-scrim moment is white-on
    // -dark regardless of the host theme background — design §2). Kept consistent
    // with the family-2/3 surfaces' surface-token approach (Color(hex:) literals).

    /// Full-bleed scrim (`rgba(8,8,12,0.8)`).
    static let scrim = (Color(hex: "#08080C") ?? Color.black).opacity(0.8)
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

    /// FIXED SMALL hot set cap — a PLAIN HStack of a bounded N (NEVER lazy / scroll).
    static let maxHotCards = 3

    // MARK: - Fixed localized copy (static presentation strings)

    static let endedLabel = "影片結束"
    static let liveEndedLabel = "直播已結束"
    static let autoPlayLabel = "%d 秒後自動播放下一支"
    static let untitledNext = "下一支影片"
    static let cancelLabel = "取消"
    static let watchNextLabel = "立即觀看"
    static let recommendTitle = "為你推薦"
    static let shuffleLabel = "換一批"
    static let emptyHotLabel = "目前沒有推薦影片"
}

// MARK: - Deterministic demo seed (previews + snapshot tests)
//
// Deterministic END moments (倒數變體 + 熱門變體) so previews / the snapshot test
// render the moment's "happy path" without a live player. Built via the skeleton's
// documented demo recipe (`MomentsModel.demoNavItem` / `demoHotItem` /
// `demoHotSet` / `LBEndScreenCountdown(remain:total:)` — all VERIFIED public inits
// reachable from `LivebuyReferenceUI`).

public extension EndScreenView {

    /// A deterministic 倒數變體 demo: an active countdown (`remain 3 / total 5`) + one
    /// watch-next preview target + a small 熱門 set, action-free. Mirrors
    /// `MomentsModel.demoEndCountdown`'s fixture.
    static func demoCountdown(theme: ReferenceUITheme) -> EndScreenView {
        EndScreenView(
            theme: theme,
            countdown: LBEndScreenCountdown(remain: 3, total: 5),
            next: [MomentsModel.demoNavItem()],
            hot: MomentsModel.demoHotSet)
    }

    /// A deterministic 熱門變體 demo: NO countdown, empty watch-next, a FIXED SMALL
    /// 熱門 set (3 cards), action-free. Mirrors `MomentsModel.demoEndHotOnly`.
    static func demoHot(theme: ReferenceUITheme) -> EndScreenView {
        EndScreenView(
            theme: theme,
            countdown: nil,
            next: [],
            hot: MomentsModel.demoHotSet)
    }

    /// A deterministic no-countdown LIVE-ENDED demo (end-screen-no-countdown #6c):
    /// 「直播已結束」title + a FIXED SMALL 熱門 set, NO countdown / NO auto-advance.
    static func demoLiveEnded(theme: ReferenceUITheme) -> EndScreenView {
        EndScreenView(
            theme: theme,
            countdown: nil,
            next: [],
            hot: MomentsModel.demoHotSet,
            liveEnded: true)
    }

    /// A deterministic no-countdown LIVE-ENDED demo with NO hot — just the
    /// 「直播已結束」title (live ended with neither next nor hot).
    static func demoLiveEndedNoHot(theme: ReferenceUITheme) -> EndScreenView {
        EndScreenView(
            theme: theme,
            countdown: nil,
            next: [],
            hot: [],
            liveEnded: true)
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

            // 熱門變體 — 為你推薦 header + plain HStack of LBPHotCards.
            EndScreenView.demoHot(theme: theme)
                .previewDisplayName("hot · recommendation row")
        }
        .frame(width: 393, height: 852)
        .previewLayout(.sizeThatFits)
    }
}
#endif
