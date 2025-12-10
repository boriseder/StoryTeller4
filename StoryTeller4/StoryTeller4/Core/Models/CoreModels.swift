import Foundation

// MARK: - Timestamp Utilities
/// Centralized timestamp handling for consistent server communication
enum TimestampConverter {
    /// Convert server timestamp (milliseconds) to Date
    static func dateFromServer(_ timestamp: TimeInterval) -> Date {
        Date(timeIntervalSince1970: timestamp / 1000)
    }
    
    /// Convert Date to server timestamp (milliseconds)
    static func serverTimestamp(from date: Date) -> TimeInterval {
        date.timeIntervalSince1970 * 1000
    }
    
    /// Current timestamp in server format (milliseconds)
    static var currentServerTimestamp: TimeInterval {
        serverTimestamp(from: Date())
    }
}

// MARK: - AudioTrack Model
/// Unified AudioTrack model - single source of truth for audio track data
/// Sendable: Passed between actors during playback
struct AudioTrack: Codable, Sendable, Hashable {
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
        guard let url = contentUrl else { return false }
        return !url.isEmpty
    }
    
    var formattedDuration: String {
        TimeFormatter.formatTime(duration)
    }
    
    // MARK: - Convenience Initializers
    init(
        index: Int,
        startOffset: Double,
        duration: Double,
        title: String? = nil,
        contentUrl: String? = nil,
        mimeType: String? = nil,
        filename: String? = nil
    ) {
        self.index = index
        self.startOffset = startOffset
        self.duration = duration
        self.title = title
        self.contentUrl = contentUrl
        self.mimeType = mimeType
        self.filename = filename
    }
}

// MARK: - AudioInfo Model
/// Technical audio metadata for validation
struct AudioInfo: Codable {
    let audioTrackCount: Int
    let downloadDate: Date
    
    init(audioTrackCount: Int, downloadDate: Date = Date()) {
        self.audioTrackCount = audioTrackCount
        self.downloadDate = downloadDate
    }
}

// MARK: - Chapter Model
struct Chapter: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let start: Double?
    let end: Double?
    let libraryItemId: String?
    let episodeId: String?
    
    init(
        id: String,
        title: String,
        start: Double? = nil,
        end: Double? = nil,
        libraryItemId: String? = nil,
        episodeId: String? = nil
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.libraryItemId = libraryItemId
        self.episodeId = episodeId
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Flexible ID handling
        if let intId = try? container.decode(Int.self, forKey: .id) {
            self.id = String(intId)
        } else {
            self.id = (try? container.decode(String.self, forKey: .id)) ?? UUID().uuidString
        }
        
        self.title = (try? container.decode(String.self, forKey: .title)) ?? "Untitled"
        self.start = try? container.decode(Double.self, forKey: .start)
        self.end = try? container.decode(Double.self, forKey: .end)
        self.libraryItemId = try? container.decode(String.self, forKey: .libraryItemId)
        self.episodeId = try? container.decode(String.self, forKey: .episodeId)
    }
    
    // MARK: - Helper Methods
    func contains(time: Double) -> Bool {
        let chapterStart = start ?? 0
        let chapterEnd = end ?? .greatestFiniteMagnitude
        return time >= chapterStart && time < chapterEnd
    }
}

// MARK: - Metadata Model
struct Metadata: Codable, Hashable {
    let title: String
    let author: String?
    let description: String?
    let isbn: String?
    let genres: [String]?
    let publishedYear: String?
    let narrator: String?
    let publisher: String?
    
    enum CodingKeys: String, CodingKey {
        case title, description, isbn, genres, publishedYear, narrator, publisher
        case authorName
        case authors
    }
    
    struct Author: Codable {
        let name: String
    }
    
    init(
        title: String,
        author: String? = nil,
        description: String? = nil,
        isbn: String? = nil,
        genres: [String]? = nil,
        publishedYear: String? = nil,
        narrator: String? = nil,
        publisher: String? = nil
    ) {
        self.title = title
        self.author = author
        self.description = description
        self.isbn = isbn
        self.genres = genres
        self.publishedYear = publishedYear
        self.narrator = narrator
        self.publisher = publisher
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        isbn = try container.decodeIfPresent(String.self, forKey: .isbn)
        genres = try container.decodeIfPresent([String].self, forKey: .genres)
        publishedYear = try container.decodeIfPresent(String.self, forKey: .publishedYear)
        narrator = try container.decodeIfPresent(String.self, forKey: .narrator)
        publisher = try container.decodeIfPresent(String.self, forKey: .publisher)
        
        // Flexible author parsing
        if let authorName = try container.decodeIfPresent(String.self, forKey: .authorName) {
            author = authorName
        } else if let authorObjects = try container.decodeIfPresent([Author].self, forKey: .authors) {
            author = authorObjects.first?.name
        } else {
            author = nil
        }
    }
}

// MARK: - Media Model
struct Media: Codable, Hashable {
    let metadata: Metadata
    let chapters: [Chapter]?
    let duration: Double?
    let size: Int64?
    let tracks: [AudioTrack]?
    let coverPath: String?
    
    var effectiveChapters: [Chapter] {
        chapters ?? []
    }
    
    var effectiveTracks: [AudioTrack] {
        tracks ?? []
    }
}
