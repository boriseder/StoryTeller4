import Foundation

protocol FetchBooksUseCaseProtocol {
    func execute(
        libraryId: String,
        collapseSeries: Bool
    ) async throws -> [Book]
}

class FetchBooksUseCase: FetchBooksUseCaseProtocol {
    private let bookRepository: BookRepositoryProtocol
    
    init(bookRepository: BookRepositoryProtocol) {
        self.bookRepository = bookRepository
    }
    
    func execute(
        libraryId: String,
        collapseSeries: Bool = false
    ) async throws -> [Book] {
        return try await bookRepository.fetchBooks(
            libraryId: libraryId,
            collapseSeries: collapseSeries
        )
    }
}
