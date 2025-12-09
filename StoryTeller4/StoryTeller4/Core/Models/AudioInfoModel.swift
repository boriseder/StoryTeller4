import Foundation

/// Technical audio metadata for validation
/// Stores information about the actual downloaded audio files
struct AudioInfo: Codable {
    let audioTrackCount: Int
    let downloadDate: Date
    
    init(audioTrackCount: Int, downloadDate: Date = Date()) {
        self.audioTrackCount = audioTrackCount
        self.downloadDate = downloadDate
    }
}
