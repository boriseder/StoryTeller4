import Foundation

// MARK: - PlaybackMode
enum PlaybackMode: CustomStringConvertible, Sendable {
    case online
    case offline
    case unavailable

    var description: String {
        switch self {
        case .online:      return "online"
        case .offline:     return "offline"
        case .unavailable: return "unavailable"
        }
    }
}

// MARK: - Errors
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

// MARK: - Protocol (Domain Layer)
@MainActor
protocol PlayBookUseCaseProtocol: AnyObject {
    func execute(
        book: Book,
        restoreState: Bool,
        autoPlay: Bool
    ) async throws
}

// MARK: - Implementation (Domain Layer)
// Kein AudiobookshelfClient, kein AudioPlayer, kein DownloadManager direkt –
// nur Domain-Protocols
@MainActor
final class PlayBookUseCase: PlayBookUseCaseProtocol {
    private let metadataService: BookMetadataServiceProtocol
    private let playbackService: PlaybackServiceProtocol
    private let downloadManager: DownloadManager
    private let appState: AppStateManager

    init(
        metadataService: BookMetadataServiceProtocol,
        playbackService: PlaybackServiceProtocol,
        downloadManager: DownloadManager,
        appState: AppStateManager
    ) {
        self.metadataService = metadataService
        self.playbackService = playbackService
        self.downloadManager = downloadManager
        self.appState = appState
    }

    func execute(
        book: Book,
        restoreState: Bool = true,
        autoPlay: Bool = false
    ) async throws {
        let playbackMode = determinePlaybackMode(book: book)

        guard playbackMode != .unavailable else {
            throw PlayBookError.notAvailableOffline(book.title)
        }

        let fullBook = try await loadBook(book: book, isOffline: playbackMode == .offline)

        playbackService.configure(downloadManager: downloadManager)
        await playbackService.load(
            book: fullBook,
            isOffline: playbackMode == .offline,
            restoreState: restoreState,
            autoPlay: autoPlay
        )

        AppLogger.general.debug("[PlayBookUseCase] Loaded: \(fullBook.title) (\(playbackMode))")
    }

    // MARK: - Private

    private func determinePlaybackMode(book: Book) -> PlaybackMode {
        let isDownloaded = metadataService.isBookDownloaded(book.id)
        let hasConnection = appState.isServerReachable

        if isDownloaded { return .offline }
        if hasConnection { return .online }
        return .unavailable
    }

    private func loadBook(book: Book, isOffline: Bool) async throws -> Book {
        let isDownloaded = metadataService.isBookDownloaded(book.id)

        if isDownloaded {
            if let localBook = try? metadataService.loadLocalMetadata(bookId: book.id) {
                return localBook
            }
            AppLogger.general.debug("[PlayBookUseCase] Local metadata failed, trying online")
        }

        guard !isOffline else {
            throw PlayBookError.bookNotDownloadedOfflineOnly(book.title)
        }

        do {
            return try await metadataService.fetchBookDetails(bookId: book.id)
        } catch {
            throw PlayBookError.fetchFailed(error)
        }
    }
}
