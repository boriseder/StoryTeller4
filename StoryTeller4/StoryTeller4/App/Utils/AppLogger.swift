import os
import Foundation

enum AppLogger {
    private static let subsystem = "at.amtabor.StoryTeller3"

    // MARK: - Logger Wrapper
    // Sendable class ensures thread safety for the static instances below
    final class LogWrapper: Sendable {
        let logger: Logger
        let category: String

        init(logger: Logger, category: String) {
            self.logger = logger
            self.category = category
        }

        func write(_ level: String, message: String, osLevel: OSLogType) {
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let line = "[\(timestamp)] \(level) [\(category)] \(message)"

            AppLogger.writeToFile(line)
            logger.log(level: osLevel, "\(message, privacy: .public)")
        }

        func debug(_ msg: String) { write("🐞 DEBUG", message: msg, osLevel: .debug) }
        func info(_ msg: String)  { write("ℹ️ INFO", message: msg, osLevel: .info) }
        func warn(_ msg: String)  { write("⚠️ WARN", message: msg, osLevel: .default) }
        func error(_ msg: String) { write("❌ ERROR", message: msg, osLevel: .error) }
    }

    // MARK: - Categories
    // Explicitly Sendable wrappers do not need 'nonisolated' keyword here
    static let general = LogWrapper(logger: Logger(subsystem: subsystem, category: "General"), category: "General")
    static let ui      = LogWrapper(logger: Logger(subsystem: subsystem, category: "UI"), category: "UI")
    static let network = LogWrapper(logger: Logger(subsystem: subsystem, category: "Network"), category: "Network")
    static let audio   = LogWrapper(logger: Logger(subsystem: subsystem, category: "Audio"), category: "Audio")
    static let cache   = LogWrapper(logger: Logger(subsystem: subsystem, category: "Cache"), category: "Cache")

    // MARK: - Safe File Logging via Actor
    private actor FileLogger {
        private let logFileURL: URL
        
        init() {
            let fm = FileManager.default
            self.logFileURL = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("AppLogs.txt")
            
            if !fm.fileExists(atPath: logFileURL.path) {
                fm.createFile(atPath: logFileURL.path, contents: nil)
            }
        }
        
        func write(_ text: String) {
            guard let data = (text + "\n").data(using: .utf8) else { return }
            // Using a local handle to ensure safety
            if let handle = try? FileHandle(forWritingTo: logFileURL) {
                defer { try? handle.close() }
                try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            }
        }
    }
    
    private static let fileLogger = FileLogger()

    static func writeToFile(_ text: String) {
        Task {
            await fileLogger.write(text)
        }
    }

    static func logFilePath() -> URL {
        let fm = FileManager.default
        return fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AppLogs.txt")
    }
}
