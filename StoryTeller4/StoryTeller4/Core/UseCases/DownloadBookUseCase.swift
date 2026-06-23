import Foundation

protocol DownloadBookUseCaseProtocol: Sendable {
    @MainActor func execute(book: Book, api: AudiobookshelfClient) async
    @MainActor func cancel(bookId: String)
    @MainActor func delete(bookId: String)
}

// MARK: - DownloadBookUseCase
//
// Thin orchestration layer between ViewModels and DownloadManager.
// ViewModels should prefer this over calling DownloadManager directly
// so that the download entry-point is a single, testable seam.

final class DownloadBookUseCase: DownloadBookUseCaseProtocol, Sendable {

    private let downloadManager: DownloadManager

    init(downloadManager: DownloadManager) {
        self.downloadManager = downloadManager
    }

    @MainActor
    func execute(book: Book, api: AudiobookshelfClient) async {
        await downloadManager.downloadBook(book, api: api)
    }

    @MainActor
    func cancel(bookId: String) {
        downloadManager.cancelDownload(for: bookId)
    }

    @MainActor
    func delete(bookId: String) {
        downloadManager.deleteBook(bookId)
    }
}
