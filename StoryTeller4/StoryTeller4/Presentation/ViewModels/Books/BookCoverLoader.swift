import SwiftUI
import AVFoundation

// MARK: - Cover Loading Errors
enum CoverLoadingError: LocalizedError {
    case invalidURL
    case downloadFailed
    case invalidImageData
    case fileSystemError
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid cover URL"
        case .downloadFailed: return "Failed to download cover"
        case .invalidImageData: return "Invalid image data"
        case .fileSystemError: return "File system error"
        }
    }
}

// MARK: - Book Cover Loader
@MainActor
class BookCoverLoader: ObservableObject {
    @Published var image: UIImage?
    @Published var isLoading: Bool = false
    @Published var hasError: Bool = false
    @Published var downloadProgress: Double = 0.0
    
    private let book: Book
    private let api: AudiobookshelfClient?
    private let downloadManager: DownloadManager?
    private let cacheManager = CoverCacheManager.shared
    private var loadTask: Task<Void, Never>?
    
    init(book: Book, api: AudiobookshelfClient? = nil, downloadManager: DownloadManager? = nil) {
        self.book = book
        self.api = api
        self.downloadManager = downloadManager
    }
    
    func load() {
        
        if image != nil {
            return
        }
        
        if isLoading {
            return
        }
        
        // Start fresh
        hasError = false
        isLoading = true
        downloadProgress = 0.0
        
        loadTask = Task { [weak self] in
            await self?.loadCoverImage()
        }
    }
    
    private func loadCoverImage() async {
        
        let memoryCacheKey = generateCacheKey()
        
        // Priority 1: Memory cache
        if let cachedImage = cacheManager.getCachedImage(for: memoryCacheKey) {
            await MainActor.run { [weak self] in
                guard let self else {
                    return
                }
                self.image = cachedImage
                self.isLoading = false
            }
            AppLogger.cache.debug("Loaded book cover from memory cache")
            return
        }
        
        // Priority 2: Disk cache
        if let diskCachedImage = cacheManager.getDiskCachedImage(for: memoryCacheKey) {
            await MainActor.run { [weak self] in
                guard let self else {
                    return
                }
                self.image = diskCachedImage
                self.isLoading = false
            }
            
            return
        }

        // Priority 3: Local downloaded cover
        if let localImage = await loadLocalCover() {
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.image = localImage
                self.isLoading = false
            }
            cacheManager.setDiskCachedImage(localImage, for: memoryCacheKey)
            AppLogger.cache.debug("Loaded book cover from local storage")
            return
        }

        // Priority 4: Embedded cover from audio files
        if let embeddedImage = await loadEmbeddedCover() {
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.image = embeddedImage
                self.isLoading = false
            }
            cacheManager.setDiskCachedImage(embeddedImage, for: memoryCacheKey)
            return
        }
        
        // Priority 5: Online cover with download and caching
        if let onlineImage = await loadOnlineCover() {
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.image = onlineImage
                self.isLoading = false
            }
            return
        }
        
        // No cover found
        await MainActor.run { [weak self] in
            guard let self else { return }
            self.hasError = true
            self.isLoading = false
        }
    }
    
    private func generateCacheKey() -> String {
        // Use consistent key regardless of download status
        // This ensures cache hits whether book is online or offline
        return "online_\(book.id)"
    }
    
    // MARK: - Local Cover Loading
    private func loadLocalCover() async -> UIImage? {
        guard let downloadManager = downloadManager,
              let localCoverURL = downloadManager.getLocalCoverURL(for: book.id),
              FileManager.default.fileExists(atPath: localCoverURL.path) else {
            return nil
        }
        
        return UIImage(contentsOfFile: localCoverURL.path)
    }
    
    // MARK: - Embedded Cover Loading
    private func loadEmbeddedCover() async -> UIImage? {
        guard let downloadManager = downloadManager else { return nil }
        
        let bookDir = downloadManager.bookDirectory(for: book.id)
        let audioDir = bookDir.appendingPathComponent("audio")
        
        guard FileManager.default.fileExists(atPath: audioDir.path) else { return nil }
        
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: audioDir,
                includingPropertiesForKeys: nil
            )
            
            let audioFiles = contents.filter {
                ["mp3", "m4a", "mp4", "flac"].contains($0.pathExtension.lowercased())
            }
            
            for audioFile in audioFiles {
                if let coverImage = await extractCoverFromAudioFile(audioFile) {
                    return coverImage
                }
            }
        } catch {
            // Silent fail
        }
        
        return nil
    }
    
    private func extractCoverFromAudioFile(_ url: URL) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        
        do {
            let metadata = try await asset.load(.commonMetadata)
            
            for item in metadata {
                if let commonKey = item.commonKey,
                   commonKey.rawValue == "artwork",
                   let data = try await item.load(.dataValue),
                   let image = UIImage(data: data) {
                    return image
                }
            }
        } catch {
            // Silent fail for individual files
        }
        
        return nil
    }
    
    // MARK: - Online Cover Loading with Download & Caching
    private func loadOnlineCover() async -> UIImage? {
        guard let api = api else { return nil }
        
        await MainActor.run { [weak self] in
            self?.downloadProgress = 0.1
        }
        
        do {
            let image = try await CoverDownloadManager.shared.downloadCover(for: book, api: api)
            await MainActor.run { [weak self] in
                self?.downloadProgress = 1.0
            }
            return image
        } catch {
            return nil
        }
    }
    
    // MARK: - Public Methods
    func preloadCover() {
        // Use weak self pattern
        if image == nil && !isLoading {
            load()
        }
    }
    
    // Safe cleanup method
    func cancelLoading() {
        loadTask?.cancel()
        loadTask = nil
        isLoading = false
    }
    
    // Proper deinit without main actor
    deinit {
        loadTask?.cancel()
    }
}

// MARK: - UserDefaults Extensions für Cache Settings
extension UserDefaults {
    private enum CacheKeys {
        static let coverCacheLimit = "cover_cache_limit"
        static let memoryCacheSize = "memory_cache_size"
        static let autoCacheCleanup = "auto_cache_cleanup"
        static let cacheOptimizationEnabled = "cache_optimization_enabled"
    }
    
    var coverCacheLimit: Int {
        get { integer(forKey: CacheKeys.coverCacheLimit) }
        set { set(newValue, forKey: CacheKeys.coverCacheLimit) }
    }
    
    var memoryCacheSize: Int {
        get { integer(forKey: CacheKeys.memoryCacheSize) }
        set { set(newValue, forKey: CacheKeys.memoryCacheSize) }
    }
    
    var autoCacheCleanup: Bool {
        get { bool(forKey: CacheKeys.autoCacheCleanup) }
        set { set(newValue, forKey: CacheKeys.autoCacheCleanup) }
    }
    
    var cacheOptimizationEnabled: Bool {
        get { bool(forKey: CacheKeys.cacheOptimizationEnabled) }
        set { set(newValue, forKey: CacheKeys.cacheOptimizationEnabled) }
    }
}
