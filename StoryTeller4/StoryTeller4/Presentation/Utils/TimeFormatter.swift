import Foundation

// MARK: - Time Formatting Utilities
struct TimeFormatter: Sendable {
    
    static func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
    
    static func formatTimeWithHours(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00:00" }
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d:%02d", hours, minutes, secs)
    }
    
    static func formatTimeCompact(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0m" }
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        
        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        } else {
            return minutes > 0 ? "\(minutes)m" : "< 1m"
        }
    }
    
    static func formatTimeRemaining(_ seconds: Double) -> String {
        return "\(formatTime(seconds)) left"
    }
    
    static func formatDuration(_ seconds: Double) -> String {
        return formatTimeWithHours(seconds)
    }
}

extension Double {
    var formattedAsTime: String { TimeFormatter.formatTime(self) }
    var formattedAsCompactTime: String { TimeFormatter.formatTimeCompact(self) }
    var formattedAsTimeRemaining: String { TimeFormatter.formatTimeRemaining(self) }
}
