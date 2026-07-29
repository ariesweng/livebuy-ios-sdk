import SwiftUI
import UIKit
import LivebuySDK
import LivebuyUI

// MARK: - WinClaimModalView — family-2 feed-win surface 3 (四階段領獎 modal，含 email 輸入)
//
// Spec: `reference-ui-rendering/spec.md`
//   § "LivebuyReferenceUI 渲染四階段領獎 modal（含 email 輸入），綁 DefaultWinClaim
//      提交、送出中與結果狀態"
// Design: `design/templates/minimal/moments.jsx` `LBWinSheet`（2026-07-24 v2 四階段重寫）
//         + `design/contract/claude-design-sync.md` **R13**（含兩條刻意分歧裁示）。
//
// ─────────────────────────────────────────────────────────────────────────────
// EMAIL-LESS 已退役（rb-ios-win-claim-email-flow）
// ─────────────────────────────────────────────────────────────────────────────
// 這張 modal 先前是 EMAIL-LESS 的「通知型」單頁 sheet：CTA 直接打
// `DefaultWinClaim.submit(winner:)` → core `requestAwardClaim(winner, nil)`。
// 但 core 預設領獎路徑 `email` **必填** —— host 未攔截 `awardClaimIntent` 又沒有 email
// 時，core fail-fast 發 `awardClaimResult(.failed)`、**連 `POST /sdk/video/claim` 都沒
// 送出**。訪客（僅 `guest_id`）全程可參加抽獎並中獎，卻沒有任何地方能填 email，於是
// turnkey host 必然回報「中獎領取失敗」。本檔即是把 email 欄位真正畫出來的那一層。
//
// 四階段流程（對齊設計稿 `LBWinSheet` 的 `stage` 機）：
//
//   claim         恭喜中獎 + award.name + ✉ email 欄 +「確認領獎」+「關閉視窗」+ footer
//     ├「確認領獎」→ confirmSubmit alert →（確定）→ submitting → done / fail
//     └「關閉視窗」/ ✕ → confirmClose alert →（確定）→ 純 dismiss
//   done          discount → 折扣碼 + 複製 + 寄送信箱；product → 待結帳商品卡
//   fail          領獎失敗 + 通用錯誤提示列 +「重新領獎」（回 confirmSubmit）+「關閉視窗」
//
// ─────────────────────────────────────────────────────────────────────────────
// 單一真相（stage 怎麼來的）
// ─────────────────────────────────────────────────────────────────────────────
// 設計稿用「一個 `stage` state」跑完全程。原生若照抄，`submitting` / `done` / `fail`
// 會變成本層自己維護的**第二份真相**，與 view-model 的 `submitInFlight` / `resultState`
// 必然分歧。因此這裡拆成：
//
//   • 本層 `@State` 只存**使用者互動意圖**（`LocalPhase`）與 email 輸入字串。
//   • 實際 stage 由**純函式** `stage(phase:submitInFlight:result:)` 推導，
//     `submitting` 綁 view-model `submitInFlight`、`done` / `fail` 綁 `resultState`。
//
// ⚠️ Known hang（view-model 已載明）：native host 攔截 `awardClaimIntent` 時 core 不發
// `awardClaimResult`，`submitInFlight` 會一直為真。收尾責任在 host（呼叫
// `dismissClaim()`）。本層 **MUST NOT** 自加提交逾時或自行猜測結果 —— 那就是第二份真相。
//
// ─────────────────────────────────────────────────────────────────────────────
// SUB-VIEW INPUT PATTERN（與 family-2 其餘 surface 相同）
// ─────────────────────────────────────────────────────────────────────────────
//   1. `theme: ReferenceUITheme`  — FIRST positional argument。
//   2. 綁定的 SNAPSHOT 值          — `winner` / `presentation` / `resultState` /
//      `submitInFlight`，由 `FeedWinModel` **by value** 傳入（不傳 model、不傳 template）。
//   3. action closures（尾段、各 `= nil`）— `onSubmit: ((String) -> Void)?`（帶使用者
//      輸入的 email，funnel 到 `DefaultWinClaim.submit(winner:email:)`）、
//      `onDismiss: (() -> Void)?`（關閉，funnel 到 `dismissClaim()` + 清容器綁定）。
//
// 本 sub-view 只讀傳入值，從不回抓 `FeedWinModel` / `DefaultPlayerTemplate`（單向資料流），
// 且所有 action 為 nil 時仍能正確渲染（demo / snapshot 可 action-free 建構）。
//
// iOS-14-safe SwiftUI only（`ZStack` / `VStack` / `HStack` / `Text` / `Button` /
// `TextField` / `RoundedRectangle` / `Circle` / `LinearGradient` / `GeometryReader` /
// `PreferenceKey` / `onReceive` 皆 iOS 13+）。
// 無 `ScrollView` / `LazyVStack`（置中 modal 禁用 scrolling 容器，且 reference-ui 的
// snapshot 路徑 `ImageRenderer` 會把它們畫成空白）。無 `.task` / `AsyncImage` /
// `NavigationStack` / `.foregroundStyle` / `.tint`。

/// family-2 的四階段領獎 modal（一次一個 `LBWinner`）。畫恭喜中獎 + 獎品名 + email 輸入欄，
/// 經確認 alert 後以 `onSubmit(email)` 提交，並依 view-model 的 `submitInFlight` /
/// `resultState` 呈現送出中 / 領獎完成 / 領獎失敗。
public struct WinClaimModalView: View {

    // MARK: - Stage 機（型別）

    /// 對外可辨識的呈現階段（對齊設計稿 `LBWinSheet` 的 `stage`）。
    public enum Stage: Equatable {
        /// 恭喜中獎 + email 輸入（可提交）。
        case claim
        /// 「確認領獎」alert（確認 email 正確）。
        case confirmSubmit
        /// 「關閉視窗」alert（強勸阻文案，行為僅 dismiss —— 見 `dismissConfirmed`）。
        case confirmClose
        /// 送出中（scrim + spinner），由 view-model `submitInFlight` 驅動。
        case submitting
        /// 領獎完成，由 view-model `resultState` 的成功態驅動。
        case done
        /// 領獎失敗，由 view-model `resultState.failureRetryable` 驅動。
        case fail
    }

    /// 本層 `@State` 持有的**使用者互動意圖**（不是 stage 本身）。
    ///
    /// `.editing` 這一格是為了忠實還原設計稿「fail →「重新領獎」→ 確認 alert →（取消）→
    /// 回到可改 email 的 claim 卡」路徑：alert 取消時一律設 `.editing`，讓殘留的
    /// `resultState`（仍是 `.failureRetryable`）不要把畫面拉回 fail 卡。真正送出時設回
    /// `.idle`，讓新一輪結果能重新驅動 done / fail。
    enum LocalPhase: Equatable {
        /// 無 alert、也未明示要回填單 —— stage 完全由 view-model 的結果決定。
        case idle
        /// 使用者明示要（回到）填單畫面，覆蓋殘留的舊結果。
        case editing
        /// 正顯示「確認領獎」alert。
        case confirmSubmit
        /// 正顯示「關閉視窗」alert。
        case confirmClose
    }

    // MARK: - 綁定的 snapshot 值（by value）

    /// 解析後的 reference-ui theme（FIRST positional argument, always）。
    public let theme: ReferenceUITheme

    /// 這張 modal 領獎的對象（`unclaimedWinners` 最早一筆）。唯讀。
    public let winner: LBWinner
    /// award 造型 / glyph 分流（`DefaultWinClaim.awardPresentation(for:)`）。唯讀。
    ///
    /// ⚠️ 它 **不再**決定主 CTA 文案（v2 起 CTA 統一「確認領獎」），也**不**決定是否要
    /// 收 email（兩種 award type 都要同一個 email 欄位）；只影響 `confirmSubmit` 的提示
    /// 文案與 `done` 階段的內容分流。
    public let presentation: LBAwardPresentation
    /// 最新的領獎結果回饋（`DefaultWinClaim.resultState`）；結果未到前為 nil。
    /// 驅動 `done` / `fail` 階段。唯讀。
    public let resultState: LBAwardClaimResultState?
    /// 送出中旗標（`DefaultWinClaim.submitInFlight`）。驅動 `submitting` 階段。
    /// **本層 MUST NOT 自造第二份 in-flight 真相** —— 只讀這一個。
    public let submitInFlight: Bool

    /// 領獎提交（帶使用者輸入的 email）。容器轉發
    /// `model.submitClaim(for: winner, email:)` → `DefaultWinClaim.submit(winner:email:)`。
    /// demo / snapshot 為 nil —— 本 view 在所有 action 為 nil 時仍正確渲染。
    private let onSubmit: ((String) -> Void)?
    /// 關閉（✕ /「關閉視窗」確認後 / `done` 階段點 scrim）。容器轉發
    /// `model.dismissClaim()` 後清掉自己的呈現綁定。demo / snapshot 為 nil。
    private let onDismiss: (() -> Void)?

    /// email 欄位是否為**真的可輸入** `TextField`（runtime 預設 `true`），或是靜態唯讀
    /// 佔位（`false`）。SwiftUI 的 `ImageRenderer`（reference-ui snapshot 路徑）**無法**
    /// 渲染 live `TextField`（會畫成黃色「unsupported control」方塊），故 snapshot /
    /// preview 走 `false`。**沿用本層既有慣例**（`GuestNameEditModalView.editable`），
    /// 不發明第二種做法。
    private let isEditable: Bool

    public init(
        theme: ReferenceUITheme,
        winner: LBWinner,
        presentation: LBAwardPresentation,
        resultState: LBAwardClaimResultState?,
        submitInFlight: Bool = false,
        onSubmit: ((String) -> Void)? = nil,
        onDismiss: (() -> Void)? = nil,
        editable: Bool = true
    ) {
        self.theme = theme
        self.winner = winner
        self.presentation = presentation
        self.resultState = resultState
        self.submitInFlight = submitInFlight
        self.onSubmit = onSubmit
        self.onDismiss = onDismiss
        self.isEditable = editable
    }

    /// EMAIL-LESS 時代的建構子 —— **DEPRECATED**，只為源碼相容保留。
    ///
    /// 舊 `onClaim`（無參數）無法帶 email，而 core 預設領獎路徑 email 必填；以此入口建構
    /// 的 modal 仍會畫出 email 欄位，只是提交時把使用者輸入的 email **丟掉**後呼叫
    /// `onClaim()` —— 若 host 的 `onClaim` 走的是 `submit(winner:)`，領獎在未被攔截時
    /// 依然必然失敗。請改用帶 `onSubmit:` 的建構子。
    ///
    /// （`onClaim` 刻意設為必填無預設值，故與新建構子不會產生多載歧義。）
    @available(*, deprecated, message: "EMAIL-LESS 領獎已退役（缺 email 時 core fail-fast、連 API 都不送）。改用帶 onSubmit: ((String) -> Void)? 的建構子，把使用者輸入的 email 交給 DefaultWinClaim.submit(winner:email:)。")
    public init(
        theme: ReferenceUITheme,
        winner: LBWinner,
        presentation: LBAwardPresentation,
        resultState: LBAwardClaimResultState?,
        onClaim: @escaping () -> Void,
        onDismiss: (() -> Void)? = nil
    ) {
        // 內部只保留 ONE submit channel：舊 closure 包成忽略 email 的新 closure。
        self.init(
            theme: theme,
            winner: winner,
            presentation: presentation,
            resultState: resultState,
            submitInFlight: false,
            onSubmit: { _ in onClaim() },
            onDismiss: onDismiss)
    }

    // MARK: - 本層 UI local state（不是 view-model）

    /// 使用者正在輸入的 email。**UI local state** —— view-model 不保存正在打的字
    /// （避免 keystroke 汙染 view-model）。驗證則一律呼叫 view-model 的純函式，見
    /// `isEmailValid`。
    @State private var email: String = ""
    /// 使用者互動意圖（見 `LocalPhase`）。
    @State private var phase: LocalPhase = .idle
    /// 量測到的底卡高度（`CardHeightKey`），只用於算鍵盤位移。
    @State private var cardHeight: CGFloat = 0
    /// 折扣碼「複製」後的短暫回饋。
    @State private var copied: Bool = false
    /// 送出中 spinner 的旋轉角（`onAppear` 後動到 360；360° 與 0° 視覺等價，故
    /// `ImageRenderer` 不論有沒有跑 `onAppear` 都畫出同一張圖 → baseline 決定式）。
    @State private var spin: Double = 0
    /// 目前鍵盤覆蓋的高度（收起 = 0），由下方兩個 `onReceive` 維護。只用於算卡片位移。
    @State private var keyboardHeight: CGFloat = 0

    // MARK: - 純推導（stage / 驗證 / 內容）

    /// 目前 stage —— 純函式推導，view-model 真相優先。
    var currentStage: Stage {
        Self.stage(phase: phase, submitInFlight: submitInFlight, result: resultState)
    }

    /// stage 推導（純函式）。優先序：
    /// 1. view-model 說在送出中 → `.submitting`（畫面不得比 view-model 樂觀）。
    /// 2. 正在顯示 alert → 該 alert 階段（alert 疊在底卡之上）。
    /// 3. 使用者明示回填單 → `.claim`（覆蓋殘留舊結果）。
    /// 4. 其餘一律由 view-model 的 `resultState` 決定。
    static func stage(phase: LocalPhase,
                      submitInFlight: Bool,
                      result: LBAwardClaimResultState?) -> Stage {
        if submitInFlight { return .submitting }
        switch phase {
        case .confirmSubmit: return .confirmSubmit
        case .confirmClose:  return .confirmClose
        case .editing:       return .claim
        case .idle:          return resultStage(result)
        }
    }

    /// 由 view-model 結果狀態映射出的終態 stage（純函式）。
    static func resultStage(_ result: LBAwardClaimResultState?) -> Stage {
        switch result {
        case .successProduct, .successDiscount: return .done
        case .failureRetryable:                 return .fail
        case .none:                             return .claim
        }
    }

    /// 主 CTA 是否可按 —— **一律**呼叫 view-model 的純函式，本層不自寫第二份規則，
    /// 這樣「畫面說可以送」與「view-model 願意送」永遠同一條判定。
    var isEmailValid: Bool { DefaultWinClaim.isValidEmail(email) }

    /// 是否為折扣型 award（影響 `confirmSubmit` 提示與 `done` 內容分流）。
    private var isDiscount: Bool { presentation == .discount }

    /// 要顯示的折扣碼：優先用領獎結果帶回的 `awardCode`（權威），退回 award 自帶的 code。
    private var discountCode: String {
        if case let .successDiscount(awardCode) = resultState, !awardCode.isEmpty { return awardCode }
        return winner.award.code
    }

    /// 獎品名（空值退回本層既有 fallback 常數）。
    private var awardName: String {
        winner.award.name.isEmpty ? Self.awardNameFallback : winner.award.name
    }

    /// alert（confirmSubmit / confirmClose）是否正疊在底卡上。
    private var isAlert: Bool {
        currentStage == .confirmSubmit || currentStage == .confirmClose
    }
    /// 底卡是否應被壓暗且不可互動（alert 或送出中）。
    private var isBusy: Bool { isAlert || currentStage == .submitting }

    // MARK: - Body

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                scrim
                baseCard(containerWidth: geo.size.width)
                    .offset(y: Self.keyboardShift(
                        keyboardHeight: keyboardHeight,
                        containerHeight: geo.size.height,
                        cardHeight: cardHeight))
                if isAlert {
                    alertLayer(containerWidth: geo.size.width)
                }
                if currentStage == .submitting {
                    submittingLayer
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            // 鍵盤觀測（iOS 13+ `onReceive`）。沒有任何 SwiftUI 自動 avoidance 可用：
            // 本 modal 由 `PlayerOverlayRootView` 以 `ignoresSafeAreaCompat()` 全幅疊放，
            // 自動 avoidance 會被抵銷；而置中 modal 的 spec 明文禁用 scrolling 容器
            // （`ImageRenderer` 也畫不出 `ScrollView`）。因此位移自己算，才能同時保證
            // 「不被鍵盤遮」與「卡頂不出界」，且判定是可單元測的純函式。
            .onReceive(NotificationCenter.default.publisher(
                for: UIResponder.keyboardWillChangeFrameNotification)) { note in
                keyboardHeight = Self.coveredKeyboardHeight(
                    keyboardFrame: (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey]
                        as? NSValue)?.cgRectValue,
                    screenMaxY: UIScreen.main.bounds.maxY)
            }
            .onReceive(NotificationCenter.default.publisher(
                for: UIResponder.keyboardWillHideNotification)) { _ in
                keyboardHeight = 0
            }
        }
    }

    // MARK: - 外層 scrim（依 stage 決定可否點擊關閉）
    //
    // 設計稿：`onClick={stage === 'done' ? onClose : undefined}` —— 只有「領獎完成」時
    // 點外層 scrim 才關閉。`claim` / `fail` 時 MUST NOT 直接關閉，否則就繞過了刻意的
    // 關閉摩擦（見 `dismissConfirmed`）。

    private var scrim: some View {
        Self.scrimColor
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { if currentStage == .done { onDismiss?() } }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(LBAccessibilityID.winClaimScrim)
    }

    // MARK: - 底卡（claim / done / fail），寬 84% 上限 320

    @ViewBuilder
    private func baseCard(containerWidth: CGFloat) -> some View {
        let width = Self.cardWidth(containerWidth: containerWidth)
        Group {
            switch currentStage {
            case .done: doneCard
            case .fail: failCard
            default:    claimCard
            }
        }
        .frame(width: width)
        .background(
            GeometryReader { g in
                Color.clear.preference(key: CardHeightKey.self, value: g.size.height)
            })
        .onPreferenceChange(CardHeightKey.self) { cardHeight = $0 }
        // 底卡在 alert / 送出中時壓暗且不可互動（設計稿 `opacity: 0.55`）。
        .opacity(isBusy ? 0.55 : 1)
        .allowsHitTesting(!isBusy)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(LBAccessibilityID.winClaimSheet)
    }

    /// 卡寬 —— 設計稿 `width: '84%', maxWidth: 320`。
    static func cardWidth(containerWidth: CGFloat) -> CGFloat {
        min(containerWidth * 0.84, 320)
    }

    // MARK: - ① claim 卡（恭喜中獎 + award.name + email 欄 + CTA + footer）

    private var claimCard: some View {
        cardShell(topPadding: 46) {
            VStack(spacing: 14) {
                congratsBlock
                emailField
                claimActions
                footer
            }
        } badge: {
            AnyView(giftBadge)
        } close: {
            // ✕ 只在 claim 卡出現（設計稿 done / fail 卡皆無 ✕）。
            AnyView(closeButton)
        }
    }

    /// 恭喜中獎標題 + **副標＝`award.name`**（v2 起不再是固定文案）。
    private var congratsBlock: some View {
        VStack(spacing: 6) {
            Text(Self.congratsTitle)
                .font(.system(size: 22 * theme.fontScale, weight: .heavy))
                .foregroundColor(theme.text)
            Text(awardName)
                .font(.system(size: 14.5 * theme.fontScale, weight: .medium))
                .foregroundColor(Self.textDim)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    /// ✉ email 輸入列（mail glyph + 欄位），sunken 膠囊 + hairline 邊框。
    private var emailField: some View {
        HStack(spacing: 9) {
            Image(systemName: "envelope")
                .font(.system(size: 18 * theme.fontScale))
                .foregroundColor(Self.textDim)
            if isEditable {
                liveEmailTextField
            } else {
                staticEmailDisplay
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Self.bgSunken))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Self.stroke, lineWidth: 1))
    }

    /// runtime 的真實可輸入欄位。
    private var liveEmailTextField: some View {
        TextField(Self.emailPlaceholder, text: $email)
            .font(.system(size: 14.5 * theme.fontScale))
            .foregroundColor(theme.text)
            .keyboardType(.emailAddress)
            .textContentType(.emailAddress)
            .autocapitalization(.none)
            .disableAutocorrection(true)
            .accessibilityIdentifier(LBAccessibilityID.winClaimEmailField)
    }

    /// snapshot / preview 的靜態渲染（`ImageRenderer` 畫不出 live `TextField`）。
    private var staticEmailDisplay: some View {
        Text(email.isEmpty ? Self.emailPlaceholder : email)
            .font(.system(size: 14.5 * theme.fontScale))
            .foregroundColor(email.isEmpty ? Self.textFaint : theme.text)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier(LBAccessibilityID.winClaimEmailField)
    }

    /// 主 CTA「確認領獎」（email 不合格 → disabled 灰底）+「關閉視窗」。
    private var claimActions: some View {
        VStack(spacing: 4) {
            Button(action: { if isEmailValid { phase = .confirmSubmit } }) {
                Text(Self.ctaSubmit)
                    .font(.system(size: 15.5 * theme.fontScale, weight: .heavy))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isEmailValid ? theme.accent : Self.shade(theme.accent, 0.35)))
                    .opacity(isEmailValid ? 1 : 0.6)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!isEmailValid)
            .accessibilityIdentifier(LBAccessibilityID.winClaimPrimary)

            Button(action: { phase = .confirmClose }) {
                Text(Self.closeLabel)
                    .font(.system(size: 14 * theme.fontScale, weight: .bold))
                    .foregroundColor(Self.textDim)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityIdentifier(LBAccessibilityID.winClaimSecondary)
        }
    }

    // MARK: - ② confirmSubmit / confirmClose alert 疊層

    private func alertLayer(containerWidth: CGFloat) -> some View {
        ZStack {
            // alert 自己的 scrim：只收起 alert（回可編輯的 claim 版面），不關整個 modal。
            Self.alertScrimColor
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { phase = .editing }

            VStack(alignment: .leading, spacing: 14) {
                Text(alertTitle)
                    .font(.system(size: 20 * theme.fontScale, weight: .heavy))
                    .foregroundColor(theme.text)

                VStack(alignment: .leading, spacing: 12) {
                    Text(alertBody)
                        .font(.system(size: 14 * theme.fontScale))
                        .foregroundColor(Self.textDim)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(alertNote)
                        .font(.system(size: 14 * theme.fontScale, weight: .semibold))
                        .foregroundColor(theme.accent)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 12) {
                    Button(action: { phase = .editing }) {
                        Text(Self.alertCancelLabel)
                            .font(.system(size: 15 * theme.fontScale, weight: .heavy))
                            .foregroundColor(theme.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(theme.accent, lineWidth: 1.5))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityIdentifier(LBAccessibilityID.winClaimAlertCancel)

                    Button(action: { alertConfirmed() }) {
                        Text(Self.alertConfirmLabel)
                            .font(.system(size: 15 * theme.fontScale, weight: .heavy))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(theme.accent))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityIdentifier(LBAccessibilityID.winClaimAlertConfirm)
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 22)
            .padding(.top, 24)
            .padding(.bottom, 20)
            .frame(width: Self.cardWidth(containerWidth: containerWidth))
            .background(theme.background)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .shadow(color: Color.black.opacity(0.4), radius: 32, x: 0, y: 24)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(LBAccessibilityID.winClaimAlert)
        }
    }

    private var alertTitle: String {
        currentStage == .confirmClose ? Self.closeAlertTitle : Self.submitAlertTitle
    }
    private var alertBody: String {
        currentStage == .confirmClose
            ? String(format: Self.closeAlertBodyFormat, awardName)
            : String(format: Self.submitAlertBodyFormat, email.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    private var alertNote: String {
        if currentStage == .confirmClose { return Self.closeAlertNote }
        return isDiscount ? Self.submitAlertNoteDiscount : Self.submitAlertNoteProduct
    }

    /// alert 的「確定」。
    private func alertConfirmed() {
        if currentStage == .confirmClose {
            dismissConfirmed()
        } else {
            // 回到 `.idle` 後才提交：這樣新一輪的 `submitInFlight` / `resultState`
            // 能直接驅動 submitting → done / fail，不被殘留的互動意圖擋住。
            phase = .idle
            onSubmit?(email)
        }
    }

    /// 🔴 **關閉領獎畫面 ＝ 純 dismiss。反直覺，改動前務必先讀完這段。**
    ///
    /// `confirmClose` 的文案照抄設計稿的強勸阻措辭（「您將放棄【獎品】的中獎資格，此動作
    /// 無法復原」／「※確認送出後，將視同為放棄領獎。」），但**行為 MUST 僅為呈現層
    /// dismiss**：
    ///   • MUST NOT 從 `unclaimedWinners` 移除該 winner
    ///   • MUST NOT 呼叫任何 API
    ///   • MUST NOT 遞減未領數量徽章（中獎入口紅點保留、可再次開啟領取）
    ///
    /// 強文案是**刻意的 UX 摩擦**（降低隨手關閉機率，但不真的剝奪資格），權威為
    /// `design/contract/claude-design-sync.md` **R13「刻意分歧（1/2）」**（使用者
    /// 2026-07-24 明示）。同一元件 `fail` 卡的「你的中獎資格仍保留」是正確描述；兩者
    /// 措辭衝突為**已知且刻意**，請勿「順手改一致」，也勿讓行為跟隨文案。
    ///
    /// 實作上只呼叫 `onDismiss` —— 容器接的是 `DefaultWinClaim.dismissClaim()`（只清
    /// `resultState` + `submitInFlight`）+ 清掉自己的呈現綁定。
    private func dismissConfirmed() {
        onDismiss?()
    }

    // MARK: - ③ submitting 疊層（scrim + 44pt spinner +「送出中…」）

    private var submittingLayer: some View {
        ZStack {
            Self.alertScrimColor
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 14) {
                // 靜態弧線 + 旋轉。這是使用者主動觸發、只存活於一次網路請求期間的
                // 進度指示，非「常駐裝飾動畫」，故不掛 power-profile 動畫節流 gate。
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .foregroundColor(theme.accent)
                    .background(
                        Circle().stroke(Self.stroke, lineWidth: 3))
                    .frame(width: 44, height: 44)
                    .rotationEffect(.degrees(spin))
                    .onAppear {
                        withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                            spin = 360
                        }
                    }
                Text(Self.submittingLabel)
                    .font(.system(size: 15 * theme.fontScale, weight: .bold))
                    .foregroundColor(theme.text)
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 26)
            .background(theme.background)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .shadow(color: Color.black.opacity(0.4), radius: 32, x: 0, y: 24)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(LBAccessibilityID.winClaimSubmitting)
        }
    }

    // MARK: - ④ done 卡（領獎完成）

    private var doneCard: some View {
        cardShell(topPadding: 48) {
            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    Text(Self.doneTitle)
                        .font(.system(size: 22 * theme.fontScale, weight: .heavy))
                        .foregroundColor(theme.text)
                    Text(isDiscount ? Self.doneSublineDiscount : Self.doneSublineProduct)
                        .font(.system(size: 14 * theme.fontScale, weight: .medium))
                        .foregroundColor(Self.textDim)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                    if isDiscount {
                        Text(email.trimmingCharacters(in: .whitespacesAndNewlines))
                            .font(.system(size: 16 * theme.fontScale, weight: .bold))
                            .foregroundColor(theme.accent)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)

                if isDiscount { discountCodeRow } else { pendingProductRow }
                footer
            }
        } badge: {
            AnyView(giftBadge)
        } close: {
            AnyView(EmptyView())
        }
    }

    /// 折扣碼 + 複製鈕。
    private var discountCodeRow: some View {
        HStack(spacing: 10) {
            Text(discountCode)
                .font(.system(size: 16 * theme.fontScale, weight: .bold, design: .monospaced))
                .foregroundColor(theme.text)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: { copyCode() }) {
                Text(copied ? Self.copiedLabel : Self.copyLabel)
                    .font(.system(size: 14.5 * theme.fontScale, weight: .heavy))
                    .foregroundColor(theme.accent)
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityIdentifier(LBAccessibilityID.winClaimCopyCode)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Self.bgSunken))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Self.stroke, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(LBAccessibilityID.winClaimResultBanner)
    }

    /// 待結帳商品卡（product 類獎品）。
    private var pendingProductRow: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(theme.accent.opacity(0.10))
                Image(systemName: "gift")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(theme.accent)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(Self.pendingItemCaption)
                    .font(.system(size: 11 * theme.fontScale, weight: .semibold))
                    .foregroundColor(Self.textDim)
                Text(awardName)
                    .font(.system(size: 14 * theme.fontScale, weight: .bold))
                    .foregroundColor(theme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Self.bgSunken))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Self.stroke, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(LBAccessibilityID.winClaimResultBanner)
    }

    private func copyCode() {
        UIPasteboard.general.string = discountCode
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.9) { copied = false }
    }

    // MARK: - ⑤ fail 卡（領獎失敗）

    private var failCard: some View {
        cardShell(topPadding: 48) {
            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    Text(Self.failTitle)
                        .font(.system(size: 22 * theme.fontScale, weight: .heavy))
                        .foregroundColor(theme.text)
                    Text(Self.failSubline)
                        .font(.system(size: 14 * theme.fontScale, weight: .medium))
                        .foregroundColor(Self.textDim)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .center)

                failNoticeRow
                failActions
                footer
            }
        } badge: {
            AnyView(failBadge)
        } close: {
            AnyView(EmptyView())
        }
    }

    /// 🔴 **錯誤提示列：版面保留、文案通用、MUST NOT 顯示捏造的錯誤代碼。**
    ///
    /// 設計稿這一列寫的是「錯誤代碼 `CLAIM_TIMEOUT` · 若持續發生請聯繫客服」，但
    /// `CLAIM_TIMEOUT` 與稿內 `jasper@livebuy.tv` / `1L9zOdX` 同性質 ＝ **demo 佔位值**。
    /// 後端**刻意不區分**領獎失敗原因（已領過 / 活動結束 / 票券無效 / email 被拒，全部
    /// `500 api.fail`，anti-enumeration），SDK 拿不到任何有意義的錯誤碼，硬填就是騙人。
    /// 因此版面照留（danger 底色 + icon），文案固定為通用值。權威：
    /// `design/contract/claude-design-sync.md` **R13「刻意分歧（2/2）」**。
    /// 待後端真的細分錯誤碼（core `LBAwardClaimStatus.unknown(Int)` 本就是 forward-compat
    /// 設計）再回來接，屆時才可顯示真實代碼。
    private var failNoticeRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Self.dangerColor)
            Text(Self.failNotice)
                .font(.system(size: 12.5 * theme.fontScale, weight: .semibold))
                .foregroundColor(Self.dangerColor)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Self.dangerColor.opacity(0.10)))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Self.dangerColor.opacity(0.30), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(LBAccessibilityID.winClaimFailNotice)
    }

    /// 「重新領獎」（回 confirmSubmit，**沿用原本輸入的 email**）+「關閉視窗」（直接關）。
    private var failActions: some View {
        VStack(spacing: 4) {
            Button(action: { phase = .confirmSubmit }) {
                Text(Self.retryLabel)
                    .font(.system(size: 15.5 * theme.fontScale, weight: .heavy))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(theme.accent))
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityIdentifier(LBAccessibilityID.winClaimPrimary)

            // fail 卡的「關閉視窗」直接關（設計稿不再追問 confirmClose）——仍是純 dismiss。
            Button(action: { dismissConfirmed() }) {
                Text(Self.closeLabel)
                    .font(.system(size: 14 * theme.fontScale, weight: .bold))
                    .foregroundColor(Self.textDim)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityIdentifier(LBAccessibilityID.winClaimSecondary)
        }
    }

    // MARK: - 共用卡殼（圓角卡 + 浮在卡頂外的徽章 + 可選 ✕）
    //
    // 設計稿的徽章是 `position:absolute; top:-30`，浮在卡**外**且有 4px 卡背景色描邊，
    // 而卡本身 `clipShape`。若把徽章放進被 clip 的卡內會被切掉，故拆成兩層 ZStack：
    // 內層（被 clip）畫卡，外層（不 clip）疊徽章。`overlay(alignment:)` 是 iOS 15+，
    // 所以用 iOS 13+ 的 `ZStack(alignment:)`。

    private func cardShell<Content: View>(
        topPadding: CGFloat,
        @ViewBuilder content: () -> Content,
        badge: () -> AnyView,
        close: () -> AnyView
    ) -> some View {
        ZStack(alignment: .top) {
            ZStack(alignment: .topTrailing) {
                content()
                    .padding(.top, topPadding)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 22)
                    .frame(maxWidth: .infinity)
                close()
                    .padding(.top, 12)
                    .padding(.trailing, 12)
            }
            .background(theme.background)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: Color.black.opacity(0.35), radius: 32, x: 0, y: 24)

            badge()
                .offset(y: -30)
        }
    }

    /// 右上角 ✕（設計稿為透明底 30×30 tap target）。
    private var closeButton: some View {
        Button(action: { phase = .confirmClose }) {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Self.textDim)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier(LBAccessibilityID.winClaimClose)
    }

    // MARK: - 徽章（60pt，浮出卡頂外，4pt 卡背景色描邊）

    /// 禮物徽章 —— glyph **恆為 gift**，MUST NOT 依 `awardPresentation` 路由
    /// （對齊設計稿 `LBWinSheet` 的 `giftSvg` 與 Android / Flutter）。confetti 疊在它後面。
    private var giftBadge: some View {
        ZStack {
            confettiLayer
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [theme.accent, Self.shade(theme.accent)]),
                    startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "gift.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(.white)
            }
            .frame(width: 60, height: 60)
            .clipShape(Circle())
            .overlay(Circle().stroke(theme.background, lineWidth: 4))
            .shadow(color: theme.accent.opacity(0.33), radius: 11, x: 0, y: 8)
        }
    }

    /// 失敗徽章（danger 實心，無 confetti）。
    private var failBadge: some View {
        ZStack {
            Circle().fill(Self.dangerColor)
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 30, weight: .semibold))
                .foregroundColor(.white)
        }
        .frame(width: 60, height: 60)
        .overlay(Circle().stroke(theme.background, lineWidth: 4))
        .shadow(color: Self.dangerColor.opacity(0.33), radius: 11, x: 0, y: 8)
    }

    // MARK: - Confetti（LBWinSheet — 20 顆靜態扇形方塊，鋪在徽章後方）
    //
    // 設計稿 `CONFETTI` 的決定式移植：20 顆彩色方塊在 ~160° 弧上扇開、錨在徽章中心、
    // 略微上偏（ty − 16）。靜態（無動畫）以保 baseline 決定式。v2 由 22 顆 → 20 顆，
    // 扇形參數（`i / 19`、`dist = 34 + (i % 4) * 14`、`ty − 16`）同步更新。

    private var confettiLayer: some View {
        ZStack {
            ForEach(0..<Self.confettiCount, id: \.self) { i in
                let p = Self.confetti(i, accent: theme.accent)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(p.color)
                    .frame(width: p.size, height: p.size)
                    .rotationEffect(.degrees(p.rotation))
                    .offset(x: p.tx, y: p.ty)
            }
        }
    }

    // MARK: - Footer（使用條款 | 隱私政策 — 保留版面、不接連結）
    //
    // R13 決策 4：連結來源尚未決定，本 change **只保留版面、不接任何實際連結 / 導覽**。
    // 故意畫成純 `Text`（不是 `Button` / `Link`），避免給出「可點」的錯誤 affordance。

    private var footer: some View {
        HStack(spacing: 0) {
            Text(Self.footerTerms)
            Text(" | ").opacity(0.5)
            Text(Self.footerPrivacy)
        }
        .font(.system(size: 12.5 * theme.fontScale, weight: .medium))
        .foregroundColor(Self.textDim)
        .accessibilityIdentifier(LBAccessibilityID.winClaimFooter)
    }

    // MARK: - 鍵盤位移（純函式）

    /// 置中卡在鍵盤彈出時該套用的垂直位移（負值 = 上移）。
    ///
    /// - 鍵盤高度 0（含所有 snapshot / `ImageRenderer` 路徑）→ 回 `0`，baseline 決定式。
    /// - 卡底緣被鍵盤壓到時上移剛好露出（`bottomGap` 留白）。
    /// - 上移量以 `topGap` 夾住，**MUST NOT** 把卡頂（含浮出 30pt 的徽章）推出畫面上緣。
    ///
    /// 之所以量測卡高而非固定上移 `keyboardHeight / 2`：後者在 iPhone SE（667pt）+ 300pt
    /// 鍵盤 + ~400pt 卡高時會把卡頂推到 −16pt（切頭）。量測後才能同時保證「不被鍵盤遮」
    /// 與「頭不出界」。
    static func keyboardShift(keyboardHeight: CGFloat,
                              containerHeight: CGFloat,
                              cardHeight: CGFloat,
                              bottomGap: CGFloat = 12,
                              topGap: CGFloat = 42) -> CGFloat {
        guard keyboardHeight > 0, containerHeight > 0, cardHeight > 0 else { return 0 }
        let cardTop = (containerHeight - cardHeight) / 2
        let overlap = (cardTop + cardHeight) - (containerHeight - keyboardHeight - bottomGap)
        guard overlap > 0 else { return 0 }
        return -min(overlap, max(0, cardTop - topGap))
    }

    /// 鍵盤實際覆蓋螢幕的高度（純函式）。frame 缺漏或鍵盤已滑出畫面時為 0。
    static func coveredKeyboardHeight(keyboardFrame: CGRect?, screenMaxY: CGFloat) -> CGFloat {
        guard let frame = keyboardFrame else { return 0 }
        return max(0, screenMaxY - frame.minY)
    }

    // MARK: - 裝飾用 design token（literal minimal hex via Color(hex:)）
    //
    // accent / text / background 來自解析後的 theme；以下是自設計稿 `theme.surface.*`
    // （light mode，`design/brands/livebuy/tokens.jsx`）逐字搬來的固定裝飾色 —— 是
    // design-literal，非 theme-resolved。與 `VideoInfoPanelView` 等保持一致，讓這些
    // sheet 讀起來像同一家人。

    /// `theme.surface.textDim`（次要 / 說明文字）。
    static let textDim = Color(hex: "#6B6775") ?? Color.gray
    /// `theme.surface.textFaint`（空欄位 placeholder）。
    static let textFaint = Color(hex: "#B6B2BE") ?? Color.gray.opacity(0.5)
    /// `theme.surface.stroke`（hairline 邊框 / spinner 底環）。
    static let stroke = Color(hex: "#ECEAF0") ?? Color.gray.opacity(0.2)
    /// `theme.surface.bgSunken`（下沉卡 / 輸入欄底色 — light mode）。
    static let bgSunken = Color(hex: "#F4F4F6") ?? Color.gray.opacity(0.08)
    /// 成功色（`#0FC3B4` — LBWinSheet confetti 的青綠）。
    static let successColor = Color(hex: "#0FC3B4") ?? Color.green
    /// 設計稿 `DANGER`（失敗徽章 / 錯誤提示列）。
    static let dangerColor = Color(hex: "#EB6E5F") ?? Color.red
    /// modal scrim（`LBWinSheet` `rgba(0,0,0,0.6)`）。
    static let scrimColor = Color.black.opacity(0.6)
    /// alert / submitting 疊層自己的 scrim（`rgba(0,0,0,0.28)`）。
    static let alertScrimColor = Color.black.opacity(0.28)

    /// confetti 顆數（v2：22 → 20）。
    static let confettiCount = 20

    /// `color` 的明暗變體（對應設計稿 `lbShade`）。`amount < 0` 壓暗（徽章漸層尾端），
    /// `amount > 0` 提亮（disabled CTA 底色）。純函式、iOS-14-safe（UIColor HSB）。
    static func shade(_ color: Color, _ amount: Double = -0.3) -> Color {
        let ui = UIColor(color)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return color }
        let brightness = amount < 0
            ? max(0, Double(b) + amount)
            : min(1, Double(b) + amount * (1 - Double(b)))
        let saturation = amount < 0 ? Double(s) : Double(s) * (1 - amount)
        return Color(hue: Double(h), saturation: saturation,
                     brightness: brightness, opacity: Double(a))
    }

    /// 一顆 confetti 的決定式落點 —— 設計稿 `LBWinSheet` `CONFETTI` map 的直接移植
    /// （20 顆、~160° 扇形、錨在徽章中心、上偏 16pt）。純函式 / 決定式。
    /// 調色盤 index 3 是解析後的 `accent`，其餘為 design-literal。
    static func confetti(_ i: Int, accent: Color)
        -> (tx: CGFloat, ty: CGFloat, rotation: Double, color: Color, size: CGFloat) {
        let angDeg = -90.0 + ((Double(i) / 19.0) * 160.0 - 80.0)
        let ang = angDeg * .pi / 180.0
        let dist = 34.0 + Double(i % 4) * 14.0
        let cols: [Color] = [
            Color(hex: "#F03246") ?? .red,
            Color(hex: "#0FC3B4") ?? .green,
            Color(hex: "#F39C12") ?? .orange,
            accent,
            Color(hex: "#111111") ?? .black,
        ]
        return (
            tx: CGFloat(cos(ang) * dist),
            ty: CGFloat(sin(ang) * dist - 16.0),
            rotation: Double((i * 47) % 360),
            color: cols[i % 5],
            size: CGFloat(5 + (i % 3) * 2))
    }

    // MARK: - 固定文案（本層全層寫死中文常數，不使用 NSLocalizedString / LBStrings）

    static let congratsTitle = "恭喜中獎"
    static let awardNameFallback = "直播間限定獎品"
    static let emailPlaceholder = "電子郵件"
    static let ctaSubmit = "確認領獎"
    static let closeLabel = "關閉視窗"
    static let footerTerms = "使用條款"
    static let footerPrivacy = "隱私政策"

    static let submitAlertTitle = "確認領獎"
    static let submitAlertBodyFormat = "請確認 %@ 填寫正確，送出後將不可變更，確定要送出領獎資料嗎？"
    static let submitAlertNoteDiscount = "※結帳折扣碼將會寄送到您的信箱內。"
    static let submitAlertNoteProduct = "※獎品將自動加入為待結帳商品。"

    /// 🔴 強勸阻文案 —— **刻意**與實際「純 dismiss」行為不符，見 `dismissConfirmed`。
    static let closeAlertTitle = "關閉視窗"
    /// 🔴 同上：文案說「放棄資格、無法復原」，行為 MUST 僅 dismiss。R13 刻意分歧 1/2。
    static let closeAlertBodyFormat = "請注意：您將放棄【%@】的中獎資格，此動作無法復原，確定要關閉視窗嗎？"
    /// 🔴 同上。
    static let closeAlertNote = "※確認送出後，將視同為放棄領獎。"

    static let alertCancelLabel = "取消"
    static let alertConfirmLabel = "確定"

    static let submittingLabel = "送出中…"

    static let doneTitle = "領獎完成"
    static let doneSublineDiscount = "結帳折扣碼已寄送到以下電子郵件"
    static let doneSublineProduct = "獎品已加入待結帳商品，結帳前完成訂購"
    static let copyLabel = "複製"
    static let copiedLabel = "已複製"
    static let pendingItemCaption = "待結帳商品"

    static let failTitle = "領獎失敗"
    static let failSubline = "領獎過程發生錯誤，你的中獎資格仍保留，請稍後再試一次。"
    /// 🔴 通用文案 —— **MUST NOT** 換成 `CLAIM_TIMEOUT` 之類捏造的錯誤代碼，理由見
    /// `failNoticeRow` 的註解（R13 刻意分歧 2/2）。
    static let failNotice = "若持續發生，請聯繫客服"
    static let retryLabel = "重新領獎"
}

// MARK: - 卡高量測（供鍵盤位移用）

/// 底卡實際高度的 `PreferenceKey`（本層既有 pattern，見 `BottomSheetPresenter`）。
private struct CardHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Deterministic demo seed (previews + snapshot tests)
//
// 完整填好的 winner（product + discount），讓 preview / snapshot 測試能決定式地畫出
// 各 stage（無 live player）。award type 以與 template classifier 相同的規則推 demo
// `presentation`（`type == "discount"` → .discount，其餘 → .product）。

public extension WinClaimModalView {

    /// 決定式 demo product winner。
    static var demoProductWinner: LBWinner {
        LBWinner(
            id: "demo-win-product-001",
            eventId: 4201,
            title: "週年慶限定抽獎",
            award: LBAward(
                type: "product",
                code: "SKU-AURORA-LIP",
                name: "Aurora 霧面唇釉 #03 珊瑚橘"))
    }

    /// 決定式 demo discount winner（`done` 時顯示折扣碼）。
    static var demoDiscountWinner: LBWinner {
        LBWinner(
            id: "demo-win-discount-001",
            eventId: 4202,
            title: "整點快閃抽獎",
            award: LBAward(
                type: "discount",
                code: "LIVE5OFF",
                name: "全館 5 折優惠券"))
    }

    /// demo winner 的 award 分流 —— 與 template 公開 classifier
    /// （`DefaultWinClaim.awardPresentation`）**同一條規則**。純函式。
    static func demoPresentation(for winner: LBWinner) -> LBAwardPresentation {
        (winner.award.type == "discount") ? .discount : .product
    }

    /// 決定式 demo（product 中獎、claim 階段、尚無結果）。
    static func demo(theme: ReferenceUITheme) -> WinClaimModalView {
        WinClaimModalView(
            theme: theme,
            winner: demoProductWinner,
            presentation: demoPresentation(for: demoProductWinner),
            resultState: nil)
    }
}

// MARK: - Test / preview seed
//
// `phase` / `email` 是 `@State`，外部無法直接指定，所以各 stage 的 snapshot baseline
// 需要一個能種子化它們的入口。這裡以同檔案內存取 `_phase` / `_email` 的方式提供，
// 命名遵守 `docs/unit-test-discipline.md` §3 的 `*ForTesting` 規範。
// **Production code never calls this.**

extension WinClaimModalView {

    /// Test-only / preview seed：種子化互動相位與已輸入的 email，並固定走
    /// `editable: false` 的靜態欄位渲染（`ImageRenderer` 畫不出 live `TextField`）。
    /// Production code never calls this.
    static func makeSeededForTesting(
        theme: ReferenceUITheme,
        winner: LBWinner,
        presentation: LBAwardPresentation,
        resultState: LBAwardClaimResultState? = nil,
        submitInFlight: Bool = false,
        phase: LocalPhase = .idle,
        email: String = ""
    ) -> WinClaimModalView {
        var view = WinClaimModalView(
            theme: theme,
            winner: winner,
            presentation: presentation,
            resultState: resultState,
            submitInFlight: submitInFlight,
            editable: false)
        view._phase = State(initialValue: phase)
        view._email = State(initialValue: email)
        return view
    }
}

#if DEBUG
struct WinClaimModalView_Previews: PreviewProvider {
    static var previews: some View {
        let theme = ReferenceUIThemePalette.minimal
        let discount = WinClaimModalView.demoDiscountWinner
        let product = WinClaimModalView.demoProductWinner
        Group {
            WinClaimModalView.makeSeededForTesting(
                theme: theme, winner: product, presentation: .product)
                .previewDisplayName("claim · empty email")

            WinClaimModalView.makeSeededForTesting(
                theme: theme, winner: product, presentation: .product,
                email: "jasper@livebuy.tv")
                .previewDisplayName("claim · valid email")

            WinClaimModalView.makeSeededForTesting(
                theme: theme, winner: discount, presentation: .discount,
                phase: .confirmSubmit, email: "jasper@livebuy.tv")
                .previewDisplayName("confirmSubmit")

            WinClaimModalView.makeSeededForTesting(
                theme: theme, winner: product, presentation: .product,
                phase: .confirmClose, email: "jasper@livebuy.tv")
                .previewDisplayName("confirmClose")

            WinClaimModalView.makeSeededForTesting(
                theme: theme, winner: discount, presentation: .discount,
                submitInFlight: true, email: "jasper@livebuy.tv")
                .previewDisplayName("submitting")

            WinClaimModalView.makeSeededForTesting(
                theme: theme, winner: discount, presentation: .discount,
                resultState: .successDiscount(awardCode: "LIVE5OFF"),
                email: "jasper@livebuy.tv")
                .previewDisplayName("done · discount")

            WinClaimModalView.makeSeededForTesting(
                theme: theme, winner: product, presentation: .product,
                resultState: .successProduct, email: "jasper@livebuy.tv")
                .previewDisplayName("done · product")

            WinClaimModalView.makeSeededForTesting(
                theme: theme, winner: product, presentation: .product,
                resultState: .failureRetryable, email: "jasper@livebuy.tv")
                .previewDisplayName("fail")
        }
        .frame(width: 393, height: 560)
        .previewLayout(.sizeThatFits)
    }
}
#endif

// MARK: - Deprecated former name (source-compatibility shim)
//
// 這個 surface 是**置中 modal**（全幅 scrim + 置中卡，無 grab handle）——不是底部
// sheet。它由 `WinClaimSheetView` 更名為 `WinClaimModalView` 以符合本質與同類 modal
// （`GuestNameEditModalView` / `AuthGateModalView`）的命名。舊名以 deprecated
// typealias 保留一個 release cycle，避免直接建構此 surface 的 host 斷掉。
// 見 change `rename-winclaim-to-modal`。
@available(*, deprecated, renamed: "WinClaimModalView")
public typealias WinClaimSheetView = WinClaimModalView
