import Foundation
import SwiftUI
import Combine

@MainActor
class DownloadManager: ObservableObject {
    @Published var downloadedBooks: [Book] = []
    @Published var downloadProgress: [String: Double] = [:]
    @Published var isDownloading: [String: Bool] = [:]
    @Published var downloadStatus: [String: String] = [:]
    @Published var downloadStage: [String: DownloadStage] = [:]
    
    internal private(set) var repository: DownloadRepository?
    
    init(repository: DownloadRepository? = nil) {
        if let repository = repository {
            self.repository = repository
        } else {
            Task { @MainActor in
                self.setupDefaultRepository()
            }
        }
        AppLogger.general.debug("[DownloadManager] Initialized with repository pattern")
    }
    
    private func setupDefaultRepository() {
        guard repository == nil else { return }
        
        let networkService = DefaultDownloadNetworkService()
        let storageService = DefaultDownloadStorageService()
        let retryPolicy = ExponentialBackoffRetryPolicy()
        let validationService = DefaultDownloadValidationService()
        let orchestrationService = DefaultDownloadOrchestrationService(
            networkService: networkService,
            storageService: storageService,
            retryPolicy: retryPolicy,
            validationService: validationService
        )
        
        let healingService = DefaultBackgroundHealingService(
            storageService: storageService,
            validationService: validationService,
            onBookRemoved: { [weak self] bookId in
                Task { @MainActor in
                    self?.downloadedBooks.removeAll { $0.id == bookId }
                }
            }
        )
        
        self.repository = DefaultDownloadRepository(
            orchestrationService: orchestrationService,
            storageService: storageService,
            validationService: validationService,
            healingService: healingService,
            downloadManager: self
        )
    }
    
    func downloadBook(_ book: Book, api: AudiobookshelfClient) async {
        guard let repository = repository else { return }
        do { try await repository.downloadBook(book, api: api) } catch {}
    }
    
    func cancelDownload(for bookId: String) { repository?.cancelDownload(for: bookId) }
    func cancelAllDownloads() { repository?.cancelAllDownloads() }
    func deleteBook(_ bookId: String) { repository?.deleteBook(bookId) }
    func deleteAllBooks() { repository?.deleteAllBooks() }
    
    func getOfflineStatus(for bookId: String) -> OfflineStatus {
        return repository?.getOfflineStatus(for: bookId) ?? .notDownloaded
    }
    
    func isBookAvailableOffline(_ bookId: String) -> Bool {
        return getOfflineStatus(for: bookId) == .available
    }
    
    func isBookDownloaded(_ bookId: String) -> Bool {
        return repository?.isBookDownloaded(bookId) ?? false
    }
    
    func getDownloadProgress(for bookId: String) -> Double {
        return downloadProgress[bookId] ?? 0.0
    }
    
    func isDownloadingBook(_ bookId: String) -> Bool {
        return isDownloading[bookId] ?? false
    }
    
    func getLocalAudioURL(for bookId: String, chapterIndex: Int) -> URL? {
        return repository?.getLocalAudioURL(for: bookId, chapterIndex: chapterIndex)
    }
    
    func getLocalCoverURL(for bookId: String) -> URL? {
        return repository?.getLocalCoverURL(for: bookId)
    }
    
    func getTotalDownloadSize() -> Int64 {
        return repository?.getTotalDownloadSize() ?? 0
    }
    
    func getBookStorageSize(_ bookId: String) -> Int64 {
        return repository?.getBookStorageSize(bookId) ?? 0
    }
    
    func bookDirectory(for bookId: String) -> URL {
        guard let repository = repository else {
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let downloadsURL = documentsURL.appendingPathComponent("Downloads", isDirectory: true)
            return downloadsURL.appendingPathComponent(bookId, isDirectory: true)
        }
        return repository.bookDirectory(for: bookId)
    }
    
    func preloadDownloadedBooksCount() async -> Int {
        return await repository?.preloadDownloadedBooks().count ?? 0
    }
}
