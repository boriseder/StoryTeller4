import Foundation

// MARK: - Playback State Model
struct PlaybackState: Codable {
    let libraryItemId: String
    var currentTime: Double
    var duration: Double
    var isFinished: Bool
    var lastUpdate: Date
    var chapterIndex: Int
    var needsSync: Bool = false
    
    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }
    
    var bookId: String { libraryItemId }
    var lastPlayed: Date { lastUpdate }
    
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
    
    // ✅ FIX: Consistent timestamp conversion (server uses milliseconds)
    init(from mediaProgress: MediaProgress, chapterIndex: Int = 0) {
        self.libraryItemId = mediaProgress.libraryItemId
        self.currentTime = mediaProgress.currentTime
        self.duration = mediaProgress.duration
        self.isFinished = mediaProgress.isFinished
        self.lastUpdate = Date(timeIntervalSince1970: mediaProgress.lastUpdate / 1000) // ✅ ms → s
        self.chapterIndex = chapterIndex
        self.needsSync = false
    }
    
    // ✅ FIX: Consistent timestamp conversion
    mutating func mergeWithServer(_ serverProgress: MediaProgress, book: Book) {
        let serverDate = Date(timeIntervalSince1970: serverProgress.lastUpdate / 1000) // ✅ ms → s
        
        if serverDate > self.lastUpdate {
            self.currentTime = serverProgress.currentTime
            self.duration = serverProgress.duration
            self.isFinished = serverProgress.isFinished
            self.lastUpdate = serverDate
            self.chapterIndex = serverProgress.chapterIndex(for: book)
            self.needsSync = false
        }
    }
}

// MARK: - Notification Extension
extension Notification.Name {
    static let playbackAutoSave = Notification.Name("playbackAutoSave")
    static let playbackStateChanged = Notification.Name("playbackStateChanged")
}
