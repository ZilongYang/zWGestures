import Foundation
import Testing

@testable import ZWGCore

/// 文案表的守卫。
///
/// 这张表的对照关系由 `switch` 的穷尽性保证（漏一条就编译不过），所以这里只需要盯住
/// **编译器管不了的三件事**：英文里混进中文、两种语言的占位符不一致、空文案。
@Suite("界面文案表")
struct L10nTests {
    /// 中日韩字符。英文表里出现任何一个都说明漏翻了。
    private static var cjk: Regex<Substring> { /[\u{3000}-\u{303F}\u{4E00}-\u{9FFF}\u{FF00}-\u{FFEF}]/ }

    private static var placeholder: Regex<Substring> { /%[0-9.]*[@diouxXeEfgGcsS]/ }

    @Test("每一条都有两种语言，且都不为空")
    func everyKeyHasBothLanguages() {
        for key in L10n.Key.allCases {
            let pair = key.pair
            #expect(!pair.zh.isEmpty, "\(key) 缺中文")
            #expect(!pair.en.isEmpty, "\(key) 缺英文")
            let intentionallyIdentical: Set<L10n.Key> = [.displayShellScriptFormat]
            #expect(
                pair.zh != pair.en || intentionallyIdentical.contains(key),
                "\(key) 中英文完全一样，疑似漏翻：\(pair.zh)"
            )
        }
    }

    @Test("英文表里不该有中日韩字符")
    func englishHasNoCJK() {
        for key in L10n.Key.allCases {
            let english = key.pair.en
            #expect(english.firstMatch(of: Self.cjk) == nil, "\(key) 的英文里有中日韩字符：\(english)")
        }
    }

    @Test("两种语言的 % 占位符必须一一对应")
    func placeholdersMatch() {
        for key in L10n.Key.allCases {
            let zh = key.pair.zh.matches(of: Self.placeholder).map { String($0.output) }
            let en = key.pair.en.matches(of: Self.placeholder).map { String($0.output) }
            #expect(zh == en, "\(key) 的占位符不一致：中文 \(zh)，英文 \(en)")
        }
    }

    @Test("语言取值：中文表里不该有整句英文")
    func chineseHasNoLongEnglishRuns() {
        // 专有名词（Web / Shell / WGestures / Finder / Apple Silicon…）是刻意保留的，它们至少有一个
        // 大写字母；真正的漏翻（整句英文留在中文表里）必然留下**全小写**的 4 字母以上单词。
        // 按词切分而不是用正则，否则 `Shell` 会被切出 `hell` 这种假阳性。
        let allowed: Set<String> = ["config", "prefs", "json", "launchagent", "gestures", "launchctl", "bootstrap"]
        for key in L10n.Key.allCases {
            for token in key.pair.zh.split(whereSeparator: { !$0.isLetter }) {
                guard token.count >= 4, token.allSatisfy({ $0.isLowercase }) else { continue }
                #expect(allowed.contains(String(token)), "\(key) 的中文里混了英文单词 \(token)：\(key.pair.zh)")
            }
        }
    }

    @Test("跟随系统：中文系统给中文，其它一律英文")
    func resolveFromSystem() {
        #expect(WGLanguagePreference.resolve(preference: .system, system: ["zh-Hans-CN", "en-US"]) == .zhHans)
        #expect(WGLanguagePreference.resolve(preference: .system, system: ["zh-Hant-TW"]) == .zhHans)
        #expect(WGLanguagePreference.resolve(preference: .system, system: ["en-US", "zh-Hans"]) == .en)
        #expect(WGLanguagePreference.resolve(preference: .system, system: ["de-DE"]) == .en)
        #expect(WGLanguagePreference.resolve(preference: .system, system: []) == .en)
    }

    @Test("显式选择压过系统语言")
    func resolveFromPreference() {
        #expect(WGLanguagePreference.resolve(preference: .en, system: ["zh-Hans"]) == .en)
        #expect(WGLanguagePreference.resolve(preference: .zhHans, system: ["en-US"]) == .zhHans)
    }

    @Test("指定语言时取到的是那一版的文案（不碰全局状态）")
    func textFollowsRequestedLanguage() {
        // 故意**不**用 `L10n.setLanguage`：语言是进程级状态，而 Swift Testing 默认并行跑用例 ——
        // 一边切语言一边断言中文，会随机把同时运行的别的用例带崩。
        // 2026-10-06 真发生过：`StrokeDirectionTests` 读到 `Right→Down`，而它断言的是「右→下」。
        #expect(L10n.text(.displayGeneralTarget, language: .zhHans) == "全局")
        #expect(L10n.text(.displayGeneralTarget, language: .en) == "General")

        #expect(L10n.format(.statusLoadedFormat, language: .zhHans, 67) == "配置已载入（67 条手势）")
        #expect(L10n.format(.statusLoadedFormat, language: .en, 67) == "Configuration loaded (67 gestures)")
    }

    @Test("语言选项用该语言自己的写法")
    func languageOptionsAreSelfNamed() {
        // 两个具体语言的名字与「当前语言」无关，可以直接断言。
        #expect(WGLanguagePreference.zhHans.localizedName == "简体中文")
        #expect(WGLanguagePreference.en.localizedName == "English")
        // 只有「跟随系统」这一项读当前语言，用纯函数版覆盖两种情形。
        #expect(L10n.text(.languageSystem, language: .en) == "System")
        #expect(L10n.text(.languageSystem, language: .zhHans) == "跟随系统")
    }
}
