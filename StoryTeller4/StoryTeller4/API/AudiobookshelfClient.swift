import Foundation

// MARK: - AudiobookshelfClient
//
// Marked @unchecked Sendable because all stored properties are either
// immutable (let) value types (APIConfig) or service objects that are
// themselves stateless after construction. No mutable shared state exists
// after init completes, making cross-actor use safe in practice.
//
// Combine import removed — nothing in this file used it.

final class AudiobookshelfClient: @unchecked Sendable {
    let connection: any ConnectionServiceProtocol
    let libraries: any LibraryServiceProtocol
    let books: any BookServiceProtocol
    let series: any SeriesServiceProtocol
    let authors: any AuthorsServiceProtocol
    let personalized: any PersonalizedServiceProtocol
    let progress: any ProgressServiceProtocol
    let bookmarks: any BookmarkServiceProtocol
    let converter: any BookConverterProtocol

    private let apiConfig: APIConfig

    init(
        baseURL: String,
        authToken: String,
        networkService: NetworkService = DefaultNetworkService()
    ) {
        let config = APIConfig(baseURL: baseURL, authToken: authToken)
        let converter = DefaultBookConverter()
        let rateLimiter = RateLimiter(minimumInterval: 0.1)

        self.connection  = DefaultConnectionService(config: config, networkService: networkService)
        self.libraries   = DefaultLibraryService(config: config, networkService: networkService)
        self.books       = DefaultBookService(config: config, networkService: networkService, converter: converter, rateLimiter: rateLimiter)
        self.series      = DefaultSeriesService(config: config, networkService: networkService, converter: converter)
        self.authors     = DefaultAuthorsService(config: config, networkService: networkService, rateLimiter: rateLimiter)
        self.personalized = DefaultPersonalizedService(config: config, networkService: networkService)
        self.progress    = DefaultProgressService(config: config, networkService: networkService)
        self.bookmarks   = DefaultBookmarkService(config: config, networkService: networkService)
        self.converter   = converter
        self.apiConfig   = config
    }

    var baseURLString: String { apiConfig.baseURL }
    var authToken: String { apiConfig.authToken }
}
