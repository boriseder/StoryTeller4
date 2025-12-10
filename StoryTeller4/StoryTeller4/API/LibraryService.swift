import Foundation

protocol LibraryServiceProtocol: Sendable {
    func fetchLibraries() async throws -> [Library]
    func fetchLibraryStats(libraryId: String) async throws -> Int
}

final class DefaultLibraryService: LibraryServiceProtocol, Sendable {
    private let config: APIConfig
    private let networkService: NetworkService
    
    init(config: APIConfig, networkService: NetworkService) {
        self.config = config
        self.networkService = networkService
    }
    
    func fetchLibraries() async throws -> [Library] {
        guard let url = URL(string: "\(config.baseURL)/api/libraries") else {
            throw AudiobookshelfError.invalidURL("\(config.baseURL)/api/libraries")
        }
        
        let request = networkService.createAuthenticatedRequest(url: url, authToken: config.authToken)
        let response: LibrariesResponse = try await networkService.performRequest(request, responseType: LibrariesResponse.self)
        
        // Filter directly by mediaType to avoid property dependency issues if model is out of sync
        return response.libraries.filter { $0.mediaType == "book" }
    }
    
    func fetchLibraryStats(libraryId: String) async throws -> Int {
        guard let url = URL(string: "\(config.baseURL)/api/libraries/\(libraryId)/items?limit=1") else {
            throw AudiobookshelfError.invalidURL("\(config.baseURL)/api/libraries/\(libraryId)/items")
        }
        
        let request = networkService.createAuthenticatedRequest(url: url, authToken: config.authToken)
        let response: LibraryItemsResponse = try await networkService.performRequest(
            request,
            responseType: LibraryItemsResponse.self
        )
        
        AppLogger.general.debug("[LibraryService] Library \(libraryId) has \(response.total ?? 0) total books")
        
        return response.total ?? 0
    }
}
