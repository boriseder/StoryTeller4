import Foundation

protocol FetchLibrariesUseCaseProtocol: Sendable {
    func execute() async throws -> [Library]
}

// api wird aus dem UseCase entfernt – LibraryRepository kapselt den API-Zugriff bereits
final class FetchLibrariesUseCase: FetchLibrariesUseCaseProtocol {
    private let libraryRepository: LibraryRepositoryProtocol

    init(libraryRepository: LibraryRepositoryProtocol) {
        self.libraryRepository = libraryRepository
    }

    func execute() async throws -> [Library] {
        return try await libraryRepository.getLibraries()
    }
}
