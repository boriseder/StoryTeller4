import Foundation

protocol FetchPersonalizedSectionsUseCaseProtocol {
    func execute(libraryId: String) async throws -> [PersonalizedSection]
}

class FetchPersonalizedSectionsUseCase: FetchPersonalizedSectionsUseCaseProtocol {
    private let bookRepository: BookRepositoryProtocol
    
    init(bookRepository: BookRepositoryProtocol) {
        self.bookRepository = bookRepository
    }
    
    func execute(libraryId: String) async throws -> [PersonalizedSection] {
        return try await bookRepository.fetchPersonalizedSections(libraryId: libraryId)
    }
}
