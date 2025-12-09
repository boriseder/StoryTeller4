import Foundation
import SwiftUI

// MARK: - DownloadManager (Refactored)

/// Refactored DownloadManager - now a pure data holder with ~200 lines
/// All business logic has been extracted to services and repository
class DownloadManager: ObservableObject {
    
    // MARK: - Published Properties (UI State)
    @Published var downloadedBooks: [Book] = []
    @Published var downloadProgress: [String: Double] = [:]
    @Published var isDownloading: [String: Bool] = [:]
    @Published var downloadStatus: [String: String] = [:]
    @Published var downloadStage: [String: DownloadStage] = [:]
    
    // MARK: - Private Properties
    // Exposed internally for factory access, but read-only from outside
    internal private(set) var repository: DownloadRepository?
    
    // MARK: - Initialization
    init(repository: DownloadRepository? = nil) {
        // Use dependency injection or create default implementation
        if let repository = repository {
            self.repository = repository
        } else {
            // Defer repository creation to avoid circular reference
            // The repository will be created via the factory after init
            Task { @MainActor in
                self.setupDefaultRepository()
            }
        }
        
        AppLogger.general.debug("[DownloadManager] Initialized with repository pattern")
    }
    
    private func setupDefaultRepository() {
        guard repository == nil else { return }
        
        // Create default service stack
        let networkService = DefaultDownloadNetworkService()
        let storageService = DefaultDownloadStorageService()
        let retryPolicy = ExponentialBackoffRetryPolicy()
        let validationService = DefaultDownloadValidationService()
        let orchestrationService = DefaultDownloadOrchestrationService(
            networkService: networkService,
            storageService: storageService,
            retryPolicy: retryPolicy,
            validationService: validationService
        )
        
        let healingService = DefaultBackgroundHealingService(
            storageService: storageService,
            validationService: validationService,
            onBookRemoved: { [weak self] bookId in
                Task { @MainActor in
                    self?.downloadedBooks.removeAll { $0.id == bookId }
                }
            }
        )
        
        self.repository = DefaultDownloadRepository(
            orchestrationService: orchestrationService,
            storageService: storageService,
            validationService: validationService,
            healingService: healingService,
            downloadManager: self
        )
    }
    
    // MARK: - Public API (Delegates to Repository)
    
    func downloadBook(_ book: Book, api: AudiobookshelfClient) async {
        guard let repository = repository else {
            AppLogger.general.error("[DownloadManager] Repository not initialized")
            return
        }
        
        do {
            try await repository.downloadBook(book, api: api)
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
    }
    
    func deleteAllBooks() {
        repository?.deleteAllBooks()
    }
    
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
    
    /// Gets the book directory URL for a given book ID
    /// This method delegates to the storage service through the repository
    func bookDirectory(for bookId: String) -> URL {
        // If repository is not initialized yet, return a fallback path
        guard let repository = repository else {
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let downloadsURL = documentsURL.appendingPathComponent("Downloads", isDirectory: true)
            return downloadsURL.appendingPathComponent(bookId, isDirectory: true)
        }
        
        // Delegate to repository which has access to storage service
        return repository.bookDirectory(for: bookId)
    }
    
    func preloadDownloadedBooksCount() async -> Int {
        return await repository?.preloadDownloadedBooks().count ?? 0
    }
}

// MARK: - Offline Status Enum

enum OfflineStatus {
    case notDownloaded
    case downloading
    case available
}

struct DownloadStatus {
    let isDownloaded: Bool
    let isDownloading: Bool
}

// MARK: - Download Stage Enum

enum DownloadStage: String, Equatable {
    case preparing = "Preparing..."
    case fetchingMetadata = "Getting book info..."
    case downloadingCover = "Downloading cover..."
    case downloadingAudio = "Downloading audio..."
    case finalizing = "Almost done..."
    case complete = "Complete!"
    case failed = "Failed"
    
    var icon: String {
        switch self {
        case .preparing:
            return "clock.arrow.circlepath"
        case .fetchingMetadata:
            return "doc.text.magnifyingglass"
        case .downloadingCover:
            return "photo.on.rectangle.angled"
        case .downloadingAudio:
            return "waveform.circle"
        case .finalizing:
            return "checkmark.circle"
        case .complete:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .preparing, .fetchingMetadata, .downloadingCover, .downloadingAudio:
            return .accentColor
        case .finalizing:
            return .orange
        case .complete:
            return .green
        case .failed:
            return .red
        }
    }
}

// MARK: - Download Error Types

enum DownloadError: LocalizedError {
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
        case .invalidCoverURL:
            return "Invalid cover URL"
        case .coverDownloadFailed:
            return "Failed to download cover after multiple attempts"
        case .audioDownloadFailed(let chapter, _):
            return "Failed to download chapter \(chapter) after multiple attempts"
        case .missingLibraryItemId:
            return "Book has no library item ID"
        case .invalidResponse:
            return "Invalid server response"
        case .httpError(let statusCode):
            return "Server error (HTTP \(statusCode))"
        case .fileTooSmall:
            return "Downloaded file is too small (corrupted)"
        case .verificationFailed:
            return "Download verification failed - some files are missing"
        case .insufficientStorage:
            return "Insufficient storage space. Please free up at least 500MB."
        case .missingContentUrl(let track):
            return "Audio track \(track + 1) is missing a content URL"
        case .invalidAudioURL(let track, let path):
            return "Failed to construct valid URL for audio track \(track + 1): \(path)"
        case .invalidImageData:
            return "Downloaded cover file is not a valid image"
        }
    }
}

// MARK: - Network Notification Extension

extension Notification.Name {
    static let networkConnectivityChanged = Notification.Name("networkConnectivityChanged")
}
