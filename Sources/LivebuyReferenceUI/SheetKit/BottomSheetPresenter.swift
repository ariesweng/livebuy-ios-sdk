import SwiftUI
import UIKit

// MARK: - Half-screen height cap gate (rb-ios-sheet-half-height)
//
// Production caps every bottom sheet at HALF the screen height (content-sized up to the cap,
// then scrolls within it). The reference-ui snapshot path renders THROUGH this presenter via
// `ImageRenderer`, which renders `ScrollView` content BLANK and never re-renders on the
// `GeometryReader` height measurement. So the snapshot tests set `lbSheetHeightUncapped = true`
// to render the card content-sized (no ScrollView, no cap) — byte-identical to the pre-cap
// baselines. Production leaves it `false` → the cap + scroll applies. (Internal; the snapshot
// tests reach it via `@testable import`.)
private struct SheetHeightUncappedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var lbSheetHeightUncapped: Bool {
        get { self[SheetHeightUncappedKey.self] }
        set { self[SheetHeightUncappedKey.self] = newValue }
    }
}

// MARK: - Drag-resize height override (rb-ios-sheetkit-resize-dismiss-unify, originally
// rb-ios-product-sheet-resize-fav-inline)
//
// `BottomSheetChrome` (the presenter) measures the UP-drag (resize) gesture and computes a live
// height FRACTION; `LBSheetScaffold` (the leaf) is what actually computes `cap` / drives the body
// frame. This environment key is the one channel between them: `BottomSheetChrome` sets it
// (non-nil) once the user has dragged the handle UP at least once during the CURRENT
// presentation; `nil` (the default) means "no override — use the leaf's own `capFraction` /
// `fillToCap`". EVERY `.lbBottomSheet(...)` call site (both the `isPresented:` and `item:`
// overloads) can set this to non-nil — the resize gesture is universal across all 5 real bottom
// sheets, not an opt-in limited to the product-sheet stack. The DOWN-drag (dismiss) gesture never
// touches this key at all (see `BottomSheetChrome.dragGesture` below —
// rb-ios-sheetkit-resize-dismiss-separate-gestures).
private struct SheetHeightFractionOverrideKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    var lbSheetHeightFractionOverride: CGFloat? {
        get { self[SheetHeightFractionOverrideKey.self] }
        set { self[SheetHeightFractionOverrideKey.self] = newValue }
    }
}

// MARK: - Resize-in-progress signal (rb-ios-sheetkit-resize-dismiss-separate-gestures, originally
// `lbSheetIsDragging` from rb-ios-sheetkit-resize-dismiss-unify)
//
// `LBSheetScaffold` reads this to FREEZE its header/footer/body `GeometryReader` measurements
// while the UP-drag (resize) branch of `dragGesture` is actively tracking touch moves (see the
// anti-jitter note on `LBSheetScaffold`'s `onPreferenceChange` handlers below). `BottomSheetChrome`
// sets it `true` only for the span of the RESIZE branch (`onChanged`'s RESIZE branch — growing,
// or, since rb-ios-sheetkit-resize-shrink-after-grow-fix, a brand-new gesture shrinking back
// toward the floor — see `dragGesture` below for the exact routing condition — through
// `onEnded`) — the DOWN-drag (dismiss) branch never sets this `true`: a dismiss drag never
// touches `lbSheetHeightFractionOverride`, so it never triggers the `LBSheetScaffold` re-layout
// feedback loop this freeze exists to prevent (see `dragGesture` below — the two branches are
// independent judgments that share no live HEIGHT calculation, only a few narrow read-only
// reference values that route between them).
private struct SheetIsResizingKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var lbSheetIsResizing: Bool {
        get { self[SheetIsResizingKey.self] }
        set { self[SheetIsResizingKey.self] = newValue }
    }
}

/// Reports the intrinsic height of a sheet region (header / body / footer) so `LBSheetScaffold`
/// can size the scrollable body UP TO the half-screen cap minus the pinned chrome. Consulted only
/// on the production (capped) path.
private struct SheetContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
private struct SheetHeaderHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
private struct SheetFooterHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Background height reporter for one sheet region.
private func sheetHeightReader<K: PreferenceKey>(_ key: K.Type) -> some View where K.Value == CGFloat {
    GeometryReader { geo in Color.clear.preference(key: key, value: geo.size.height) }
}

/// Same as `sheetHeightReader(_:)`, but the underlying `GeometryReader` is only MOUNTED while
/// `active` is true — when `active == false` this is an `EmptyView`, not merely a reader whose
/// output is ignored. Mounting/unmounting a `GeometryReader` on every touch-move sample of an
/// active drag (rather than just discarding its measured result) is what removes the actual
/// per-frame layout-measurement COST, not only the resulting `@State` write — see
/// rb-ios-sheet-resize-drag-render-cost-jitter: freezing only the *result* of a `GeometryReader`
/// still leaves its measurement PASS running on every re-render, a real per-frame cost distinct
/// from the one-frame-behind feedback loop `rb-ios-sheetkit-resize-dismiss-unify` fixed.
@ViewBuilder
private func sheetHeightReader<K: PreferenceKey>(
    _ key: K.Type, active: Bool
) -> some View where K.Value == CGFloat {
    if active {
        sheetHeightReader(key)
    }
}

// MARK: - LBSheetScaffold — pinned header + scrollable body + pinned footer (rb-ios-sheet-pinned-header-footer)
//
// Every grab-handle bottom sheet leaf wraps its three regions in `LBSheetScaffold` so the HEADER
// (title / tabs / close) and FOOTER (CTA / toggle) stay PINNED while only the BODY scrolls — and
// the WHOLE sheet stays ≤ half the screen height.
//
//   • Production (`lbSheetHeightUncapped == false`, default): `VStack { header; ScrollView{body}; footer }`
//     where the body's scroll viewport = `min(bodyIntrinsic, ½screen − header − footer)` (measured
//     via background GeometryReaders). Short sheets stay content-sized; tall ones scroll the body
//     between the pinned header/footer, total ≤ ½ screen.
//   • Snapshot/ImageRenderer (`lbSheetHeightUncapped == true`, set by reference-ui snapshot tests):
//     `VStack { header; body; footer }` — content-sized, NO ScrollView (ImageRenderer renders
//     ScrollView blank). This is byte-identical to the leaf's prior flat `VStack`, so baselines
//     stay unchanged.
//
// Scroll-position reset on content swap (rb-ios-recommendation-switch-scroll-reset): the
// production `ScrollView` above is wrapped in a `ScrollViewReader` with a fixed-identity
// zero-height top anchor placed just before `bodyContent()`. `scrollResetKey` (below) is `nil`
// for every pre-existing call site (`VideoInfoPanelView` / `ProductListView` /
// `NotifyRestockSheetView`), so `.onChange` never fires there and this is byte-identical to the
// prior bare `ScrollView { bodyContent() }`. `ProductDetailSheetView` is the one caller that
// passes a non-nil key (`detail.productId`) — when the SAME sheet instance swaps in a different
// product (a "更多商品" recommendation-card tap re-feeding `detail` into the same
// `.lbBottomSheet(item:)` presentation, rb-ios-recommendation-nav-simplify), the key changes and
// the body jumps back to the top instead of keeping the PREVIOUS product's scroll offset — a
// `UIScrollView` content offset is intrinsic to the scroll view, not the content, so it never
// resets on its own just because the content's data changed underneath it.
struct LBSheetScaffold<Header: View, BodyContent: View, Footer: View>: View {
    @Environment(\.lbSheetHeightUncapped) private var uncapped
    /// Live drag-resize override (rb-ios-sheetkit-resize-dismiss-unify), set by
    /// `BottomSheetChrome` once the user has dragged the handle during the current presentation
    /// (any of the 5 real bottom sheets). `nil` (the default — before the first drag this
    /// presentation) → this scaffold's own `fillToCap` / `capFraction` decide `cap`, unaffected.
    @Environment(\.lbSheetHeightFractionOverride) private var heightFractionOverride
    /// Whether the UP-drag (resize) branch of the handle gesture is CURRENTLY tracking touch
    /// moves (rb-ios-sheetkit-resize-dismiss-separate-gestures) — see the anti-jitter note on the
    /// `onPreferenceChange` handlers below. Never set `true` by the DOWN-drag (dismiss) branch.
    @Environment(\.lbSheetIsResizing) private var isResizing

    /// `true` → 固定高度填滿到 cap（content 頂部對齊、footer 釘底、不足處下方留白、超出則捲動），
    /// body-fill 行為對齊設計稿；cap 固定 0.4 螢幕（rb-ios-compact-sheet-cap-and-footer；原
    /// rb-ios-addtocart-sheet-height-align-restock 為設計 `min(drawerH, 70%)` 的 0.7，已由產品覆蓋）。
    /// `false`（預設）→ content-sized（既有行為），cap 改讀 `capFraction`。snapshot（`uncapped`）
    /// 路徑不受此旗標影響。宣告於三個 `@ViewBuilder` 閉包之前，使多重 trailing-closure call site 仍可用。
    var fillToCap: Bool = false
    /// The non-`fillToCap` cap fraction (screen-height multiplier) for THIS instance. Defaults to
    /// `0.5`, shared by every content-sized leaf — `VideoInfoPanelView` / `ProductListView` /
    /// `ProductDetailSheetView`'s `.detail` presentation all rely on this default (none pass
    /// `capFraction` explicitly). `rb-ios-product-sheet-resize-fav-inline` had `.detail` pass
    /// `0.9` explicitly as its STATIC cap; `rb-ios-sheetkit-resize-dismiss-unify` reverted that —
    /// `0.9` is now purely the shared drag-resize ceiling (`BottomSheetChrome.resizeCeilingFraction`),
    /// reachable by dragging the handle up, not any leaf's static default. Ignored when
    /// `fillToCap == true` (that branch always uses `0.4`).
    var capFraction: CGFloat = 0.5

    /// Identity the production `ScrollView` resets its scroll position on (`nil`, the default,
    /// never resets — rb-ios-recommendation-switch-scroll-reset). Every pre-existing call site
    /// (`VideoInfoPanelView` / `ProductListView` / `NotifyRestockSheetView`) leaves this `nil`, so
    /// `.onChange(of:)` below never fires and behavior is byte-identical to before this key
    /// existed. `ProductDetailSheetView` passes `AnyHashable(detail.productId)` — the ONE existing
    /// mechanism that swaps this scaffold's `bodyContent()` data on an already-mounted instance
    /// (a "更多商品" recommendation-card tap re-feeding a DIFFERENT product's `LBProductDetailState`
    /// into the same `.lbBottomSheet(item:)` presentation). `productId` (not the whole `detail`)
    /// is deliberate: an in-place data refresh of the SAME product (e.g. a poll updating stock/
    /// price) MUST NOT reset the user's scroll position — only an actual product switch should.
    var scrollResetKey: AnyHashable? = nil

    /// Fixed identity for the zero-height top anchor `scrollResetKey`'s `.onChange` scrolls to.
    /// A `static` computed property (Swift does not allow a `static let` STORED property on a
    /// generic type like `LBSheetScaffold<Header, BodyContent, Footer>`) — cheap to recompute,
    /// evaluated at most once per body render. `private static` (not per-instance) is safe: every
    /// `LBSheetScaffold` presentation owns its own `ScrollViewReader`/`ScrollView` pair, so this
    /// identity is never visible to — or able to collide with — another on-screen scaffold's
    /// anchor, nor with any business-content `.id()` inside `bodyContent()` (this string is
    /// namespaced and never exposed outside this file).
    private static var scrollTopAnchorID: String { "lb-sheet-scaffold-scroll-top" }

    @ViewBuilder var header: () -> Header
    @ViewBuilder var bodyContent: () -> BodyContent
    @ViewBuilder var footer: () -> Footer

    @State private var headerH: CGFloat = 0
    @State private var footerH: CGFloat = 0
    @State private var bodyH: CGFloat = 0

    /// `fillToCap` sheet 固定 0.4 螢幕高（精簡購買 / 補貨 sheet 的產品指定高度，覆蓋設計
    /// `min(drawerH, 70%)`；rb-ios-compact-sheet-cap-and-footer）；一般 sheet 維持 `capFraction`
    /// （預設 0.5）。使用者拖曳出的 `heightFractionOverride`（非 nil 時）整段取代這兩者——現為
    /// 全部 5 個 bottom sheet 共用的行為（rb-ios-sheetkit-resize-dismiss-unify，取代原本僅
    /// `.lbBottomSheet(item:)` 三張 sheet 才有的 opt-in）。
    private var cap: CGFloat {
        let fraction = heightFractionOverride ?? (fillToCap ? 0.4 : capFraction)
        return UIScreen.main.bounds.height * fraction
    }
    /// `true` when the sheet should FILL to `cap` (content top-aligned, footer pinned, extra space
    /// blank / scrollable) rather than stay content-sized: either the leaf opted into `fillToCap`,
    /// or the user has live-resized this presentation (in which case the resized height should be
    /// visibly filled, same semantics as `fillToCap`).
    private var effectiveFillToCap: Bool { fillToCap || heightFractionOverride != nil }
    /// Body scroll viewport = cap 減去釘住的 header + footer（floored 使 chrome 過高時仍留可捲區），
    /// 維持整張 sheet ≤ cap。
    private var bodyMax: CGFloat { Self.bodyViewport(cap: cap, headerH: headerH, footerH: footerH) }

    /// Pure：body 捲動視窗高 = `max(120, cap - header - footer)`。抽出供單元測（fillToCap 同高保證）。
    static func bodyViewport(cap: CGFloat, headerH: CGFloat, footerH: CGFloat) -> CGFloat {
        max(120, cap - headerH - footerH)
    }

    /// Pure：`fillToCap` 時整張 sheet 總高 = `header + bodyViewport + footer`。當 `cap - header - footer ≥ 120`
    /// 時恆等於 `cap`（與 header/footer 高度無關）——這保證**不同 footer 的 AddToCart 與 NotifyRestock
    /// 在同一 cap 下固定同高**（rb-ios-addtocart-sheet-height-align-restock）。抽出供單元測。
    static func filledSheetHeight(cap: CGFloat, headerH: CGFloat, footerH: CGFloat) -> CGFloat {
        headerH + bodyViewport(cap: cap, headerH: headerH, footerH: footerH) + footerH
    }

    var body: some View {
        if uncapped {
            // Snapshot / ImageRenderer：維持 content-sized（無 ScrollView / 無 cap），baseline 確定性。
            // `fillToCap` 在此路徑無效（cap 行為本來就不進 snapshot，見檔頭 rb-ios-sheet-half-height）。
            VStack(spacing: 0) {
                header()
                bodyContent()
                footer()
            }
        } else {
            VStack(spacing: 0) {
                header().background(sheetHeightReader(SheetHeaderHeightKey.self, active: !isResizing))
                // `ScrollViewReader` + a zero-height top anchor (rb-ios-recommendation-switch-
                // scroll-reset): lets `scrollResetKey`'s `.onChange` below jump the scroll
                // position back to the top when the caller swaps in different content (see the
                // struct-level doc comment). The anchor sits OUTSIDE `bodyContent()` itself (not
                // injected into it), so it adds zero height and does not disturb
                // `SheetContentHeightKey`'s existing measurement of `bodyContent()` alone.
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            Color.clear.frame(height: 0).id(Self.scrollTopAnchorID)
                            bodyContent().background(sheetHeightReader(SheetContentHeightKey.self, active: !isResizing))
                        }
                    }
                    // `effectiveFillToCap`（`fillToCap` 或使用者已拖曳出高度覆寫）：固定填滿到 bodyMax
                    // （content 頂部對齊、下方留白 / 超出捲動）→ sheet 固定 = cap。否則 content-sized（既有行為）。
                    .frame(height: effectiveFillToCap ? bodyMax : (bodyH <= 0 ? bodyMax : min(bodyH, bodyMax)))
                    .onChange(of: scrollResetKey) { _ in
                        proxy.scrollTo(Self.scrollTopAnchorID, anchor: .top)
                    }
                }
                footer().background(sheetHeightReader(SheetFooterHeightKey.self, active: !isResizing))
            }
            // Anti-jitter freeze (rb-ios-sheetkit-resize-dismiss-unify, hardened by
            // rb-ios-sheet-resize-drag-render-cost-jitter, rescoped to the UP-drag/resize branch
            // ONLY by rb-ios-sheetkit-resize-dismiss-separate-gestures — the DOWN-drag/dismiss
            // branch never sets `isResizing == true`, since dismiss never touches
            // `heightFractionOverride` and therefore never triggers the feedback loop this freeze
            // exists to prevent): while the resize branch is actively tracking touch moves
            // (`isResizing == true`), these three `GeometryReader`s are UNMOUNTED entirely (see the
            // `active:` overload of `sheetHeightReader` above) — not merely present-but-ignored.
            // The original fix (guarding the `onPreferenceChange` write below with `if
            // !isResizing`) only stopped the *result* from reaching `@State`; the
            // `GeometryReader`s themselves kept re-running their layout-measurement pass on every
            // touch-move sample regardless, a real per-frame cost (3 readers here + one more in
            // `BottomSheetChrome.card` for the resize floor) that could miss a frame budget and
            // show up as a persistent stutter during the drag itself — most visible on slow drags,
            // where the same-size hitch is a larger fraction of the expected per-frame motion.
            // Unmounting removes that cost outright. `cap` / `bodyMax` recompute from a FROZEN
            // header/footer pair instead, driven purely by `heightFractionOverride` (no round trip
            // through this scaffold's own layout). Measurement resumes immediately once the resize
            // gesture ends (`isResizing` flips back to `false`, remounting the readers), so content
            // that changes BETWEEN gestures (e.g. the add-to-cart CTA spinner altering footer
            // height) is still picked up correctly. The `if !isResizing` guards below are kept as a
            // defensive no-op belt-and-braces — they should never fire while unmounted, since an
            // unmounted `GeometryReader` reports no preference at all.
            .onPreferenceChange(SheetHeaderHeightKey.self) { if !isResizing { headerH = $0 } }
            .onPreferenceChange(SheetFooterHeightKey.self) { if !isResizing { footerH = $0 } }
            .onPreferenceChange(SheetContentHeightKey.self) { if !isResizing { bodyH = $0 } }
        }
    }
}

// MARK: - SheetKit BottomSheetPresenter — the shared bottom-sheet chrome
//
// One iOS-14-safe presenter for EVERY grab-handle bottom sheet (`VideoInfoPanelView` /
// `ProductListView` here; `ProductDetailSheetView` / `NotifyRestockSheetView` via
// `sheetkit-migrate`). It owns the modal chrome so the leaf sheets carry only their content:
//
//   • full-bleed dim scrim (a transparent `Button` over `Color.black.opacity(0.55)` — the
//     iOS-14-safe recipe proven by `GuestNameEditModalView`; NOT an `onTapGesture` on a
//     `Color`, which renders unreliably headless). Tapping the scrim dismisses, and because
//     it sits ABOVE the host content it also blocks the video gesture layer below.
//   • bottom-anchored card with the shared `SheetGrabHandle` + `theme.background` +
//     `TopRoundedRectangle(20)` + the house shadow.
//   • drag-to-resize (UP) + drag-to-dismiss (DOWN) on the HANDLE strip as TWO STRUCTURALLY
//     INDEPENDENT judgments (rb-ios-sheetkit-resize-dismiss-separate-gestures), routed by the
//     sign of `value.translation.height` at each touch sample — a positive/zero sample also
//     routes to the resize (shrink) branch while a BRAND-NEW gesture still has room to shrink a
//     previously-grown height back toward this presentation's floor
//     (`rb-ios-sheetkit-resize-shrink-after-grow-fix`, see `dragGesture` for the exact combined
//     condition) — replacing the prior `rb-ios-sheetkit-resize-dismiss-unify` design, which
//     computed BOTH through one shared pure
//     function (`dragState`) and one shared freeze flag every touch sample regardless of
//     direction. That shared state machine needed 3 follow-up jitter-fix rounds, and every one of
//     those rounds' own root-cause diagnosis says the jitter "only happens during up-drag
//     resize" — dismiss was never the source, yet was forced to share the same machinery.
//       - UP-drag (resize): the sheet content's height FLOOR is THIS presentation's own
//         default/resting height (`floorFraction`, kept updated to the latest real measurement
//         of `sheetContent()` alone until the user starts dragging, then frozen —
//         `resolvedFloorFraction`, rb-ios-sheetkit-resize-floor-measurement-race-fix; see
//         `CardHeightKey` below), the CEILING is a shared
//         `resizeCeilingFraction` (80%, rb-ios-sheetkit-resize-ceiling-eighty-percent — originally
//         90%) across all 5 real bottom sheets. Dragging UP grows the
//         height toward the ceiling, clamped at the floor on the low end. Driven by the pure
//         function `resizedHeightFraction(...)` — see below.
//       - DOWN-drag (dismiss): independent of the resize branch's state — reads none of
//         `heightFraction` / `floorFraction` / `resizeBaseFraction` directly. `dragOffset` is
//         `max(0, translation.height - reference)`, where `reference` is `shrinkFloorCrossing`
//         when this gesture had shrink room (rb-ios-sheetkit-resize-shrink-after-grow-fix), or `0`
//         otherwise — i.e. relative to THIS gesture's own absolute touch-down point, regardless of
//         any resize excursion this same continuous gesture made first (rb-ios-sheetkit-dismiss-
//         android-parity — a same-gesture resize gets NO credit, unlike the reverted
//         `rb-ios-sheetkit-dismiss-after-resize-fix`; see `localDismissTranslation`'s doc comment
//         for why: that credit made the live visual `dragOffset` snap discontinuously the instant a
//         sample crossed back into this branch, since the resize branch pins `dragOffset` at `0`
//         throughout the whole upward excursion). Past the 100pt threshold on release, dismiss (via
//         the unchanged `dragReleaseOutcome(...)`); otherwise bounce back to 0 — byte-for-byte the
//         pre-rb-ios-sheetkit-resize-dismiss-unify down-drag logic (rb-ios-sheet-drag-dismiss-
//         jitter: the raw translation IS the peek offset), for EVERY same-gesture case now, not
//         just "never resized this gesture" — matching Android's `computeDismissExcessPx`, which
//         never adopted a same-gesture peak credit either (see `DraggableSheetGrabHandle.kt`).
//   • scrim `.opacity` + card `.move(edge:.bottom)` enter/exit transitions.
//   • Anti-jitter freeze while the UP-drag (resize) branch is tracking touch moves — SCOPED to
//     resize only, never triggered by a dismiss drag (`rb-ios-sheetkit-resize-dismiss-unify`,
//     hardened by `rb-ios-sheet-resize-drag-render-cost-jitter` and
//     `rb-ios-sheet-drag-render-drawinggroup`, rescoped by
//     `rb-ios-sheetkit-resize-dismiss-separate-gestures`): `LBSheetScaffold` UNMOUNTS its
//     header/footer/body `GeometryReader`s entirely for the resize gesture's duration
//     (`lbSheetIsResizing` environment key) — not merely discards their result — breaking BOTH
//     the one-frame-behind feedback loop that produced the original visible jitter (resize
//     changing `heightFraction` on every touch move) AND the ongoing per-frame layout-measurement
//     COST of four live `GeometryReader`s during a resize drag, which could miss a frame budget
//     and show up as a persistent stutter through the drag itself (most visible on slow drags).
//     `BottomSheetChrome.card`'s own `CardHeightKey` reader is similarly unmounted once the user
//     starts dragging (`heightFraction` non-nil), since nothing consumes further measurements
//     past that point anyway — see `resolvedFloorFraction` below.
//     `BottomSheetChrome.card` previously ALSO flattened itself via `.drawingGroup()` during a
//     resize drag (round-4, `rb-ios-sheet-drag-render-drawinggroup`) — this was REMOVED by
//     `rb-ios-sheetkit-resize-drawinggroup-identity-loss-fix` after a Simulator capture confirmed
//     it caused `LBSheetScaffold`'s `@State` to be torn down mid-drag (SwiftUI view-identity loss
//     from the `if isResizing { ... } else { ... }` branch producing different concrete types),
//     leaving the sheet's body content fully blank for the drag's duration. See `cardSurface`'s
//     comment for the full write-up; whether the resize branch's own jitter (the problem
//     `.drawingGroup()` was trying to solve) needs a different fix is left to
//     `rb-ios-sheet-drag-hitch-investigation`, not re-litigated here.
//
// Presentation state stays with the CONTAINER (`isPresented` / `item` bindings); the presenter
// only renders chrome + forwards `onDismiss`. `DragGesture` / `.offset` / `withAnimation` /
// `Button` / `.transition` are all iOS-13+ — no `if #available` needed.

public extension View {
    /// Present `content` as a shared bottom sheet while `isPresented` is true. Dismiss paths
    /// (drag the handle past threshold / tap the scrim) set `isPresented = false` and call
    /// `onDismiss`.
    func lbBottomSheet<SheetContent: View>(
        theme: ReferenceUITheme,
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> SheetContent
    ) -> some View {
        modifier(BottomSheetPresentedModifier(
            theme: theme, isPresented: isPresented, onDismiss: onDismiss, sheetContent: content))
    }

    /// `item:` overload (mirrors `.sheet(item:)`) so `sheetkit-migrate` can replace the one
    /// real `.sheet(item:)` (product detail / restock) with the shared chrome.
    ///
    /// Drag-to-resize + drag-to-dismiss (rb-ios-sheetkit-resize-dismiss-unify) apply
    /// UNCONDITIONALLY to every presentation through this overload — there is no longer an
    /// opt-in flag (the prior `resizable: Bool` parameter is removed); see
    /// `BottomSheetChrome.dragGesture` for the two independent branches
    /// (rb-ios-sheetkit-resize-dismiss-separate-gestures).
    func lbBottomSheet<Item: Identifiable, SheetContent: View>(
        theme: ReferenceUITheme,
        item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> SheetContent
    ) -> some View {
        modifier(BottomSheetItemModifier(
            theme: theme, item: item, onDismiss: onDismiss, sheetContent: content))
    }
}

// MARK: - Presenter-owned slide animation
//
// The shared sheet slide curve (design `lbp-sheet-in`, sdk-components.jsx:
// `cubic-bezier(0.32, 0.72, 0.18, 1)` / 0.32s). `timingCurve` is iOS-13+.
//
// The presenter OWNS this animation so EVERY bottom sheet slides up on present and
// down on dismiss REGARDLESS of whether the caller wrapped the present/dismiss toggle
// in `withAnimation` (the prior fragility: VideoInfoPanel / ProductList wrapped it and
// slid, but ProductDetail / NotifyRestock — presented via `syncPresentation`'s plain
// `onChange` — popped instead of slid). Each modifier mirrors its binding into an
// internal `@State` flipped inside `withAnimation(sheetSlide)`, so the chrome's
// `.transition(.move(.bottom))` always plays. The `@State` is seeded from the binding's
// value in `init` (NOT `onAppear`) so the `ImageRenderer` snapshot path — which runs no
// `onAppear` / animation — still renders the chrome at `.constant(true)` (baselines
// stay byte-identical).
/// Duration (seconds) shared by `sheetSlide` and (rb-ios-sheet-drag-dismiss-jitter) the
/// `DispatchQueue.main.asyncAfter` delay that defers `onDismiss()` until the drag-to-dismiss
/// slide-out finishes — a single named source so the two can't drift out of sync.
private let sheetSlideDuration: TimeInterval = 0.32
private let sheetSlide = Animation.timingCurve(0.32, 0.72, 0.18, 1, duration: sheetSlideDuration)

// MARK: - Modifiers

struct BottomSheetPresentedModifier<SheetContent: View>: ViewModifier {
    let theme: ReferenceUITheme
    @Binding var isPresented: Bool
    let onDismiss: (() -> Void)?
    @ViewBuilder let sheetContent: () -> SheetContent

    /// Presenter-owned presence mirror. Seeded from the binding in `init` (so the
    /// ImageRenderer static path renders the chrome at `.constant(true)`), then flipped
    /// inside `withAnimation(sheetSlide)` on every binding change so present/dismiss slide.
    @State private var presented: Bool

    init(theme: ReferenceUITheme,
         isPresented: Binding<Bool>,
         onDismiss: (() -> Void)?,
         @ViewBuilder sheetContent: @escaping () -> SheetContent) {
        self.theme = theme
        self._isPresented = isPresented
        self.onDismiss = onDismiss
        self.sheetContent = sheetContent
        self._presented = State(initialValue: isPresented.wrappedValue)
    }

    func body(content: Content) -> some View {
        ZStack {
            content
            if presented {
                BottomSheetChrome(theme: theme, onDismiss: dismiss) { sheetContent() }
            }
        }
        // Mirror the binding into `presented` inside the slide animation so present
        // (slide up) and dismiss (slide down) animate even when the caller flips
        // `isPresented` without its own `withAnimation`.
        .onChange(of: isPresented) { newValue in
            withAnimation(sheetSlide) { presented = newValue }
        }
    }

    private func dismiss() {
        // scrim tap / drag past threshold → drive the binding false (the onChange mirror
        // plays the slide-down) + forward onDismiss. No inline withAnimation needed.
        isPresented = false
        onDismiss?()
    }
}

struct BottomSheetItemModifier<Item: Identifiable, SheetContent: View>: ViewModifier {
    let theme: ReferenceUITheme
    @Binding var item: Item?
    let onDismiss: (() -> Void)?
    @ViewBuilder let sheetContent: (Item) -> SheetContent

    /// Presenter-owned presence mirror (seeded from the binding in `init`).
    @State private var presented: Bool
    /// The item whose content is drawn. Captured on present / switch; RETAINED during the
    /// slide-down (when the binding is already nil) so the exit transition has content.
    /// Dynamic fields (variant / qty / cartCount) still read live from the model in the
    /// `sheetContent` closure on every re-render — `displayItem` only carries the static
    /// product fields + the exit content.
    @State private var displayItem: Item?

    init(theme: ReferenceUITheme,
         item: Binding<Item?>,
         onDismiss: (() -> Void)?,
         @ViewBuilder sheetContent: @escaping (Item) -> SheetContent) {
        self.theme = theme
        self._item = item
        self.onDismiss = onDismiss
        self.sheetContent = sheetContent
        self._presented = State(initialValue: item.wrappedValue != nil)
        self._displayItem = State(initialValue: item.wrappedValue)
    }

    func body(content: Content) -> some View {
        ZStack {
            content
            if presented, let shown = displayItem {
                BottomSheetChrome(theme: theme, onDismiss: dismiss) { sheetContent(shown) }
            }
        }
        .onChange(of: item?.id) { _ in
            if let current = item { displayItem = current }   // entering / switching → capture content
            withAnimation(sheetSlide) { presented = (item != nil) }
        }
    }

    private func dismiss() {
        item = nil
        onDismiss?()
    }
}

// MARK: - Drag-release decision (rb-ios-sheet-drag-dismiss-jitter)
//
// Pure decision extracted from `BottomSheetChrome.dragGesture`'s `onEnded` so the threshold
// logic is unit-testable without SwiftUI gesture simulation (this target has no ViewInspector /
// UI-automation infra — see `BottomSheetDragDismissOutcomeTests.swift`). Release past the
// threshold used to call `onDismiss()` immediately while `dragOffset` stayed at its release-time
// value un-animated; the container's own `.transition(.move(edge:.bottom))` would then animate
// the slide-out from scratch, unaware of the already-applied drag offset — two independent,
// unsynchronized motions stacking in the same frame (visible jitter on release). The fix keeps
// the decision here pure and moves the two-stage animation (slide `dragOffset` off-screen, THEN
// dismiss) into `dragGesture.onEnded`.
enum SheetDragReleaseOutcome: Equatable {
    /// Drag exceeded the dismiss threshold: animate `dragOffset` to `targetOffset` (fully
    /// off-screen) along the card's own motion, then — only once that finishes — tell the
    /// container to unmount. By the time `.transition(.move(edge:.bottom))` takes over, the
    /// card is already off-screen, so its motion is invisible (no stacked jitter).
    case dismiss(targetOffset: CGFloat)
    /// Drag released under the threshold: spring the card back to `dragOffset == 0` (sheet stays
    /// open). Unchanged from the pre-existing behavior.
    case bounceBack
}

// MARK: - Content height measurement (rb-ios-product-sheet-resize-fav-inline, extended by
// rb-ios-sheetkit-resize-dismiss-unify)
//
// Background `GeometryReader` reader on `sheetContent()` — deliberately NOT the whole card
// (which also includes `SheetGrabHandle` above it): `LBSheetScaffold.cap` (what
// `heightFractionOverride` drives) represents ONLY `sheetContent()`'s own header+body+footer
// total, with no notion of the handle, so this reader must measure on the SAME basis or the
// very first drag sample would compute a `cap` that's `SheetGrabHandle`'s height too tall,
// jumping `bodyMax` the instant the override goes non-nil (see the `card` computed property's
// comment for the full derivation). Two consumers: (1) latches `BottomSheetChrome.floorFraction`
// — this presentation's resize FLOOR — the first time a real (non-override) height is measured,
// so the presenter never needs to know whether it's hosting a `fillToCap` or content-sized leaf
// (design.md Decision 3); (2) a defensive fallback so a resize gesture's first sample has a real
// "current height" to compute its starting fraction from even if `floorFraction` somehow hasn't
// latched yet. Mirrors the `sheetHeightReader` pattern above; never drives any rendering itself.
private struct CardHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

// MARK: - Chrome (scrim + bottom-anchored card + handle + drag)

/// The visual + gesture chrome shared by every bottom sheet. Renders nothing about WHEN it
/// shows (the modifiers own that); it only draws the scrim + card and forwards `onDismiss`.
struct BottomSheetChrome<SheetContent: View>: View {
    let theme: ReferenceUITheme
    let onDismiss: () -> Void
    @ViewBuilder let sheetContent: () -> SheetContent

    /// Drag-to-dismiss threshold (pt) past which release dismisses; otherwise spring back.
    private static var dismissThreshold: CGFloat { 100 }

    /// Shared height-resize CEILING across every bottom sheet (rb-ios-sheetkit-resize-dismiss-unify)
    /// — dragging the handle UP never grows the FULL CARD (handle + `sheetContent()`) past 80% of
    /// the screen, regardless of the sheet's own default/floor height (see `floorFraction`
    /// below). All 5 real bottom sheets (VideoInfoPanel / ProductList / ProductDetail(`.detail`) /
    /// AddToCart / NotifyRestock) share this one value. This constant itself stays a pure 80%
    /// (originally 90%, lowered by product decision — rb-ios-sheetkit-resize-ceiling-eighty-
    /// percent) — `resizedHeightFraction(...)` is what subtracts the handle's height before
    /// applying it to `sheetContent()`, see that function's doc comment (rb-ios-sheetkit-resize-
    /// ceiling-handle-overshoot-fix).
    static var resizeCeilingFraction: CGFloat { 0.80 }

    /// Fallback floor (25%, the pre-unification hardcoded minimum) used ONLY in the practically
    /// unreachable case a drag begins before the card's first layout pass has measured anything
    /// (`floorFraction == nil` AND `measuredCardHeight == 0`). Once the card is on screen —
    /// required for the user to touch its grab handle — `floorFraction` is already latched from
    /// the real measurement (see the `CardHeightKey` `onPreferenceChange` handler below).
    private static var fallbackFloorFraction: CGFloat { 0.25 }

    /// Pure: what a drag release should do, given the released translation and the full
    /// off-screen travel distance. `> dismissThreshold` (strict) matches the pre-existing
    /// threshold semantics bit-for-bit — only the two dismiss-side actions changed (see
    /// `SheetDragReleaseOutcome.dismiss`), not the threshold comparison itself. Extracted for
    /// unit testing (rb-ios-sheet-drag-dismiss-jitter) — call as
    /// `BottomSheetChrome<EmptyView>.dragReleaseOutcome(...)`. Signature / behavior UNCHANGED
    /// across every change that has touched this file — `rb-ios-sheetkit-resize-dismiss-unify`
    /// briefly routed it through the merged `dragState(...).dragOffset`;
    /// `rb-ios-sheetkit-resize-dismiss-separate-gestures` reverted the CALLER back to feeding it
    /// the raw dismiss-branch gesture translation directly (see `dragGesture` below) — this
    /// function itself was never touched by either change.
    static func dragReleaseOutcome(
        translationHeight: CGFloat,
        offscreenDistance: CGFloat
    ) -> SheetDragReleaseOutcome {
        translationHeight > dismissThreshold
            ? .dismiss(targetOffset: offscreenDistance)
            : .bounceBack
    }

    /// Pure: the live height fraction for the UP-drag (resize) branch of a continuous handle drag
    /// (rb-ios-sheetkit-resize-dismiss-separate-gestures — the resize-only half of what used to
    /// be the merged `dragState(...)`; the dismiss half is no longer computed by any shared
    /// function, see `dragGesture` below). `baseFraction` is the fraction in effect when the
    /// CURRENT gesture began (so consecutive drags compose); `floorFraction` is THIS
    /// presentation's own default/resting height (captured once — see the `CardHeightKey`
    /// `onPreferenceChange` handler below, NOT a fixed constant — see `fallbackFloorFraction`'s
    /// doc comment for why a fixed floor was a known defect of the pre-unification design);
    /// `translationHeight` is the gesture's cumulative vertical translation (negative = up =
    /// taller); `screenHeight` is the reference screen height.
    ///
    /// The card's fraction tracks `baseFraction - translationHeight/screenHeight`, clamped to
    /// `[floorFraction, effectiveCeiling]`. Guards `screenHeight <= 0` by returning
    /// `baseFraction` unchanged (defensive; never hit in practice —
    /// `UIScreen.main.bounds.height` is always positive).
    ///
    /// `handleHeight` (rb-ios-sheetkit-resize-ceiling-handle-overshoot-fix): this function's
    /// return value only ever drives `sheetContent()`'s own height (via `LBSheetScaffold.cap`) —
    /// but the visible CARD is `SheetGrabHandle()` (fixed height, `handleHeight`) stacked ON TOP
    /// of `sheetContent()`. Clamping `sheetContent()` alone at the full `resizeCeilingFraction`
    /// (90% at the time — the ceiling was later lowered to 80% by
    /// rb-ios-sheetkit-resize-ceiling-eighty-percent, unrelated to this fix) let the handle's
    /// height push the actual card past that ceiling at full drag — confirmed via Simulator pixel
    /// measurement (~91.7-91.9% at max against the then-90% ceiling, across two different sheets,
    /// matching `resizeCeilingFraction + handleHeight/screenHeight` almost exactly).
    /// `effectiveCeiling` subtracts the handle's screen-height-relative share from
    /// `resizeCeilingFraction` BEFORE clamping `sheetContent()`'s own fraction, so
    /// `sheetContent()` + handle together land exactly at `resizeCeilingFraction`, whatever its
    /// current value is. Deliberately NOT applied to `floorFraction` (the floor's measurement
    /// basis stays `sheetContent()`-only, unchanged) — see `CardHeightKey`'s `onPreferenceChange`
    /// handler for why: avoiding a visible jump on the FIRST drag sample doesn't apply to the
    /// ceiling, since the user dragging all the way up already expects to land on some fixed
    /// maximum.
    static func resizedHeightFraction(
        baseFraction: CGFloat,
        floorFraction: CGFloat,
        translationHeight: CGFloat,
        screenHeight: CGFloat,
        handleHeight: CGFloat
    ) -> CGFloat {
        guard screenHeight > 0 else { return baseFraction }
        let candidate = baseFraction + (-translationHeight / screenHeight)
        let effectiveCeiling = resizeCeilingFraction - (handleHeight / screenHeight)
        return min(effectiveCeiling, max(floorFraction, candidate))
    }

    /// Pure: the DOWN-drag (dismiss) branch's threshold input. Measured relative to this
    /// gesture's absolute touch-down point, regardless of any resize excursion this same
    /// continuous gesture may have made first (rb-ios-sheetkit-dismiss-android-parity — reverts
    /// `rb-ios-sheetkit-dismiss-after-resize-fix`'s same-gesture peak credit; see below for why).
    /// `shrinkFloorCrossing` (`rb-ios-sheetkit-resize-shrink-after-grow-fix`) is unaffected: a
    /// BRAND-NEW gesture that starts with shrink room (this presentation was already taller than
    /// its floor when this gesture began) still measures its threshold relative to the point
    /// where that shrink room is exhausted, not this gesture's own absolute touch-down point —
    /// see that `@State`'s doc comment. `nil` when this gesture had no shrink room to begin with
    /// (the ordinary case), in which case this returns `rawTranslationHeight` unchanged.
    ///
    /// **Why the same-gesture peak credit was reverted**: `rb-ios-sheetkit-dismiss-after-resize-
    /// fix` made growing then reversing WITHOUT releasing require only ~(resize amount reversed)
    /// of travel to reach the 100pt dismiss threshold, instead of (resize amount + 100pt) — but
    /// the live visual `dragOffset` (see `dragGesture` below) reads this SAME value continuously
    /// while the finger is still down, not just at release. Because the resize branch pins
    /// `dragOffset` at `0` throughout the whole upward excursion, the instant a sample crosses
    /// back into this branch, the formula already "owed" the entire historical resize distance in
    /// one step — the card visually snapped toward (or past) off-screen in a single frame, rather
    /// than following the finger continuously from that crossing point. A real-device comparison
    /// against Android's parity function (`DraggableSheetGrabHandle.kt`'s
    /// `computeDismissExcessPx`) confirmed Android never took this credit for a within-gesture
    /// reversal — its plain, crossing-relative formula feels smooth (no jump) at the cost of
    /// needing the same 100pt travel past the floor regardless of how large the prior resize was,
    /// exactly what `shrinkFloorCrossing` already does for the cross-gesture case below. This
    /// change brings iOS's SAME-gesture case in line with that: smooth, jump-free visual tracking
    /// over the shorter travel distance `-dismiss-after-resize-fix` had bought. The cross-gesture
    /// case (`shrinkFloorCrossing`) is untouched — it was never jump-prone (its own crossing-
    /// relative math already reads `0` exactly at the moment the floor is reached).
    static func localDismissTranslation(
        rawTranslationHeight: CGFloat,
        shrinkFloorCrossing: CGFloat?
    ) -> CGFloat {
        rawTranslationHeight - (shrinkFloorCrossing ?? 0)
    }

    /// Pure: decides whether/how a new `CardHeightKey` measurement should update `floorFraction`
    /// (rb-ios-sheetkit-resize-floor-measurement-race-fix). `heightFraction == nil` (the user
    /// hasn't started a resize drag this presentation yet) → adopt the latest measurement
    /// (keep reflecting it — MUST NOT latch only the first one, since a single measurement can
    /// land on a transient value from BEFORE `LBSheetScaffold`'s own nested `bodyH` measurement
    /// has converged — a real-device Simulator capture caught `floorFraction` locking onto 65%
    /// of screen height when the content's true stable height was 34.5%, matching exactly the
    /// `bodyMax` fallback frame `ScrollView` uses before `bodyH` lands). `heightFraction` non-nil
    /// (a resize drag has begun) → keep `currentFloor` frozen (matches the existing "this
    /// gesture's floor is decided once, at drag start, and doesn't get recomputed mid-drag"
    /// design).
    static func resolvedFloorFraction(
        currentFloor: CGFloat?,
        heightFraction: CGFloat?,
        newMeasurement: CGFloat
    ) -> CGFloat? {
        heightFraction == nil ? newMeasurement : currentFloor
    }

    @State private var dragOffset: CGFloat = 0
    /// Live drag-resize result (rb-ios-sheetkit-resize-dismiss-unify), written ONLY by the
    /// UP-drag (resize) branch of `dragGesture`. `nil` = the user hasn't dragged UP this
    /// presentation yet — the leaf's own default cap applies.
    @State private var heightFraction: CGFloat?
    /// The fraction in effect at the START of the CURRENT resize gesture; `nil` between resize
    /// gestures. Captured once per resize gesture (first up-drag sample), cleared in `onEnded`.
    /// Never touched by the dismiss branch.
    @State private var resizeBaseFraction: CGFloat?
    /// `sheetContent()`'s last-measured on-screen height (pt) — NOT the whole card, deliberately
    /// EXCLUDING the grab handle above it (fed by `CardHeightKey`, measured on `sheetContent()`
    /// alone; see the `card` computed property's comment for why). Also seeds `floorFraction`
    /// (below) and, defensively, a gesture's base fraction if a drag somehow begins before
    /// `floorFraction` has latched. The `CardHeightKey` reader that feeds this is only mounted
    /// while `floorFraction == nil` (rb-ios-sheet-resize-drag-render-cost-jitter) — once latched,
    /// this value simply stops updating (it has no consumer past that point anyway).
    @State private var measuredCardHeight: CGFloat = 0
    /// This presentation's default/resting height fraction (rb-ios-sheetkit-resize-dismiss-unify).
    /// — the RESIZE FLOOR. Kept updated to the LATEST `sheetContent()` measurement
    /// (`resolvedFloorFraction`, rb-ios-sheetkit-resize-floor-measurement-race-fix — supersedes
    /// the original "latch once, on the first measurement" design, which could freeze onto a
    /// transient pre-layout-convergence value) until the user actually starts a resize drag
    /// (`heightFraction` goes non-nil), at which point it freezes and stops updating for the rest
    /// of this presentation, even as subsequent drags change the rendered height via
    /// `heightFraction`. `nil` until the first measurement lands; resets to `nil` on the next
    /// presentation (fresh `@State`, same lifecycle as `heightFraction`).
    @State private var floorFraction: CGFloat?
    /// Whether the UP-drag (resize) branch of the handle gesture is CURRENTLY tracking touch
    /// moves (rb-ios-sheetkit-resize-dismiss-separate-gestures) — forwarded to `LBSheetScaffold`
    /// via `lbSheetIsResizing` so it can freeze its own measurements for the resize gesture's
    /// duration (see the anti-jitter note there). `true` only for the span of the resize branch
    /// (`dragGesture.onChanged`'s RESIZE branch — see that function for the exact routing
    /// condition, widened by rb-ios-sheetkit-resize-shrink-after-grow-fix — through `.onEnded`);
    /// the DOWN-drag (dismiss) branch never sets this `true` — it has no reason to, since dismiss
    /// never touches `lbSheetHeightFractionOverride`.
    @State private var isResizing = false
    /// How much MORE positive `translation.height` a brand-new gesture needs before its shrink
    /// room (relative to this presentation's real floor) is exhausted
    /// (`rb-ios-sheetkit-resize-shrink-after-grow-fix`). `nil` means "no shrink room" — either
    /// this presentation has never been dragged UP (current height already equals
    /// `floorFraction`), or the current height IS the floor for some other reason. Non-nil is
    /// always `>= 0` (`(currentHeightAtGestureStart - floorFraction) * screenHeight`).
    ///
    /// **The bug this fixes**: dragging the handle UP once (say floor 45% → 70%) and releasing
    /// leaves `heightFraction == 0.70` — deliberately kept ACROSS gestures (see `heightFraction`'s
    /// own doc comment: consecutive drags compose). But `dragGesture.onChanged` used to route
    /// PURELY on `value.translation.height`'s sign: a brand-new gesture's FIRST touch sample is
    /// never negative on its own (a fresh touch has `translation.height == 0`, then goes positive
    /// as the user pulls down), so a new "pull down" gesture went straight into the DISMISS
    /// branch — which only ever produces `dragOffset` (a visual peek), never touches
    /// `heightFraction` at all. The card could only stay at 70% (bounce back) or close entirely
    /// (past 100pt) — the 45%-70% range was completely unreachable from a NEW gesture, even
    /// though `resizedHeightFraction(...)` itself has always been able to compute a smaller
    /// fraction (see `testResizedHeightFraction_dragDown_decreasesByTranslationFraction`) — the
    /// bug was entirely in which branch a new gesture's samples got routed to, not in the height
    /// math itself.
    ///
    /// Captured ONCE per gesture, at the same first-sample checkpoint that captures
    /// `resizeBaseFraction` (see `dragGesture` below) — deliberately BEFORE the direction check,
    /// so both branches can read it: `value.translation.height < shrinkFloorCrossing!` (while
    /// non-nil) routes a POSITIVE-translation sample into the RESIZE branch (shrinking, via the
    /// unchanged `resizedHeightFraction(...)`) instead of DISMISS, for exactly as long as there is
    /// still room above the floor. Once `translation.height` reaches or passes this value, the
    /// height has reached the floor and the SAME gesture's continued downward drag falls through
    /// to the DISMISS branch — whose 100pt threshold is then measured relative to THIS value (see
    /// `localDismissTranslation` below), not the gesture's own absolute touch-down point, so the
    /// user doesn't have to drag 100pt further just because they happened to start from a taller
    /// height. Reset to `nil` at the end of every gesture (`onEnded`), same lifecycle as
    /// `resizeBaseFraction`.
    ///
    /// Used to be one of two dismiss-reference states, alongside `resizePeakTranslation` (the
    /// same-gesture resize-excursion peak) — kept deliberately SEPARATE from it rather than merged
    /// into one dual-purpose state (see design.md Decision 2 of `rb-ios-sheetkit-resize-shrink-
    /// after-grow-fix` for why collapsing them would have repeated the shape of a different,
    /// already-fixed bug, `rb-android-sheetkit-resize-floor-reanchor-fix`). `resizePeakTranslation`
    /// was later removed entirely (rb-ios-sheetkit-dismiss-android-parity) — this is now the ONLY
    /// state `localDismissTranslation` reads beyond the raw touch sample itself.
    @State private var shrinkFloorCrossing: CGFloat?

    var body: some View {
        ZStack {
            scrim
                .transition(.opacity)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                card
                    .transition(.move(edge: .bottom))
            }
        }
        // Names a coordinate space anchored to this OUTER ZStack (rb-ios-sheetkit-resize-render-
        // cost-fix) — this container's own frame does NOT move/resize during a resize drag (only
        // `card` inside it grows). `dragGesture` below anchors to THIS space instead of the
        // default `.local` (see that property's doc-comment for why: `.local` would anchor to
        // `SheetGrabHandle`, whose own screen position moves as a direct result of the drag it's
        // hosting).
        .coordinateSpace(name: "bottomSheetChromeSpace")
    }

    // Full-bleed dim scrim — transparent Button (iOS-14-safe; an onTapGesture on a Color
    // renders unreliably headless). Sits above host content → also blocks the video below.
    private var scrim: some View {
        Button(action: onDismiss) {
            Color.black.opacity(0.55)
                .edgesIgnoringSafeArea(.all)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(LBAccessibilityID.bottomSheetScrim)
    }

    private var card: some View {
        cardSurface
            .shadow(color: Color.black.opacity(0.18), radius: 14, x: 0, y: -4)
            .offset(y: max(0, dragOffset))
    }

    // MARK: - `.drawingGroup()` REMOVED (rb-ios-sheetkit-resize-drawinggroup-identity-loss-fix,
    // overturning round-4 / rb-ios-sheet-drag-render-drawinggroup)
    //
    // round-4 conditionally wrapped this surface in `.drawingGroup()` while `isResizing == true`,
    // to flatten shadow/compositing cost during a resize drag (see git history for that
    // rationale). A Simulator capture found this caused a confirmed CORRECTNESS bug, not just a
    // theoretical risk: `if isResizing { surface.drawingGroup() } else { surface }` makes the two
    // branches different concrete types, so SwiftUI's `@ViewBuilder` produces a
    // `_ConditionalContent<TrueContent, FalseContent>` — the instant `isResizing` flips, SwiftUI
    // treats this as a BRAND NEW view identity, destroying and reconstructing `cardContent`
    // (including the nested `LBSheetScaffold`'s `headerH`/`footerH`/`bodyH` `@State`, which reset
    // to `0`). That collided with the anti-jitter mechanism directly below (which unmounts the
    // `GeometryReader`s that would otherwise re-measure those three values while resizing) —
    // together, the freshly-reset `@State` had no way to recover until the ENTIRE drag ended.
    // Screenshot evidence: the sheet's body content (e.g. the product list) rendered fully BLANK
    // for the whole duration of a resize drag; header and footer (unaffected by this specific
    // `@State` reset, being pinned chrome) kept rendering correctly.
    //
    // `.drawingGroup()`'s own performance rationale was never verified with Instruments or an
    // on-device frame-rate measurement (round-4's own comment said so at the time) — trading an
    // unverified performance hypothesis for a confirmed, always-reproducing blank-content bug was
    // not a reasonable trade. This surface is REMOVED, not "optimized" — `cardSurface` reverts to
    // its pre-round-4 single-branch form below, so `isResizing` no longer affects its type and
    // `LBSheetScaffold`'s `@State` is never torn down mid-drag. See design.md "Decisions" §1 for
    // the alternatives considered (forcing view identity with `.id()`; hoisting the `@State` out
    // of the conditionally-rebuilt subtree) and why removal was chosen over both.
    private var cardSurface: some View {
        cardContent
            .background(theme.background)
            .clipShape(TopRoundedRectangle(radius: 20))
    }

    private var cardContent: some View {
        VStack(spacing: 0) {
            SheetGrabHandle()
                .contentShape(Rectangle())   // whole handle strip is the drag target
                .gesture(dragGesture)
            // The leaf owns its own half-screen cap + body scroll via `LBSheetScaffold`
            // (pinned header/footer, scrollable body — rb-ios-sheet-pinned-header-footer). The
            // presenter only draws the grab handle + card chrome. `heightFraction` (non-nil once
            // the user has dragged UP this presentation) and `isResizing` are forwarded via
            // environment so the leaf's `LBSheetScaffold` can override its own cap and freeze its
            // measurements while the RESIZE branch is dragging (rb-ios-sheetkit-resize-dismiss-
            // unify, rescoped to resize-only by rb-ios-sheetkit-resize-dismiss-separate-gestures).
            //
            // `CardHeightKey` is measured HERE — on `sheetContent()` alone, NOT the outer VStack
            // — because `LBSheetScaffold.cap` (what `heightFractionOverride` ultimately drives)
            // represents ONLY `sheetContent()`'s own total height (header + body + footer); it
            // has no notion of the grab handle above it. Measuring the whole card (handle +
            // content) would fold `SheetGrabHandle`'s fixed 32pt (a `.frame(height:)` centering
            // the 36×4pt pill, rb-ios-sheetkit-drag-row-height-32pt — originally ~16pt via 8pt
            // top padding + 4pt pill + 4pt bottom padding, briefly 44pt via rb-ios-sheetkit-
            // drag-row-height) into `floorFraction`, so the very FIRST drag sample — even at ~0
            // net translation — would compute a `cap` ~32pt taller than the sheet's actual
            // pre-drag content height, and `bodyMax` would jump by that amount
            // the instant `heightFractionOverride` goes non-nil (content-sized → fill-to-cap).
            // Scoping the reader to `sheetContent()` keeps `floorFraction` and `cap` on the SAME
            // basis as `LBSheetScaffold`'s own header/body/footer measurements, so the mode switch lands
            // on the identical pixel height (design.md Decision 4). Note:
            // `testFloorFraction_derivedFromSheetContentHeightOnly_reproducesPreDragBodyHeightWithoutJump`
            // only checks the arithmetic identity `cap - headerH - footerH == bodyH`; it does not
            // mount `BottomSheetChrome` and so cannot by itself catch the reader being moved back
            // onto the outer `VStack` — this comment's claim rests on the reader being attached
            // here, not on that test.
            //
            // The reader is only MOUNTED while `heightFraction == nil` (rb-ios-sheet-resize-drag-
            // render-cost-jitter, condition updated by rb-ios-sheetkit-resize-floor-measurement-
            // race-fix) — once the user starts a resize drag, `measuredCardHeight`'s further
            // updates have no consumer at all (`dragGesture.onChanged`'s `floor` fallback —
            // `measuredCardHeight > 0 ? ... : fallbackFloorFraction` — is dead once `floorFraction`
            // is non-nil, since `floorFraction ?? ...` short-circuits first, and `floorFraction`
            // is guaranteed non-nil by the time a drag can begin — the card has to be on screen,
            // i.e. already measured, for the user to touch its grab handle), so continuing to
            // re-measure once dragging was pure waste: a `GeometryReader` layout pass on every
            // touch-move sample of EVERY subsequent drag this presentation, for a value nothing
            // reads. Unmounting it removes that cost outright, not just its (already-discarded)
            // result. BEFORE the first drag, though, the reader stays mounted and keeps updating
            // `floorFraction` on every measurement (see `resolvedFloorFraction` below) — this is
            // deliberately NOT "mounted only until the first measurement" (that was the old,
            // buggy behavior).
            sheetContent()
                .environment(\.lbSheetHeightFractionOverride, heightFraction)
                .environment(\.lbSheetIsResizing, isResizing)
                .background(sheetHeightReader(CardHeightKey.self, active: heightFraction == nil))
                .onPreferenceChange(CardHeightKey.self) { newHeight in
                    measuredCardHeight = newHeight
                    // Keep reflecting the LATEST measurement into the RESIZE FLOOR until the user
                    // actually starts a resize drag (rb-ios-sheetkit-resize-floor-measurement-
                    // race-fix) — this is "the height `sheetContent()` actually rendered at,
                    // before any drag" for EVERY leaf kind (a `fillToCap` leaf measures its
                    // fixed cap; a content-sized leaf measures its natural content height), so
                    // the presenter never needs to know which kind of leaf it's hosting
                    // (rb-ios-sheetkit-resize-dismiss-unify, design.md Decision 3). MUST NOT latch
                    // only the first measurement — `CardHeightKey` measures `sheetContent()` as a
                    // whole, but `LBSheetScaffold`'s own nested body-height `GeometryReader`
                    // (`SheetContentHeightKey`) is a separate, independently-converging layout
                    // pass; a single early measurement can land before that inner pass has
                    // settled, freezing onto a transient value (a real-device Simulator capture
                    // caught exactly this: `floorFraction` locked at 65% of screen height —
                    // matching the `ScrollView`'s pre-convergence `bodyMax` fallback frame plus
                    // header/footer — when the content's true stable height was 34.5%). Once the
                    // user starts dragging (`heightFraction` non-nil), `resolvedFloorFraction`
                    // freezes the value and this reader unmounts on the next `body` evaluation.
                    if newHeight > 0 {
                        floorFraction = Self.resolvedFloorFraction(
                            currentFloor: floorFraction,
                            heightFraction: heightFraction,
                            newMeasurement: newHeight / UIScreen.main.bounds.height)
                    }
                }
        }
    }

    // MARK: - Drag gesture (rb-ios-sheetkit-resize-dismiss-separate-gestures, dismiss threshold
    // reference point updated by rb-ios-sheetkit-dismiss-after-resize-fix, cross-gesture shrink
    // routing added by rb-ios-sheetkit-resize-shrink-after-grow-fix)
    //
    // Two branches. Routed by the CURRENT touch sample's `translation.height`: negative always
    // means RESIZE (growing); a non-negative sample still counts as RESIZE too, but only while it
    // is shrinking a previously-grown height back down toward this presentation's floor — i.e.
    // while it is `< shrinkFloorCrossing` (a value captured once at this gesture's first sample,
    // `nil` when there is no shrink room — see that `@State`'s doc comment,
    // `rb-ios-sheetkit-resize-shrink-after-grow-fix`). Once a sample is neither of those, it's
    // DISMISS. This routing condition is evaluated as ONE combined check per sample (not "sign
    // first, crossing second") — see the `isResizeSample` local below.
    //
    // Aside from that routing widening, the two branches' own bodies still mirror the pre-
    // `rb-ios-sheetkit-resize-dismiss-unify` structure. The resize branch never
    // reads `dragOffset` (beyond resetting it to 0 when it takes over, discarding a same-gesture
    // down-peek that reversed upward past 0); the dismiss branch never reads `heightFraction` /
    // `floorFraction` / `resizeBaseFraction` at all — the two branches share NO state at all
    // (rb-ios-sheetkit-dismiss-android-parity removed the one channel that used to exist,
    // `resizePeakTranslation` — see `localDismissTranslation`'s doc comment for why). A same-
    // gesture resize-then-reverse is measured exactly like a plain pull-down that never resized at
    // all: relative to this gesture's own absolute touch-down point, with no credit for distance
    // already travelled during the resize.
    // `.named("bottomSheetChromeSpace")` (rb-ios-sheetkit-resize-render-cost-fix), NOT the
    // default `.local` — `.local` would anchor `translation`/`location` to `SheetGrabHandle`'s
    // OWN frame, but that frame moves (this card is bottom-pinned and grows upward, so the
    // handle's screen position shifts as `heightFraction` — this gesture's own output — changes),
    // making the coordinate conversion a function of the gesture's own effect. A real-device
    // capture confirmed the resulting artifact directly: per-sample NSLog of `value.time` (the
    // touch sample's own timestamp), `value.startLocation`, and `value.location` showed a SINGLE
    // recognizer delivering correctly time-ordered samples (`value.time` strictly increasing, one
    // call per display frame, `value.startLocation` constant) from a stable gesture start — yet
    // `value.location` itself alternated between two smooth but offset tracks, because adjacent
    // samples were converted through the handle's pre- vs. post-relayout frame whenever that
    // relayout didn't keep up with the touch-sampling rate. Anchoring to this outer, non-moving
    // space instead removes the feedback loop outright: re-running the same capture on the same
    // device showed `translation`/`heightFraction` converge to a single monotonic sequence, and
    // the visible jitter was gone.
    private var dragGesture: some Gesture {
        DragGesture(coordinateSpace: .named("bottomSheetChromeSpace"))
            .onChanged { value in
                // Capture this GESTURE's `base` / `floor` / `shrinkFloorCrossing` on its very
                // first sample — BEFORE the direction check, so both branches can read the result
                // (rb-ios-sheetkit-resize-shrink-after-grow-fix). This used to happen only inside
                // the RESIZE branch (`base`/`floor` were computed there, `resizeBaseFraction`
                // captured there too); it's hoisted here because a brand-new gesture that STARTS
                // by shrinking needs to know its crossing point before it can even decide which
                // branch to route into. `resizeBaseFraction == nil` is this gesture's own "is this
                // the first sample?" signal (`onEnded` always clears it), unchanged from before.
                let screenHeight = UIScreen.main.bounds.height
                let floor = floorFraction
                    ?? (measuredCardHeight > 0 ? measuredCardHeight / screenHeight : Self.fallbackFloorFraction)
                if resizeBaseFraction == nil {
                    let base = heightFraction ?? floor
                    resizeBaseFraction = base
                    // `> floor` (strict): equal means this presentation is ALREADY at its floor —
                    // the "never dragged up" / "already shrunk all the way" degenerate case — and
                    // MUST produce `nil`, not `0`, so the routing check below (`crossing != nil`)
                    // degrades to exactly the pre-fix sign-only check.
                    shrinkFloorCrossing = base > floor ? (base - floor) * screenHeight : nil
                }
                let base = resizeBaseFraction!
                let crossing = shrinkFloorCrossing

                // ONE combined routing check per sample: negative translation is always RESIZE
                // (growing, unchanged from before); a non-negative translation is ALSO RESIZE, but
                // only while there's still shrink room left this gesture (`crossing != nil` and
                // this sample hasn't reached it yet) — that's the new "cross-gesture shrink" path.
                // Everything else is DISMISS.
                let isResizeSample = value.translation.height < 0
                    || (crossing != nil && value.translation.height < crossing!)

                guard isResizeSample else {
                    // DISMISS branch — reads none of the resize branch's state at all
                    // (`heightFraction` / `floorFraction` / `resizeBaseFraction`). Its threshold is
                    // measured relative to `crossing` when this gesture had shrink room
                    // (rb-ios-sheetkit-resize-shrink-after-grow-fix), otherwise relative to this
                    // gesture's own absolute touch-down point — a same-gesture resize excursion
                    // earlier in THIS gesture gets no credit (rb-ios-sheetkit-dismiss-android-
                    // parity — see `localDismissTranslation`'s doc comment for why).
                    isResizing = false
                    dragOffset = max(0, Self.localDismissTranslation(
                        rawTranslationHeight: value.translation.height,
                        shrinkFloorCrossing: crossing))
                    return
                }
                // RESIZE branch — dragging UP grows the card toward the shared 80% ceiling from
                // THIS presentation's own floor (its default/resting height, latched once — see
                // `CardHeightKey` above); since rb-ios-sheetkit-resize-shrink-after-grow-fix, a
                // non-negative sample that's still short of `crossing` ALSO lands here, shrinking
                // the card back down toward that same floor via the exact same unchanged
                // `resizedHeightFraction(...)` call below (the function's own math has always been
                // direction-agnostic — see `testResizedHeightFraction_dragDown_
                // decreasesByTranslationFraction`). Discards any partial down-peek `dragOffset`
                // this same continuous gesture may have accrued before reversing upward past 0, so
                // the two mutually-exclusive visual effects (offset vs. live height) never combine.
                isResizing = true
                dragOffset = 0
                heightFraction = Self.resizedHeightFraction(
                    baseFraction: base,
                    floorFraction: floor,
                    translationHeight: value.translation.height,
                    screenHeight: screenHeight,
                    handleHeight: SheetGrabHandle.fixedHeight)
            }
            .onEnded { value in
                // `wasResizing` snapshots `isResizing` BEFORE this handler resets it — every
                // RESIZE-branch `onChanged` sample writes `isResizing = true`, every DISMISS-branch
                // sample writes `false` (see `dragGesture.onChanged` above), so its value coming
                // into `onEnded` is exactly "which branch produced this gesture's LAST `onChanged`
                // sample?" (SwiftUI always delivers a final `onChanged` at the released value
                // before `onEnded` fires).
                //
                // rb-ios-sheetkit-resize-shrink-after-grow-fix: this REPLACES the prior
                // `guard value.translation.height >= 0 else { return }`, which used the ABSOLUTE
                // translation's sign as a proxy for the same question. That proxy was exact ONLY
                // because, pre-this-change, the RESIZE branch's condition was itself exactly
                // `translation.height < 0` — so the sign and `isResizing` always agreed. Now that
                // the RESIZE branch also covers "non-negative but still short of
                // `shrinkFloorCrossing`" (a brand-new gesture shrinking a previously-grown height),
                // a gesture released MID-SHRINK has `translation.height >= 0` while its last sample
                // was still RESIZE — the old proxy would have wrongly fallen through to a
                // dismiss/bounce decision instead of keeping the shrunk height as-is. Reading
                // `isResizing` directly is correct in both the old and new cases (when
                // `shrinkFloorCrossing` is `nil` throughout, `isResizing`'s value AT THIS POINT is
                // provably identical to `value.translation.height < 0` at the gesture's final
                // sample, so every pre-existing scenario is byte-identical — only the new
                // mid-shrink-release case changes, which is exactly the fix's intent).
                let wasResizing = isResizing
                isResizing = false
                resizeBaseFraction = nil   // always clear — the next gesture starts fresh
                // `shrinkFloorCrossing` is scoped to a single continuous gesture — always reset it
                // here (via every exit path below, `defer` runs regardless of which `return` /
                // fallthrough is taken) so the next gesture starts clean. Read below (in the
                // guard-passed path) before this fires.
                defer {
                    shrinkFloorCrossing = nil
                }
                // Released while the gesture's LAST `onChanged` sample was still RESIZE (growing
                // past the ceiling, OR — since rb-ios-sheetkit-resize-shrink-after-grow-fix — still
                // shrinking toward the floor after a cross-gesture regrowth): the current height is
                // KEPT as-is (no snap-back, no dismiss check) — matches the
                // pre-rb-ios-sheetkit-resize-dismiss-unify behavior for the growing case, extended
                // to the new shrinking case by the same rule ("last sample was RESIZE → keep the
                // height"). `dragOffset` is guaranteed 0 here (the resize branch above always
                // resets it), so there's nothing to animate even if this guard weren't here.
                guard !wasResizing else { return }
                let localTranslation = Self.localDismissTranslation(
                    rawTranslationHeight: value.translation.height,
                    shrinkFloorCrossing: shrinkFloorCrossing)
                switch Self.dragReleaseOutcome(
                    translationHeight: localTranslation,
                    offscreenDistance: UIScreen.main.bounds.height
                ) {
                case .dismiss(let targetOffset):
                    // Slide the card the rest of the way off-screen along the SAME motion the
                    // user's finger was already driving (no independent transition kicking in
                    // mid-gesture), THEN — only once that finishes — unmount the container. This
                    // is what prevents the release-time jitter (rb-ios-sheet-drag-dismiss-jitter).
                    withAnimation(sheetSlide) {
                        dragOffset = targetOffset
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + sheetSlideDuration) {
                        onDismiss()
                    }
                case .bounceBack:
                    // Released under the 100pt threshold while net-downward (or exactly at 0):
                    // spring the peek back to 0 (sheet rests at its current height).
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        dragOffset = 0
                    }
                }
            }
    }
}
