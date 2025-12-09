import Foundation

// MARK: - Time Formatting Utilities
enum TimeFormatter {
    
    /// Formats time in MM:SS or H:MM:SS format
    /// - Parameter seconds: Time duration in seconds
    /// - Returns: Formatted time string
    static func formatTime(_ seconds: Double) -> String {
        // Handle edge cases
        guard seconds.isFinite && seconds >= 0 else {
            return "0:00"
        }
        
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
    
    /// Formats time with explicit hours display (always H:MM:SS)
    /// - Parameter seconds: Time duration in seconds
    /// - Returns: Formatted time string with hours
    static func formatTimeWithHours(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else {
            return "0:00:00"
        }
        
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        
        return String(format: "%d:%02d:%02d", hours, minutes, secs)
    }
    
    /// Formats time in compact format (e.g., "1h 23m", "45m", "2m")
    /// - Parameter seconds: Time duration in seconds
    /// - Returns: Compact formatted time string
    static func formatTimeCompact(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else {
            return "0m"
        }
        
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        
        if hours > 0 {
            if minutes > 0 {
                return "\(hours)h \(minutes)m"
            } else {
                return "\(hours)h"
            }
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "< 1m"
        }
    }
    
    /// Formats remaining time with "left" suffix
    /// - Parameter seconds: Remaining time in seconds
    /// - Returns: Formatted remaining time string
    static func formatTimeRemaining(_ seconds: Double) -> String {
        let formattedTime = formatTime(seconds)
        return "\(formattedTime) left"
    }
    
    static func formatDuration(_ seconds: Double) -> String {
        // Für Hörbücher ist die Gesamtdauer meist in Stunden
        return formatTimeWithHours(seconds) // Immer H:MM:SS für Duration
    }
}


// MARK: - Double Extension for convenience
extension Double {
    /// Formats the double value as time string
    var formattedAsTime: String {
        TimeFormatter.formatTime(self)
    }
    
    /// Formats the double value as compact time string
    var formattedAsCompactTime: String {
        TimeFormatter.formatTimeCompact(self)
    }
    
    /// Formats the double value as remaining time string
    var formattedAsTimeRemaining: String {
        TimeFormatter.formatTimeRemaining(self)
    }
}
