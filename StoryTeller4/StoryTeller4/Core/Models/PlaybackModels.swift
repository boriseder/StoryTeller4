import Foundation

// MARK: - PlaybackSession Request
struct PlaybackSessionRequest: Codable, Sendable {
    let deviceInfo: DeviceInfo
    let supportedMimeTypes: [String]
    let mediaPlayer: String
    
    struct DeviceInfo: Codable, Sendable {
        let clientVersion: String
        let deviceId: String?
        let clientName: String?
    }
    
    init(
        deviceInfo: DeviceInfo,
        supportedMimeTypes: [String] = ["audio/mpeg", "audio/mp4", "audio/aac"],
        mediaPlayer: String = "iOS App"
    ) {
        self.deviceInfo = deviceInfo
        self.supportedMimeTypes = supportedMimeTypes
        self.mediaPlayer = mediaPlayer
    }
}

// MARK: - PlaybackSession Response
struct PlaybackSessionResponse: Codable, Sendable {
    let id: String
    let audioTracks: [AudioTrack]
    let duration: Double
    let mediaType: String
    let libraryItemId: String
    let episodeId: String?
    
    var totalTracks: Int { audioTracks.count }
    var hasEpisode: Bool { episodeId != nil }
    
    func track(at index: Int) -> AudioTrack? {
        guard audioTracks.indices.contains(index) else { return nil }
        return audioTracks[index]
    }
}

// MARK: - MediaProgress Model
struct MediaProgress: Codable, Identifiable, Sendable {
    let id: String
    let libraryItemId: String
    let episodeId: String?
    let duration: Double
    let progress: Double
    let currentTime: Double
    let isFinished: Bool
    let hideFromContinueListening: Bool
    let lastUpdate: Date
    let startedAt: Date
    let finishedAt: Date?
    
    var progressPercentage: Double {
        guard duration > 0 else { return 0 }
        return (progress * 100).rounded()
    }
    
    var remainingTime: Double { max(0, duration - currentTime) }
    var formattedProgress: String { "\(Int(progressPercentage))%" }
    
    enum CodingKeys: String, CodingKey {
        case id, libraryItemId, episodeId, duration, progress, currentTime
        case isFinished, hideFromContinueListening, lastUpdate, startedAt, finishedAt
    }
    
    init(
        id: String,
        libraryItemId: String,
        episodeId: String? = nil,
        duration: Double,
        progress: Double,
        currentTime: Double,
        isFinished: Bool = false,
        hideFromContinueListening: Bool = false,
        lastUpdate: Date = Date(),
        startedAt: Date = Date(),
        finishedAt: Date? = nil
    ) {
        self.id = id
        self.libraryItemId = libraryItemId
        self.episodeId = episodeId
        self.duration = duration
        self.progress = progress
        self.currentTime = currentTime
        self.isFinished = isFinished
        self.hideFromContinueListening = hideFromContinueListening
        self.lastUpdate = lastUpdate
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        libraryItemId = try container.decode(String.self, forKey: .libraryItemId)
        episodeId = try container.decodeIfPresent(String.self, forKey: .episodeId)
        duration = try container.decode(Double.self, forKey: .duration)
        progress = try container.decode(Double.self, forKey: .progress)
        currentTime = try container.decode(Double.self, forKey: .currentTime)
        isFinished = try container.decode(Bool.self, forKey: .isFinished)
        hideFromContinueListening = try container.decode(Bool.self, forKey: .hideFromContinueListening)
        
        let lastUpdateTimestamp = try container.decode(TimeInterval.self, forKey: .lastUpdate)
        lastUpdate = TimestampConverter.dateFromServer(lastUpdateTimestamp)
        
        let startedTimestamp = try container.decode(TimeInterval.self, forKey: .startedAt)
        startedAt = TimestampConverter.dateFromServer(startedTimestamp)
        
        if let finishedTimestamp = try container.decodeIfPresent(TimeInterval.self, forKey: .finishedAt) {
            finishedAt = TimestampConverter.dateFromServer(finishedTimestamp)
        } else {
            finishedAt = nil
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(libraryItemId, forKey: .libraryItemId)
        try container.encodeIfPresent(episodeId, forKey: .episodeId)
        try container.encode(duration, forKey: .duration)
        try container.encode(progress, forKey: .progress)
        try container.encode(currentTime, forKey: .currentTime)
        try container.encode(isFinished, forKey: .isFinished)
        try container.encode(hideFromContinueListening, forKey: .hideFromContinueListening)
        try container.encode(TimestampConverter.serverTimestamp(from: lastUpdate), forKey: .lastUpdate)
        try container.encode(TimestampConverter.serverTimestamp(from: startedAt), forKey: .startedAt)
        if let finishedAt = finishedAt {
            try container.encode(TimestampConverter.serverTimestamp(from: finishedAt), forKey: .finishedAt)
        }
    }
    
    func chapterIndex(for book: Book) -> Int {
        book.chapterIndex(at: currentTime)
    }
    
    func toPlaybackState(for book: Book) -> PlaybackState {
        PlaybackState(
            libraryItemId: libraryItemId,
            currentTime: currentTime,
            duration: duration,
            isFinished: isFinished,
            lastUpdate: lastUpdate,
            chapterIndex: chapterIndex(for: book)
        )
    }
}

// MARK: - PlaybackState Model
struct PlaybackState: Codable, Sendable {
    let libraryItemId: String
    var currentTime: Double
    var duration: Double
    var isFinished: Bool
    var lastUpdate: Date
    var chapterIndex: Int
    var needsSync: Bool // Added to fix compiler error
    
    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }
    
    var bookId: String { libraryItemId }
    var lastPlayed: Date { lastUpdate }
    var progressPercentage: Double { (progress * 100).rounded() }
    
    init(
        libraryItemId: String,
        currentTime: Double,
        duration: Double,
        isFinished: Bool,
        lastUpdate: Date = Date(),
        chapterIndex: Int = 0,
        needsSync: Bool = false
    ) {
        self.libraryItemId = libraryItemId
        self.currentTime = currentTime
        self.duration = duration
        self.isFinished = isFinished
        self.lastUpdate = lastUpdate
        self.chapterIndex = chapterIndex
        self.needsSync = needsSync
    }
    
    init(from mediaProgress: MediaProgress, chapterIndex: Int = 0) {
        self.libraryItemId = mediaProgress.libraryItemId
        self.currentTime = mediaProgress.currentTime
        self.duration = mediaProgress.duration
        self.isFinished = mediaProgress.isFinished
        self.lastUpdate = mediaProgress.lastUpdate
        self.chapterIndex = chapterIndex
        self.needsSync = false
    }
    
    func updating(
        currentTime: Double? = nil,
        duration: Double? = nil,
        isFinished: Bool? = nil,
        chapterIndex: Int? = nil,
        needsSync: Bool? = nil
    ) -> PlaybackState {
        PlaybackState(
            libraryItemId: libraryItemId,
            currentTime: currentTime ?? self.currentTime,
            duration: duration ?? self.duration,
            isFinished: isFinished ?? self.isFinished,
            lastUpdate: Date(),
            chapterIndex: chapterIndex ?? self.chapterIndex,
            needsSync: needsSync ?? self.needsSync
        )
    }
}
