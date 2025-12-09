// AudioTrack.swift
// Unified AudioTrack model - replaces all other definitions
import Foundation

// MARK: - AudioTrack (Unified Model)
/// Single source of truth for audio track data throughout the app
struct AudioTrack: Codable {
    let index: Int
    let startOffset: Double
    let duration: Double
    let title: String?
    let contentUrl: String?
    let mimeType: String?
    let filename: String?
    
    // MARK: - Computed Properties
    var displayTitle: String {
        title ?? "Track \(index + 1)"
    }
    
    var hasValidUrl: Bool {
        contentUrl != nil && !(contentUrl?.isEmpty ?? true)
    }
    
    var formattedDuration: String {
        TimeFormatter.formatTime(duration)
    }
}

// MARK: - Coding Keys (for flexible API responses)
extension AudioTrack {
    enum CodingKeys: String, CodingKey {
        case index
        case startOffset
        case duration
        case title
        case contentUrl
        case mimeType
        case filename
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        index = try container.decode(Int.self, forKey: .index)
        startOffset = try container.decode(Double.self, forKey: .startOffset)
        duration = try container.decode(Double.self, forKey: .duration)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        contentUrl = try container.decodeIfPresent(String.self, forKey: .contentUrl)
        mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType)
        filename = try container.decodeIfPresent(String.self, forKey: .filename)
    }
}

// MARK: - Convenience Initializers
extension AudioTrack {
    /// Create AudioTrack for offline playback
    init(index: Int, startOffset: Double, duration: Double, title: String?, filename: String) {
        self.index = index
        self.startOffset = startOffset
        self.duration = duration
        self.title = title
        self.contentUrl = nil
        self.mimeType = nil
        self.filename = filename
    }
    
    /// Create minimal AudioTrack from API response
    init(index: Int, startOffset: Double, duration: Double, title: String?) {
        self.index = index
        self.startOffset = startOffset
        self.duration = duration
        self.title = title
        self.contentUrl = nil
        self.mimeType = nil
        self.filename = nil
    }
}
