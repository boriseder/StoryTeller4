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
    
    // Delete Confirmation
    var showingDeleteConfirmation = false
    var showingDeleteAllConfirmation = false
    var bookToDelete: Book?
    
    // MARK: - Constants
    let storageThreshold: Int64 = 1_000_000_000 // 1GB warning
    
    // MARK: - Dependencies
    let downloadManager: DownloadManager
    let player: AudioPlayer
    let api: AudiobookshelfClient
    let appState: AppStateManager
    private let storageMonitor: StorageMonitor
    private let playBookUseCase: PlayBookUseCase
    let onBookSelected: () -> Void
    
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
        
        // Initial load
        refreshData()
    }
    
    func refreshData() {
        downloadedBooks = downloadManager.downloadedBooks
        updateStorageInfo()
    }
    
    func updateStorageInfo() {
        totalStorageUsed = downloadManager.getTotalDownloadSize()
        // FIX: storageMonitor.getStorageInfo() returns the struct containing availableSpace
        availableStorage = storageMonitor.getStorageInfo().availableSpace
        showStorageWarning = availableStorage < storageThreshold
    }
    
    // MARK: - Actions
    
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
    
    // MARK: - Delete Logic
    
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
    
    // MARK: - Helpers
    
    func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
    
    func getBookStorageSize(_ book: Book) -> String {
        let size = downloadManager.getBookStorageSize(book.id)
        return formatBytes(size)
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
