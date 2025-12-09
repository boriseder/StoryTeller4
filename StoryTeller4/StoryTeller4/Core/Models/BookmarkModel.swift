import Foundation

// MARK: - Bookmark Model
struct Bookmark: Codable, Identifiable {
    let libraryItemId: String
    let time: Double
    let title: String
    let createdAt: TimeInterval
    
    var id: String {
        "\(libraryItemId)-\(time)-\(createdAt)"
    }
    
    var createdDate: Date {
        Date(timeIntervalSince1970: createdAt / 1000) // Server uses milliseconds
    }
    
    var formattedTime: String {
        TimeFormatter.formatTime(time)
    }
    
    /// Finde das Kapitel, in dem dieser Bookmark liegt
    func chapterIndex(for book: Book) -> Int {
        for (index, chapter) in book.chapters.enumerated() {
            let start = chapter.start ?? 0
            let end = chapter.end ?? Double.greatestFiniteMagnitude
            
            if time >= start && time < end {
                return index
            }
        }
        
        return max(0, book.chapters.count - 1)
    }
    
    /// Kapitel-Name für diesen Bookmark
    func chapterTitle(for book: Book) -> String? {
        let index = chapterIndex(for: book)
        guard index < book.chapters.count else { return nil }
        return book.chapters[index].title
    }
}

// MARK: - Enhanced Bookmark Model
struct EnrichedBookmark: Identifiable {
    let bookmark: Bookmark
    let book: Book?
    
    var id: String { bookmark.id }
    var isBookLoaded: Bool { book != nil }
    var displayTitle: String { bookmark.title }
    var bookTitle: String { book?.title ?? "Loading..." }
}

// MARK: - Bookmark Sort Options
enum BookmarkSortOption: String, CaseIterable, Identifiable {
    case dateNewest = "Date (Newest)"
    case dateOldest = "Date (Oldest)"
    case timeInBook = "Time in Book"
    case bookTitle = "Book Title"
    
    var id: String { rawValue }
}
