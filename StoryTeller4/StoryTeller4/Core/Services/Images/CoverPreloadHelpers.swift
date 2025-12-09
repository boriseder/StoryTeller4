
import Foundation

@MainActor
enum CoverPreloadHelpers {
    
    /// Preload covers for books with smart batching
    /// - Parameters:
    ///   - books: Books to preload covers for
    ///   - api: API client for fetching covers
    ///   - downloadManager: Download manager for checking offline status
    ///   - limit: Maximum number of covers to preload (default: 6)
    static func preloadIfNeeded(
        books: [Book],
        api: AudiobookshelfClient?,
        downloadManager: DownloadManager?,
        limit: Int = 6
    ) {
        guard !books.isEmpty else { return }
        guard let api = api else { return }
        
        CoverCacheManager.shared.preloadCovers(
            for: Array(books.prefix(limit)),
            api: api,
            downloadManager: downloadManager
        )
    }
    
    /// Preload covers for a single book
    /// - Parameters:
    ///   - book: Book to preload cover for
    ///   - api: API client for fetching covers
    ///   - downloadManager: Download manager for checking offline status
    static func preloadIfNeeded(
        book: Book,
        api: AudiobookshelfClient?,
        downloadManager: DownloadManager?
    ) {
        preloadIfNeeded(
            books: [book],
            api: api,
            downloadManager: downloadManager,
            limit: 1
        )
    }
}
