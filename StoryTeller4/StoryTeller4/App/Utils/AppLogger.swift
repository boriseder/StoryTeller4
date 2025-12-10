import os
import Foundation

enum AppLogger {
    private nonisolated static let subsystem = "at.amtabor.StoryTeller3"

    // MARK: - Logger Wrapper
    final class LogWrapper: Sendable {
        let category: String
        
        nonisolated init(category: String) {
            self.category = category
        }

        func write(_ level: String, message: String, osLevel: OSLogType) {
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let line = "[\(timestamp)] \(level) [\(category)] \(message)"

            AppLogger.writeToFile(line)
            
            // Create logger on-demand in MainActor context
            Task { @MainActor in
                let logger = Logger(subsystem: AppLogger.subsystem, category: self.category)
                logger.log(level: osLevel, "\(message, privacy: .public)")
            }
        }

        func debug(_ msg: String) { write("🐞 DEBUG", message: msg, osLevel: .debug) }
        func info(_ msg: String)  { write("ℹ️ INFO", message: msg, osLevel: .info) }
        func warn(_ msg: String)  { write("⚠️ WARN", message: msg, osLevel: .default) }
        func error(_ msg: String) { write("❌ ERROR", message: msg, osLevel: .error) }
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
