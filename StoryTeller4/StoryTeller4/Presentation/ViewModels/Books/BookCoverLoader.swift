import Foundation
import SwiftUI
import Observation

@MainActor
@Observable
class BookCoverLoader {
    var image: UIImage?
    var isLoading = false
    var hasError = false
    
    private let book: Book
    private let api: AudiobookshelfClient?
    private let downloadManager: DownloadManager?
    private let cacheManager: any CoverCacheManagerProtocol
    private var loadTask: Task<Void, Never>?
    
    init(
        book: Book,
        api: AudiobookshelfClient?,
        downloadManager: DownloadManager?,
        cacheManager: any CoverCacheManagerProtocol = CoverCacheManager.shared
    ) {
        self.book = book
        self.api = api
        self.downloadManager = downloadManager
        self.cacheManager = cacheManager
    }
    
    func load() {
        // Cancel any existing load task
        loadTask?.cancel()
        
        // Check memory cache first
        if let cached = cacheManager.getCachedImage(for: book.id) {
            self.image = cached
            self.hasError = false
            return
        }
        
        guard let api = api else {
            self.hasError = true
            return
        }
        
        // Verify cover exists
        guard book.coverPath != nil else {
            self.hasError = true
            return
        }
        
        isLoading = true
        hasError = false
        
        // Extract for thread-safety before entering Task
        let baseURL = api.baseURLString
        let token = api.authToken
        let bookId = book.id
        let hasCover = true
        let cacheManager = self.cacheManager
        
        loadTask = Task {
            // Check disk cache asynchronously off main thread
            if let diskCached = await cacheManager.getDiskCachedImage(for: bookId) {
                guard !Task.isCancelled else { return }
                self.image = diskCached
                self.isLoading = false
                self.hasError = false
                return
            }
            
            var downloadedImage: UIImage?
            
            do {
                downloadedImage = try await CoverDownloadManager.shared.downloadCover(
                    for: bookId,
                    hasCover: hasCover,
                    baseURL: baseURL,
                    authToken: token,
                    cacheManager: cacheManager
                )
            } catch {
                AppLogger.network.error("[BookCoverLoader] Failed to download cover: \(error)")
            }
            
            // Check if task was cancelled
            guard !Task.isCancelled else { return }
            
            self.isLoading = false
            if let image = downloadedImage {
                self.image = image
                self.hasError = false
            } else {
                self.hasError = true
            }
        }
    }
    
    func cancelLoading() {
        loadTask?.cancel()
        loadTask = nil
        isLoading = false
    }
    
    func preloadCover() {
        load()
    }
}
