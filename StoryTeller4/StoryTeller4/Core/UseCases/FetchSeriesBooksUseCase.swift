import Foundation

protocol FetchSeriesBooksUseCaseProtocol: Sendable {
    func execute(libraryId: String, seriesId: String) async throws -> [Book]
}

// BookRepository muss fetchSeriesBooks(libraryId:seriesId:) implementieren
final class FetchSeriesBooksUseCase: FetchSeriesBooksUseCaseProtocol {
    private let bookRepository: BookRepositoryProtocol

    init(bookRepository: BookRepositoryProtocol) {
        self.bookRepository = bookRepository
    }

    func execute(libraryId: String, seriesId: String) async throws -> [Book] {
        return try await bookRepository.fetchSeriesBooks(libraryId: libraryId, seriesId: seriesId)
    }
}
