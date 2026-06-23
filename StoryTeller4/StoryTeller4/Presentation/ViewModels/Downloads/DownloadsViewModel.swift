import SwiftUI
import Observation

// MARK: - DownloadsViewModel

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

    // Delete confirmation
    var showingDeleteConfirmation = false
    var showingDeleteAllConfirmation = false
    var bookToDelete: Book?

    // MARK: - Constants

    let storageThreshold: Int64 = 1_000_000_000  // 1 GB

    // MARK: - Dependencies

    let downloadManager: DownloadManager
    let player: AudioPlayer
    let api: AudiobookshelfClient
    let appState: AppStateManager
    private let storageMonitor: StorageMonitor
    private let playBookUseCase: PlayBookUseCase
    let onBookSelected: () -> Void

    // MARK: - Init

    init(
        downloadManager: DownloadManager,
        player: AudioPlayer,
        api: AudiobookshelfClient,
        appState: AppStateManager,
        storageMonitor: StorageMonitor,
        onBookSelected: @escaping () -> Void
    ) {
        self.downloadManager = downloadManager
        self.player = player
        self.api = api
        self.appState = appState
        self.storageMonitor = storageMonitor
        self.onBookSelected = onBookSelected
        self.playBookUseCase = PlayBookUseCase()
    }

    // MARK: - Lifecycle (call from .task in the view)

    func loadData() async {
        _ = await downloadManager.preloadDownloadedBooksCount()
        refreshData()
    }

    func refreshData() {
        // downloadManager.downloadedBooks is now the authoritative list,
        // kept in sync by the onStateChanged callback — no manual pull needed.
        downloadedBooks = downloadManager.downloadedBooks
        updateStorageInfo()
    }

    func updateStorageInfo() {
        totalStorageUsed = downloadManager.getTotalDownloadSize()
        availableStorage = storageMonitor.getStorageInfo().availableSpace
        showStorageWarning = availableStorage < storageThreshold
    }

    // MARK: - Per-Book Download State Accessors
    //
    // Views call these instead of indexing into raw dictionaries.

    func downloadProgress(for book: Book) -> Double {
        downloadManager.progress(for: book.id)
    }

    func downloadStage(for book: Book) -> DownloadStage {
        downloadManager.stage(for: book.id)
    }

    func isDownloading(_ book: Book) -> Bool {
        downloadManager.isDownloadingBook(book.id)
    }

    func offlineStatus(for book: Book) -> OfflineStatus {
        downloadManager.getOfflineStatus(for: book.id)
    }

    // MARK: - Playback

    func playBook(_ book: Book, autoPlay: Bool = false) async {
        do {
            try await playBookUseCase.execute(
                book: book,
                api: api,
                player: player,
                downloadManager: downloadManager,
                appState: appState,
                restoreState: true,
                autoPlay: autoPlay
            )
            onBookSelected()
        } catch {
            errorMessage = error.localizedDescription
            showingErrorAlert = true
        }
    }

    // MARK: - Delete

    func requestDeleteBook(_ book: Book) {
        bookToDelete = book
        showingDeleteConfirmation = true
    }

    func confirmDeleteBook() {
        guard let book = bookToDelete else { return }
        downloadManager.deleteBook(book.id)
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

    func formatBytes(_ bytes: Int64) -> String {
        byteFormatter.string(fromByteCount: bytes)
    }

    func getBookStorageSize(_ book: Book) -> String {
        formatBytes(downloadManager.getBookStorageSize(book.id))
    }
}

// MARK: - Placeholder

extension DownloadsViewModel {
    @MainActor
    static var placeholder: DownloadsViewModel {
        DownloadsViewModel(
            downloadManager: DownloadManager(),
            player: AudioPlayer(),
            api: AudiobookshelfClient(baseURL: "", authToken: ""),
            appState: AppStateManager.shared,
            storageMonitor: StorageMonitor(),
            onBookSelected: {}
        )
    }
}
