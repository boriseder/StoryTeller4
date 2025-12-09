import Foundation

protocol DownloadBookUseCaseProtocol {
    func execute(book: Book, api: AudiobookshelfClient) async
    func cancel(bookId: String)
    func delete(bookId: String)
}

class DownloadBookUseCase: DownloadBookUseCaseProtocol {
    private let downloadManager: DownloadManager
    
    init(downloadManager: DownloadManager) {
        self.downloadManager = downloadManager
    }
    
    func execute(book: Book, api: AudiobookshelfClient) async {
        await downloadManager.downloadBook(book, api: api)
    }
    
    func cancel(bookId: String) {
        downloadManager.cancelDownload(for: bookId)
    }
    
    func delete(bookId: String) {
        downloadManager.deleteBook(bookId)
    }
}
