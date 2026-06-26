import SwiftUI
import Observation

@MainActor
@Observable
class DownloadsViewModel {

    // MARK: - UI State
    var downloadedBooks: [Book] = []
    var availableStorage: Int64 = 0
    var totalStorageUsed: Int64 = 0
    var showStorageWarning = false
    var errorMessage: String?
    var showingErrorAlert = false

    var showingDeleteConfirmation = false
    var showingDeleteAllConfirmation = false
    var bookToDelete: Book?

    // MARK: - Constants
    let storageThreshold: Int64 = 1_000_000_000

    // MARK: - Dependencies
    let downloadManager: DownloadManager                    // UI state observation
    private let downloadUseCase: any DownloadBookUseCaseProtocol  // mutations → repository
    private let storageMonitor: StorageMonitor
    private let playBookUseCase: PlayBookUseCaseProtocol
    let onBookSelected: () -> Void

    // MARK: - Init
    init(
        downloadManager: DownloadManager,
        downloadUseCase: any DownloadBookUseCaseProtocol,
        player: AudioPlayer,
        api: AudiobookshelfClient,
        appState: AppStateManager,
        storageMonitor: StorageMonitor,
        onBookSelected: @escaping () -> Void
    ) {
        self.downloadManager = downloadManager
        self.downloadUseCase = downloadUseCase
        self.storageMonitor = storageMonitor
        self.onBookSelected = onBookSelected
        self.playBookUseCase = PlayBookUseCase(
            metadataService: BookMetadataService(api: api, downloadManager: downloadManager),
            playbackService: PlaybackService(player: player, api: api),
            downloadManager: downloadManager,
            appState: appState
        )
    }

    // MARK: - Lifecycle
    func loadData() async {
        _ = await downloadManager.preloadDownloadedBooksCount()
        refreshData()
    }

    func refreshData() {
        downloadedBooks = downloadManager.downloadedBooks
        updateStorageInfo()
    }

    func updateStorageInfo() {
        totalStorageUsed = downloadManager.getTotalDownloadSize()
        availableStorage = storageMonitor.getStorageInfo().availableSpace
        showStorageWarning = availableStorage < storageThreshold
    }

    // MARK: - Per-Book Download State Accessors (DownloadManager — UI state, correct)
    func downloadProgress(for book: Book) -> Double  { downloadManager.progress(for: book.id) }
    func downloadStage(for book: Book) -> DownloadStage { downloadManager.stage(for: book.id) }
    func isDownloading(_ book: Book) -> Bool         { downloadManager.isDownloadingBook(book.id) }
    func offlineStatus(for book: Book) -> OfflineStatus { downloadManager.getOfflineStatus(for: book.id) }

    // MARK: - Playback
    func playBook(_ book: Book, autoPlay: Bool = false) async {
        do {
            try await playBookUseCase.execute(
                book: book,
                restoreState: true,
                autoPlay: autoPlay
            )
            onBookSelected()
        } catch {
            errorMessage = error.localizedDescription
            showingErrorAlert = true
        }
    }

    // MARK: - Delete (routed through use case → repository)

    func requestDeleteBook(_ book: Book) {
        bookToDelete = book
        showingDeleteConfirmation = true
    }

    func confirmDeleteBook() {
        guard let book = bookToDelete else { return }
        downloadUseCase.delete(bookId: book.id)
        bookToDelete = nil
        showingDeleteConfirmation = false
        refreshData()
    }

    func cancelDelete() {
        bookToDelete = nil
        showingDeleteConfirmation = false
    }

    // MARK: - Formatting
    private let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowsNonnumericFormatting = false
        return f
    }()

    func formatBytes(_ bytes: Int64) -> String        { byteFormatter.string(fromByteCount: bytes) }
    func getBookStorageSize(_ book: Book) -> String   { formatBytes(downloadManager.getBookStorageSize(book.id)) }
}

// MARK: - Placeholder
extension DownloadsViewModel {
    @MainActor
    static var placeholder: DownloadsViewModel {
        let downloadManager = DownloadManager()
        return DownloadsViewModel(
            downloadManager: downloadManager,
            downloadUseCase: DownloadBookUseCase(
                repository: DefaultDownloadRepository.placeholder
            ),
            player: AudioPlayer(),
            api: AudiobookshelfClient(baseURL: "", authToken: ""),
            appState: AppStateManager.shared,
            storageMonitor: StorageMonitor(),
            onBookSelected: {}
        )
    }
}
