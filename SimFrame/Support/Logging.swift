import Foundation
import OSLog

enum AppLog {
    static let subsystem = "com.xuemingbo.SimFrame"
    static let library = Logger(subsystem: subsystem, category: "FrameLibrary")
    static let rendering = Logger(subsystem: subsystem, category: "Rendering")
    static let app = Logger(subsystem: subsystem, category: "App")
}

