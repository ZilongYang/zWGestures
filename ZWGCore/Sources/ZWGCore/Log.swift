import Foundation
import os

/// Centralised `os.Logger` handles.
///
/// Prefer these over `print` so output is visible in Console.app or via:
/// `log stream --predicate 'subsystem == "com.zilong.zwgestures"'`
public enum Log {
    public static let subsystem = "com.zilong.zwgestures"

    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let config = Logger(subsystem: subsystem, category: "config")
    public static let input = Logger(subsystem: subsystem, category: "input")
    public static let recog = Logger(subsystem: subsystem, category: "recog")
    public static let target = Logger(subsystem: subsystem, category: "target")
    public static let action = Logger(subsystem: subsystem, category: "action")
    public static let overlay = Logger(subsystem: subsystem, category: "overlay")
    public static let ui = Logger(subsystem: subsystem, category: "ui")
}
