import Foundation

// MARK: - Protocol
// Erbt von Sendable, damit es sicher referenziert werden kann
protocol FetchBooksUseCaseProtocol: Sendable {
    func execute(libraryId: String, collapseSeries: Bool) async throws -> [Book]
}

// MARK: - Implementation
// final + Sendable: Stateless logic container
final class FetchBooksUseCase: FetchBooksUseCaseProtocol, Sendable {
    private let bookRepository: BookRepositoryProtocol
    
    init(bookRepository: BookRepositoryProtocol) {
        self.bookRepository = bookRepository
    }
    
    func execute(libraryId: String, collapseSeries: Bool = false) async throws -> [Book] {
        return try await bookRepository.fetchBooks(
            libraryId: libraryId,
            collapseSeries: collapseSeries
        )
    }
}
