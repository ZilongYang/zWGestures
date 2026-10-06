import Foundation
import Testing

@testable import ZWGCore

/// `Language` 是本项目对 `prefs.json` 的扩展键，规则与 `WGIntent.enabled` 一样：
/// **缺键即默认（跟随系统），且只在非默认时才写出**。这里钉住往返与写出行为 ——
/// 2026-10-06 作者验收时亲眼看到「保存到 en、再保存一次又变回 system」，需要一条测试证明
/// 机制本身不会丢这个键（那次是画面上的选择器停在旧语言、保存的是模型里的值）。
@Suite("界面语言偏好")
struct PreferencesLanguageTests {
    @Test("缺键即跟随系统")
    func missingKeyMeansSystem() throws {
        let json = #"{"AutoStart":true,"StartDragTimeout":250,"TargetMode":"Focused"}"#
        let preferences = try JSONDecoder().decode(WGPreferences.self, from: Data(json.utf8))
        #expect(preferences.language == .system)
    }

    @Test("跟随系统时不写出 Language 键（逐键一致守卫的前提）")
    func systemIsNotWritten() throws {
        let preferences = WGPreferences()
        let data = try JSONEncoder().encode(preferences)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["Language"] == nil)
    }

    @Test("显式语言会写出并可原样读回")
    func explicitLanguageRoundTrips() throws {
        var preferences = WGPreferences()
        preferences.language = .en
        let data = try JSONEncoder().encode(preferences)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["Language"] as? String == "en")
        #expect(try JSONDecoder().decode(WGPreferences.self, from: data).language == .en)

        preferences.language = .zhHans
        let zh = try JSONEncoder().encode(preferences)
        #expect(try JSONDecoder().decode(WGPreferences.self, from: zh).language == .zhHans)
    }

    @MainActor
    @Test("偏好模型会把语言带进待保存的偏好里，并算作有改动")
    func modelCarriesLanguageIntoEdits() {
        let model = PreferencesModel(preferences: WGPreferences())
        #expect(!model.isDirty)

        model.language = .en
        #expect(model.isDirty)
        #expect(model.editedPreferences.language == .en)

        // 保存后再次载入同一份偏好，选择器必须停在 en —— 显示与模型脱节正是当初的现场问题。
        model.markSaved()
        #expect(!model.isDirty)
        model.load(preferences: model.editedPreferences)
        #expect(model.language == .en)
    }

    @Test("语言只在偏好里记，不进手势配置（配置编码一字不变）")
    func languageDoesNotTouchConfig() throws {
        let config = WGConfig()
        let encoded = try JSONEncoder().encode(config)
        let text = String(decoding: encoded, as: UTF8.self)
        #expect(!text.contains("Language"))
    }
}
