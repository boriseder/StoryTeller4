import Foundation

// MARK: - Repository Protocol
protocol BookRepositoryProtocol {
    func fetchBooks(libraryId: String, collapseSeries: Bool) async throws -> [Book]
    func fetchBookDetails(bookId: String) async throws -> Book
 //   func searchBooks(libraryId: String, query: String) async throws -> [Book]
    func fetchSeries(libraryId: String) async throws -> [Series]
    func fetchSeriesBooks(libraryId: String, seriesId: String) async throws -> [Book]
    func fetchPersonalizedSections(libraryId: String) async throws -> [PersonalizedSection]
    func fetchAuthors(libraryId: String) async throws -> [Author]
    func fetchAuthorDetails(authorId: String, libraryId: String) async throws -> Author
    
}

// MARK: - Repository Errors
enum RepositoryError: LocalizedError {
    case networkError(Error)
    case decodingError(Error)
    case notFound
    case invalidData
    case unauthorized
    case serverError(Int)
    
    var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Data parsing error: \(error.localizedDescription)"
        case .notFound:
            return "Resource not found"
        case .invalidData:
            return "Invalid or corrupted data"
        case .unauthorized:
            return "Authentication required"
        case .serverError(let code):
            return "Server error (code: \(code))"
        }
    }
}

// MARK: - Book Repository Implementation
class BookRepository: BookRepositoryProtocol {
    
    private let api: AudiobookshelfClient
    private let cache: BookCacheProtocol?
    
    init(api: AudiobookshelfClient, cache: BookCacheProtocol? = nil) {
        self.api = api
        self.cache = cache
    }
    
    // MARK: - Public Methods
    
    func fetchBooks(libraryId: String, collapseSeries: Bool) async throws -> [Book] {
        do {
            let books = try await api.books.fetchBooks(
                libraryId: libraryId,
                limit: 0,
                collapseSeries: collapseSeries
            )
            
            cache?.cacheBooks(books, for: libraryId)
            AppLogger.general.debug("[BookRepository] Fetched \(books.count) books from library \(libraryId)")
            return books
            
        } catch let decodingError as DecodingError {
            AppLogger.general.debug("[BookRepository] Decoding error: \(decodingError)")
            
            if let cachedBooks = cache?.getCachedBooks(for: libraryId) {
                AppLogger.general.debug("[BookRepository] Returning \(cachedBooks.count) cached books")
                return cachedBooks
            }
            
            throw RepositoryError.decodingError(decodingError)
            
        } catch let urlError as URLError {
            AppLogger.general.debug("[BookRepository] Network error: \(urlError)")
            
            if let cachedBooks = cache?.getCachedBooks(for: libraryId) {
                AppLogger.general.debug("[BookRepository] Returning \(cachedBooks.count) cached books (offline)")
                return cachedBooks
            }
            
            throw RepositoryError.networkError(urlError)
            
        } catch {
            throw RepositoryError.networkError(error)
        }
    }
    
    func fetchBookDetails(bookId: String) async throws -> Book {
        do {
            let book = try await api.books.fetchBookDetails(bookId: bookId, retryCount: 3)
            
            cache?.cacheBook(book)
            AppLogger.general.debug("[BookRepository] Fetched details for book: \(book.title)")
            return book
            
        } catch let decodingError as DecodingError {
            AppLogger.general.debug("[BookRepository] Decoding error for book \(bookId): \(decodingError)")
            
            if let cachedBook = cache?.getCachedBook(bookId: bookId) {
                AppLogger.general.debug("[BookRepository] Returning cached book")
                return cachedBook
            }
            
            throw RepositoryError.decodingError(decodingError)
            
        } catch let urlError as URLError {
            if let cachedBook = cache?.getCachedBook(bookId: bookId) {
                AppLogger.general.debug("[BookRepository] Returning cached book (offline)")
                return cachedBook
            }
            
            throw RepositoryError.networkError(urlError)
            
        } catch {
            throw RepositoryError.networkError(error)
        }
    }
    
    func fetchSeries(libraryId: String) async throws -> [Series] {
        do {
            let series = try await api.series.fetchSeries(libraryId: libraryId, limit: 1000)
            
            // ADD: Cache successful fetch
            cache?.cacheSeries(series, for: libraryId)
            
            AppLogger.general.debug("[BookRepository] Fetched \(series.count) series")
            return series
            
        } catch let decodingError as DecodingError {
            // ADD: Try cache on error
            if let cachedSeries = cache?.getCachedSeries(for: libraryId) {
                AppLogger.general.debug("[BookRepository] Returning \(cachedSeries.count) cached series")
                return cachedSeries
            }
            throw RepositoryError.decodingError(decodingError)
            
        } catch let urlError as URLError {
            // ADD: Try cache on network error
            if let cachedSeries = cache?.getCachedSeries(for: libraryId) {
                AppLogger.general.debug("[BookRepository] Returning \(cachedSeries.count) cached series (offline)")
                return cachedSeries
            }
            throw RepositoryError.networkError(urlError)
            
        } catch {
            throw RepositoryError.networkError(error)
        }
    }
    
    func fetchSeriesBooks(libraryId: String, seriesId: String) async throws -> [Book] {
        do {
            let books = try await api.series.fetchSeriesBooks(libraryId: libraryId, seriesId: seriesId)
            AppLogger.general.debug("[BookRepository] Fetched \(books.count) books for series \(seriesId)")
            return books
            
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
            
            // ADD: Cache successful fetch
            cache?.cacheSections(sections, for: libraryId)
            
            AppLogger.general.debug("[BookRepository] Fetched \(sections.count) personalized sections")
            return sections
            
        } catch let decodingError as DecodingError {
            // ADD: Try cache on error
            if let cachedSections = cache?.getCachedSections(for: libraryId) {
                AppLogger.general.debug("[BookRepository] Returning \(cachedSections.count) cached sections")
                return cachedSections
            }
            throw RepositoryError.decodingError(decodingError)
            
        } catch let urlError as URLError {
            // ADD: Try cache on network error
            if let cachedSections = cache?.getCachedSections(for: libraryId) {
                AppLogger.general.debug("[BookRepository] Returning \(cachedSections.count) cached sections (offline)")
                return cachedSections
            }
            throw RepositoryError.networkError(urlError)
            
        } catch {
            throw RepositoryError.networkError(error)
        }
    }
    
    // MARK: - Authors
    
    func fetchAuthors(libraryId: String) async throws -> [Author] {
        do {
            let authors = try await api.authors.fetchAuthors(libraryId: libraryId)
            
            // Cache successful fetch
            cache?.cacheAuthors(authors, for: libraryId)
            
            AppLogger.general.debug("[BookRepository] Fetched \(authors.count) authors")
            return authors
            
        } catch let decodingError as DecodingError {
            // Try cache on decoding error
            if let cachedAuthors = cache?.getCachedAuthors(for: libraryId) {
                AppLogger.general.debug("[BookRepository] Returning \(cachedAuthors.count) cached authors")
                return cachedAuthors
            }
            throw RepositoryError.decodingError(decodingError)
            
        } catch let urlError as URLError {
            // Try cache on network error (offline)
            if let cachedAuthors = cache?.getCachedAuthors(for: libraryId) {
                AppLogger.general.debug("[BookRepository] Returning \(cachedAuthors.count) cached authors (offline)")
                return cachedAuthors
            }
            throw RepositoryError.networkError(urlError)
            
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
            
            // Write cache
            cache?.cacheAuthorDetails(author, authorId: authorId)
            
            AppLogger.general.debug("[BookRepository] Fetched author details: \(author.name)")
            return author
            
        } catch let decodingError as DecodingError {
            AppLogger.general.debug("[BookRepository] Decoding error for author \(authorId): \(decodingError)")
            
            // Read cache on error
            if let cached = cache?.getCachedAuthorDetails(authorId: authorId) {
                AppLogger.general.debug("[BookRepository] Returning cached author details")
                return cached
            }
            
            throw RepositoryError.decodingError(decodingError)
            
        } catch let urlError as URLError {
            
            // Read cache on network error
            if let cached = cache?.getCachedAuthorDetails(authorId: authorId) {
                AppLogger.general.debug("[BookRepository] Returning cached author details (offline)")
                return cached
            }
            
            throw RepositoryError.networkError(urlError)
            
        } catch {
            throw RepositoryError.networkError(error)
        }
    }
/*
    func searchBooks(libraryId: String, query: String) async throws -> [Book] {
        guard !query.isEmpty else {
            return []
        }
        
        do {
            let allBooks = try await fetchBooks(libraryId: libraryId, collapseSeries: false)
            
            let filteredBooks = allBooks.filter { book in
                book.title.localizedCaseInsensitiveContains(query) ||
                (book.author?.localizedCaseInsensitiveContains(query) ?? false)
            }
            
            AppLogger.general.debug("[BookRepository] Search '\(query)' found \(filteredBooks.count) books")
            
            return filteredBooks
            
        } catch {
            throw error
        }
    }
*/
    
    func clearCache() {
        cache?.clearCache()
        AppLogger.general.debug("[BookRepository] Cache cleared")
    }

}

// MARK: - Book Cache Protocol
protocol BookCacheProtocol {
    // Existing
    func cacheBooks(_ books: [Book], for libraryId: String)
    func cacheBook(_ book: Book)
    func getCachedBooks(for libraryId: String) -> [Book]?
    func getCachedBook(bookId: String) -> Book?
    func clearCache()
    
    // New methods for persisting book cache
    func cacheSections(_ sections: [PersonalizedSection], for libraryId: String)
    func getCachedSections(for libraryId: String) -> [PersonalizedSection]?
    func cacheSeries(_ series: [Series], for libraryId: String)
    func getCachedSeries(for libraryId: String) -> [Series]?
    func getCacheTimestamp(for key: String) -> Date?
    func clearExpiredCache(maxAge: TimeInterval)
    
    // Authors
    func cacheAuthors(_ authors: [Author], for libraryId: String)
    func getCachedAuthors(for libraryId: String) -> [Author]?
    func cacheAuthorDetails(_ author: Author, authorId: String)
    func getCachedAuthorDetails(authorId: String) -> Author?

}

// MARK: - Simple In-Memory Cache Implementation
class BookCache: BookCacheProtocol {
    // KEEP: Existing memory cache
    private var booksCache: [String: [Book]] = [:]
    private var bookDetailsCache: [String: Book] = [:]
    private var sectionsCache: [String: [PersonalizedSection]] = [:]
    private var seriesCache: [String: [Series]] = [:]
    private var authorsCache: [String: [Author]] = [:] 
    private var authorDetailsCache: [String: Author] = [:]
    private let cacheQueue = DispatchQueue(label: "com.storyteller3.bookcache")
    
    // ADD: Disk persistence
    private let fileManager = FileManager.default
    private let diskCacheURL: URL
    private let maxCacheAge: TimeInterval = 24 * 60 * 60  // 24 hours
    
    init() {
        // Setup disk cache directory
        let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.diskCacheURL = cachesURL.appendingPathComponent("BookCache", isDirectory: true)
        
        // Create directory if needed
        try? fileManager.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)
        
        // Load existing cache from disk
        loadCacheFromDisk()
        
        AppLogger.general.debug("[BookCache] Initialized with disk persistence at: \(diskCacheURL.path)")
    }
    
    // MODIFY: Save to disk when caching
    func cacheBooks(_ books: [Book], for libraryId: String) {
        cacheQueue.async {
            self.booksCache[libraryId] = books
            self.saveToDisk(books, key: "books_\(libraryId)")
        }
    }
    
    func cacheBook(_ book: Book) {
        cacheQueue.async {
            self.bookDetailsCache[book.id] = book
            self.saveToDisk(book, key: "book_\(book.id)")
        }
    }
    
    // KEEP: Existing getCached methods (they read from memory cache)
    func getCachedBooks(for libraryId: String) -> [Book]? {
        cacheQueue.sync {
            // Check memory first
            if let cached = booksCache[libraryId] {
                return cached
            }
            
            // Try disk if not in memory
            if let diskCached: [Book] = loadFromDisk(key: "books_\(libraryId)") {
                booksCache[libraryId] = diskCached  // Populate memory cache
                return diskCached
            }
            
            return nil
        }
    }
    
    func getCachedBook(bookId: String) -> Book? {
        cacheQueue.sync {
            // Check memory first
            if let cached = bookDetailsCache[bookId] {
                return cached
            }
            
            // Try disk if not in memory
            if let diskCached: Book = loadFromDisk(key: "book_\(bookId)") {
                bookDetailsCache[bookId] = diskCached
                return diskCached
            }
            
            return nil
        }
    }
    
    func cacheAuthors(_ authors: [Author], for libraryId: String) {
        cacheQueue.async {
            self.authorsCache[libraryId] = authors
            self.saveToDisk(authors, key: "authors_\(libraryId)")
        }
    }
    
    func getCachedAuthors(for libraryId: String) -> [Author]? {
        cacheQueue.sync {
            // Check memory first
            if let cached = authorsCache[libraryId] {
                return cached
            }
            
            // Try disk if not in memory
            if let diskCached: [Author] = loadFromDisk(key: "authors_\(libraryId)") {
                authorsCache[libraryId] = diskCached
                return diskCached
            }
            
            return nil
        }
    }
    
    func cacheAuthorDetails(_ author: Author, authorId: String) {
        cacheQueue.async {
            self.authorDetailsCache[authorId] = author
            self.saveToDisk(author, key: "author_details_\(authorId)")
        }
    }
    
    func getCachedAuthorDetails(authorId: String) -> Author? {
        cacheQueue.sync {
            // Check memory first
            if let cached = authorDetailsCache[authorId] {
                return cached
            }
            
            // Try disk if not in memory
            if let diskCached: Author = loadFromDisk(key: "author_details_\(authorId)") {
                authorDetailsCache[authorId] = diskCached
                return diskCached
            }
            
            return nil
        }
    }

    
    // Methods for sections and series
    func cacheSections(_ sections: [PersonalizedSection], for libraryId: String) {
        cacheQueue.async {
            self.sectionsCache[libraryId] = sections
            self.saveToDisk(sections, key: "sections_\(libraryId)")
        }
    }
    
    func getCachedSections(for libraryId: String) -> [PersonalizedSection]? {
        cacheQueue.sync {
            if let cached = sectionsCache[libraryId] {
                return cached
            }
            
            if let diskCached: [PersonalizedSection] = loadFromDisk(key: "sections_\(libraryId)") {
                sectionsCache[libraryId] = diskCached
                return diskCached
            }
            
            return nil
        }
    }
    
    func cacheSeries(_ series: [Series], for libraryId: String) {
        cacheQueue.async {
            self.seriesCache[libraryId] = series
            self.saveToDisk(series, key: "series_\(libraryId)")
        }
    }
    
    func getCachedSeries(for libraryId: String) -> [Series]? {
        cacheQueue.sync {
            if let cached = seriesCache[libraryId] {
                return cached
            }
            
            if let diskCached: [Series] = loadFromDisk(key: "series_\(libraryId)") {
                seriesCache[libraryId] = diskCached
                return diskCached
            }
            
            return nil
        }
    }
    
    func clearCache() {
        cacheQueue.async {
            self.booksCache.removeAll()
            self.bookDetailsCache.removeAll()
            self.sectionsCache.removeAll()
            self.seriesCache.removeAll()
            self.authorsCache.removeAll()
            self.authorDetailsCache.removeAll()
            
            // Clear disk cache
            try? self.fileManager.removeItem(at: self.diskCacheURL)
            try? self.fileManager.createDirectory(at: self.diskCacheURL, withIntermediateDirectories: true)
            
            AppLogger.general.debug("[BookCache] Cache cleared")
        }
    }

    
    // Cache timestamp tracking
    func getCacheTimestamp(for key: String) -> Date? {
        let metadataURL = diskCacheURL.appendingPathComponent("\(key)_metadata.json")
        
        guard let data = try? Data(contentsOf: metadataURL),
              let metadata = try? JSONDecoder().decode(CacheMetadata.self, from: data) else {
            return nil
        }
        
        return metadata.timestamp
    }
    
    func clearExpiredCache(maxAge: TimeInterval = 24 * 60 * 60) {
        cacheQueue.async {
            guard let files = try? self.fileManager.contentsOfDirectory(
                at: self.diskCacheURL,
                includingPropertiesForKeys: [.creationDateKey]
            ) else {
                return
            }
            
            let now = Date()
            for file in files {
                guard let creationDate = try? file.resourceValues(forKeys: [.creationDateKey]).creationDate else {
                    continue
                }
                
                if now.timeIntervalSince(creationDate) > maxAge {
                    try? self.fileManager.removeItem(at: file)
                    AppLogger.general.debug("[BookCache] Removed expired: \(file.lastPathComponent)")
                }
            }
        }
    }
    
    // MARK: - Private Disk I/O Methods
    
    private func saveToDisk<T: Encodable>(_ data: T, key: String) {
        let fileURL = diskCacheURL.appendingPathComponent("\(key).json")
        
        guard let encoded = try? JSONEncoder().encode(data) else {
            AppLogger.general.error("[BookCache] Failed to encode: \(key)")
            return
        }
        
        do {
            try encoded.write(to: fileURL)
            
            // Save metadata with timestamp
            let metadata = CacheMetadata(timestamp: Date())
            let metadataURL = diskCacheURL.appendingPathComponent("\(key)_metadata.json")
            if let metadataData = try? JSONEncoder().encode(metadata) {
                try metadataData.write(to: metadataURL)
            }
            
            AppLogger.general.debug("[BookCache] Saved to disk: \(key)")
        } catch {
            AppLogger.general.error("[BookCache] Failed to write: \(key) - \(error)")
        }
    }
    
    private func loadFromDisk<T: Decodable>(key: String) -> T? {
        let fileURL = diskCacheURL.appendingPathComponent("\(key).json")
        
        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        
        // Check if expired
        if let timestamp = getCacheTimestamp(for: key),
           Date().timeIntervalSince(timestamp) > maxCacheAge {
            AppLogger.general.debug("[BookCache] Expired: \(key)")
            try? fileManager.removeItem(at: fileURL)
            return nil
        }
        
        guard let decoded = try? JSONDecoder().decode(T.self, from: data) else {
            AppLogger.general.error("[BookCache] Failed to decode: \(key)")
            return nil
        }
        
        AppLogger.general.debug("[BookCache] Loaded from disk: \(key)")
        return decoded
    }
    
    private func loadCacheFromDisk() {
        // Load all cached data on init
        // This happens in background, so we don't block initialization
        cacheQueue.async {
            // Implementation: scan directory and load all .json files
            // Not critical for first version - cache will populate on-demand via getCached methods
            AppLogger.general.debug("[BookCache] Ready to load from disk on-demand")
        }
    }
}

// MARK: - Cache Metadata

private struct CacheMetadata: Codable {
    let timestamp: Date
}
