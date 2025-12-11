import Foundation
import SwiftUI
import Observation

// MARK: - Helper Enums (Must be before class usage or Sendable)

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
    case preparing = "Preparing..."
    case fetchingMetadata = "Getting book info..."
    case downloadingCover = "Downloading cover..."
    case downloadingAudio = "Downloading audio..."
    case finalizing = "Almost done..."
    case complete = "Complete!"
    case failed = "Failed"
    
    var icon: String {
        switch self {
        case .preparing: return "clock.arrow.circlepath"
        case .fetchingMetadata: return "doc.text.magnifyingglass"
        case .downloadingCover: return "photo.on.rectangle.angled"
        case .downloadingAudio: return "waveform.circle"
        case .finalizing: return "checkmark.circle"
        case .complete: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .preparing, .fetchingMetadata, .downloadingCover, .downloadingAudio:
            return .accentColor
        case .finalizing: return .orange
        case .complete: return .green
        case .failed: return .red
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
        case .invalidCoverURL: return "Invalid cover URL"
        case .coverDownloadFailed: return "Failed to download cover"
        case .audioDownloadFailed(let chapter, _): return "Failed to download chapter \(chapter)"
        case .missingLibraryItemId: return "Book has no library item ID"
        case .invalidResponse: return "Invalid server response"
        case .httpError(let statusCode): return "Server error (HTTP \(statusCode))"
        case .fileTooSmall: return "Downloaded file is too small (corrupted)"
        case .verificationFailed: return "Download verification failed"
        case .insufficientStorage: return "Insufficient storage space"
        case .missingContentUrl(let track): return "Audio track \(track + 1) missing content URL"
        case .invalidAudioURL(let track, let path): return "Invalid URL for track \(track + 1): \(path)"
        case .invalidImageData: return "Invalid cover image data"
        }
    }
}


// MARK: - DownloadManager
@MainActor
@Observable
class DownloadManager {
    
    // MARK: - State
    var downloadedBooks: [Book] = []
    var downloadProgress: [String: Double] = [:]
    var isDownloading: [String: Bool] = [:]
    var downloadStatus: [String: String] = [:]
    var downloadStage: [String: DownloadStage] = [:]
    
    // MARK: - Dependencies
    // Internal repository reference
    internal private(set) var repository: DownloadRepository?
    
    init() {
        AppLogger.general.debug("[DownloadManager] Initialized")
    }
    
    // Dependency Injection method
    func configure(repository: DownloadRepository) {
        self.repository = repository
        AppLogger.general.debug("[DownloadManager] Repository configured")
    }
    
    // MARK: - Public API
    
    func downloadBook(_ book: Book, api: AudiobookshelfClient) async {
        guard let repository = repository else {
            AppLogger.general.error("[DownloadManager] Repository not configured")
            return
        }
        do { try await repository.downloadBook(book, api: api) } catch {
            AppLogger.general.error("Download failed: \(error)")
        }
    }
    
    func cancelDownload(for bookId: String) { repository?.cancelDownload(for: bookId) }
    func cancelAllDownloads() { repository?.cancelAllDownloads() }
    func deleteBook(_ bookId: String) { repository?.deleteBook(bookId) }
    func deleteAllBooks() { repository?.deleteAllBooks() }
    
    func getOfflineStatus(for bookId: String) -> OfflineStatus {
        return repository?.getOfflineStatus(for: bookId) ?? .notDownloaded
    }
    
    func isBookAvailableOffline(_ bookId: String) -> Bool {
        return getOfflineStatus(for: bookId) == .available
    }
    
    func isBookDownloaded(_ bookId: String) -> Bool {
        return repository?.isBookDownloaded(bookId) ?? false
    }
    
    func getDownloadProgress(for bookId: String) -> Double {
        return downloadProgress[bookId] ?? 0.0
    }
    
    func isDownloadingBook(_ bookId: String) -> Bool {
        return isDownloading[bookId] ?? false
    }
    
    func getLocalAudioURL(for bookId: String, chapterIndex: Int) -> URL? {
        return repository?.getLocalAudioURL(for: bookId, chapterIndex: chapterIndex)
    }
    
    func getLocalCoverURL(for bookId: String) -> URL? {
        return repository?.getLocalCoverURL(for: bookId)
    }
    
    func getTotalDownloadSize() -> Int64 {
        return repository?.getTotalDownloadSize() ?? 0
    }
    
    func getBookStorageSize(_ bookId: String) -> Int64 {
        return repository?.getBookStorageSize(bookId) ?? 0
    }
    
    func bookDirectory(for bookId: String) -> URL {
        guard let repository = repository else {
            // Fallback (safe default)
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            return documentsURL.appendingPathComponent("Downloads").appendingPathComponent(bookId)
        }
        return repository.bookDirectory(for: bookId)
    }
    
    func preloadDownloadedBooksCount() async -> Int {
        return await repository?.preloadDownloadedBooks().count ?? 0
    }
}
