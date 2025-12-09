// PlaybackSessionModel.swift
import Foundation

// MARK: - PlaybackSession Request
struct PlaybackSessionRequest: Codable {
    let deviceInfo: DeviceInfo
    let supportedMimeTypes: [String]
    let mediaPlayer: String
    
    struct DeviceInfo: Codable {
        let clientVersion: String
        let deviceId: String?
        let clientName: String?
    }
}

// MARK: - PlaybackSession Response
struct PlaybackSessionResponse: Codable {
    let id: String
    let audioTracks: [AudioTrack]  // ✅ Uses unified AudioTrack from AudioTrack.swift
    let duration: Double
    let mediaType: String
    let libraryItemId: String
    let episodeId: String?
    
    // MARK: - Convenience Properties
    var totalTracks: Int {
        audioTracks.count
    }
    
    var hasEpisode: Bool {
        episodeId != nil
    }
    
    func track(at index: Int) -> AudioTrack? {
        guard index >= 0 && index < audioTracks.count else { return nil }
        return audioTracks[index]
    }
}
