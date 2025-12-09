import Foundation

protocol FetchSeriesBooksUseCaseProtocol {
    func execute(libraryId: String, seriesId: String) async throws -> [Book]
}

class FetchSeriesBooksUseCase: FetchSeriesBooksUseCaseProtocol {
    private let api: AudiobookshelfClient
    
    init(api: AudiobookshelfClient) {
        self.api = api
    }
    
    func execute(libraryId: String, seriesId: String) async throws -> [Book] {
        return try await api.series.fetchSeriesBooks(libraryId: libraryId, seriesId: seriesId)
    }
}
