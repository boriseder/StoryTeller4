import Foundation
import SwiftUI

// MARK: - Time Formatter
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
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        
        if h > 0 {
            return m > 0 ? "\(h)h \(m)m" : "\(h)h"
        } else {
            return m > 0 ? "\(m)m" : "< 1m"
        }
    }
    
    static func formatTimeRemaining(_ seconds: Double) -> String {
        return "\(formatTime(seconds)) left"
    }
    
    static func formatDuration(_ seconds: Double) -> String {
        return formatTimeWithHours(seconds)
    }
}

// MARK: - Double Extensions
extension Double {
    var formattedAsTime: String { TimeFormatter.formatTime(self) }
    var formattedAsCompactTime: String { TimeFormatter.formatTimeCompact(self) }
    var formattedAsTimeRemaining: String { TimeFormatter.formatTimeRemaining(self) }
}

// MARK: - HTML String Extension
extension String {
    func htmlToAttributedString() -> AttributedString {
        guard let data = self.data(using: .utf8) else {
            return AttributedString(self)
        }
        
        do {
            let nsString = try NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
            )
            return AttributedString(nsString.string)
        } catch {
            return AttributedString(self)
        }
    }
}
