import Foundation

public struct WGConfigLoadResult: Sendable {
    public var config: WGConfig
    /// Non-fatal problems found while reading the file, surfaced in the UI and the log.
    public var warnings: [String]
}

/// Reads and writes WGestures-format JSON.
public enum WGConfigCodec {
    /// Object types this build understands. Anything else is reported rather than silently
    /// dropped.
    static let knownTypes: Set<String> = [
        "KeyDownStep", "StrokeStep", "MoveToEdgeCornerStep", "ScrollStep",
        "KeySeqCommand", "WebSearchCommand", "ShellScriptCommand", "SystemFunctionKeyCommand",
        "MacAppTarget", "MacDesktopTarget",
    ]

    static let knownRootKeys: Set<String> = ["General", "Groups", "Apps", "Specials"]

    public static func decode(_ data: Data) throws -> WGConfigLoadResult {
        let cleaned = stripByteOrderMark(data)
        let config = try makeDecoder().decode(WGConfig.self, from: cleaned)

        var warnings: [String] = []
        if let raw = try? JSONSerialization.jsonObject(with: cleaned) {
            let unknown = unknownTypes(in: raw)
            if !unknown.isEmpty {
                warnings.append("配置里有本版本不认识的对象类型，相关内容会被丢弃：\(unknown.sorted().joined(separator: ", "))")
            }
            let unknownKeys = unknownRootKeys(in: raw)
            if !unknownKeys.isEmpty {
                warnings.append("配置里有未识别的顶层字段：\(unknownKeys.sorted().joined(separator: ", "))")
            }
        }
        return WGConfigLoadResult(config: config, warnings: warnings)
    }

    public static func encode(_ config: WGConfig) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(config)
    }

    public static func decodePreferences(_ data: Data) throws -> WGPreferences {
        try JSONDecoder().decode(WGPreferences.self, from: stripByteOrderMark(data))
    }

    public static func encodePreferences(_ preferences: WGPreferences) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(preferences)
    }

    // MARK: - Helpers

    private static func makeDecoder() -> JSONDecoder {
        JSONDecoder()
    }

    /// The original app writes some files with a UTF-8 BOM, which `JSONDecoder` rejects.
    static func stripByteOrderMark(_ data: Data) -> Data {
        let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
        guard data.count >= 3, Array(data.prefix(3)) == bom else { return data }
        return data.dropFirst(3)
    }

    static func unknownTypes(in object: Any) -> Set<String> {
        var found: Set<String> = []
        walk(object) { dictionary in
            if let type = dictionary["$type"] as? String, !knownTypes.contains(type) {
                found.insert(type)
            }
        }
        return found
    }

    static func unknownRootKeys(in object: Any) -> Set<String> {
        guard let root = object as? [String: Any] else { return [] }
        return Set(root.keys).subtracting(knownRootKeys)
    }

    private static func walk(_ object: Any, visit: ([String: Any]) -> Void) {
        if let dictionary = object as? [String: Any] {
            visit(dictionary)
            for value in dictionary.values { walk(value, visit: visit) }
        } else if let array = object as? [Any] {
            for value in array { walk(value, visit: visit) }
        }
    }
}
