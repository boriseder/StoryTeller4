import Foundation

// MARK: - BookMetadataServiceProtocol (Domain Layer)
// Abstrahiert das Laden von Book-Details, egal ob online oder lokal
@MainActor
protocol BookMetadataServiceProtocol: AnyObject {
    func fetchBookDetails(bookId: String) async throws -> Book
    func loadLocalMetadata(bookId: String) throws -> Book
    func isBookDownloaded(_ bookId: String) -> Bool
}

// MARK: - PlaybackServiceProtocol (Domain Layer)
// Abstrahiert den Player – ViewModel/UseCase weiß nichts über AudioPlayer-Internals
@MainActor
protocol PlaybackServiceProtocol: AnyObject {
    func configure(downloadManager: DownloadManager)
    func load(book: Book, isOffline: Bool, restoreState: Bool, autoPlay: Bool) async
}

// MARK: - BookMetadataService (Data Layer)
@MainActor
final class BookMetadataService: BookMetadataServiceProtocol {
    private let api: AudiobookshelfClient
    private let downloadManager: DownloadManager

    init(api: AudiobookshelfClient, downloadManager: DownloadManager) {
        self.api = api
        self.downloadManager = downloadManager
    }

    func fetchBookDetails(bookId: String) async throws -> Book {
        return try await api.books.fetchBookDetails(bookId: bookId, retryCount: 3)
    }

    func loadLocalMetadata(bookId: String) throws -> Book {
        let bookDir = downloadManager.bookDirectory(for: bookId)
        let metadataURL = bookDir.appendingPathComponent("metadata.json")

        guard FileManager.default.fileExists(atPath: metadataURL.path) else {
            throw BookMetadataError.localMetadataNotFound(bookId)
        }

        let data = try Data(contentsOf: metadataURL)
        return try JSONDecoder().decode(Book.self, from: data)
    }

    func isBookDownloaded(_ bookId: String) -> Bool {
        return downloadManager.isBookDownloaded(bookId)
    }
}

// MARK: - PlaybackService (Data Layer)
@MainActor
final class PlaybackService: PlaybackServiceProtocol {
    private let player: AudioPlayer
    private let api: AudiobookshelfClient

    init(player: AudioPlayer, api: AudiobookshelfClient) {
        self.player = player
        self.api = api
    }

    func configure(downloadManager: DownloadManager) {
        player.configure(
            baseURL: api.baseURLString,
            authToken: api.authToken,
            downloadManager: downloadManager
        )
    }

    func load(book: Book, isOffline: Bool, restoreState: Bool, autoPlay: Bool) async {
        await player.load(
            book: book,
            isOffline: isOffline,
            restoreState: restoreState,
            autoPlay: autoPlay
        )
    }
}

// MARK: - Domain Error
enum BookMetadataError: LocalizedError {
    case localMetadataNotFound(String)

    var errorDescription: String? {
        switch self {
        case .localMetadataNotFound(let id):
            return "Local metadata not found for book: \(id)"
        }
    }
}
