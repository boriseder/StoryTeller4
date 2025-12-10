import SwiftUI
import Combine

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
        if image != nil || isLoading { return }
        
        loadTask?.cancel()
        hasError = false
        isLoading = true
        
        loadTask = Task { [weak self] in
            await self?.loadAuthorImage()
        }
    }
    
    private func loadAuthorImage() async {
        let cacheKey = "author_\(author.id)"
        
        if let cachedImage = cacheManager.getCachedImage(for: cacheKey) {
            updateImage(cachedImage)
            return
        }
        
        if let diskCachedImage = cacheManager.getDiskCachedImage(for: cacheKey) {
            updateImage(diskCachedImage)
            return
        }
        
        if let onlineImage = await downloadAuthorImage() {
            cacheManager.setCachedImage(onlineImage, for: cacheKey)
            updateImage(onlineImage)
            return
        }
        
        await MainActor.run {
            self.hasError = true
            self.isLoading = false
        }
    }
    
    private func updateImage(_ image: UIImage) {
        Task { @MainActor in
            self.image = image
            self.isLoading = false
        }
    }
    
    private func downloadAuthorImage() async -> UIImage? {
        guard let api = api else { return nil }
        
        // DATEN EXTRAHIEREN (auf MainActor) bevor wir in den Hintergrund gehen
        let baseURL = api.baseURLString
        let token = api.authToken
        let authorId = author.id
        
        do {
            return try await CoverDownloadManager.shared.downloadAuthorImage(
                for: authorId,
                baseURL: baseURL,
                authToken: token,
                cacheManager: CoverCacheManager.shared
            )
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
