//
//  PlayerProgressState.swift
//  StoryTeller4
//
//  Created by Boris Eder on 12.12.25.
//


import Foundation

/// Unified progress calculation for consistency across all player views
struct PlayerProgressState {
    let currentTime: TimeInterval
    let duration: TimeInterval
    let mode: ProgressMode
    
    enum ProgressMode {
        case chapter  // Relative to current chapter
        case book     // Absolute position in book
    }
    
    /// Safe progress value (0...1) with proper bounds checking
    var normalizedProgress: Double {
        guard duration > 0 else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }
    
    /// Formatted display time with proper handling of edge cases
    var currentTimeFormatted: String {
        TimeFormatter.formatTime(max(0, currentTime))
    }
    
    /// Remaining time with safety checks
    var remainingTime: TimeInterval {
        max(0, duration - currentTime)
    }
    
    var remainingTimeFormatted: String {
        TimeFormatter.formatTime(remainingTime)
    }
    
    /// Safe seek position calculation for tap gestures
    func seekPosition(for tapLocation: CGFloat, in totalWidth: CGFloat) -> TimeInterval? {
        guard totalWidth > 0, duration > 0 else { return nil }
        let progress = max(0, min(tapLocation / totalWidth, 1))
        return progress * duration
    }
}

extension AudioPlayer {
    /// Get unified progress state based on display mode
    func progressState(mode: PlayerProgressState.ProgressMode) -> PlayerProgressState {
        switch mode {
        case .chapter:
            return PlayerProgressState(
                currentTime: relativeCurrentTime,
                duration: chapterDuration,
                mode: .chapter
            )
        case .book:
            return PlayerProgressState(
                currentTime: absoluteCurrentTime,
                duration: totalBookDuration,
                mode: .book
            )
        }
    }
}