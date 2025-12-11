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
        
        guard let coverPath = book.coverPath else {
            self.hasError = true
            return
        }
        
        isLoading = true
        hasError = false
        
        // Extract for thread-safety
        let baseURL = api.baseURLString
        let token = api.authToken
        let bookId = book.id
        
        loadTask = Task {
            var downloadedImage: UIImage?
            
            do {
                downloadedImage = try await CoverDownloadManager.shared.downloadCover(
                    for: bookId,
                    coverPath: coverPath,
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
