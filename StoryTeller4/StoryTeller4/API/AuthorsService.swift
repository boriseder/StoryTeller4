import Foundation

protocol AuthorsServiceProtocol {
    func fetchAuthors(libraryId: String) async throws -> [Author]
    func fetchAuthor(authorId: String, libraryId: String, includeBooks: Bool, includeSeries: Bool) async throws -> Author
}

class DefaultAuthorsService: AuthorsServiceProtocol {
    private let config: APIConfig
    private let networkService: NetworkService
    private let rateLimiter: RateLimiter
    
    init(config: APIConfig, networkService: NetworkService, rateLimiter: RateLimiter) {
        self.config = config
        self.networkService = networkService
        self.rateLimiter = rateLimiter
    }
    
    func fetchAuthors(libraryId: String) async throws -> [Author] {
        await rateLimiter.waitIfNeeded()
        
        guard let url = URL(string: "\(config.baseURL)/api/libraries/\(libraryId)/authors") else {
            throw AudiobookshelfError.invalidURL("\(config.baseURL)/api/libraries/\(libraryId)/authors")
        }
        
        AppLogger.general.debug("[AuthorService] Fetching authors from URL: \(url)")
        
        let request = networkService.createAuthenticatedRequest(url: url, authToken: config.authToken)
        let response: AuthorsResponse = try await networkService.performRequest(request, responseType: AuthorsResponse.self)
        
        return response.authors
    }
    func fetchAuthor(
        authorId: String,
        libraryId: String,
        includeBooks: Bool,
        includeSeries: Bool,
        
    ) async throws -> Author {
        
        await rateLimiter.waitIfNeeded()
        
        // Build URL with query parameters
        var components = URLComponents(string: "\(config.baseURL)/api/authors/\(authorId)")
        
        // Build include parameter values
        let includeItems = [
            includeBooks ? "items" : nil,
            includeSeries ? "series" : nil
        ].compactMap { $0 }
        
        // Set query items for include and library
        components?.queryItems = [
            URLQueryItem(name: "include", value: includeItems.joined(separator: ",")),
            URLQueryItem(name: "library", value: libraryId)
        ]
        
        // Get final URL with query parameters
        guard let url = components?.url else {
            throw AudiobookshelfError.invalidURL("\(config.baseURL)/api/authors/\(authorId)")
        }
        
        AppLogger.general.debug("[AuthorService] Fetching author details from URL: \(url.absoluteString)")
        
        let request = networkService.createAuthenticatedRequest(url: url, authToken: config.authToken)
        
        // Decode Author directly (no wrapper object for author details endpoint)
        let author: Author = try await networkService.performRequest(
            request,
            responseType: Author.self
        )
        
        return author
    }
}
