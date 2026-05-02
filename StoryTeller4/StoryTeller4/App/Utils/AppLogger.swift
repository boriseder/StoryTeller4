import os
import Foundation

enum AppLogger {
    private nonisolated static let subsystem = "at.amtabor.StoryTeller3"

    // MARK: - Logger Wrapper
    final class LogWrapper: Sendable {
        let category: String
        private let osLogger: Logger
        
        nonisolated init(category: String) {
            self.category = category
            // 1. Initialize the logger ONCE per category
            self.osLogger = Logger(subsystem: AppLogger.subsystem, category: category)
        }

        nonisolated func write(_ level: String, message: String, osLevel: OSLogType) {
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let line = "[\(timestamp)] \(level) [\(category)] \(message)"

            AppLogger.writeToFile(line)
            
            // 2. Log synchronously and directly. No Task, no MainActor hop.
            osLogger.log(level: osLevel, "\(message, privacy: .public)")
        }

        nonisolated func debug(_ msg: String) { write("🐞 DEBUG", message: msg, osLevel: .debug) }
        nonisolated func info(_ msg: String)  { write("ℹ️ INFO", message: msg, osLevel: .info) }
        nonisolated func warn(_ msg: String)  { write("⚠️ WARN", message: msg, osLevel: .default) }
        nonisolated func error(_ msg: String) { write("❌ ERROR", message: msg, osLevel: .error) }
    }

    // MARK: - Categories (using computed properties to avoid init isolation)
    nonisolated static var general: LogWrapper { LogWrapper(category: "General") }
    nonisolated static var ui: LogWrapper { LogWrapper(category: "UI") }
    nonisolated static var network: LogWrapper { LogWrapper(category: "Network") }
    nonisolated static var audio: LogWrapper { LogWrapper(category: "Audio") }
    nonisolated static var cache: LogWrapper { LogWrapper(category: "Cache") }

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
            
            if let handle = try? FileHandle(forWritingTo: logFileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            }
        }
    }
    
    private nonisolated static let fileLogger = FileLogger()

    nonisolated static func writeToFile(_ text: String) {
        // The file I/O is still safely isolated to the FileLogger actor
        Task {
            await fileLogger.write(text)
        }
    }

    nonisolated static func logFilePath() -> URL {
        let fm = FileManager.default
        return fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AppLogs.txt")
    }
}
