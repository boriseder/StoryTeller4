import SwiftUI
import Observation

// MARK: - Universal Media Image Loader
/// Unified loader for book covers, author portraits, and audiobookshelf media assets.
@MainActor
@Observable
class MediaImageLoader {
    var image: UIImage?
    var isLoading = false
    var hasError = false
    
    private let cacheKey: String
    private let imagePath: String?
    private let api: AudiobookshelfClient?
    private let cacheManager: any CoverCacheManagerProtocol
    private var loadTask: Task<Void, Never>?
    
    init(
        cacheKey: String,
        imagePath: String?,
        api: AudiobookshelfClient?,
        cacheManager: any CoverCacheManagerProtocol = CoverCacheManager.shared
    ) {
        self.cacheKey = cacheKey
        self.imagePath = imagePath
        self.api = api
        self.cacheManager = cacheManager
    }
    
    func load() {
        if image != nil || isLoading { return }
        
        loadTask?.cancel()
        hasError = false
        isLoading = true
        
        if let cached = cacheManager.getCachedImage(for: cacheKey) {
            self.image = cached
            self.isLoading = false
            return
        }
        
        loadTask = Task {
            if let diskCached = await cacheManager.getDiskCachedImage(for: cacheKey) {
                self.image = diskCached
                self.isLoading = false
                return
            }
            
            guard let api = api, let path = imagePath, !path.isEmpty else {
                self.hasError = true
                self.isLoading = false
                return
            }
            
            let fullURLString = "\(api.baseURLString)\(path.hasPrefix("/") ? path : "/" + path)"
            guard let url = URL(string: fullURLString) else {
                self.hasError = true
                self.isLoading = false
                return
            }
            
            var request = URLRequest(url: url)
            if !api.authToken.isEmpty {
                request.addValue("Bearer \(api.authToken)", forHTTPHeaderField: "Authorization")
            }
            
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200,
                      let downloadedImage = UIImage(data: data) else {
                    self.hasError = true
                    self.isLoading = false
                    return
                }
                
                cacheManager.setCachedImage(downloadedImage, for: cacheKey)
                self.image = downloadedImage
                self.isLoading = false
            } catch {
                if !Task.isCancelled {
                    self.hasError = true
                    self.isLoading = false
                }
            }
        }
    }
    
    func cancel() {
        loadTask?.cancel()
        loadTask = nil
    }
}
