import Foundation

/// 把配置里「已知的英文手势名」换成中文。
///
/// **为什么需要它**：从原版 WGestures 导入的配置里，`Name` 存的就是原版的英文名（`Close`、
/// `Web Search`……）。原版自己的中文界面靠 `zh_CN.lproj/tr_bootstrap.json` 这张译名表把它们
/// 显示成中文；本项目的界面虽然是双语的，但手势名属于**用户数据**（不参与界面本地化），
/// 所以在中文界面下这些英文名会显得突兀。
///
/// **规则**（作者 2026-10-06 定的）：
/// * 只改**表里有的**名字，一个字都不猜；
/// * 用户自己起的名字、以及已经是中文的名字一律不动；
/// * 只能由作者显式触发（菜单项）或启动时询问并确认后执行，**绝不静默改写**配置；
///   调用方负责先备份（`ConfigStore.saveConfig` 本来就会备份）。
public enum WGNameTranslator {
    /// 一处改名。`targetIndex` 与 `intentIndex` 都按 `WGConfig.allTargets` 的顺序。
    public struct Rename: Equatable, Sendable {
        public let targetIndex: Int
        public let intentIndex: Int
        public let from: String
        public let to: String

        public init(targetIndex: Int, intentIndex: Int, from: String, to: String) {
            self.targetIndex = targetIndex
            self.intentIndex = intentIndex
            self.from = from
            self.to = to
        }
    }

    /// 读译名表（英文 → 中文）。
    ///
    /// 文件缺失或格式不对都当作空表：改名是可选的贴心功能，不该因为它让应用起不来。
    public static func loadTranslations(from url: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: url),
              let table = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return table
    }

    /// 需要改名的位置，按文件顺序。表里没有的名字、以及译名与原名相同的条目都会被跳过。
    public static func renames(in config: WGConfig, using table: [String: String]) -> [Rename] {
        var result: [Rename] = []
        for (targetIndex, target) in config.allTargets.enumerated() {
            for (intentIndex, intent) in target.intents.enumerated() {
                guard let translated = table[intent.name], translated != intent.name else { continue }
                result.append(
                    Rename(
                        targetIndex: targetIndex,
                        intentIndex: intentIndex,
                        from: intent.name,
                        to: translated
                    )
                )
            }
        }
        return result
    }

    /// 就地改名，返回实际改了几处。
    @discardableResult
    public static func apply(_ renames: [Rename], to config: inout WGConfig) -> Int {
        var changed = 0
        for rename in renames {
            config.mutateTarget(at: rename.targetIndex) { target in
                guard target.intents.indices.contains(rename.intentIndex) else { return }
                target.intents[rename.intentIndex].name = rename.to
                changed += 1
            }
        }
        return changed
    }
}
