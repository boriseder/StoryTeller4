import Foundation

protocol FetchSeriesUseCaseProtocol {
    func execute(libraryId: String) async throws -> [Series]
}

class FetchSeriesUseCase: FetchSeriesUseCaseProtocol {
    private let bookRepository: BookRepositoryProtocol
    
    init(bookRepository: BookRepositoryProtocol) {
        self.bookRepository = bookRepository
    }
    
    func execute(libraryId: String) async throws -> [Series] {
        return try await bookRepository.fetchSeries(libraryId: libraryId)
    }
}
