import Foundation

// MARK: - Protocol
//
// The repository owns all download business logic and its own transient
// in-flight state. It communicates upward via a single callback —
// onStateChanged — and has zero knowledge of DownloadManager.

protocol DownloadRepository: Sendable {
    /// Fired on @MainActor every time any download state changes.
    /// DownloadManager wires itself in here during configure(repository:).
    @MainActor var onStateChanged: DownloadStateCallback? { get set }

    @MainActor func downloadBook(_ book: Book, api: AudiobookshelfClient) async throws
    @MainActor func cancelDownload(for bookId: String)
    @MainActor func cancelAllDownloads()
    @MainActor func deleteBook(_ bookId: String)
    @MainActor func deleteAllBooks()
    @MainActor func getDownloadedBooks() -> [Book]
    @MainActor func preloadDownloadedBooks() async -> [Book]
    @MainActor func isBookDownloaded(_ bookId: String) -> Bool
    @MainActor func getOfflineStatus(for bookId: String) -> OfflineStatus
    @MainActor func getDownloadProgress(for bookId: String) -> Double
    @MainActor func getLocalAudioURL(for bookId: String, chapterIndex: Int) -> URL?
    @MainActor func getLocalCoverURL(for bookId: String) -> URL?
    @MainActor func getTotalDownloadSize() -> Int64
    @MainActor func getBookStorageSize(_ bookId: String) -> Int64
    @MainActor func bookDirectory(for bookId: String) -> URL
}

// MARK: - Default Implementation

@MainActor
final class DefaultDownloadRepository: DownloadRepository {

    // MARK: - Services (injected, no upward references)

    private let orchestrationService: DownloadOrchestrationService
    private let storageService: DownloadStorageService
    private let validationService: DownloadValidationService
    private let healingService: BackgroundHealingService

    // MARK: - Owned State
    //
    // Previously these lived inside DownloadManager and were mutated from
    // here via a weak reference. They now live where the mutations happen.

    private var downloadedBooks: [Book] = []
    private var activeStates: [String: DownloadState] = [:]
    private var downloadTasks: [String: Task<Void, Never>] = [:]

    // MARK: - Upward Communication (one direction only)

    /// Set by DownloadManager.configure(repository:) — never set from within
    /// this class itself. The repository fires it; it never reads from it.
    var onStateChanged: DownloadStateCallback?

    // MARK: - Init

    init(
        orchestrationService: DownloadOrchestrationService,
        storageService: DownloadStorageService,
        validationService: DownloadValidationService,
        healingService: BackgroundHealingService,
        startHealing: Bool = true
    ) {
        self.orchestrationService = orchestrationService
        self.storageService = storageService
        self.validationService = validationService
        self.healingService = healingService

        loadDownloadedBooks()

        if startHealing {
            healingService.start()
        }
    }

    // MARK: - DownloadRepository

    func downloadBook(_ book: Book, api: AudiobookshelfClient) async throws {
        guard storageService.checkAvailableStorage(requiredSpace: 500_000_000) else {
            throw DownloadError.insufficientStorage
        }

        guard !isBookDownloaded(book.id),
              activeStates[book.id]?.isDownloading != true else {
            return
        }

        let task = Task {
            publish(book.id, DownloadState(
                progress: 0.0,
                stage: .preparing,
                statusMessage: "Preparing...",
                isDownloading: true
            ))

            do {
                try await orchestrationService.downloadBook(book, api: api) { [weak self] bookId, progress, status, stage in
                    Task { @MainActor [weak self] in
                        self?.publish(bookId, DownloadState(
                            progress: progress,
                            stage: stage,
                            statusMessage: status,
                            isDownloading: true
                        ))
                    }
                }

                if let downloadedBook = loadBook(bookId: book.id) {
                    downloadedBooks.append(downloadedBook)

                    publish(book.id, DownloadState(
                        progress: 1.0,
                        stage: .complete,
                        statusMessage: "Complete",
                        isDownloading: false
                    ))

                    try? await Task.sleep(nanoseconds: 2_000_000_000)

                    // Clear transient state; notify observer so it can clean up UI
                    activeStates.removeValue(forKey: book.id)
                    onStateChanged?(book.id, DownloadState())
                }
            } catch {
                handleDownloadFailure(bookId: book.id, error: error.localizedDescription)
            }
        }

        downloadTasks[book.id] = task
        await task.value
        downloadTasks.removeValue(forKey: book.id)
    }

    func cancelDownload(for bookId: String) {
        orchestrationService.cancelDownload(for: bookId)
        downloadTasks[bookId]?.cancel()
        downloadTasks.removeValue(forKey: bookId)
        activeStates.removeValue(forKey: bookId)
        onStateChanged?(bookId, DownloadState())
    }

    func cancelAllDownloads() {
        for bookId in downloadTasks.keys {
            cancelDownload(for: bookId)
        }
    }

    func deleteBook(_ bookId: String) {
        let bookDir = storageService.bookDirectory(for: bookId)
        do {
            try storageService.deleteBookDirectory(at: bookDir)
            downloadedBooks.removeAll { $0.id == bookId }
            activeStates.removeValue(forKey: bookId)
            onStateChanged?(bookId, DownloadState())
        } catch {
            AppLogger.general.error("Failed to delete book: \(error)")
        }
    }

    func deleteAllBooks() {
        for book in downloadedBooks {
            deleteBook(book.id)
        }
    }

    func getDownloadedBooks() -> [Book] {
        return downloadedBooks
    }

    func preloadDownloadedBooks() async -> [Book] {
        let books = storageService.loadDownloadedBooks()
            .filter { validationService.validateBookIntegrity(bookId: $0.id, storageService: storageService).isValid }
        downloadedBooks = books
        // Notify observer so DownloadManager.downloadedBooks stays in sync
        for book in books {
            onStateChanged?(book.id, activeStates[book.id] ?? DownloadState())
        }
        return books
    }

    func isBookDownloaded(_ bookId: String) -> Bool {
        return downloadedBooks.contains { $0.id == bookId }
    }

    func getOfflineStatus(for bookId: String) -> OfflineStatus {
        if activeStates[bookId]?.isDownloading == true { return .downloading }
        if isBookDownloaded(bookId) { return .available }
        return .notDownloaded
    }

    func getDownloadProgress(for bookId: String) -> Double {
        return activeStates[bookId]?.progress ?? 0.0
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

    // MARK: - Private

    /// Single point where state is mutated locally and propagated upward.
    private func publish(_ bookId: String, _ state: DownloadState) {
        activeStates[bookId] = state
        onStateChanged?(bookId, state)
    }

    private func handleDownloadFailure(bookId: String, error: String) {
        let bookDir = storageService.bookDirectory(for: bookId)
        try? storageService.deleteBookDirectory(at: bookDir)

        publish(bookId, DownloadState(
            progress: 0.0,
            stage: .failed,
            statusMessage: error,
            isDownloading: false
        ))
    }

    private func loadDownloadedBooks() {
        let books = storageService.loadDownloadedBooks()
        downloadedBooks = books.filter {
            validationService.validateBookIntegrity(bookId: $0.id, storageService: storageService).isValid
        }
    }

    private func loadBook(bookId: String) -> Book? {
        let metadataFile = storageService.bookDirectory(for: bookId)
            .appendingPathComponent("metadata.json")
        guard let data = try? Data(contentsOf: metadataFile),
              let book = try? JSONDecoder().decode(Book.self, from: data) else {
            return nil
        }
        return book
    }

    deinit {
        let service = healingService
        Task { @MainActor in service.stop() }
        for (_, task) in downloadTasks { task.cancel() }
    }

    // MARK: - Placeholder (for ViewModels in preview / pre-login state)

    @MainActor
    static let placeholder: DefaultDownloadRepository = {
        let storageService = DefaultDownloadStorageService()
        let networkService = DefaultDownloadNetworkService()
        let validationService = DefaultDownloadValidationService()
        let retryPolicy = ExponentialBackoffRetryPolicy()

        let orchestrationService = DefaultDownloadOrchestrationService(
            networkService: networkService,
            storageService: storageService,
            retryPolicy: retryPolicy,
            validationService: validationService
        )

        let healingService = DefaultBackgroundHealingService(
            storageService: storageService,
            validationService: validationService,
            onBookRemoved: { _ in }         // no-op: placeholder has no live observer
        )

        return DefaultDownloadRepository(
            orchestrationService: orchestrationService,
            storageService: storageService,
            validationService: validationService,
            healingService: healingService,
            startHealing: false             // never start background work in a placeholder
        )
    }()
}

// MARK: - Protocol extension convenience

extension DownloadRepository where Self == DefaultDownloadRepository {
    @MainActor
    static var placeholder: DefaultDownloadRepository {
        DefaultDownloadRepository.placeholder
    }
}
