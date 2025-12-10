import Foundation

// MARK: - Series Model
struct Series: Codable, Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let name: String
    let nameIgnorePrefix: String?
    let nameIgnorePrefixSort: String?
    let numBooks: Int
    let books: [LibraryItem]?
    let addedAt: Date
    
    var totalDuration: Double { books?.reduce(0) { $0 + ($1.media.duration ?? 0) } ?? 0 }
    var bookCount: Int { books?.count ?? numBooks }
    var firstBook: LibraryItem? { books?.first }
    var coverPath: String? { firstBook?.media.coverPath }
    var author: String? { firstBook?.media.metadata.author }
    var formattedDuration: String { TimeFormatter.formatTimeCompact(totalDuration) }
    var displayName: String { name }
    
    init(id: String, name: String, nameIgnorePrefix: String? = nil, nameIgnorePrefixSort: String? = nil, numBooks: Int, books: [LibraryItem]? = nil, addedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.nameIgnorePrefix = nameIgnorePrefix
        self.nameIgnorePrefixSort = nameIgnorePrefixSort
        self.numBooks = numBooks
        self.books = books
        self.addedAt = addedAt
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name, nameIgnorePrefix, nameIgnorePrefixSort, numBooks, books, addedAt
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        nameIgnorePrefix = try container.decodeIfPresent(String.self, forKey: .nameIgnorePrefix)
        nameIgnorePrefixSort = try container.decodeIfPresent(String.self, forKey: .nameIgnorePrefixSort)
        numBooks = try container.decode(Int.self, forKey: .numBooks)
        books = try container.decodeIfPresent([LibraryItem].self, forKey: .books)
        
        if let timestamp = try? container.decode(TimeInterval.self, forKey: .addedAt) {
            addedAt = TimestampConverter.dateFromServer(timestamp)
        } else {
            addedAt = Date()
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(nameIgnorePrefix, forKey: .nameIgnorePrefix)
        try container.encodeIfPresent(nameIgnorePrefixSort, forKey: .nameIgnorePrefixSort)
        try container.encode(numBooks, forKey: .numBooks)
        try container.encodeIfPresent(books, forKey: .books)
        try container.encode(TimestampConverter.serverTimestamp(from: addedAt), forKey: .addedAt)
    }
    
    static func == (lhs: Series, rhs: Series) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - LibraryItem Model
struct LibraryItem: Codable, Identifiable, Sendable, Hashable {
    let id: String
    let media: Media
    let libraryId: String?
    let isFile: Bool?
    let isMissing: Bool?
    let isInvalid: Bool?
    let collapsedSeries: Series?
    
    var isCollapsedSeries: Bool { collapsedSeries != nil }
    var isValid: Bool { !(isMissing ?? false) && !(isInvalid ?? false) }
    var title: String { collapsedSeries?.name ?? media.metadata.title }
    var author: String? { collapsedSeries?.author ?? media.metadata.author }
    var coverPath: String? { collapsedSeries?.coverPath ?? media.coverPath }
}

// MARK: - Book Model
struct Book: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: String
    let title: String
    let author: String?
    let chapters: [Chapter]
    let coverPath: String?
    let collapsedSeries: Series?
    
    var isCollapsedSeries: Bool { collapsedSeries != nil }
    var displayTitle: String { collapsedSeries?.name ?? title }
    var seriesBookCount: Int { collapsedSeries?.numBooks ?? 1 }
    
    func coverURL(baseURL: String) -> URL? {
        guard let coverPath = coverPath else { return nil }
        return URL(string: "\(baseURL)\(coverPath)")
    }
    
    func chapter(at time: Double) -> Chapter? {
        chapters.first { $0.contains(time: time) }
    }
    
    func chapterIndex(at time: Double) -> Int {
        chapters.firstIndex { $0.contains(time: time) } ?? max(0, chapters.count - 1)
    }
    
    enum CodingKeys: String, CodingKey {
        case id, title, author, chapters, coverPath, collapsedSeries
    }
    
    init(id: String, title: String, author: String?, chapters: [Chapter], coverPath: String?, collapsedSeries: Series?) {
        self.id = id
        self.title = title
        self.author = author
        self.chapters = chapters
        self.coverPath = coverPath
        self.collapsedSeries = collapsedSeries
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        author = try container.decodeIfPresent(String.self, forKey: .author)
        chapters = try container.decode([Chapter].self, forKey: .chapters)
        coverPath = try container.decodeIfPresent(String.self, forKey: .coverPath)
        collapsedSeries = try container.decodeIfPresent(Series.self, forKey: .collapsedSeries)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(author, forKey: .author)
        try container.encode(chapters, forKey: .chapters)
        try container.encodeIfPresent(coverPath, forKey: .coverPath)
        try container.encodeIfPresent(collapsedSeries, forKey: .collapsedSeries)
    }
    
    static func == (lhs: Book, rhs: Book) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Library Model
struct Library: Codable, Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let name: String
    let mediaType: String?
}

struct LibrariesResponse: Codable, Sendable {
    let libraries: [Library]
}

struct LibraryItemsResponse: Decodable, Sendable {
    let results: [LibraryItem]
    let total: Int?
    let limit: Int?
    let page: Int?
}

struct SeriesResponse: Decodable, Sendable {
    let results: [Series]
}
