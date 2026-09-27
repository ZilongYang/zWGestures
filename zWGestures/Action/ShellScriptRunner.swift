import AppKit
import Foundation

/// Runs shell-script commands.
///
/// Scripts are executed off the main thread: they can block for seconds, and the gesture engine
/// must never be delayed by a slow command.
enum ShellScriptRunner {
    static func run(script: String, environment: [String: String]) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", script]

            var merged = ProcessInfo.processInfo.environment
            merged.merge(environment) { _, new in new }
            process.environment = merged
            // Relative paths in scripts should resolve somewhere sensible.
            process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                // Read before waiting: a full pipe buffer would deadlock the child otherwise.
                let output = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                let text = String(data: output, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if process.terminationStatus == 0 {
                    Log.action.notice("Shell 脚本执行完成（退出码 0）")
                    if !text.isEmpty {
                        Log.action.debug("输出：\(text, privacy: .public)")
                    }
                } else {
                    Log.action.error("""
                        Shell 脚本退出码 \(process.terminationStatus, privacy: .public)：\
                        \(text, privacy: .public)
                        """)
                }
            } catch {
                Log.action.error("Shell 脚本无法启动：\(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
