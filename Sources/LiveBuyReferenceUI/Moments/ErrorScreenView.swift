import SwiftUI
import LiveBuySDK
import LiveBuyUI

// MARK: - ErrorScreenView — family-4 player moment surface 3 (terminal error)
//
// Spec: `reference-ui-rendering/spec.md` (family-4 moments, surface 3 error)
// Design: rb-ios-moments design.md §3 +
//          `design/templates/minimal/moments.jsx` `LBPErrorScreen` (lines 652-770).
//
// The full-screen TERMINAL error moment for ONE `LBPlayerErrorState`. It is the
// third of the three family-4 moment sub-views composed by `MomentsOverlayView`,
// and it implements the agreed SUB-VIEW INPUT PATTERN documented in
// `MomentsOverlayView.swift`:
//
//   1. `theme: ReferenceUITheme`            — FIRST positional argument, always.
//   2. bound SNAPSHOT VALUE                 — `error: LBPlayerErrorState` (`{ kind,
//      phase }`), passed BY VALUE from `MomentsModel` (never the model, never the
//      template). The container gates on `error != nil`, so this sub-view takes a
//      NON-optional value.
//   3. action closures (LAST, each `= nil`) — `onRetry: (() -> Void)?` (host wires
//      to the core player re-load; shown only when retry can help, i.e. `.stream`)
//      and `onDismiss: (() -> Void)?` (the 返回 / 前往更新 exit). The container does
//      NOT own actions; they forward to the host-wired container closures — NO
//      template / player moment intent exists for retry / dismiss (design §"守住的
//      不變式"). `.outdated`'s 前往更新 primary also forwards `onDismiss` (design wires
//      the outdated primary to `onDismiss`); the host treats it as the upgrade entry.
//
// This sub-view reads ONLY its passed-in value; it never reaches back into
// `MomentsModel` / `DefaultPlayerTemplate` (one-way data flow). It MUST NOT
// re-classify `LBError` — `kind` is ALREADY classified by the template
// (`DefaultErrorState`); this layer ONLY maps the pre-classified `kind` to human
// copy (NO raw code shown). It MUST NOT drive / call retry itself — retry is the
// CORE player's job (SDK auto-retries 3×/3s); the 重試 CTA ONLY forwards `onRetry`.
//
// `phase` is always `.failed` (the only case core exposes — `.retrying` is NOT
// exposed; retries stay `buffering`). The terminal-error variant is the only one
// in scope, mirroring `DefaultErrorState`.
//
// COPY BY KIND (人話, NO raw code — design §"訊息一律人話", aligned to LBPErrorScreen):
//   • `.stream`   「連線發生問題」/「目前無法載入這場直播，請確認網路後再試一次。」
//                  → 重試 (onRetry, accent primary) + 返回 (onDismiss, outlined)
//   • `.notFound` 「找不到這部影片」/「這部影片可能已下架或不存在。」
//                  → 返回 only (onDismiss, filled solo — retry won't help)
//   • `.outdated` 「請更新 App 以繼續觀看」/「你的版本較舊，更新後即可觀看這場直播。」
//                  → 前往更新 only (onDismiss, accent primary — retry won't help)
//
// For `.notFound` / `.outdated` the 重試 CTA is HIDDEN — retrying will not change the
// outcome (the video is gone / the build is rejected). `.notFound` offers a single
// 返回; `.outdated` offers a single accent 前往更新 (its dedicated upgrade affordance,
// design `primaryKind: 'primary'`). Only `.stream` shows the 重試 primary CTA.
//
// iOS-14-safe SwiftUI only. `ZStack` / `VStack` / `HStack` / `Text` / `Button` /
// `Circle` / `RoundedRectangle` / `Image(systemName:)` are all iOS-13+. No
// `.task` / `AsyncImage` / `NavigationStack` / `.foregroundStyle` / `.tint`.
//
// ⚠️ NO ScrollView / LazyVStack / LazyHStack / LazyVGrid anywhere in rendered
// content — `ImageRenderer` renders those BLANK (the family-3 lesson). The error
// card is a fixed centered `VStack` / `HStack`.

/// The family-4 full-screen terminal error moment for one `LBPlayerErrorState`.
/// Renders a centered error card — an icon + kind-specific 人話 title / body — over
/// a full-bleed dim scrim, with a primary 重試 CTA (shown only for `.stream`, where
/// retry can help) and a secondary 關閉. Retry is the core player's job; the CTA
/// only FORWARDS `onRetry`. Reads ONLY the passed-in error (no re-classification).
public struct ErrorScreenView: View {

    /// The resolved reference-ui theme (FIRST positional argument, always).
    public let theme: ReferenceUITheme

    /// The terminal error snapshot this moment renders (`{ kind, phase }`). The
    /// container gates on `error != nil`, so this is NON-optional. Read-only —
    /// `kind` is ALREADY classified by the template (this layer never re-classifies
    /// `LBError`); `phase` is always `.failed`.
    public let error: LBPlayerErrorState

    /// Host-wired「重試」→ host → core re-load. Retry is the CORE player's job (SDK
    /// auto-retries 3×/3s); this layer ONLY forwards the CTA tap, never retries /
    /// loads itself. Shown only for `.stream` (retry can't help `.notFound` /
    /// `.outdated`). nil for demo / snapshot instances (the CTA is inert).
    private let onRetry: (() -> Void)?
    /// Host-wired「關閉」→ host → dismiss the error moment / player. nil for demo /
    /// snapshot instances (the view renders correctly action-free).
    private let onDismiss: (() -> Void)?

    public init(
        theme: ReferenceUITheme,
        error: LBPlayerErrorState,
        onRetry: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.theme = theme
        self.error = error
        self.onRetry = onRetry
        self.onDismiss = onDismiss
    }

    // MARK: - Derived presentation (pure — maps PRE-CLASSIFIED kind to copy/glyph)
    //
    // NOTE: this is NOT re-classification of `LBError` — `kind` is already the
    // template's classification. We map the three KNOWN `kind` cases to human copy
    // + an SF Symbol glyph + whether the 重試 CTA is available. NO raw code shown.

    /// Whether retry can help. Only `.stream` (transient stream / network) — for
    /// `.notFound` (gone) / `.outdated` (build rejected) retry never changes the
    /// outcome, so the 重試 CTA is hidden (`.notFound` → 返回, `.outdated` → 前往更新).
    private var canRetry: Bool { error.kind == .stream }

    /// Kind-specific human title (NO raw code).
    private var title: String {
        switch error.kind {
        case .stream:   return Self.streamTitle
        case .notFound: return Self.notFoundTitle
        case .outdated: return Self.outdatedTitle
        }
    }

    /// Kind-specific human body line (NO raw code).
    private var body_: String {
        switch error.kind {
        case .stream:   return Self.streamBody
        case .notFound: return Self.notFoundBody
        case .outdated: return Self.outdatedBody
        }
    }

    /// Kind-specific SF Symbol glyph (mirrors the design's per-kind SVG icons:
    /// `.stream` → struck-through wifi, `.notFound` → magnifier, `.outdated` →
    /// up-arrow). All iOS-13+ SF Symbols.
    private var glyph: String {
        switch error.kind {
        case .stream:   return "wifi.slash"
        case .notFound: return "magnifyingglass"
        case .outdated: return "arrow.up.circle"
        }
    }

    /// `.outdated` tints with the brand accent (a「前往更新」-style affordance, not a
    /// danger); `.stream` / `.notFound` tint with the design's danger color.
    private var iconTint: Color { error.kind == .outdated ? theme.accent : Self.danger }

    public var body: some View {
        // Full-bleed dim scrim (design `rgba(10,10,14,0.9)`) with the centered
        // error card composited over it. Plain ZStack / VStack — no Lazy / Scroll.
        ZStack {
            Self.scrim
                .edgesIgnoringSafeArea(.all)

            VStack(spacing: 16) {
                iconBadge
                messageBlock
                actions
            }
            .padding(.horizontal, 36)
            .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Icon badge (tinted circle + kind glyph — LBPErrorScreen icon disc)

    private var iconBadge: some View {
        ZStack {
            Circle()
                .fill(iconTint.opacity(0.14))
                .overlay(
                    Circle().stroke(iconTint.opacity(0.40), lineWidth: 1))
            Image(systemName: glyph)
                .font(.system(size: 26, weight: .semibold))
                .foregroundColor(iconTint)
        }
        .frame(width: 60, height: 60)
    }

    // MARK: - Message block (人話 title + body — NO raw code)

    private var messageBlock: some View {
        VStack(spacing: 7) {
            Text(title)
                .font(.system(size: 18 * theme.fontScale, weight: .heavy))
                .foregroundColor(Self.onScrimText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(body_)
                .font(.system(size: 13 * theme.fontScale))
                .foregroundColor(Self.onScrimDim)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 280)
    }

    // MARK: - Actions (per-kind — aligned to LBPErrorScreen)
    //
    // `.stream`   → 重試 (accent primary, forwards onRetry) + 返回 (outlined secondary,
    //               onDismiss).
    // `.notFound` → 返回 ONLY, the FILLED solo affordance (onDismiss) — retry won't help.
    // `.outdated` → 前往更新 ONLY, an accent PRIMARY CTA (onDismiss; the host treats it
    //               as the upgrade entry) — retry won't help, no secondary.

    private var actions: some View {
        VStack(spacing: 10) {
            switch error.kind {
            case .stream:
                // Primary 重試 → host → core re-load (this layer never retries).
                retryPrimaryButton
                // Secondary 返回 — outlined (the design's transparent + 1px stroke).
                backButton(filled: false)
            case .outdated:
                // 前往更新 — the dedicated accent upgrade CTA (no retry glyph). Forwards
                // onDismiss (design wires the outdated primary to onDismiss); the host
                // treats it as the upgrade entry. No secondary.
                upgradePrimaryButton
            case .notFound:
                // 返回 ONLY — the single action, the filled solo affordance (retry is
                // hidden; the video is gone).
                backButton(filled: true)
            }
        }
        .frame(maxWidth: 260)
        .padding(.top, 4)
    }

    /// `.stream` primary 重試 — accent fill + refresh glyph, forwards `onRetry`.
    private var retryPrimaryButton: some View {
        Button(action: { onRetry?() }) {
            HStack(spacing: 7) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                Text(Self.retryLabel)
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
    }

    /// `.outdated` primary 前往更新 — accent fill, NO retry glyph (it's an upgrade CTA,
    /// not a retry). Forwards `onDismiss` (design `isOutdated ? onDismiss`).
    private var upgradePrimaryButton: some View {
        Button(action: { onDismiss?() }) {
            Text(Self.upgradeLabel)
                .font(.system(size: 15 * theme.fontScale, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(theme.accent))
        }
        .buttonStyle(PlainButtonStyle())
    }

    /// 返回 — forwards `onDismiss`. `filled` (no primary present, `.notFound`) draws the
    /// solo filled affordance (`onScrimFill`); otherwise the outlined secondary
    /// (transparent + 1px stroke, beneath `.stream`'s 重試).
    private func backButton(filled: Bool) -> some View {
        Button(action: { onDismiss?() }) {
            Text(Self.backLabel)
                .font(.system(size: (filled ? 15 : 14.5) * theme.fontScale, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, filled ? 13 : 12)
                .background(
                    Group {
                        if filled {
                            RoundedRectangle(cornerRadius: 12).fill(Self.onScrimFill)
                        } else {
                            RoundedRectangle(cornerRadius: 12).stroke(Self.onScrimStroke, lineWidth: 1)
                        }
                    })
                // Whole pill is the tap target — the outlined (stroke-only) variant would
                // otherwise only hit-test the 1px border + text, leaving the interior dead.
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Decorative design tokens (literal minimal hex via Color(hex:))
    //
    // accent / text come from the resolved theme. These are FIXED decorative colors
    // lifted verbatim from the design's `LBPErrorScreen` (the dark scrim + on-scrim
    // whites + danger) — design-literal, NOT theme-resolved (the error moment is a
    // dark full-bleed scrim regardless of the light surface theme), consistent with
    // the family-2/3 surfaces' surface-token approach.

    /// Full-bleed dim scrim (`rgba(10,10,14,0.9)` — design `LBPErrorScreen` bg).
    static let scrim = (Color(hex: "#0A0A0E") ?? Color.black).opacity(0.9)
    /// Danger glyph / icon color (`#EB6E5F` — design `DANGER` = danger.400).
    static let danger = Color(hex: "#EB6E5F") ?? Color.red
    /// Primary on-scrim text (white).
    static let onScrimText = Color.white
    /// Secondary on-scrim text (`rgba(255,255,255,0.62)`).
    static let onScrimDim = Color.white.opacity(0.62)
    /// Outlined secondary button stroke (`rgba(255,255,255,0.28)`).
    static let onScrimStroke = Color.white.opacity(0.28)
    /// Solo-secondary filled affordance (`rgba(255,255,255,0.12)`).
    static let onScrimFill = Color.white.opacity(0.12)

    // MARK: - Fixed localized copy (static presentation strings — 人話, NO raw code)

    static let streamTitle   = "連線發生問題"
    static let streamBody    = "目前無法載入這場直播，請確認網路後再試一次。"
    static let notFoundTitle = "找不到這部影片"
    static let notFoundBody  = "這部影片可能已下架或不存在。"
    static let outdatedTitle = "請更新 App 以繼續觀看"
    static let outdatedBody  = "你的版本較舊，更新後即可觀看這場直播。"
    static let retryLabel    = "重試"
    static let backLabel     = "返回"
    static let upgradeLabel  = "前往更新"
}

// MARK: - Deterministic demo seed (previews + snapshot tests)
//
// Deterministic error snapshots for each `kind` so previews / the snapshot test
// render the three error variants without a live player. `phase` is always
// `.failed` (the only core-exposed phase). All inits were verified against the
// public `LiveBuyUI` source (`DefaultErrorState.swift`).

public extension ErrorScreenView {

    /// A deterministic demo error state for one `kind`, phase `.failed`.
    static func demoError(kind: LBPlayerErrorKind = .stream) -> LBPlayerErrorState {
        LBPlayerErrorState(kind: kind, phase: .failed)
    }

    /// A deterministic demo error screen for one `kind` (default `.stream`),
    /// action-free (renders correctly with `onRetry` / `onDismiss` nil).
    static func demo(
        theme: ReferenceUITheme,
        kind: LBPlayerErrorKind = .stream
    ) -> ErrorScreenView {
        ErrorScreenView(theme: theme, error: demoError(kind: kind))
    }
}

#if DEBUG
struct ErrorScreenView_Previews: PreviewProvider {
    static var previews: some View {
        let theme = ReferenceUIThemePalette.minimal
        Group {
            // .stream → 重試 + 關閉.
            ErrorScreenView.demo(theme: theme, kind: .stream)
                .previewDisplayName("stream · 重試 + 關閉")

            // .notFound → 關閉 only.
            ErrorScreenView.demo(theme: theme, kind: .notFound)
                .previewDisplayName("notFound · 關閉")

            // .outdated → 關閉 only (accent-tinted icon).
            ErrorScreenView.demo(theme: theme, kind: .outdated)
                .previewDisplayName("outdated · 關閉")
        }
        .frame(width: 393, height: 852)
        .previewLayout(.sizeThatFits)
    }
}
#endif
