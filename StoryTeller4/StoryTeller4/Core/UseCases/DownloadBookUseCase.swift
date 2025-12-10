import Foundation

protocol DownloadBookUseCaseProtocol: Sendable {
    @MainActor func execute(book: Book, api: AudiobookshelfClient) async
    @MainActor func cancel(bookId: String)
    @MainActor func delete(bookId: String)
}

final class DownloadBookUseCase: DownloadBookUseCaseProtocol, Sendable {
    // DownloadManager is @MainActor isolated, so holding a reference is safe in a Sendable class
    // but interacting with it generally requires @MainActor context or await.
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
