import Foundation

// MARK: - Progress Callback Type
typealias DownloadProgressCallback = (String, Double, String, DownloadStage) -> Void

// MARK: - Protocol
protocol DownloadOrchestrationService {
    func downloadBook(_ book: Book, api: AudiobookshelfClient, onProgress: @escaping DownloadProgressCallback) async throws
    func cancelDownload(for bookId: String)
}

// MARK: - Default Implementation
final class DefaultDownloadOrchestrationService: DownloadOrchestrationService {
    
    private let networkService: DownloadNetworkService
    private let storageService: DownloadStorageService
    private let retryPolicy: RetryPolicyService
    private let validationService: DownloadValidationService
    private var downloadTasks: [String: Task<Void, Never>] = [:]
    
    init(
        networkService: DownloadNetworkService,
        storageService: DownloadStorageService,
        retryPolicy: RetryPolicyService,
        validationService: DownloadValidationService
    ) {
        self.networkService = networkService
        self.storageService = storageService
        self.retryPolicy = retryPolicy
        self.validationService = validationService
    }
    
    // MARK: - DownloadOrchestrationService
    
    func downloadBook(_ book: Book, api: AudiobookshelfClient, onProgress: @escaping DownloadProgressCallback) async throws {
        // Stage 1: Create directory
        onProgress(book.id, 0.05, "Creating download folder...", .preparing)
        let bookDir = try storageService.createBookDirectory(for: book.id)
        
        // Stage 2: Fetch metadata
        onProgress(book.id, 0.10, "Fetching book details...", .fetchingMetadata)
        let fullBook = try await api.books.fetchBookDetails(bookId: book.id, retryCount: 3)

        // Stage 3: Save metadata
        onProgress(book.id, 0.15, "Saving book information...", .fetchingMetadata)
        try storageService.saveBookMetadata(fullBook, to: bookDir)
        
        // Stage 4: Download cover
        if let coverPath = fullBook.coverPath {
            onProgress(book.id, 0.20, "Downloading cover...", .downloadingCover)
            try await downloadCoverWithRetry(bookId: book.id, coverPath: coverPath, api: api, bookDir: bookDir)
        }
        
        // Stage 5: Download audio files
        onProgress(book.id, 0.25, "Downloading audio files...", .downloadingAudio)
        let audioTrackCount = try await downloadAudioFiles(for: fullBook, api: api, bookDir: bookDir, onProgress: onProgress)
        
        // Stage 5.5: Save audio info for validation
        // Fix: Added downloadDate parameter
        let audioInfo = AudioInfo(audioTrackCount: audioTrackCount, downloadDate: Date())
        try storageService.saveAudioInfo(audioInfo, to: bookDir)
        
        // Stage 6: Validate
        onProgress(book.id, 0.95, "Verifying download...", .finalizing)
        let validation = validationService.validateBookIntegrity(bookId: book.id, storageService: storageService)
        guard validation.isValid else { throw DownloadError.verificationFailed }
        
        // Stage 7: Complete
        onProgress(book.id, 1.0, "Download complete!", .complete)
    }
    
    func cancelDownload(for bookId: String) {
        downloadTasks[bookId]?.cancel()
        downloadTasks.removeValue(forKey: bookId)
    }
    
    // MARK: - Private Methods
    
    private func downloadCoverWithRetry(bookId: String, coverPath: String, api: AudiobookshelfClient, bookDir: URL) async throws {
        var lastError: Error?
        for attempt in 0..<retryPolicy.maxRetries {
            do {
                let data = try await networkService.downloadCover(bookId: bookId, api: api)
                let coverFile = bookDir.appendingPathComponent("cover.jpg")
                try storageService.saveCoverImage(data, to: coverFile)
                return
            } catch {
                lastError = error
                if retryPolicy.shouldRetry(attempt: attempt, error: error) {
                    try await Task.sleep(nanoseconds: retryPolicy.delay(for: attempt))
                } else { break }
            }
        }
        throw DownloadError.coverDownloadFailed(underlying: lastError)
    }
    
    private func downloadAudioFiles(for book: Book, api: AudiobookshelfClient, bookDir: URL, onProgress: @escaping DownloadProgressCallback) async throws -> Int {
        guard let firstChapter = book.chapters.first, let libraryItemId = firstChapter.libraryItemId else {
            throw DownloadError.missingLibraryItemId
        }
        
        let audioDir = bookDir.appendingPathComponent("audio", isDirectory: true)
        try FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)
        
        let session = try await networkService.createPlaybackSession(libraryItemId: libraryItemId, api: api)
        let totalTracks = session.audioTracks.count
        
        for (index, audioTrack) in session.audioTracks.enumerated() {
            guard let contentUrl = audioTrack.contentUrl else { throw DownloadError.missingContentUrl(track: index) }
            
            let audioURL = try buildAudioURL(baseURL: api.baseURLString, contentUrl: contentUrl)
            let localURL = audioDir.appendingPathComponent("chapter_\(index).mp3")
            
            try await downloadAudioFileWithRetry(from: audioURL, to: localURL, api: api, bookId: book.id, totalTracks: totalTracks, currentTrack: index, onProgress: onProgress)
        }
        return totalTracks
    }
    
    private func buildAudioURL(baseURL: String, contentUrl: String) throws -> URL {
        if let url = URL(string: "\(baseURL)\(contentUrl)") { return url }
        if let encoded = contentUrl.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
           let url = URL(string: "\(baseURL)\(encoded)") { return url }
        throw DownloadError.invalidAudioURL(track: 0, path: contentUrl)
    }
    
    private func downloadAudioFileWithRetry(from url: URL, to localURL: URL, api: AudiobookshelfClient, bookId: String, totalTracks: Int, currentTrack: Int, onProgress: @escaping DownloadProgressCallback) async throws {
        var lastError: Error?
        for attempt in 0..<retryPolicy.maxRetries {
            do {
                onProgress(bookId, Double(currentTrack)/Double(totalTracks), "Downloading track \(currentTrack+1)/\(totalTracks)", .downloadingAudio)
                let data = try await networkService.downloadFile(from: url, authToken: api.authToken)
                try storageService.saveAudioFile(data, to: localURL)
                return
            } catch {
                lastError = error
                if retryPolicy.shouldRetry(attempt: attempt, error: error) { try await Task.sleep(nanoseconds: retryPolicy.delay(for: attempt)) } else { break }
            }
        }
        throw DownloadError.audioDownloadFailed(chapter: currentTrack + 1, underlying: lastError)
    }
}
