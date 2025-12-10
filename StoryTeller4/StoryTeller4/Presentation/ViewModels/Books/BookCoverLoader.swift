import Foundation
import SwiftUI
import Combine

@MainActor
class BookCoverLoader: ObservableObject {
    @Published var image: UIImage?
    @Published var isLoading = false
    
    private let book: Book
    private let api: AudiobookshelfClient?
    private let downloadManager: DownloadManager?
    
    init(book: Book, api: AudiobookshelfClient?, downloadManager: DownloadManager?) {
        self.book = book
        self.api = api
        self.downloadManager = downloadManager
    }
    
    func loadCover() {
        // 1. Try Memory/Disk Cache synchronously if possible
        if let cached = CoverCacheManager.shared.getCachedImage(for: book.id) {
            self.image = cached
            return
        }
        
        if let diskCached = CoverCacheManager.shared.getDiskCachedImage(for: book.id) {
            self.image = diskCached
            return
        }
        
        // 2. Download
        guard let api = api else { return }
        guard let coverPath = book.coverPath else { return }
        
        isLoading = true
        
        // Capture strings on MainActor before passing to background actor to avoid isolation issues
        let baseURL = api.baseURLString
        let token = api.authToken
        let bookId = book.id
        
        Task {
            var downloadedImage: UIImage?
            
            do {
                // Fix: Added 'try' to the throwing async call
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
            
            // Capture result for MainActor update
            let finalImage = downloadedImage
            
            Task { @MainActor in
                self.isLoading = false
                if let image = finalImage {
                    self.image = image
                }
            }
        }
    }
    
    func preloadCover() {
        loadCover()
    }
}
