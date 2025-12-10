import Foundation

// MARK: - Protocol
protocol DownloadRepository: Sendable {
    @MainActor func downloadBook(_ book: Book, api: AudiobookshelfClient) async throws
    @MainActor func cancelDownload(for bookId: String)
    @MainActor func cancelAllDownloads()
    @MainActor func deleteBook(_ bookId: String)
    @MainActor func deleteAllBooks()
    @MainActor func getDownloadedBooks() -> [Book]
    @MainActor func preloadDownloadedBooks() async -> [Book]
    @MainActor func isBookDownloaded(_ bookId: String) -> Bool
    @MainActor func getOfflineStatus(for bookId: String) -> OfflineStatus
    @MainActor func getDownloadStatus(for bookId: String) -> DownloadStatus
    @MainActor func getDownloadProgress(for bookId: String) -> Double
    @MainActor func getLocalAudioURL(for bookId: String, chapterIndex: Int) -> URL?
    @MainActor func getLocalCoverURL(for bookId: String) -> URL?
    @MainActor func getTotalDownloadSize() -> Int64
    @MainActor func getBookStorageSize(_ bookId: String) -> Int64
    @MainActor func bookDirectory(for bookId: String) -> URL
    
    @MainActor var onProgress: DownloadProgressCallback? { get set }
}

// MARK: - Default Implementation
@MainActor
final class DefaultDownloadRepository: DownloadRepository {
    
    private let orchestrationService: DownloadOrchestrationService
    private let storageService: DownloadStorageService
    private let validationService: DownloadValidationService
    private let healingService: BackgroundHealingService
    
    private weak var downloadManager: DownloadManager?
    
    var onProgress: DownloadProgressCallback?
    
    private var downloadTasks: [String: Task<Void, Never>] = [:]
    
    init(
        orchestrationService: DownloadOrchestrationService,
        storageService: DownloadStorageService,
        validationService: DownloadValidationService,
        healingService: BackgroundHealingService,
        downloadManager: DownloadManager
    ) {
        self.orchestrationService = orchestrationService
        self.storageService = storageService
        self.validationService = validationService
        self.healingService = healingService
        self.downloadManager = downloadManager
        
        loadDownloadedBooks()
        healingService.start()
    }
    
    func downloadBook(_ book: Book, api: AudiobookshelfClient) async throws {
        guard storageService.checkAvailableStorage(requiredSpace: 500_000_000) else {
            throw DownloadError.insufficientStorage
        }
        
        guard !isBookDownloaded(book.id),
              let manager = downloadManager,
              !manager.isDownloadingBook(book.id) else {
            return
        }
        
        let task = Task {
            guard let manager = self.downloadManager else { return }
            manager.isDownloading[book.id] = true
            manager.downloadProgress[book.id] = 0.0
            manager.downloadStage[book.id] = .preparing
            manager.downloadStatus[book.id] = "Preparing..."
            
            do {
                try await self.orchestrationService.downloadBook(book, api: api) { bookId, progress, status, stage in
                    Task { @MainActor in
                        guard let manager = self.downloadManager else { return }
                        manager.downloadProgress[bookId] = progress
                        manager.downloadStatus[bookId] = status
                        manager.downloadStage[bookId] = stage
                    }
                }
                
                if let downloadedBook = self.loadBook(bookId: book.id) {
                    manager.downloadedBooks.append(downloadedBook)
                    manager.isDownloading[book.id] = false
                    manager.downloadProgress[book.id] = 1.0
                    manager.downloadStage[book.id] = .complete
                    manager.downloadStatus[book.id] = "Complete"
                    
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    manager.downloadStatus.removeValue(forKey: book.id)
                    manager.downloadStage.removeValue(forKey: book.id)
                }
            } catch {
                self.handleDownloadFailure(bookId: book.id, error: error.localizedDescription)
            }
        }
        
        downloadTasks[book.id] = task
        await task.value
        downloadTasks.removeValue(forKey: book.id)
    }
    
    private func handleDownloadFailure(bookId: String, error: String) {
        guard let manager = self.downloadManager else { return }
        manager.isDownloading[bookId] = false
        manager.downloadProgress[bookId] = 0.0
        manager.downloadStage[bookId] = .failed
        manager.downloadStatus[bookId] = error
        
        let bookDir = storageService.bookDirectory(for: bookId)
        try? storageService.deleteBookDirectory(at: bookDir)
    }
    
    func cancelDownload(for bookId: String) {
        orchestrationService.cancelDownload(for: bookId)
        downloadTasks[bookId]?.cancel()
        downloadTasks.removeValue(forKey: bookId)
    }
    
    func cancelAllDownloads() {
        for bookId in downloadTasks.keys { cancelDownload(for: bookId) }
    }
    
    func deleteBook(_ bookId: String) {
        let bookDir = storageService.bookDirectory(for: bookId)
        do {
            try storageService.deleteBookDirectory(at: bookDir)
            downloadManager?.downloadedBooks.removeAll { $0.id == bookId }
            downloadManager?.downloadProgress.removeValue(forKey: bookId)
            downloadManager?.isDownloading.removeValue(forKey: bookId)
        } catch {
            AppLogger.general.error("Failed to delete book: \(error)")
        }
    }
    
    func deleteAllBooks() {
        let allBooks = getDownloadedBooks()
        for book in allBooks { deleteBook(book.id) }
    }
    
    func getDownloadedBooks() -> [Book] {
        return downloadManager?.downloadedBooks ?? []
    }
    
    func preloadDownloadedBooks() async -> [Book] {
        let books = storageService.loadDownloadedBooks()
            .filter { validationService.validateBookIntegrity(bookId: $0.id, storageService: storageService).isValid }
        downloadManager?.downloadedBooks = books
        return books
    }
    
    func isBookDownloaded(_ bookId: String) -> Bool {
        return downloadManager?.downloadedBooks.contains(where: { $0.id == bookId }) ?? false
    }

    func getOfflineStatus(for bookId: String) -> OfflineStatus {
        if downloadManager?.isDownloadingBook(bookId) == true { return .downloading }
        if isBookDownloaded(bookId) { return .available }
        return .notDownloaded
    }
    
    func getDownloadStatus(for bookId: String) -> DownloadStatus {
        let status = getOfflineStatus(for: bookId)
        return DownloadStatus(
            isDownloaded: status == .available,
            isDownloading: status == .downloading
        )
    }
    
    func getDownloadProgress(for bookId: String) -> Double {
        return downloadManager?.downloadProgress[bookId] ?? 0.0
    }
    
    func getLocalAudioURL(for bookId: String, chapterIndex: Int) -> URL? {
        return storageService.getLocalAudioURL(for: bookId, chapterIndex: chapterIndex)
    }
    
    func getLocalCoverURL(for bookId: String) -> URL? {
        return storageService.getLocalCoverURL(for: bookId)
    }
    
    func getTotalDownloadSize() -> Int64 {
        return storageService.getTotalDownloadSize()
    }
    
    func getBookStorageSize(_ bookId: String) -> Int64 {
        return storageService.getBookStorageSize(bookId)
    }
    
    func bookDirectory(for bookId: String) -> URL {
        return storageService.bookDirectory(for: bookId)
    }
    
    private func loadDownloadedBooks() {
        let books = storageService.loadDownloadedBooks()
        let validBooks = books.filter { book in
            validationService.validateBookIntegrity(bookId: book.id, storageService: storageService).isValid
        }
        downloadManager?.downloadedBooks = validBooks
    }
    
    private func loadBook(bookId: String) -> Book? {
        let metadataFile = storageService.bookDirectory(for: bookId).appendingPathComponent("metadata.json")
        guard let data = try? Data(contentsOf: metadataFile),
              let book = try? JSONDecoder().decode(Book.self, from: data) else {
            return nil
        }
        return book
    }
    
    deinit {
        let service = healingService
        // Fix: Use MainActor task to call methods on main-actor isolated property
        Task { @MainActor in
            service.stop()
        }
        for (_, task) in downloadTasks { task.cancel() }
    }
}
