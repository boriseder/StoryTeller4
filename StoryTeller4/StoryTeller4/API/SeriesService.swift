import Foundation

protocol SeriesServiceProtocol {
    func fetchSeries(libraryId: String, limit: Int) async throws -> [Series]
    func fetchSeriesBooks(libraryId: String, seriesId: String) async throws -> [Book]
}

class DefaultSeriesService: SeriesServiceProtocol {
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
            return response.results.map { $0.toSeries() }
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
            
            AppLogger.general.debug("[SeriesService] fetchSeriesBooks found \(response.results.count) books")
            
            let books = response.results.compactMap { converter.convertLibraryItemToBook($0) }
            return BookSortHelpers.sortByBookNumber(books)
            
        } catch {
            AppLogger.general.debug("[SeriesService] fetchSeriesBooks error: \(error)")
            throw error
        }
    }
    
    private func encodeSeriesId(_ seriesId: String) -> String {
        guard let data = seriesId.data(using: .utf8) else {
            AppLogger.general.debug("[SeriesService] Failed to encode series ID to UTF-8: \(seriesId)")
            return seriesId
        }
        
        let base64 = data.base64EncodedString()
        let urlSafe = base64
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        
        AppLogger.general.debug("[SeriesService] Series ID encoding: '\(seriesId)' -> '\(urlSafe)'")
        
        return urlSafe
    }
}
