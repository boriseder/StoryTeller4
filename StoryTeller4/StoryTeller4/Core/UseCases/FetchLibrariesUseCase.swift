import Foundation

protocol FetchLibrariesUseCaseProtocol {
    func execute(api: AudiobookshelfClient) async throws -> [Library]
}

class FetchLibrariesUseCase: FetchLibrariesUseCaseProtocol {
    func execute(api: AudiobookshelfClient) async throws -> [Library] {
        return try await api.libraries.fetchLibraries()
    }
}
