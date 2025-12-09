import Foundation

class AudiobookshelfClient {
    let connection: ConnectionServiceProtocol
    let libraries: LibraryServiceProtocol
    let books: BookServiceProtocol
    let series: SeriesServiceProtocol
    let authors: AuthorsServiceProtocol
    let personalized: PersonalizedServiceProtocol
    let progress: ProgressServiceProtocol
    let bookmarks: BookmarkServiceProtocol
    let converter: BookConverterProtocol

    private let apiConfig: APIConfig    // Dirty hack #1

    init(
        baseURL: String,
        authToken: String,
        networkService: NetworkService = DefaultNetworkService()
    ) {
        let config = APIConfig(baseURL: baseURL, authToken: authToken)
        let converter = DefaultBookConverter()
        let rateLimiter = RateLimiter(minimumInterval: 0.1)
        
        self.connection = DefaultConnectionService(config: config, networkService: networkService)
        self.libraries = DefaultLibraryService(config: config, networkService: networkService)
        self.books = DefaultBookService(config: config, networkService: networkService, converter: converter, rateLimiter: rateLimiter)
        self.series = DefaultSeriesService(config: config, networkService: networkService, converter: converter)
        self.authors = DefaultAuthorsService(config: config, networkService: networkService, rateLimiter: rateLimiter)
        self.personalized = DefaultPersonalizedService(config: config, networkService: networkService)
        self.progress = DefaultProgressService(config: config, networkService: networkService)
        self.bookmarks = DefaultBookmarkService(config: config, networkService: networkService)
        self.converter = converter
        
        
        self.apiConfig = config  // speichern
        
    }
    
    var baseURLString: String { apiConfig.baseURL }
    var authToken: String { apiConfig.authToken }

}
