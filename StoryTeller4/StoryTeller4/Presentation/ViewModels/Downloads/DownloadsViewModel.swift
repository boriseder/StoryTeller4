import SwiftUI

@MainActor
class DownloadsViewModel: ObservableObject {
    // MARK: - Published UI State
    @Published var progressState = DownloadProgressState()
    @Published var errorMessage: String?
    @Published var showingErrorAlert = false
    
    // For smooth transistions
    @Published var contentLoaded = false

    // MARK: - Dependencies
    private let downloadUseCase: DownloadBookUseCase
    private let playBookUseCase: PlayBookUseCase
    private let storageMonitor: StorageMonitor
    private var storageUpdateTimer: Timer?
    
    let downloadManager: DownloadManager
    let player: AudioPlayer
    let api: AudiobookshelfClient
    let appState: AppStateManager
    let onBookSelected: () -> Void

    // MARK: - Computed Properties for UI
    var downloadedBooks: [Book] {
        downloadManager.downloadedBooks
    }
    
    var bookToDelete: Book? {
        get { progressState.bookToDelete }
        set { progressState.bookToDelete = newValue }
    }
    
    var showingDeleteConfirmation: Bool {
        get { progressState.showingDeleteConfirmation }
        set { progressState.showingDeleteConfirmation = newValue }
    }
    
    var showingDeleteAllConfirmation: Bool {
        get { progressState.showingDeleteAllConfirmation }
        set { progressState.showingDeleteAllConfirmation = newValue }
    }
    
    var totalStorageUsed: Int64 {
        progressState.totalStorageUsed
    }
    
    var availableStorage: Int64 {
        progressState.availableStorage
    }
    
    var showStorageWarning: Bool {
        progressState.showStorageWarning
    }
    
    var storageThreshold: Int64 {
        progressState.storageThreshold
    }
    
    // MARK: - Init with DI
    init(
        downloadManager: DownloadManager,
        player: AudioPlayer,
        api: AudiobookshelfClient,
        appState: AppStateManager,
        storageMonitor: StorageMonitor = StorageMonitor(),
        onBookSelected: @escaping () -> Void
    ) {
        self.downloadManager = downloadManager
        self.player = player
        self.api = api
        self.appState = appState
        self.storageMonitor = storageMonitor
        self.downloadUseCase = DownloadBookUseCase(downloadManager: downloadManager)
        self.playBookUseCase = PlayBookUseCase()
        self.onBookSelected = onBookSelected
        
        updateStorageInfo()
        setupStorageMonitoring()
    }
    
    // MARK: - Actions (Delegate to Use Cases)
    func updateStorageInfo() {
        let info = storageMonitor.getStorageInfo()
        let warningLevel = storageMonitor.getWarningLevel()
        
        let totalUsed = downloadManager.getTotalDownloadSize()
        
        progressState.updateStorage(
            totalUsed: totalUsed,
            available: info.availableSpace,
            warningLevel: warningLevel
        )
        
        AppLogger.general.debug("[Downloads] Storage - Used: \(info.usedSpaceFormatted), Available: \(info.availableSpaceFormatted)")
    }
    
    private func setupStorageMonitoring() {
        storageUpdateTimer = Timer.scheduledTimer(withTimeInterval: 300.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateStorageInfo()
            }
        }
    }
    
    func getBookStorageSize(_ book: Book) -> String {
        let size = downloadManager.getBookStorageSize(book.id)
        return storageMonitor.formatBytes(size)
    }
    
    func formatBytes(_ bytes: Int64) -> String {
        return storageMonitor.formatBytes(bytes)
    }
    
    // MARK: - Playback
    func playBook(
        _ book: Book,
        autoPlay: Bool = false
    ) async {
        guard downloadManager.isBookDownloaded(book.id) else {
            errorMessage = "Book is not downloaded"
            showingErrorAlert = true
            return
        }
        
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
            AppLogger.general.debug("[DownloadsViewModel] Playback error: \(error)")
        }
    }
    
    // MARK: - Delete Operations
    func requestDeleteBook(_ book: Book) {
        progressState.requestDelete(book)
    }
    
    func confirmDeleteBook() {
        guard let book = progressState.bookToDelete else { return }
        
        AppLogger.general.debug("[Downloads] Deleting book: \(book.title)")
        downloadUseCase.delete(bookId: book.id)
        
        progressState.confirmDelete()
        
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            self?.updateStorageInfo()
        }
    }
    
    func cancelDelete() {
        progressState.cancelDelete()
    }
    
    func requestDeleteAll() {
        progressState.requestDeleteAll()
    }
    
    func confirmDeleteAll() {
        AppLogger.general.debug("[Downloads] Deleting all downloads")
        downloadManager.deleteAllBooks()
        
        progressState.confirmDeleteAll()
        
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            self?.updateStorageInfo()
        }
    }
    
    func cancelDeleteAll() {
        progressState.cancelDeleteAll()
    }
    
    deinit {
        storageUpdateTimer?.invalidate()
        storageUpdateTimer = nil
    }
}
