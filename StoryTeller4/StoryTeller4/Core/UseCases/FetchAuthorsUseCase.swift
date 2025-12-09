
import Foundation

protocol FetchAuthorsUseCaseProtocol {
    func execute(libraryId: String) async throws -> [Author]
}

class FetchAuthorsUseCase: FetchAuthorsUseCaseProtocol {
    private let bookRepository: BookRepositoryProtocol
    
    init(bookRepository: BookRepositoryProtocol) {
        self.bookRepository = bookRepository
    }
    
    func execute(libraryId: String) async throws -> [Author] {
        let authors = try await bookRepository.fetchAuthors(libraryId: libraryId)
        
        // Optional: Business Logic hier
        // z.B. Sortierung, Filterung von Autoren ohne Bücher, etc.
        return authors
            .filter { ($0.numBooks ?? 0) > 0 }
            .sorted { $0.name < $1.name }    }
}
