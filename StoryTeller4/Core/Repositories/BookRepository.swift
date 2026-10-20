import Foundation

// MARK: - Protocol (Domain Layer)
// Kein AudiobookshelfClient sichtbar – reine Domain-Typen
protocol BookRepositoryProtocol: Sendable {
    func fetchBooks(libraryId: String, collapseSeries: Bool) async throws -> [Book]
    func fetchBookDetails(bookId: String) async throws -> Book
    func fetchSeries(libraryId: String) async throws -> [Series]
    func fetchSeriesBooks(libraryId: String, seriesId: String) async throws -> [Book]
    func fetchPersonalizedSections(libraryId: String) async throws -> [PersonalizedSection]
    func fetchAuthors(libraryId: String) async throws -> [Author]
    func fetchAuthorDetails(authorId: String, libraryId: String) async throws -> Author
    func clearCache() async
}

// MARK: - Repository Errors (Domain Layer)
enum RepositoryError: LocalizedError, Sendable {
    case networkError(Error)
    case decodingError(Error)
    case notFound
    case invalidData
    case unauthorized
    case serverError(Int)

    var errorDescription: String? {
        switch self {
        case .networkError(let error):  return "Network error: \(error.localizedDescription)"
        case .decodingError(let error): return "Decoding error: \(error.localizedDescription)"
        case .notFound:                 return "Resource not found"
        case .invalidData:              return "Invalid data received"
        case .unauthorized:             return "Unauthorized access"
        case .serverError(let code):    return "Server error \(code)"
        }
    }
}

// MARK: - Implementation (Data Layer)
// AudiobookshelfClient ist ausschließlich hier sichtbar
final class BookRepository: BookRepositoryProtocol, Sendable {

    private let api: AudiobookshelfClient
    private let cache: BookCacheProtocol?

    init(api: AudiobookshelfClient, cache: BookCacheProtocol? = nil) {
        self.api = api
        self.cache = cache
    }

    func fetchBooks(libraryId: String, collapseSeries: Bool) async throws -> [Book] {
        do {
            let books = try await api.books.fetchBooks(
                libraryId: libraryId,
                limit: 0,
                collapseSeries: collapseSeries
            )
            await cache?.cacheBooks(books, for: libraryId)
            return books
        } catch let error as DecodingError {
            throw RepositoryError.decodingError(error)
        } catch let error as URLError {
            throw RepositoryError.networkError(error)
        } catch {
            throw RepositoryError.networkError(error)
        }
    }

    func fetchBookDetails(bookId: String) async throws -> Book {
        do {
            let book = try await api.books.fetchBookDetails(bookId: bookId, retryCount: 3)
            await cache?.cacheBook(book)
            return book
        } catch let error as DecodingError {
            throw RepositoryError.decodingError(error)
        } catch let error as URLError {
            throw RepositoryError.networkError(error)
        } catch {
            throw RepositoryError.networkError(error)
        }
    }

    func fetchSeries(libraryId: String) async throws -> [Series] {
        do {
            let series = try await api.series.fetchSeries(libraryId: libraryId, limit: 1000)
            await cache?.cacheSeries(series, for: libraryId)
            return series
        } catch let error as DecodingError {
            throw RepositoryError.decodingError(error)
        } catch let error as URLError {
            throw RepositoryError.networkError(error)
        } catch {
            throw RepositoryError.networkError(error)
        }
    }

    // Vorher: kein Error-Mapping, RepositoryError wurde nie geworfen
    func fetchSeriesBooks(libraryId: String, seriesId: String) async throws -> [Book] {
        do {
            return try await api.series.fetchSeriesBooks(libraryId: libraryId, seriesId: seriesId)
        } catch let error as DecodingError {
            throw RepositoryError.decodingError(error)
        } catch let error as URLError {
            throw RepositoryError.networkError(error)
        } catch {
            throw RepositoryError.networkError(error)
        }
    }

    func fetchPersonalizedSections(libraryId: String) async throws -> [PersonalizedSection] {
        do {
            let sections = try await api.personalized.fetchPersonalizedSections(
                libraryId: libraryId,
                limit: 10
            )
            await cache?.cacheSections(sections, for: libraryId)
            return sections
        } catch let error as DecodingError {
            throw RepositoryError.decodingError(error)
        } catch let error as URLError {
            throw RepositoryError.networkError(error)
        } catch {
            throw RepositoryError.networkError(error)
        }
    }

    func fetchAuthors(libraryId: String) async throws -> [Author] {
        do {
            let authors = try await api.authors.fetchAuthors(libraryId: libraryId)
            await cache?.cacheAuthors(authors, for: libraryId)
            return authors
        } catch let error as DecodingError {
            throw RepositoryError.decodingError(error)
        } catch let error as URLError {
            throw RepositoryError.networkError(error)
        } catch {
            throw RepositoryError.networkError(error)
        }
    }

    func fetchAuthorDetails(authorId: String, libraryId: String) async throws -> Author {
        do {
            let author = try await api.authors.fetchAuthor(
                authorId: authorId,
                libraryId: libraryId,
                includeBooks: true,
                includeSeries: true
            )
            await cache?.cacheAuthorDetails(author, authorId: authorId)
            return author
        } catch let error as DecodingError {
            throw RepositoryError.decodingError(error)
        } catch let error as URLError {
            throw RepositoryError.networkError(error)
        } catch {
            throw RepositoryError.networkError(error)
        }
    }

    func clearCache() async {
        await cache?.clearCache()
    }
}

// MARK: - Cache Protocol (Data Layer)
protocol BookCacheProtocol: Sendable {
    func cacheBooks(_ books: [Book], for libraryId: String) async
    func cacheBook(_ book: Book) async
    func getCachedBooks(for libraryId: String) async -> [Book]?
    func getCachedBook(bookId: String) async -> Book?
    func clearCache() async

    func cacheSections(_ sections: [PersonalizedSection], for libraryId: String) async
    func getCachedSections(for libraryId: String) async -> [PersonalizedSection]?
    func cacheSeries(_ series: [Series], for libraryId: String) async
    func getCachedSeries(for libraryId: String) async -> [Series]?

    func cacheAuthors(_ authors: [Author], for libraryId: String) async
    func getCachedAuthors(for libraryId: String) async -> [Author]?
    func cacheAuthorDetails(_ author: Author, authorId: String) async
    func getCachedAuthorDetails(authorId: String) async -> Author?
}

// MARK: - Cache Implementation (Data Layer)
actor BookCache: BookCacheProtocol {
    private var booksCache: [String: [Book]] = [:]
    private var bookDetailsCache: [String: Book] = [:]
    private var sectionsCache: [String: [PersonalizedSection]] = [:]
    private var seriesCache: [String: [Series]] = [:]
    private var authorsCache: [String: [Author]] = [:]
    private var authorDetailsCache: [String: Author] = [:]

    private let diskCacheURL: URL
    private let maxCacheAge: TimeInterval = 24 * 60 * 60

    init() {
        let fm = FileManager.default
        let cachesURL = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.diskCacheURL = cachesURL.appendingPathComponent("BookCache", isDirectory: true)
        try? fm.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)
    }

    func cacheBooks(_ books: [Book], for libraryId: String) {
        booksCache[libraryId] = books
        Task.detached { [diskCacheURL] in
            await Self.saveToDisk(books, key: "books_\(libraryId)", at: diskCacheURL)
        }
    }

    func cacheBook(_ book: Book) {
        bookDetailsCache[book.id] = book
        Task.detached { [diskCacheURL] in
            await Self.saveToDisk(book, key: "book_\(book.id)", at: diskCacheURL)
        }
    }

    func getCachedBooks(for libraryId: String) -> [Book]? {
        if let cached = booksCache[libraryId] { return cached }
        if let disk: [Book] = Self.loadFromDiskSync(key: "books_\(libraryId)", at: diskCacheURL, maxAge: maxCacheAge) {
            booksCache[libraryId] = disk
            return disk
        }
        return nil
    }

    func getCachedBook(bookId: String) -> Book? {
        if let cached = bookDetailsCache[bookId] { return cached }
        if let disk: Book = Self.loadFromDiskSync(key: "book_\(bookId)", at: diskCacheURL, maxAge: maxCacheAge) {
            bookDetailsCache[bookId] = disk
            return disk
        }
        return nil
    }

    func cacheAuthors(_ authors: [Author], for libraryId: String) {
        authorsCache[libraryId] = authors
        Task.detached { [diskCacheURL] in
            await Self.saveToDisk(authors, key: "authors_\(libraryId)", at: diskCacheURL)
        }
    }

    func getCachedAuthors(for libraryId: String) -> [Author]? {
        if let cached = authorsCache[libraryId] { return cached }
        if let disk: [Author] = Self.loadFromDiskSync(key: "authors_\(libraryId)", at: diskCacheURL, maxAge: maxCacheAge) {
            authorsCache[libraryId] = disk
            return disk
        }
        return nil
    }

    func cacheAuthorDetails(_ author: Author, authorId: String) {
        authorDetailsCache[authorId] = author
        Task.detached { [diskCacheURL] in
            await Self.saveToDisk(author, key: "author_details_\(authorId)", at: diskCacheURL)
        }
    }

    func getCachedAuthorDetails(authorId: String) -> Author? {
        if let cached = authorDetailsCache[authorId] { return cached }
        if let disk: Author = Self.loadFromDiskSync(key: "author_details_\(authorId)", at: diskCacheURL, maxAge: maxCacheAge) {
            authorDetailsCache[authorId] = disk
            return disk
        }
        return nil
    }

    func cacheSections(_ sections: [PersonalizedSection], for libraryId: String) {
        sectionsCache[libraryId] = sections
        Task.detached { [diskCacheURL] in
            await Self.saveToDisk(sections, key: "sections_\(libraryId)", at: diskCacheURL)
        }
    }

    func getCachedSections(for libraryId: String) -> [PersonalizedSection]? {
        if let cached = sectionsCache[libraryId] { return cached }
        if let disk: [PersonalizedSection] = Self.loadFromDiskSync(key: "sections_\(libraryId)", at: diskCacheURL, maxAge: maxCacheAge) {
            sectionsCache[libraryId] = disk
            return disk
        }
        return nil
    }

    func cacheSeries(_ series: [Series], for libraryId: String) {
        seriesCache[libraryId] = series
        Task.detached { [diskCacheURL] in
            await Self.saveToDisk(series, key: "series_\(libraryId)", at: diskCacheURL)
        }
    }

    func getCachedSeries(for libraryId: String) -> [Series]? {
        if let cached = seriesCache[libraryId] { return cached }
        if let disk: [Series] = Self.loadFromDiskSync(key: "series_\(libraryId)", at: diskCacheURL, maxAge: maxCacheAge) {
            seriesCache[libraryId] = disk
            return disk
        }
        return nil
    }

    func clearCache() {
        booksCache.removeAll()
        bookDetailsCache.removeAll()
        sectionsCache.removeAll()
        seriesCache.removeAll()
        authorsCache.removeAll()
        authorDetailsCache.removeAll()

        let url = diskCacheURL
        Task.detached {
            let fm = FileManager.default
            try? fm.removeItem(at: url)
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
            AppLogger.general.debug("[BookCache] Cache cleared")
        }
    }

    // MARK: - Private Disk I/O
    nonisolated private static func saveToDisk<T: Encodable & Sendable>(
        _ data: T,
        key: String,
        at cacheURL: URL
    ) async {
        let fileURL = cacheURL.appendingPathComponent("\(key).json")
        guard let encoded = try? JSONEncoder().encode(data) else { return }
        try? encoded.write(to: fileURL)

        let metadata = LocalCacheMetadata(timestamp: Date())
        let metadataURL = cacheURL.appendingPathComponent("\(key)_metadata.json")
        if let metadataData = try? JSONEncoder().encode(metadata) {
            try? metadataData.write(to: metadataURL)
        }
    }

    nonisolated private static func loadFromDiskSync<T: Decodable & Sendable>(
        key: String,
        at cacheURL: URL,
        maxAge: TimeInterval
    ) -> T? {
        let fileURL = cacheURL.appendingPathComponent("\(key).json")
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

        let metadataURL = cacheURL.appendingPathComponent("\(key)_metadata.json")
        if let metaData = try? Data(contentsOf: metadataURL),
           let metadata = try? JSONDecoder().decode(LocalCacheMetadata.self, from: metaData),
           Date().timeIntervalSince(metadata.timestamp) > maxAge {
            try? FileManager.default.removeItem(at: fileURL)
            try? FileManager.default.removeItem(at: metadataURL)
            return nil
        }

        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(T.self, from: data) else { return nil }
        return decoded
    }
}

// MARK: - Cache Metadata Helper
struct LocalCacheMetadata: Codable, Sendable {
    let timestamp: Date

    nonisolated init(timestamp: Date) { self.timestamp = timestamp }

    enum CodingKeys: String, CodingKey { case timestamp }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(timestamp, forKey: .timestamp)
    }
}

// MARK: - Placeholder
extension BookRepository {
    @MainActor
    static var placeholder: BookRepository {
        BookRepository(api: AudiobookshelfClient(baseURL: "", authToken: ""))
    }
}
