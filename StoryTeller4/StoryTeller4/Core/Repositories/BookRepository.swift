import Foundation

// MARK: - Repository Protocol
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

// MARK: - Repository Errors
enum RepositoryError: LocalizedError, Sendable {
    case networkError(Error)
    case decodingError(Error)
    case notFound
    case invalidData
    case unauthorized
    case serverError(Int)
    
    var errorDescription: String? {
        switch self {
        case .networkError(let error): return "Network error: \(error.localizedDescription)"
        case .decodingError(let error): return "Data parsing error: \(error.localizedDescription)"
        case .notFound: return "Resource not found"
        case .invalidData: return "Invalid or corrupted data"
        case .unauthorized: return "Authentication required"
        case .serverError(let code): return "Server error (code: \(code))"
        }
    }
}

// MARK: - Book Repository Implementation
final class BookRepository: BookRepositoryProtocol, Sendable {
    
    private let api: AudiobookshelfClient
    private let cache: BookCacheProtocol?
    
    init(api: AudiobookshelfClient, cache: BookCacheProtocol? = nil) {
        self.api = api
        self.cache = cache
    }
    
    // MARK: - Public Methods
    
    func fetchBooks(libraryId: String, collapseSeries: Bool) async throws -> [Book] {
        do {
            let books = try await api.books.fetchBooks(libraryId: libraryId, limit: 0, collapseSeries: collapseSeries)
            await cache?.cacheBooks(books, for: libraryId)
            AppLogger.general.debug("[BookRepository] Fetched \(books.count) books")
            return books
        } catch let decodingError as DecodingError {
            AppLogger.general.debug("[BookRepository] Decoding error: \(decodingError)")
            if let cachedBooks = await cache?.getCachedBooks(for: libraryId) { return cachedBooks }
            throw RepositoryError.decodingError(decodingError)
        } catch let urlError as URLError {
            AppLogger.general.debug("[BookRepository] Network error: \(urlError)")
            if let cachedBooks = await cache?.getCachedBooks(for: libraryId) { return cachedBooks }
            throw RepositoryError.networkError(urlError)
        } catch {
            throw RepositoryError.networkError(error)
        }
    }
    
    func fetchBookDetails(bookId: String) async throws -> Book {
        do {
            let book = try await api.books.fetchBookDetails(bookId: bookId, retryCount: 3)
            await cache?.cacheBook(book)
            return book
        } catch let decodingError as DecodingError {
            if let cachedBook = await cache?.getCachedBook(bookId: bookId) { return cachedBook }
            throw RepositoryError.decodingError(decodingError)
        } catch let urlError as URLError {
            if let cachedBook = await cache?.getCachedBook(bookId: bookId) { return cachedBook }
            throw RepositoryError.networkError(urlError)
        } catch {
            throw RepositoryError.networkError(error)
        }
    }
    
    func fetchSeries(libraryId: String) async throws -> [Series] {
        do {
            let series = try await api.series.fetchSeries(libraryId: libraryId, limit: 1000)
            await cache?.cacheSeries(series, for: libraryId)
            return series
        } catch let decodingError as DecodingError {
            if let cached = await cache?.getCachedSeries(for: libraryId) { return cached }
            throw RepositoryError.decodingError(decodingError)
        } catch let urlError as URLError {
            if let cached = await cache?.getCachedSeries(for: libraryId) { return cached }
            throw RepositoryError.networkError(urlError)
        } catch {
            throw RepositoryError.networkError(error)
        }
    }
    
    func fetchSeriesBooks(libraryId: String, seriesId: String) async throws -> [Book] {
        do {
            return try await api.series.fetchSeriesBooks(libraryId: libraryId, seriesId: seriesId)
        } catch let decodingError as DecodingError {
            throw RepositoryError.decodingError(decodingError)
        } catch let urlError as URLError {
            throw RepositoryError.networkError(urlError)
        } catch {
            throw RepositoryError.networkError(error)
        }
    }
    
    func fetchPersonalizedSections(libraryId: String) async throws -> [PersonalizedSection] {
        do {
            let sections = try await api.personalized.fetchPersonalizedSections(libraryId: libraryId, limit: 10)
            await cache?.cacheSections(sections, for: libraryId)
            return sections
        } catch let decodingError as DecodingError {
            if let cached = await cache?.getCachedSections(for: libraryId) { return cached }
            throw RepositoryError.decodingError(decodingError)
        } catch let urlError as URLError {
            if let cached = await cache?.getCachedSections(for: libraryId) { return cached }
            throw RepositoryError.networkError(urlError)
        } catch {
            throw RepositoryError.networkError(error)
        }
    }
    
    func fetchAuthors(libraryId: String) async throws -> [Author] {
        do {
            let authors = try await api.authors.fetchAuthors(libraryId: libraryId)
            await cache?.cacheAuthors(authors, for: libraryId)
            return authors
        } catch let decodingError as DecodingError {
            if let cached = await cache?.getCachedAuthors(for: libraryId) { return cached }
            throw RepositoryError.decodingError(decodingError)
        } catch let urlError as URLError {
            if let cached = await cache?.getCachedAuthors(for: libraryId) { return cached }
            throw RepositoryError.networkError(urlError)
        } catch {
            throw RepositoryError.networkError(error)
        }
    }

    func fetchAuthorDetails(authorId: String, libraryId: String) async throws -> Author {
        do {
            let author = try await api.authors.fetchAuthor(authorId: authorId, libraryId: libraryId, includeBooks: true, includeSeries: true)
            await cache?.cacheAuthorDetails(author, authorId: authorId)
            return author
        } catch let decodingError as DecodingError {
            if let cached = await cache?.getCachedAuthorDetails(authorId: authorId) { return cached }
            throw RepositoryError.decodingError(decodingError)
        } catch let urlError as URLError {
            if let cached = await cache?.getCachedAuthorDetails(authorId: authorId) { return cached }
            throw RepositoryError.networkError(urlError)
        } catch {
            throw RepositoryError.networkError(error)
        }
    }
    
    func clearCache() async {
        await cache?.clearCache()
    }
}

// MARK: - Book Cache Protocol
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

// MARK: - Actor Cache Implementation
actor BookCache: BookCacheProtocol {
    private var booksCache: [String: [Book]] = [:]
    private var bookDetailsCache: [String: Book] = [:]
    private var sectionsCache: [String: [PersonalizedSection]] = [:]
    private var seriesCache: [String: [Series]] = [:]
    private var authorsCache: [String: [Author]] = [:]
    private var authorDetailsCache: [String: Author] = [:]
    
    private let fileManager = FileManager.default
    private let diskCacheURL: URL
    private let maxCacheAge: TimeInterval = 24 * 60 * 60  // 24 hours
    
    init() {
        let fm = FileManager.default
        let cachesURL = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.diskCacheURL = cachesURL.appendingPathComponent("BookCache", isDirectory: true)
        try? fm.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)
    }
    
    // MARK: - Caching Methods
    
    func cacheBooks(_ books: [Book], for libraryId: String) {
        self.booksCache[libraryId] = books
        saveToDisk(books, key: "books_\(libraryId)")
    }
    
    func cacheBook(_ book: Book) {
        self.bookDetailsCache[book.id] = book
        saveToDisk(book, key: "book_\(book.id)")
    }
    
    func getCachedBooks(for libraryId: String) -> [Book]? {
        if let cached = booksCache[libraryId] { return cached }
        if let diskCached: [Book] = loadFromDisk(key: "books_\(libraryId)") {
            booksCache[libraryId] = diskCached
            return diskCached
        }
        return nil
    }
    
    func getCachedBook(bookId: String) -> Book? {
        if let cached = bookDetailsCache[bookId] { return cached }
        if let diskCached: Book = loadFromDisk(key: "book_\(bookId)") {
            bookDetailsCache[bookId] = diskCached
            return diskCached
        }
        return nil
    }
    
    func cacheAuthors(_ authors: [Author], for libraryId: String) {
        self.authorsCache[libraryId] = authors
        saveToDisk(authors, key: "authors_\(libraryId)")
    }
    
    func getCachedAuthors(for libraryId: String) -> [Author]? {
        if let cached = authorsCache[libraryId] { return cached }
        if let diskCached: [Author] = loadFromDisk(key: "authors_\(libraryId)") {
            authorsCache[libraryId] = diskCached
            return diskCached
        }
        return nil
    }
    
    func cacheAuthorDetails(_ author: Author, authorId: String) {
        self.authorDetailsCache[authorId] = author
        saveToDisk(author, key: "author_details_\(authorId)")
    }
    
    func getCachedAuthorDetails(authorId: String) -> Author? {
        if let cached = authorDetailsCache[authorId] { return cached }
        if let diskCached: Author = loadFromDisk(key: "author_details_\(authorId)") {
            authorDetailsCache[authorId] = diskCached
            return diskCached
        }
        return nil
    }

    func cacheSections(_ sections: [PersonalizedSection], for libraryId: String) {
        self.sectionsCache[libraryId] = sections
        saveToDisk(sections, key: "sections_\(libraryId)")
    }
    
    func getCachedSections(for libraryId: String) -> [PersonalizedSection]? {
        if let cached = sectionsCache[libraryId] { return cached }
        if let diskCached: [PersonalizedSection] = loadFromDisk(key: "sections_\(libraryId)") {
            sectionsCache[libraryId] = diskCached
            return diskCached
        }
        return nil
    }
    
    func cacheSeries(_ series: [Series], for libraryId: String) {
        self.seriesCache[libraryId] = series
        saveToDisk(series, key: "series_\(libraryId)")
    }
    
    func getCachedSeries(for libraryId: String) -> [Series]? {
        if let cached = seriesCache[libraryId] { return cached }
        if let diskCached: [Series] = loadFromDisk(key: "series_\(libraryId)") {
            seriesCache[libraryId] = diskCached
            return diskCached
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
        
        try? fileManager.removeItem(at: diskCacheURL)
        try? fileManager.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)
        
        AppLogger.general.debug("[BookCache] Cache cleared")
    }

    // MARK: - Private Disk I/O Methods
    
    private func saveToDisk<T: Encodable & Sendable>(_ data: T, key: String) {
        let fileURL = diskCacheURL.appendingPathComponent("\(key).json")
        guard let encoded = try? JSONEncoder().encode(data) else { return }
        
        try? encoded.write(to: fileURL)
        
        // Save metadata
        let metadata = CacheMetadata(timestamp: Date())
        let metadataURL = diskCacheURL.appendingPathComponent("\(key)_metadata.json")
        if let metadataData = try? JSONEncoder().encode(metadata) {
            try? metadataData.write(to: metadataURL)
        }
    }
    
    private func loadFromDisk<T: Decodable & Sendable>(key: String) -> T? {
        let fileURL = diskCacheURL.appendingPathComponent("\(key).json")
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        
        // Check expiry
        let metadataURL = diskCacheURL.appendingPathComponent("\(key)_metadata.json")
        if let metaData = try? Data(contentsOf: metadataURL),
           let metadata = try? JSONDecoder().decode(CacheMetadata.self, from: metaData),
           Date().timeIntervalSince(metadata.timestamp) > maxCacheAge {
            try? fileManager.removeItem(at: fileURL)
            try? fileManager.removeItem(at: metadataURL)
            return nil
        }
        
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(T.self, from: data) else {
            return nil
        }
        
        return decoded
    }
}
