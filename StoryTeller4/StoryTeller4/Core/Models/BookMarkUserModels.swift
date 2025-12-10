import Foundation

// MARK: - Bookmark Model
struct Bookmark: Codable, Identifiable, Hashable {
    let libraryItemId: String
    let time: Double
    let title: String
    let createdAt: Date
    
    var id: String {
        "\(libraryItemId)-\(time)-\(createdAt.timeIntervalSince1970)"
    }
    
    var formattedTime: String {
        TimeFormatter.formatTime(time)
    }
    
    // MARK: - Coding Keys
    enum CodingKeys: String, CodingKey {
        case libraryItemId, time, title, createdAt
    }
    
    init(
        libraryItemId: String,
        time: Double,
        title: String,
        createdAt: Date = Date()
    ) {
        self.libraryItemId = libraryItemId
        self.time = time
        self.title = title
        self.createdAt = createdAt
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        libraryItemId = try container.decode(String.self, forKey: .libraryItemId)
        time = try container.decode(Double.self, forKey: .time)
        title = try container.decode(String.self, forKey: .title)
        
        // Server uses milliseconds
        let timestamp = try container.decode(TimeInterval.self, forKey: .createdAt)
        createdAt = TimestampConverter.dateFromServer(timestamp)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(libraryItemId, forKey: .libraryItemId)
        try container.encode(time, forKey: .time)
        try container.encode(title, forKey: .title)
        try container.encode(TimestampConverter.serverTimestamp(from: createdAt), forKey: .createdAt)
    }
    
    // MARK: - Helper Methods
    func chapterIndex(for book: Book) -> Int {
        book.chapterIndex(at: time)
    }
    
    func chapter(for book: Book) -> Chapter? {
        book.chapter(at: time)
    }
    
    func chapterTitle(for book: Book) -> String? {
        chapter(for: book)?.title
    }
    
    // MARK: - Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Enhanced Bookmark Model
struct EnrichedBookmark: Identifiable {
    let bookmark: Bookmark
    let book: Book?
    
    var id: String {
        bookmark.id
    }
    
    var isBookLoaded: Bool {
        book != nil
    }
    
    var displayTitle: String {
        bookmark.title
    }
    
    var bookTitle: String {
        book?.title ?? "Loading..."
    }
    
    var formattedTime: String {
        bookmark.formattedTime
    }
    
    var createdAt: Date {
        bookmark.createdAt
    }
}

// MARK: - Bookmark Sort Options
enum BookmarkSortOption: String, CaseIterable, Identifiable {
    case dateNewest = "Date (Newest)"
    case dateOldest = "Date (Oldest)"
    case timeInBook = "Time in Book"
    case bookTitle = "Book Title"
    
    var id: String { rawValue }
    
    var systemImage: String {
        switch self {
        case .dateNewest, .dateOldest:
            return "calendar"
        case .timeInBook:
            return "clock"
        case .bookTitle:
            return "book"
        }
    }
    
    func sort(_ bookmarks: [EnrichedBookmark]) -> [EnrichedBookmark] {
        switch self {
        case .dateNewest:
            return bookmarks.sorted { $0.createdAt > $1.createdAt }
        case .dateOldest:
            return bookmarks.sorted { $0.createdAt < $1.createdAt }
        case .timeInBook:
            return bookmarks.sorted { $0.bookmark.time < $1.bookmark.time }
        case .bookTitle:
            return bookmarks.sorted { $0.bookTitle < $1.bookTitle }
        }
    }
}

// MARK: - User Data Model
/// Sendable: API response containing user state, shared across app
struct UserData: Codable, Sendable {
    let id: String
    let username: String
    let email: String?
    let type: String
    let token: String
    let mediaProgress: [MediaProgress]
    let bookmarks: [Bookmark]
    
    // MARK: - Helper Methods
    func bookmarks(for libraryItemId: String) -> [Bookmark] {
        bookmarks
            .filter { $0.libraryItemId == libraryItemId }
            .sorted { $0.time < $1.time }
    }
    
    func progress(for libraryItemId: String) -> MediaProgress? {
        mediaProgress.first { $0.libraryItemId == libraryItemId }
    }
    
    func hasProgress(for libraryItemId: String) -> Bool {
        progress(for: libraryItemId) != nil
    }
    
    func hasBookmarks(for libraryItemId: String) -> Bool {
        !bookmarks(for: libraryItemId).isEmpty
    }
    
    var isAdmin: Bool {
        type.lowercased() == "admin"
    }
}
