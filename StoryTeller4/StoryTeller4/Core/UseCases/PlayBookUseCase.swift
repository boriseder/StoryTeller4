import Foundation

enum PlaybackMode: CustomStringConvertible {
    case online
    case offline
    case unavailable
    
    var description: String {
        switch self {
        case .online: return "online"
        case .offline: return "offline"
        case .unavailable: return "unavailable"
        }
    }
}

enum PlayBookError: LocalizedError {
    case notAvailableOffline(String)
    case fetchFailed(Error)
    case bookNotDownloadedOfflineOnly(String)  // NEW
    
    var errorDescription: String? {
        switch self {
        case .notAvailableOffline(let title):
            return "'\(title)' is not available offline and no internet connection is available."
        case .fetchFailed(let error):
            return "Could not load book: \(error.localizedDescription)"
        case .bookNotDownloadedOfflineOnly(let title):
            return "'\(title)' needs to be downloaded for offline playback."
        }
    }
}

protocol PlayBookUseCaseProtocol {
    func execute(
        book: Book,
        api: AudiobookshelfClient,
        player: AudioPlayer,
        downloadManager: DownloadManager,
        appState: AppStateManager,
        restoreState: Bool,
        autoPlay: Bool,

    ) async throws
}

class PlayBookUseCase: PlayBookUseCaseProtocol {
    
    func execute(
        book: Book,
        api: AudiobookshelfClient,
        player: AudioPlayer,
        downloadManager: DownloadManager,
        appState: AppStateManager,
        restoreState: Bool = true,
        autoPlay: Bool = false,

    ) async throws {
        
        // 1. EARLY EXIT: Check playback feasibility FIRST
        let playbackMode = determinePlaybackMode(
            book: book,
            downloadManager: downloadManager,
            appState: appState
        )
        
        // 2. FAIL FAST: Don't even try to load metadata if unavailable
        guard playbackMode != .unavailable else {
            let isDownloaded = downloadManager.isBookDownloaded(book.id)
            if isDownloaded {
                // This should never happen, but handle gracefully
                AppLogger.general.error("[PlayBookUseCase] Logic error: Book downloaded but marked unavailable")
            }
            throw PlayBookError.notAvailableOffline(book.title)
        }
        
        // 3. Load metadata (online or offline)
        let fullBook = try await loadBookMetadata(
            book: book,
            api: api,
            downloadManager: downloadManager,
            isOffline: playbackMode == .offline
        )
        
        // 4. Configure player
        player.configure(
            baseURL: api.baseURLString,
            authToken: api.authToken,
            downloadManager: downloadManager
        )
        
        // 5. Load player with appropriate mode
        let isOffline = playbackMode == .offline
        await player.load(
            book: fullBook,
            isOffline: isOffline,
            restoreState: restoreState,
            autoPlay: autoPlay
        )

        AppLogger.general.debug("[PlayBookUseCase] Loaded: \(fullBook.title) (\(playbackMode))")
        
    }
    
    // REFACTOR: Separated concerns - metadata loading
    private func loadBookMetadata(
        book: Book,
        api: AudiobookshelfClient,
        downloadManager: DownloadManager,
        isOffline: Bool
    ) async throws -> Book {
        
        let isDownloaded = downloadManager.isBookDownloaded(book.id)
        
        // Try local metadata first if downloaded
        if isDownloaded {
            do {
                let localBook = try loadLocalMetadata(bookId: book.id, downloadManager: downloadManager)
                AppLogger.general.debug("[PlayBookUseCase] Loaded from local metadata: \(localBook.title)")
                return localBook
            } catch {
                AppLogger.general.debug("[PlayBookUseCase] Local metadata failed, trying online")
            }
        }
        
        // Fallback to online (or fail if offline-only mode)
        guard !isOffline else {
            throw PlayBookError.bookNotDownloadedOfflineOnly(book.title)
        }
        
        do {
            return try await api.books.fetchBookDetails(bookId: book.id, retryCount: 3)
        } catch {
            AppLogger.general.debug("[PlayBookUseCase] Online fetch failed: \(error)")
            throw PlayBookError.fetchFailed(error)
        }
    }
    
    // CLEANER: More explicit playback mode logic
    private func determinePlaybackMode(
        book: Book,
        downloadManager: DownloadManager,
        appState: AppStateManager
    ) -> PlaybackMode {
        let isDownloaded = downloadManager.isBookDownloaded(book.id)
        let hasConnection = appState.isServerReachable
        
        // Priority 1: Downloaded = Always offline mode
        if isDownloaded {
            return .offline
        }
        
        // Priority 2: Network available = Stream online
        if hasConnection {
            return .online
        }
        
        // Priority 3: No download, no network = Unavailable
        return .unavailable

    }
    
    private func loadLocalMetadata(bookId: String, downloadManager: DownloadManager) throws -> Book {
        let bookDir = downloadManager.bookDirectory(for: bookId)
        let metadataURL = bookDir.appendingPathComponent("metadata.json")
        
        guard FileManager.default.fileExists(atPath: metadataURL.path) else {
            throw PlayBookError.fetchFailed(NSError(
                domain: "PlayBookUseCase",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Local metadata not found"]
            ))
        }
        
        let data = try Data(contentsOf: metadataURL)
        return try JSONDecoder().decode(Book.self, from: data)
    }
}
