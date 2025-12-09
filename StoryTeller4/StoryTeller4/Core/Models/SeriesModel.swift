import Foundation

// MARK: - Series Models

struct Series: Codable, Identifiable, Equatable, Hashable {  // ✅ Simplified
    let id: String
    let name: String
    let nameIgnorePrefix: String?
    let nameIgnorePrefixSort: String?
    let books: [LibraryItem]
    let addedAt: TimeInterval
    
    // MARK: - Computed Properties
    
    /// Total duration of all books in the series
    var totalDuration: Double {
        books.reduce(0) { total, book in
            total + (book.media.duration ?? 0)
        }
    }
    
    var bookCount: Int {
        books.count
    }
    
    var firstBook: LibraryItem? {
        books.first
    }
    
    var coverPath: String? {
        firstBook?.media.coverPath
    }
    
    var author: String? {
        firstBook?.media.metadata.author
    }
    
    var formattedDuration: String {
        TimeFormatter.formatTimeCompact(totalDuration)
    }
    
    // MARK: - Equatable & Hashable
    
    static func == (lhs: Series, rhs: Series) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - SeriesResponseItem (for API responses)
struct SeriesResponseItem: Decodable {
    let id: String
    let name: String
    let nameIgnorePrefix: String?
    let nameIgnorePrefixSort: String?
    let books: [LibraryItem]
    let addedAt: TimeInterval
    
    // Conversion method to Series
    func toSeries() -> Series {
        return Series(
            id: id,
            name: name,
            nameIgnorePrefix: nameIgnorePrefix,
            nameIgnorePrefixSort: nameIgnorePrefixSort,
            books: books,
            addedAt: addedAt
        )
    }
}

// MARK: - SeriesResponse (API wrapper)
struct SeriesResponse: Decodable {
    let results: [SeriesResponseItem]
    let total: Int
    let limit: Int
    let page: Int
    let sortBy: String?
    let sortDesc: Bool
    let filterBy: String?
    let mediaType: String?
    let minified: Bool
    let collapseseries: Bool?
    let include: String?
}
