import Foundation

// MARK: - ReferenceUIStrings — reference-ui 自帶字串表的查表入口
//
// Spec: `reference-ui-rendering/spec.md`
//   §「（iOS）LivebuyReferenceUI 文案走 reference-ui 字串表並支援執行中切換語言」
// Change: `rb-ios-i18n-string-table`（design.md 有完整 key 清單與命名規則）。
//
// reference-ui 的使用者可見文案一律經 `text(_:_:)` 依「目前語言」查表：
//   • 目前語言 = `ReferenceUILanguage.shared.effectiveCode`（來源是 core 的
//     `Livebuy.currentLanguage`，經 `Livebuy.addLanguageListener` 即時更新）。
//   • 找不到 key 時依序 fallback：目前語言表 → en 表 → key 本身（debug log）。
//     （`rb-ios-i18n-fallback-en`：由 zh-TW 改為 en，對齊 core 語言優先序最後的 fallback en。）
//   • 占位符四端統一為具名 `{name}`（不用 `%@` / `%d`），由 `format(_:_:)` 代入。
//
// 字串表本體在同目錄的 `ReferenceUIStrings+<locale>.swift`，每個 locale 一個檔、一行一筆
// `"key": "value",`（之後的四端對照 script 會用 regex 逐行解析，所以每筆 MUST 獨佔一行、
// 不跨行、不串接，值內不出現 ASCII 雙引號或反斜線）。zh-TW 表是 key 清單的權威來源。
//
// 不依賴 core 的 `LBLocalizedString`（internal，且其 key 之後會退役）。

enum ReferenceUIStrings {

    /// The 5 locales reference-ui ships tables for — same set as core's `currentLanguage`.
    static let supportedLanguages: [String] = ["zh-TW", "zh-CN", "en", "ms-MY", "id-ID"]

    /// Fallback locale: the missing-key fallback table in `resolve` AND the value
    /// `ReferenceUILanguage.normalize` maps unsupported / empty codes to. `en`, matching core's
    /// last-resort language (`rb-ios-i18n-fallback-en`). The zh-TW table stays the authoritative
    /// key list — that role is expressed by the completeness tests, not by this constant.
    static let fallbackLanguage = "en"

    /// locale code → table.
    static let tables: [String: [String: String]] = [
        "zh-TW": zhTW,
        "zh-CN": zhCN,
        "en": en,
        "ms-MY": msMY,
        "id-ID": idID,
    ]

    /// Look up `key` in the CURRENT reference-ui language and substitute `{name}` placeholders.
    static func text(_ key: String, _ args: [String: String] = [:]) -> String {
        resolve(key, args, language: ReferenceUILanguage.shared.effectiveCode)
    }

    /// Pure lookup: `language` table → `fallbackLanguage` (en) table → `key` itself (with a debug log).
    static func resolve(_ key: String,
                        _ args: [String: String] = [:],
                        language: String,
                        tables: [String: [String: String]] = tables,
                        missingKeyLog: (String) -> Void = logMissingKey) -> String {
        if let value = tables[language]?[key] ?? tables[fallbackLanguage]?[key] {
            return format(value, args)
        }
        missingKeyLog(key)
        return key
    }

    /// Replace every `{name}` in `template` with `args[name]`. Placeholders without an arg
    /// are left as-is (visible in QA rather than silently blanked).
    static func format(_ template: String, _ args: [String: String]) -> String {
        guard !args.isEmpty else { return template }
        var out = template
        for (name, value) in args {
            out = out.replacingOccurrences(of: "{\(name)}", with: value)
        }
        return out
    }

    /// The set of `{name}` placeholder names in `value` (used by the completeness tests).
    static func placeholders(in value: String) -> Set<String> {
        var names = Set<String>()
        var rest = value[...]
        while let open = rest.firstIndex(of: "{") {
            let afterOpen = rest.index(after: open)
            guard let close = rest[afterOpen...].firstIndex(of: "}") else { break }
            names.insert(String(rest[afterOpen..<close]))
            rest = rest[rest.index(after: close)...]
        }
        return names
    }

    // MARK: - Locale-aware formatting

    /// The Foundation `Locale` used for date formatting in `language`. Callers pass an already
    /// normalized code (one of the 5 supported), so `default` is only reached by "zh-TW" — it is
    /// not a string fallback and is unaffected by `fallbackLanguage`.
    static func locale(for language: String) -> Locale {
        switch language {
        case "zh-CN": return Locale(identifier: "zh_CN")
        case "en": return Locale(identifier: "en_US")
        case "ms-MY": return Locale(identifier: "ms_MY")
        case "id-ID": return Locale(identifier: "id_ID")
        default: return Locale(identifier: "zh_TW")
        }
    }

    /// Month + day in `language`'s CLDR "MMMd" skeleton (zh-TW `6月11日`, en `Jun 11`,
    /// ms-MY / id-ID `11 Jun`). Fixed Gregorian calendar + GMT on both the components and the
    /// formatter → timezone-independent and deterministic. nil for an invalid month/day.
    static func monthDay(month: Int, day: Int, language: String) -> String? {
        var calendar = Calendar(identifier: .gregorian)
        let gmt = TimeZone(secondsFromGMT: 0) ?? .current
        calendar.timeZone = gmt
        // A leap year so 2/29 stays valid; the year is not displayed.
        guard (1...12).contains(month), (1...31).contains(day),
              let date = calendar.date(from: DateComponents(year: 2024, month: month, day: day)),
              calendar.component(.day, from: date) == day else { return nil }
        let locale = locale(for: language)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = gmt
        formatter.locale = locale
        formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "MMMd", options: 0, locale: locale)
        return formatter.string(from: date)
    }

    // MARK: - Missing-key log

    static func logMissingKey(_ key: String) {
        #if DEBUG
        print("[LivebuyReferenceUI] missing string key '\(key)' — falling back to the key itself")
        #endif
    }
}
