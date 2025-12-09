
import SwiftUI

// MARK: - Author Image Loader
@MainActor
class AuthorImageLoader: ObservableObject {
    @Published var image: UIImage?
    @Published var isLoading: Bool = false
    @Published var hasError: Bool = false
    
    private let author: Author
    private let api: AudiobookshelfClient?
    private let cacheManager = CoverCacheManager.shared
    private var loadTask: Task<Void, Never>?
    
    init(author: Author, api: AudiobookshelfClient? = nil) {
        self.author = author
        self.api = api
    }
    
    func load() {
        // Skip if already loaded or currently loading
        if image != nil || isLoading {
            return
        }
        
        loadTask?.cancel()
        hasError = false
        isLoading = true
        
        loadTask = Task { [weak self] in
            await self?.loadAuthorImage()
        }
    }
    
    private func loadAuthorImage() async {
        let cacheKey = "author_\(author.id)"
        
        // Priority 1: Memory cache
        if let cachedImage = cacheManager.getCachedImage(for: cacheKey) {
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.image = cachedImage
                self.isLoading = false
            }
            AppLogger.cache.debug("Loaded author image from memory cache")
            return
        }
        
        // Priority 2: Disk cache
        if let diskCachedImage = cacheManager.getDiskCachedImage(for: cacheKey) {
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.image = diskCachedImage
                self.isLoading = false
            }
            AppLogger.cache.debug("Loaded author image from disk cache")
            return
        }
        
        // Priority 3: Download from server using CoverDownloadManager
        if let onlineImage = await downloadAuthorImage() {
            // Cache the downloaded image
            cacheManager.setCachedImage(onlineImage, for: cacheKey)
            cacheManager.setDiskCachedImage(onlineImage, for: cacheKey)
            
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.image = onlineImage
                self.isLoading = false
            }
            AppLogger.cache.debug("Downloaded and cached author image")
            return
        }
        
        // No image found
        await MainActor.run { [weak self] in
            guard let self else { return }
            self.hasError = true
            self.isLoading = false
        }
    }
    
    private func downloadAuthorImage() async -> UIImage? {
        guard let api = api else {
            return nil
        }
        
        // Use CoverDownloadManager to download (it handles baseURL and auth)
        do {
            let image = try await CoverDownloadManager.shared.downloadAuthorImage(
                for: author,
                api: api
            )
            return image
        } catch {
            AppLogger.network.error("Failed to download author image: \(error)")
            return nil
        }
    }
    
    func cancelLoading() {
        loadTask?.cancel()
        loadTask = nil
        isLoading = false
    }
    
    deinit {
        loadTask?.cancel()
    }
}

