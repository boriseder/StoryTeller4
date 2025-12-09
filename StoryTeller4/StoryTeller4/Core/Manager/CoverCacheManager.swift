import SwiftUI

enum MemoryPressureLevel {
    case warning    // Standard iOS memory warning
    case critical   // Manual trigger for critical situations
}

// MARK: - Cover Cache Manager
@MainActor
class CoverCacheManager: ObservableObject {
    static let shared = CoverCacheManager()
    
    private let cache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private var observers: [NSObjectProtocol] = []

    private init() {
        // Setup memory cache
        cache.countLimit = 100
        cache.totalCostLimit = 50 * 1024 * 1024 // 100MB
        
        // Setup disk cache directory
        let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDirectory = cachesURL.appendingPathComponent("BookCovers", isDirectory: true)
        
        createCacheDirectory()
        
        // Setup memory warning handling
        setupMemoryWarningHandling()
    }
    
    // Memory Warning Setup ohne Sendable closure
    private func setupMemoryWarningHandling() {
        // Memory warning observer
        let memoryObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleMemoryPressure(level: .warning)
            }
        }
        observers.append(memoryObserver)
        
        // Background observer
        let backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                AppLogger.general.debug("App backgrounded - clearing memory cache")
                self?.cache.removeAllObjects()
            }
        }
        observers.append(backgroundObserver)
    }
    
    private func createCacheDirectory() {
        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
    }
    
    // MARK: - Memory Cache
    func getCachedImage(for key: String) -> UIImage? {
        return cache.object(forKey: NSString(string: key))
    }
    
    func setCachedImage(_ image: UIImage, for key: String) {
        let cost = Int(image.size.width * image.size.height * 4) // Rough memory estimate
        cache.setObject(image, forKey: NSString(string: key), cost: cost)
    }
    
    // MARK: - Disk Cache
    private func diskCacheURL(for key: String) -> URL {
        let safeKey = key.removingPercentEncoding ?? key
        let filename = safeKey.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? safeKey
        return cacheDirectory.appendingPathComponent("\(filename).jpg")
    }
    
    func getDiskCachedImage(for key: String) -> UIImage? {
        let url = diskCacheURL(for: key)
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else {
            return nil
        }
        
        // Also store in memory cache
        setCachedImage(image, for: key)
        return image
    }
    
    func setDiskCachedImage(_ image: UIImage, for key: String) {
        let url = diskCacheURL(for: key)
        guard let data = image.jpegData(compressionQuality: 0.8) else { return }
        
        // Prüfen, ob Datei schon existiert
        guard !fileManager.fileExists(atPath: url.path) else {
            AppLogger.cache.debug("Image already cached for key: \(key)")
            return
        }

        
        try? data.write(to: url)
        setCachedImage(image, for: key)
        
    }
    
    // MARK: - Cache Management
    func clearMemoryCache() {
        cache.removeAllObjects()
    }
    
    func clearDiskCache() {
        try? fileManager.removeItem(at: cacheDirectory)
        createCacheDirectory()
    }
    
    func clearAllCache() {
        clearMemoryCache()
        clearDiskCache()
    }
    
    func handleMemoryPressure(level: MemoryPressureLevel) {
        switch level {
        case .warning:
            handleMemoryWarning()
            
        case .critical:
            handleCriticalMemory()
        }
    }

    private func handleMemoryWarning() {
        AppLogger.general.debug("Memory warning - clearing memory cache")
        
        // Clear memory cache
        cache.removeAllObjects()
        
        // Cancel low-priority downloads
        Task {
            await CoverDownloadManager.shared.cancelAllDownloads()
        }
    }

    private func handleCriticalMemory() {
        AppLogger.general.debug("Critical memory pressure - aggressive cleanup")
        
        // Clear memory cache
        cache.removeAllObjects()
        
        // Clear old disk cache items (keep only 20 most recent)
        clearOldestDiskCacheItems(keepCount: 20)
        
        // Cancel ALL downloads
        Task {
            await CoverDownloadManager.shared.shutdown()
        }
    }

    // MARK: - Public Memory Management

    /// Trigger critical memory cleanup manually
    /// Use when app detects severe memory pressure
    func triggerCriticalCleanup() {
        handleMemoryPressure(level: .critical)
    }
    
    func getCacheSize() -> Int64 {
        guard let enumerator = fileManager.enumerator(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        
        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
               resourceValues.isRegularFile == true,
               let fileSize = resourceValues.fileSize {
                totalSize += Int64(fileSize)
            }
        }
        return totalSize
    }
    
    // MARK: - Dynamic Cache Configuration
    func updateCacheLimits() {
        let countLimit = UserDefaults.standard.integer(forKey: "cover_cache_limit")
        let sizeLimit = UserDefaults.standard.integer(forKey: "memory_cache_size")
        
        cache.countLimit = countLimit > 0 ? countLimit : 100
        cache.totalCostLimit = (sizeLimit > 0 ? sizeLimit : 50) * 1024 * 1024 // MB to bytes
        
    }
    
    // MARK: - Cache Optimization
    func optimizeCache() async {
        // Remove corrupted files
        let corruptedFiles = findCorruptedCacheFiles()
        for file in corruptedFiles {
            try? fileManager.removeItem(at: file)
        }
        
        // Clean up old files if cache is too large
        if getCacheSize() > 200 * 1024 * 1024 { // 200MB threshold
            clearOldestDiskCacheItems(keepCount: 100)
        }
        
        AppLogger.general.debug("[CoverCache] Cache optimization completed")
    }
    
    private func findCorruptedCacheFiles() -> [URL] {
        guard let enumerator = fileManager.enumerator(at: cacheDirectory, includingPropertiesForKeys: nil) else {
            return []
        }
        
        var corruptedFiles: [URL] = []
        
        for case let fileURL as URL in enumerator {
            // Try to load image to check if it's corrupted
            if let data = try? Data(contentsOf: fileURL),
               UIImage(data: data) == nil {
                corruptedFiles.append(fileURL)
            }
        }
        
        return corruptedFiles
    }
    
    private func clearOldestDiskCacheItems(keepCount: Int = 50) {
        guard let enumerator = fileManager.enumerator(
            at: cacheDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]
        ) else { return }
        
        var files: [(URL, Date)] = []
        
        for case let fileURL as URL in enumerator {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
                if resourceValues.isRegularFile == true,
                   let modificationDate = resourceValues.contentModificationDate {
                    files.append((fileURL, modificationDate))
                }
            } catch {
                AppLogger.general.debug("[CoverCache] Error reading file attributes: \(error)")
            }
        }
        
        // Sort by modification date (oldest first)
        files.sort { $0.1 < $1.1 }
        
        // Remove oldest files if we exceed keepCount
        let filesToRemove = files.dropLast(keepCount)
        for (fileURL, _) in filesToRemove {
            try? fileManager.removeItem(at: fileURL)
        }
        
        if !filesToRemove.isEmpty {
            AppLogger.general.debug("[CoverCache] Removed \(filesToRemove.count) old cache files")
        }
    }
    
    // MARK: - Preloading
    func preloadCovers(for books: [Book], api: AudiobookshelfClient?, downloadManager: DownloadManager?) {
        Task { @MainActor in
            for book in books.prefix(10) { // Limit preloading
                let loader = BookCoverLoader(book: book, api: api, downloadManager: downloadManager)
                loader.preloadCover()
            }
        }
    }
}
