import Foundation

protocol DownloadBookUseCaseProtocol: Sendable {
    @MainActor func execute(book: Book, api: AudiobookshelfClient) async throws
    @MainActor func cancel(bookId: String)
    @MainActor func delete(bookId: String)
}

// MARK: - DownloadBookUseCase
//
// Routes through DownloadRepository (data layer) instead of DownloadManager
// (UI state layer). DownloadManager is a SwiftUI state holder — use cases
// must not depend on it. The repository is the correct entry point for
// download business logic.
//
// execute() now throws so callers can surface DownloadError.insufficientStorage
// and other domain errors rather than silently swallowing them.

final class DownloadBookUseCase: DownloadBookUseCaseProtocol, Sendable {

    private let repository: any DownloadRepository

    init(repository: any DownloadRepository) {
        self.repository = repository
    }

    @MainActor
    func execute(book: Book, api: AudiobookshelfClient) async throws {
        try await repository.downloadBook(book, api: api)
    }

    @MainActor
    func cancel(bookId: String) {
        repository.cancelDownload(for: bookId)
    }

    @MainActor
    func delete(bookId: String) {
        repository.deleteBook(bookId)
    }
}
