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
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Stage 2: Fetch metadata
        onProgress(book.id, 0.10, "Fetching book details...", .fetchingMetadata)
        let fullBook = try await api.books.fetchBookDetails(bookId: book.id, retryCount: 3)

        // Stage 3: Save metadata
        onProgress(book.id, 0.15, "Saving book information...", .fetchingMetadata)
        try storageService.saveBookMetadata(fullBook, to: bookDir)
        
        // Stage 4: Download cover
        if let coverPath = fullBook.coverPath {
            onProgress(book.id, 0.20, "Downloading cover...", .downloadingCover)
            try await downloadCoverWithRetry(
                bookId: book.id,
                coverPath: coverPath,
                api: api,
                bookDir: bookDir
            )
        }
        
        // Stage 5: Download audio files
        onProgress(book.id, 0.25, "Downloading audio files...", .downloadingAudio)
        try await Task.sleep(nanoseconds: 200_000_000)
        let audioTrackCount = try await downloadAudioFiles(
            for: fullBook,
            api: api,
            bookDir: bookDir,
            onProgress: onProgress
        )
        
        // Stage 5.5: Save audio info for validation
        let audioInfo = AudioInfo(audioTrackCount: audioTrackCount)
        try storageService.saveAudioInfo(audioInfo, to: bookDir)
        AppLogger.general.debug("[DownloadOrchestration] Saved audio info: \(audioTrackCount) tracks")
        
        // RACE CONDITION FIX: Ensure all file operations are flushed to disk
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Stage 6: Validate
        onProgress(book.id, 0.95, "Verifying download...", .finalizing)
        let validation = validationService.validateBookIntegrity(
            bookId: book.id,
            storageService: storageService
        )
        
        guard validation.isValid else {
            throw DownloadError.verificationFailed
        }
        
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Stage 7: Complete
        onProgress(book.id, 1.0, "Download complete!", .complete)
        AppLogger.general.debug("[DownloadOrchestration] Successfully downloaded: \(fullBook.title)")
    }
    
    func cancelDownload(for bookId: String) {
        downloadTasks[bookId]?.cancel()
        downloadTasks.removeValue(forKey: bookId)
        AppLogger.general.debug("[DownloadOrchestration] Cancelled download: \(bookId)")
    }
    
    // MARK: - Private Methods
    
    /// Downloads book cover with retry logic
    /// Note: coverPath parameter kept for backwards compatibility but not used
    /// The API's canonical cover endpoint is /api/items/{id}/cover
    private func downloadCoverWithRetry(
        bookId: String,
        coverPath: String,
        api: AudiobookshelfClient,
        bookDir: URL
    ) async throws {
        
        var lastError: Error?
        
        for attempt in 0..<retryPolicy.maxRetries {
            do {
                // ✅ CLEAN: Network service handles URL construction and validation
                let data = try await networkService.downloadCover(bookId: bookId, api: api)
                
                let coverFile = bookDir.appendingPathComponent("cover.jpg")
                try storageService.saveCoverImage(data, to: coverFile)
                
                AppLogger.general.debug("[DownloadOrchestration] Cover saved successfully")
                return
                
            } catch {
                lastError = error
                AppLogger.general.warn("[DownloadOrchestration] Cover download attempt \(attempt + 1)/\(retryPolicy.maxRetries) failed: \(error.localizedDescription)")
                
                if retryPolicy.shouldRetry(attempt: attempt, error: error) {
                    let delay = retryPolicy.delay(for: attempt)
                    try await Task.sleep(nanoseconds: delay)
                } else {
                    break
                }
            }
        }
        
        throw DownloadError.coverDownloadFailed(underlying: lastError)
    }
    
    private func downloadAudioFiles(
        for book: Book,
        api: AudiobookshelfClient,
        bookDir: URL,
        onProgress: @escaping DownloadProgressCallback
    ) async throws -> Int {
        guard let firstChapter = book.chapters.first,
              let libraryItemId = firstChapter.libraryItemId else {
            throw DownloadError.missingLibraryItemId
        }
        
        let audioDir = bookDir.appendingPathComponent("audio", isDirectory: true)
        try FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)
        
        let session = try await networkService.createPlaybackSession(libraryItemId: libraryItemId, api: api)
        let totalTracks = session.audioTracks.count
        
        AppLogger.general.debug("[DownloadOrchestration] Downloading \(totalTracks) audio tracks")
        
        for (index, audioTrack) in session.audioTracks.enumerated() {
            // ✅ CRITICAL FIX: Properly unwrap the Optional contentUrl
            guard let contentUrl = audioTrack.contentUrl else {
                AppLogger.general.error("[DownloadOrchestration] Audio track \(index) missing contentUrl")
                throw DownloadError.missingContentUrl(track: index)
            }
            
            // ✅ Build URL safely with proper validation
            let audioURL = try buildAudioURL(
                baseURL: api.baseURLString,
                contentUrl: contentUrl,
                trackIndex: index
            )
            
            let fileName = "chapter_\(index).mp3"
            let localURL = audioDir.appendingPathComponent(fileName)
            
            try await downloadAudioFileWithRetry(
                from: audioURL,
                to: localURL,
                api: api,
                bookId: book.id,
                totalTracks: totalTracks,
                currentTrack: index,
                onProgress: onProgress
            )
        }
        
        return totalTracks
    }
    
    /// Safely constructs an audio URL with proper validation and encoding
    private func buildAudioURL(
        baseURL: String,
        contentUrl: String,
        trackIndex: Int
    ) throws -> URL {
        // Strategy 1: Try direct concatenation first (most common case)
        let urlString = "\(baseURL)\(contentUrl)"
        
        AppLogger.general.debug("[DownloadOrchestration] Building URL for track \(trackIndex): \(urlString)")
        
        if let url = URL(string: urlString) {
            return url
        }
        
        // Strategy 2: Try URL encoding the content path
        AppLogger.general.warn("[DownloadOrchestration] Direct URL creation failed, trying percent encoding")
        
        if let encodedPath = contentUrl.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
           let url = URL(string: "\(baseURL)\(encodedPath)") {
            AppLogger.general.info("[DownloadOrchestration] Successfully created URL with percent encoding")
            return url
        }
        
        // Strategy 3: Use URLComponents for complex cases
        AppLogger.general.warn("[DownloadOrchestration] Percent encoding failed, trying URLComponents")
        
        if var components = URLComponents(string: baseURL) {
            let path = contentUrl.hasPrefix("/") ? contentUrl : "/\(contentUrl)"
            components.path = components.path + path
            
            if let url = components.url {
                AppLogger.general.info("[DownloadOrchestration] Successfully created URL via URLComponents")
                return url
            }
        }
        
        // All strategies failed - throw detailed error
        AppLogger.general.error("""
            [DownloadOrchestration] Failed to build audio URL for track \(trackIndex)
            Base URL: \(baseURL)
            Content URL: \(contentUrl)
            Combined: \(urlString)
            """)
        
        throw DownloadError.invalidAudioURL(track: trackIndex, path: contentUrl)
    }
    
    private func downloadAudioFileWithRetry(
        from url: URL,
        to localURL: URL,
        api: AudiobookshelfClient,
        bookId: String,
        totalTracks: Int,
        currentTrack: Int,
        onProgress: @escaping DownloadProgressCallback
    ) async throws {
        var lastError: Error?
        
        let baseProgress = 0.25
        let audioProgressRange = 0.70
        let chapterStartProgress = baseProgress + (audioProgressRange * Double(currentTrack) / Double(totalTracks))
        let chapterEndProgress = baseProgress + (audioProgressRange * Double(currentTrack + 1) / Double(totalTracks))
        
        for attempt in 0..<retryPolicy.maxRetries {
            do {
                let chapterNum = currentTrack + 1
                let attemptInfo = attempt > 0 ? " (retry \(attempt))" : ""
                
                onProgress(bookId, chapterStartProgress, "Downloading chapter \(chapterNum)/\(totalTracks)\(attemptInfo)...", .downloadingAudio)
                
                let data = try await networkService.downloadFile(from: url, authToken: api.authToken)
                try storageService.saveAudioFile(data, to: localURL)
                
                let percentComplete = Int((Double(chapterNum) / Double(totalTracks)) * 100)
                onProgress(bookId, chapterEndProgress, "Downloaded chapter \(chapterNum)/\(totalTracks) (\(percentComplete)%)", .downloadingAudio)
                
                AppLogger.general.debug("[DownloadOrchestration] Chapter \(chapterNum)/\(totalTracks) downloaded")
                return
                
            } catch {
                lastError = error
                AppLogger.general.debug("[DownloadOrchestration] Chapter \(currentTrack + 1) attempt \(attempt + 1) failed: \(error)")
                
                if retryPolicy.shouldRetry(attempt: attempt, error: error) {
                    let delay = retryPolicy.delay(for: attempt)
                    try await Task.sleep(nanoseconds: delay)
                } else {
                    break
                }
            }
        }
        
        throw DownloadError.audioDownloadFailed(chapter: currentTrack + 1, underlying: lastError)
    }
}
