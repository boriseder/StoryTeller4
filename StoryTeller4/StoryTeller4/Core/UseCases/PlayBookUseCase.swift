import Foundation

protocol PlayBookUseCaseProtocol: Sendable {
    // Arguments like AudioPlayer and AppStateManager are @MainActor types.
    // The function itself should run on MainActor to interact with them synchronously.
    @MainActor func execute(
        book: Book,
        api: AudiobookshelfClient,
        player: AudioPlayer,
        downloadManager: DownloadManager,
        appState: AppStateManager,
        restoreState: Bool,
        autoPlay: Bool
    ) async throws
}

final class PlayBookUseCase: PlayBookUseCaseProtocol, Sendable {
    
    @MainActor
    func execute(
        book: Book,
        api: AudiobookshelfClient,
        player: AudioPlayer,
        downloadManager: DownloadManager,
        appState: AppStateManager,
        restoreState: Bool = true,
        autoPlay: Bool = false
    ) async throws {
        
        let playbackMode = determinePlaybackMode(
            book: book,
            downloadManager: downloadManager,
            appState: appState
        )
        
        guard playbackMode != .unavailable else {
            throw PlayBookError.notAvailableOffline(book.title)
        }
        
        let fullBook = try await loadBookMetadata(
            book: book,
            api: api,
            downloadManager: downloadManager,
            isOffline: playbackMode == .offline
        )
        
        player.configure(
            baseURL: api.baseURLString,
            authToken: api.authToken,
            downloadManager: downloadManager
        )
        
        await player.load(
            book: fullBook,
            isOffline: playbackMode == .offline,
            restoreState: restoreState,
            autoPlay: autoPlay
        )

        AppLogger.general.debug("[PlayBookUseCase] Loaded: \(fullBook.title) (\(playbackMode))")
    }
    
    // MARK: - Private Helpers (Stateless)
    // These manipulate @MainActor types, so they inherit that isolation naturally when called from execute
    
    @MainActor
    private func loadBookMetadata(
        book: Book,
        api: AudiobookshelfClient,
        downloadManager: DownloadManager,
        isOffline: Bool
    ) async throws -> Book {
        // Implementation remains same...
        // MainActor isolation allows synchronous access to downloadManager.isBookDownloaded
        
        let isDownloaded = downloadManager.isBookDownloaded(book.id)
        
        if isDownloaded {
            do {
                let localBook = try loadLocalMetadata(bookId: book.id, downloadManager: downloadManager)
                return localBook
            } catch {
                AppLogger.general.debug("[PlayBookUseCase] Local metadata failed, trying online")
            }
        }
        
        guard !isOffline else {
            throw PlayBookError.bookNotDownloadedOfflineOnly(book.title)
        }
        
        do {
            return try await api.books.fetchBookDetails(bookId: book.id, retryCount: 3)
        } catch {
            throw PlayBookError.fetchFailed(error)
        }
    }
    
    @MainActor
    private func determinePlaybackMode(
        book: Book,
        downloadManager: DownloadManager,
        appState: AppStateManager
    ) -> PlaybackMode {
        let isDownloaded = downloadManager.isBookDownloaded(book.id)
        let hasConnection = appState.isServerReachable
        
        if isDownloaded { return .offline }
        if hasConnection { return .online }
        return .unavailable
    }
    
    @MainActor
    private func loadLocalMetadata(bookId: String, downloadManager: DownloadManager) throws -> Book {
        let bookDir = downloadManager.bookDirectory(for: bookId)
        let metadataURL = bookDir.appendingPathComponent("metadata.json")
        
        // FileManager is thread-safe
        guard FileManager.default.fileExists(atPath: metadataURL.path) else {
            throw NSError(domain: "PlayBookUseCase", code: -1, userInfo: [NSLocalizedDescriptionKey: "Local metadata not found"])
        }
        
        let data = try Data(contentsOf: metadataURL)
        return try JSONDecoder().decode(Book.self, from: data)
    }
}
