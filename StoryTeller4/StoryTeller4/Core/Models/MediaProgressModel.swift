
import Foundation

// MARK: - Media Progress Model
struct MediaProgress: Codable, Identifiable {
    let id: String
    let libraryItemId: String
    let episodeId: String?
    let duration: Double
    let progress: Double
    let currentTime: Double
    let isFinished: Bool
    let hideFromContinueListening: Bool
    let lastUpdate: TimeInterval
    let startedAt: TimeInterval
    let finishedAt: TimeInterval?
    
    enum CodingKeys: String, CodingKey {
        case id, libraryItemId, episodeId, duration, progress, currentTime
        case isFinished, hideFromContinueListening, lastUpdate, startedAt, finishedAt
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
        lastUpdate = try container.decode(TimeInterval.self, forKey: .lastUpdate)
        startedAt = try container.decode(TimeInterval.self, forKey: .startedAt)
        finishedAt = try container.decodeIfPresent(TimeInterval.self, forKey: .finishedAt)
    }
    
    // MARK: - Helper: Map currentTime to Chapter Index
    func chapterIndex(for book: Book) -> Int {
        // Find which chapter contains this currentTime
        for (index, chapter) in book.chapters.enumerated() {
            let start = chapter.start ?? 0
            let end = chapter.end ?? Double.greatestFiniteMagnitude
            
            if currentTime >= start && currentTime < end {
                return index
            }
        }
        
        // Fallback: if currentTime is beyond all chapters, return last chapter
        return max(0, book.chapters.count - 1)
    }
    
    // MARK: - Convert to Local PlaybackState
    func toPlaybackState(for book: Book) -> PlaybackState {
        let chapterIdx = chapterIndex(for: book)
        
        return PlaybackState(
            libraryItemId: libraryItemId,
            currentTime: currentTime,
            duration: duration,
            isFinished: isFinished,
            lastUpdate: Date(timeIntervalSince1970: lastUpdate / 1000), // Server uses milliseconds
            chapterIndex: chapterIdx,
            needsSync: false  // Vom Server geladen, also bereits synced
        )
    }
}
