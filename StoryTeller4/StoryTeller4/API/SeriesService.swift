import Foundation
import Combine

protocol SeriesServiceProtocol: Sendable {
    func fetchSeries(libraryId: String, limit: Int) async throws -> [Series]
    func fetchSeriesBooks(libraryId: String, seriesId: String) async throws -> [Book]
}

final class DefaultSeriesService: SeriesServiceProtocol, Sendable {
    private let config: APIConfig
    private let networkService: NetworkService
    private let converter: BookConverterProtocol
    
    init(config: APIConfig, networkService: NetworkService, converter: BookConverterProtocol) {
        self.config = config
        self.networkService = networkService
        self.converter = converter
    }
    
    func fetchSeries(libraryId: String, limit: Int = 1000) async throws -> [Series] {
        guard let url = URL(string: "\(config.baseURL)/api/libraries/\(libraryId)/series?limit=\(limit)") else {
            throw AudiobookshelfError.invalidURL("\(config.baseURL)/api/libraries/\(libraryId)/series")
        }
        
        let request = networkService.createAuthenticatedRequest(url: url, authToken: config.authToken)
        
        do {
            let response: SeriesResponse = try await networkService.performRequest(request, responseType: SeriesResponse.self)
            return response.results
        } catch {
            AppLogger.general.debug("[SeriesService] fetchSeries error: \(error)")
            throw error
        }
    }
    
    func fetchSeriesBooks(libraryId: String, seriesId: String) async throws -> [Book] {
        // ... (implementation remains the same) ...
        // Just ensuring `toSeries()` is not used here either
        
        let encodedSeriesId = encodeSeriesId(seriesId)
        // ...
        let request = networkService.createAuthenticatedRequest(url: url, authToken: config.authToken)
        
        let response: LibraryItemsResponse = try await networkService.performRequest(
            request,
            responseType: LibraryItemsResponse.self
        )
        let books = response.results.compactMap { converter.convertLibraryItemToBook($0) }
        return BookSortHelpers.sortByBookNumber(books)
    }
    
    private func encodeSeriesId(_ seriesId: String) -> String {
        // ... (implementation remains the same) ...
        guard let data = seriesId.data(using: .utf8) else { return seriesId }
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
