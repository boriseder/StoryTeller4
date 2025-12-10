import Foundation

enum PlaybackMode: CustomStringConvertible, Sendable {
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

enum PlayBookError: LocalizedError, Sendable {
    case notAvailableOffline(String)
    case fetchFailed(Error)
    case bookNotDownloadedOfflineOnly(String)
    
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

protocol PlayBookUseCaseProtocol: Sendable {
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
        
        let isOffline = playbackMode == .offline
        await player.load(
            book: fullBook,
            isOffline: isOffline,
            restoreState: restoreState,
            autoPlay: autoPlay
        )

        AppLogger.general.debug("[PlayBookUseCase] Loaded: \(fullBook.title) (\(playbackMode))")
    }
    
    @MainActor
    private func loadBookMetadata(
        book: Book,
        api: AudiobookshelfClient,
        downloadManager: DownloadManager,
        isOffline: Bool
    ) async throws -> Book {
        
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
        
        guard FileManager.default.fileExists(atPath: metadataURL.path) else {
            throw NSError(domain: "PlayBookUseCase", code: -1, userInfo: [NSLocalizedDescriptionKey: "Local metadata not found"])
        }
        
        let data = try Data(contentsOf: metadataURL)
        return try JSONDecoder().decode(Book.self, from: data)
    }
}
