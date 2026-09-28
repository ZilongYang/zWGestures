import Foundation
import Testing

@testable import ZWGCore

@Suite("开机自启：LaunchAgent 兜底")
struct LaunchAgentTests {
    @Test("写在用户的 LaunchAgents 目录里，标签固定")
    func plistLocation() {
        let url = LaunchAgent.plistURL
        #expect(url.lastPathComponent == "com.zilong.zwgestures.plist")
        #expect(url.path.contains("/Library/LaunchAgents/"))
        #expect(url.path.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.path))
        #expect(LaunchAgent.label == "com.zilong.zwgestures")
    }

    @Test("plist 内容正确：标签、RunAtLoad、经 open -a 启动指定应用")
    func plistContents() throws {
        let data = try LaunchAgent.makePlist(appPath: "/Applications/zWGestures.app")
        let plist = try #require(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        #expect(plist["Label"] as? String == "com.zilong.zwgestures")
        #expect(plist["RunAtLoad"] as? Bool == true)
        #expect(plist["ProcessType"] as? String == "Interactive")
        // 必须经过 open -a：直接执行二进制会绕过 LaunchServices，
        // 于是应用已经手动启动时还会再起一个实例。
        let arguments = try #require(plist["ProgramArguments"] as? [String])
        #expect(arguments == ["/usr/bin/open", "-a", "/Applications/zWGestures.app"])
    }

    @Test("生成的是合法 XML plist，能被系统解析回来")
    func plistIsValidXML() throws {
        let data = try LaunchAgent.makePlist(appPath: "/Applications/微信.app")
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("<?xml"))
        #expect(text.contains("<!DOCTYPE plist"))
        // 非 ASCII 路径要能原样往返（用户的应用可能叫「微信」）。
        let plist = try #require(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        let arguments = try #require(plist["ProgramArguments"] as? [String])
        #expect(arguments.last == "/Applications/微信.app")
    }
}
