import Foundation
import SwiftUI
import Observation

// MARK: - Helper Enums

enum OfflineStatus: Sendable {
    case notDownloaded
    case downloading
    case available
}

struct DownloadStatus: Sendable {
    let isDownloaded: Bool
    let isDownloading: Bool
}

enum DownloadStage: String, Equatable, Sendable {
    case preparing          = "Preparing..."
    case fetchingMetadata   = "Getting book info..."
    case downloadingCover   = "Downloading cover..."
    case downloadingAudio   = "Downloading audio..."
    case finalizing         = "Almost done..."
    case complete           = "Complete!"
    case failed             = "Failed"

    var icon: String {
        switch self {
        case .preparing:        return "clock.arrow.circlepath"
        case .fetchingMetadata: return "doc.text.magnifyingglass"
        case .downloadingCover: return "photo.on.rectangle.angled"
        case .downloadingAudio: return "waveform.circle"
        case .finalizing:       return "checkmark.circle"
        case .complete:         return "checkmark.circle.fill"
        case .failed:           return "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .preparing, .fetchingMetadata, .downloadingCover, .downloadingAudio:
            return .accentColor
        case .finalizing:   return .orange
        case .complete:     return .green
        case .failed:       return .red
        }
    }
}

enum DownloadError: LocalizedError, Sendable {
    case invalidCoverURL
    case coverDownloadFailed(underlying: Error?)
    case audioDownloadFailed(chapter: Int, underlying: Error?)
    case missingLibraryItemId
    case invalidResponse
    case httpError(statusCode: Int)
    case fileTooSmall
    case verificationFailed
    case insufficientStorage
    case missingContentUrl(track: Int)
    case invalidAudioURL(track: Int, path: String)
    case invalidImageData

    var errorDescription: String? {
        switch self {
        case .invalidCoverURL:                          return "Invalid cover URL"
        case .coverDownloadFailed:                      return "Failed to download cover"
        case .audioDownloadFailed(let chapter, _):      return "Failed to download chapter \(chapter)"
        case .missingLibraryItemId:                     return "Book has no library item ID"
        case .invalidResponse:                          return "Invalid server response"
        case .httpError(let statusCode):                return "Server error (HTTP \(statusCode))"
        case .fileTooSmall:                             return "Downloaded file is too small (corrupted)"
        case .verificationFailed:                       return "Download verification failed"
        case .insufficientStorage:                      return "Insufficient storage space"
        case .missingContentUrl(let track):             return "Audio track \(track + 1) missing content URL"
        case .invalidAudioURL(let track, let path):     return "Invalid URL for track \(track + 1): \(path)"
        case .invalidImageData:                         return "Invalid cover image data"
        }
    }
}

// MARK: - DownloadManager
//
// Responsibilities (and only these):
//   1. Hold @Observable state for SwiftUI views to observe.
//   2. Delegate all business logic to the injected DownloadRepository.
//   3. Wire the repository's onStateChanged callback so UI state
//      stays in sync without the repository knowing this class exists.
//
// Dependency direction: DownloadManager → DownloadRepository (protocol only).
// The repository never imports or references DownloadManager.

@MainActor
@Observable
final class DownloadManager {

    // MARK: - @Observable UI State
    //
    // Written exclusively via the onStateChanged callback wired in configure().
    // Views observe these; nothing else mutates them directly.

    private(set) var downloadedBooks: [Book] = []
    private(set) var downloadStates: [String: DownloadState] = [:]

    // MARK: - Convenience Accessors (used by Views and ViewModels)

    func progress(for bookId: String) -> Double {
        downloadStates[bookId]?.progress ?? 0.0
    }

    func stage(for bookId: String) -> DownloadStage {
        downloadStates[bookId]?.stage ?? .preparing
    }

    func statusMessage(for bookId: String) -> String {
        downloadStates[bookId]?.statusMessage ?? ""
    }

    func isDownloadingBook(_ bookId: String) -> Bool {
        downloadStates[bookId]?.isDownloading ?? false
    }

    // MARK: - Repository (one-directional dependency)

    internal private(set) var repository: (any DownloadRepository)?

    // MARK: - Init

    init() {
        AppLogger.general.debug("[DownloadManager] Initialized")
    }

    // MARK: - Configuration
    //
    // Called once by ServiceContainer after both objects are constructed.
    // This is the only place the callback is wired — keeping the
    // one-directional data flow explicit and traceable.

    func configure(repository: any DownloadRepository) {
        var repo = repository

        // Capture as immutable let so the @Sendable closure doesn't
        // hold a reference to a mutating var (which Swift rejects).
        let capturedRepo = repo

        // Repository → Manager (state flows upward, never downward).
        // The closure is @Sendable, so we must hop to MainActor before
        // touching any @MainActor-isolated properties.
        repo.onStateChanged = { [weak self] bookId, state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if state.isDownloading || state.stage == .complete || state.stage == .failed {
                    self.downloadStates[bookId] = state
                } else {
                    // Empty/cleared state: remove entry to keep the dict lean
                    self.downloadStates.removeValue(forKey: bookId)
                }
                // Keep downloadedBooks in sync after every state change
                self.downloadedBooks = capturedRepo.getDownloadedBooks()
            }
        }

        self.repository = repo
        AppLogger.general.debug("[DownloadManager] Repository configured")
    }

    // MARK: - Public API (pure delegation to repository)

    func downloadBook(_ book: Book, api: AudiobookshelfClient) async {
        guard let repository else {
            AppLogger.general.error("[DownloadManager] Repository not configured")
            return
        }
        do {
            try await repository.downloadBook(book, api: api)
            // downloadedBooks is refreshed via the callback; no manual sync needed
        } catch {
            AppLogger.general.error("[DownloadManager] Download failed: \(error)")
        }
    }

    func cancelDownload(for bookId: String) {
        repository?.cancelDownload(for: bookId)
    }

    func cancelAllDownloads() {
        repository?.cancelAllDownloads()
    }

    func deleteBook(_ bookId: String) {
        repository?.deleteBook(bookId)
        // downloadedBooks refresh is driven by the callback
    }

    func deleteAllBooks() {
        repository?.deleteAllBooks()
    }

    // MARK: - Query pass-throughs

    func getOfflineStatus(for bookId: String) -> OfflineStatus {
        repository?.getOfflineStatus(for: bookId) ?? .notDownloaded
    }

    func isBookAvailableOffline(_ bookId: String) -> Bool {
        getOfflineStatus(for: bookId) == .available
    }

    func isBookDownloaded(_ bookId: String) -> Bool {
        repository?.isBookDownloaded(bookId) ?? false
    }

    /// Legacy accessor kept for call-site compatibility.
    func getDownloadProgress(for bookId: String) -> Double {
        progress(for: bookId)
    }

    func getLocalAudioURL(for bookId: String, chapterIndex: Int) -> URL? {
        repository?.getLocalAudioURL(for: bookId, chapterIndex: chapterIndex)
    }

    func getLocalCoverURL(for bookId: String) -> URL? {
        repository?.getLocalCoverURL(for: bookId)
    }

    func getTotalDownloadSize() -> Int64 {
        repository?.getTotalDownloadSize() ?? 0
    }

    func getBookStorageSize(_ bookId: String) -> Int64 {
        repository?.getBookStorageSize(bookId) ?? 0
    }

    func bookDirectory(for bookId: String) -> URL {
        if let repository {
            return repository.bookDirectory(for: bookId)
        }
        // Safe fallback — repository not yet configured
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Downloads").appendingPathComponent(bookId)
    }

    func preloadDownloadedBooksCount() async -> Int {
        guard let repository else { return 0 }
        let books = await repository.preloadDownloadedBooks()
        downloadedBooks = books
        return books.count
    }
}
