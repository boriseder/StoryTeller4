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
    private var loadTask: Task<Void, Never>?
    
    init(book: Book, api: AudiobookshelfClient?, downloadManager: DownloadManager?) {
        self.book = book
        self.api = api
        self.downloadManager = downloadManager
    }
    
    func load() {
        // Cancel any existing load task
        loadTask?.cancel()
        
        // Check caches first
        if let cached = CoverCacheManager.shared.getCachedImage(for: book.id) {
            self.image = cached
            self.hasError = false
            return
        }
        
        if let diskCached = CoverCacheManager.shared.getDiskCachedImage(for: book.id) {
            self.image = diskCached
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
        // Note: We don't use the raw string path anymore in the manager, passing true effectively
        let hasCover = true
        
        loadTask = Task {
            var downloadedImage: UIImage?
            
            do {
                downloadedImage = try await CoverDownloadManager.shared.downloadCover(
                    for: bookId,
                    hasCover: hasCover,
                    baseURL: baseURL,
                    authToken: token,
                    cacheManager: CoverCacheManager.shared
                )
            } catch {
                AppLogger.network.error("[BookCoverLoader] Failed to download cover: \(error)")
            }
            
            // Check if task was cancelled
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                self.isLoading = false
                if let image = downloadedImage {
                    self.image = image
                    self.hasError = false
                } else {
                    self.hasError = true
                }
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
