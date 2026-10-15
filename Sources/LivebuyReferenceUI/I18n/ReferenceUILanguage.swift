import Combine
import Foundation
import LivebuySDK

// MARK: - ReferenceUILanguage — reference-ui 目前語言（ObservableObject，驅動即時重繪）
//
// Change: `rb-ios-i18n-string-table`（design.md「即時重繪」一節）。
//
// 單一 process-wide 實例 `shared`：
//   • init 時讀一次 core 的 `Livebuy.currentLanguage`（core 不重播目前值），
//   • 並且只訂閱一次 `Livebuy.addLanguageListener`（closure 以 `[weak self]` 捕獲，
//     deinit 時取消訂閱）→ 不會 retain cycle，也不會重複訂閱。
//   • core 在 main thread 非同步通知新語言 → `code` 改變 → `objectWillChange` →
//     所有以 `@ObservedObject` 觀察它的 SwiftUI 畫面重算 body，`ReferenceUIStrings.text`
//     重新查表 → 畫面即時換成新語言。
//
// `codeOverrideForTesting`：test-only 釘選（例如所有既有 snapshot 測試釘在 zh-TW，不依賴模擬器
// 語言）；非 nil 時優先於 `code`。正式程式碼不設定它。

/// Where the reference-ui language comes from — injectable so the wiring is unit-testable
/// with a fake source (`internal-testability`: side effects via ctor injection).
struct ReferenceUILanguageSource {
    /// Current language code (read once at init).
    let current: () -> String
    /// Subscribe to language changes; returns an unsubscribe closure.
    let subscribe: (@escaping (String) -> Void) -> () -> Void

    /// Production source: core's public language API.
    static let core = ReferenceUILanguageSource(
        current: { Livebuy.currentLanguage },
        subscribe: { listener in Livebuy.addLanguageListener(listener) })
}

final class ReferenceUILanguage: ObservableObject {

    /// The process-wide instance every reference-ui view observes.
    static let shared = ReferenceUILanguage()

    /// The language reported by the source (always one of the 5 supported codes). Main thread.
    @Published private(set) var code: String

    /// Test-only pin; wins over `code` when non-nil. Main thread.
    @Published var codeOverrideForTesting: String?

    /// The language the string tables are looked up in.
    var effectiveCode: String { codeOverrideForTesting ?? code }

    private var unsubscribe: (() -> Void)?

    init(source: ReferenceUILanguageSource = .core) {
        code = Self.normalize(source.current())
        unsubscribe = source.subscribe { [weak self] newCode in
            self?.apply(newCode)
        }
    }

    deinit {
        unsubscribe?()
    }

    /// Apply a language reported by the source. Core delivers on main; hop to main otherwise
    /// so `objectWillChange` always fires on the main thread.
    func apply(_ newCode: String) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.apply(newCode) }
            return
        }
        let normalized = Self.normalize(newCode)
        if normalized != code { code = normalized }
    }

    /// Unsupported / empty codes fall back to `ReferenceUIStrings.fallbackLanguage` (en),
    /// matching core's last-resort language (`rb-ios-i18n-fallback-en`).
    static func normalize(_ raw: String) -> String {
        ReferenceUIStrings.supportedLanguages.contains(raw) ? raw : ReferenceUIStrings.fallbackLanguage
    }
}
