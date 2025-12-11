import Foundation
import SwiftUI
import Combine

@MainActor
class BookCoverLoader: ObservableObject {
    @Published var image: UIImage?
    @Published var isLoading = false
    @Published var hasError = false
    
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
        
        // 1. Memory Cache (Fastest)
        if let cached = CoverCacheManager.shared.getCachedImage(for: book.id) {
            self.image = cached
            self.hasError = false
            return
        }
        
        // 2. Offline Downloads (Local Storage)
        // CHECK: If book is downloaded, use that cover!
        if let downloadManager = downloadManager,
           let localURL = downloadManager.getLocalCoverURL(for: book.id),
           let data = try? Data(contentsOf: localURL),
           let localImage = UIImage(data: data) {
            
            // Populate memory cache for next time
            CoverCacheManager.shared.setCachedImage(localImage, for: book.id)
            
            self.image = localImage
            self.hasError = false
            return
        }
        
        // 3. Disk Cache (Temp Internet Cache)
        if let diskCached = CoverCacheManager.shared.getDiskCachedImage(for: book.id) {
            self.image = diskCached
            self.hasError = false
            return
        }
        
        // 4. Network Request
        guard let api = api else {
            // No API and not found locally -> Error
            self.hasError = true
            return
        }
        
        // Safe check: does book even have a cover?
        let hasCover = book.coverPath != nil
        if !hasCover {
            self.hasError = true
            return
        }
        
        isLoading = true
        hasError = false
        
        let baseURL = api.baseURLString
        let token = api.authToken
        let bookId = book.id
        
        loadTask = Task {
            var downloadedImage: UIImage?
            
            do {
                downloadedImage = try await CoverDownloadManager.shared.downloadCover(
                    for: bookId,
                    hasCover: hasCover, // Pass bool instead of path string
                    baseURL: baseURL,
                    authToken: token,
                    cacheManager: CoverCacheManager.shared
                )
            } catch {
                AppLogger.network.error("[BookCoverLoader] Failed to download cover: \(error)")
            }
            
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
