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
        let encodedSeriesId = encodeSeriesId(seriesId)
        
        var components = URLComponents(string: "\(config.baseURL)/api/libraries/\(libraryId)/items")!
        components.queryItems = [
            URLQueryItem(name: "limit", value: "1000"),
            URLQueryItem(name: "filter", value: "series.\(encodedSeriesId)")
        ]
        
        guard let url = components.url else {
            throw AudiobookshelfError.invalidURL("\(config.baseURL)/api/libraries/\(libraryId)/items")
        }
        
        let request = networkService.createAuthenticatedRequest(url: url, authToken: config.authToken)
        
        do {
            let response: LibraryItemsResponse = try await networkService.performRequest(
                request,
                responseType: LibraryItemsResponse.self
            )
            
            let books = response.results.compactMap { converter.convertLibraryItemToBook($0) }
            return BookSortHelpers.sortByBookNumber(books)
            
        } catch {
            AppLogger.general.debug("[SeriesService] fetchSeriesBooks error: \(error)")
            throw error
        }
    }
    
    private func encodeSeriesId(_ seriesId: String) -> String {
        guard let data = seriesId.data(using: .utf8) else {
            return seriesId
        }
        
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
