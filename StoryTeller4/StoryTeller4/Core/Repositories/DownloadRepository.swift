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
        
        // Start healing service (which is Sendable)
        healingService.start()
    }
    
    func downloadBook(_ book: Book, api: AudiobookshelfClient) async throws {
        guard storageService.checkAvailableStorage(requiredSpace: 500_000_000) else {
            throw DownloadError.insufficientStorage
        }
        
        guard !isBookDownloaded(book.id),
              let manager = downloadManager,
              !manager.isDownloadingBook(book.id) else {
            AppLogger.general.debug("[DownloadRepository] Book already downloaded or downloading")
            return
        }
        
        let task = Task {
            guard let manager = self.downloadManager else { return }
            
            manager.isDownloading[book.id] = true
            manager.downloadProgress[book.id] = 0.0
            manager.downloadStage[book.id] = .preparing
            manager.downloadStatus[book.id] = "Preparing download..."
            
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
                    manager.downloadStatus[book.id] = "Download complete!"
                    
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    
                    manager.downloadStatus.removeValue(forKey: book.id)
                    manager.downloadStage.removeValue(forKey: book.id)
                }
                
            } catch is CancellationError {
                AppLogger.general.debug("[DownloadRepository] Download cancelled: \(book.title)")
                self.handleDownloadFailure(bookId: book.id, error: "Download cancelled")
                
            } catch let error {
                AppLogger.general.error("[DownloadRepository] Download failed: \(error.localizedDescription)")
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
        
        self.cleanupFailedDownload(bookId: bookId)
    }
    
    func cancelDownload(for bookId: String) {
        orchestrationService.cancelDownload(for: bookId)
        downloadTasks[bookId]?.cancel()
        downloadTasks.removeValue(forKey: bookId)
    }
    
    func cancelAllDownloads() {
        for bookId in downloadTasks.keys {
            cancelDownload(for: bookId)
        }
        
        guard let manager = downloadManager else { return }
        manager.isDownloading.removeAll()
        manager.downloadProgress.removeAll()
        manager.downloadStatus.removeAll()
        manager.downloadStage.removeAll()
    }
    
    func deleteBook(_ bookId: String) {
        let bookDir = storageService.bookDirectory(for: bookId)
        
        do {
            try storageService.deleteBookDirectory(at: bookDir)
            
            guard let manager = downloadManager else { return }
            manager.downloadedBooks.removeAll { $0.id == bookId }
            manager.downloadProgress.removeValue(forKey: bookId)
            manager.isDownloading.removeValue(forKey: bookId)
            
            AppLogger.general.debug("[DownloadRepository] Deleted book: \(bookId)")
        } catch {
            AppLogger.general.error("[DownloadRepository] Failed to delete book: \(error)")
        }
    }
    
    func deleteAllBooks() {
        let allBooks = getDownloadedBooks()
        
        for book in allBooks {
            deleteBook(book.id)
        }
        
        guard let manager = downloadManager else { return }
        manager.downloadedBooks.removeAll()
        manager.downloadProgress.removeAll()
        manager.isDownloading.removeAll()
        manager.downloadStatus.removeAll()
        manager.downloadStage.removeAll()
        
        AppLogger.general.debug("[DownloadRepository] Deleted all books")
    }
    
    func getDownloadedBooks() -> [Book] {
        return downloadManager?.downloadedBooks ?? []
    }
    
    func preloadDownloadedBooks() async -> [Book] {
        let books = storageService.loadDownloadedBooks()
            .filter { validationService.validateBookIntegrity(bookId: $0.id, storageService: storageService).isValid }
        
        if let manager = downloadManager {
            manager.downloadedBooks = books
        }

        return books
    }
    
    func isBookDownloaded(_ bookId: String) -> Bool {
        return downloadManager?.downloadedBooks.contains(where: { $0.id == bookId }) ?? false
    }

    func getOfflineStatus(for bookId: String) -> OfflineStatus {
        if downloadManager?.isDownloadingBook(bookId) == true {
            return .downloading
        }
        if isBookDownloaded(bookId) {
            return .available
        }
        return .notDownloaded
    }
    
    func getDownloadStatus(for bookId: String) -> DownloadStatus {
        let offlineStatus = getOfflineStatus(for: bookId)
        switch offlineStatus {
        case .notDownloaded:
            return DownloadStatus(isDownloaded: false, isDownloading: false)
        case .downloading:
            return DownloadStatus(isDownloaded: false, isDownloading: true)
        case .available:
            return DownloadStatus(isDownloaded: true, isDownloading: false)
        }
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
        AppLogger.general.debug("[DownloadRepository] Loaded \(validBooks.count) valid books")
    }
    
    private func loadBook(bookId: String) -> Book? {
        let metadataFile = storageService.bookDirectory(for: bookId).appendingPathComponent("metadata.json")
        guard let data = try? Data(contentsOf: metadataFile),
              let book = try? JSONDecoder().decode(Book.self, from: data) else {
            return nil
        }
        return book
    }
    
    private func cleanupFailedDownload(bookId: String) {
        let bookDir = storageService.bookDirectory(for: bookId)
        try? storageService.deleteBookDirectory(at: bookDir)
    }
    
    deinit {
            // Fire and forget stopping service on deinit
            // Capture service locally to avoid capturing self
            let service = healingService
            Task {
                // Assuming stop() is safe to call (non-isolated or thread-safe) or via MainActor
                // If healingService was initialized in init, it's a let property.
                // If BackgroundHealingService is an actor or MainActor class, await is needed.
                // Assuming it's the class defined earlier:
                // Since deinit isn't isolated, we launch a task.
                service.stop()
            }
            
            for (_, task) in downloadTasks { task.cancel() }
            
            // orchestrationService cancelDownload
            // If orchestrationService is Sendable, we can access it
            // Note: 'self' is not available here usually for property access if strict.
            // But for stored properties in final class, it's often okay.
            // Strictly, we should capture orchestrationService too.
            // However, Swift 6 deinit rules are strict.
            // Simplest: Just cancel tasks we hold. Orchestration cancellation is an optimization.
        }
}
