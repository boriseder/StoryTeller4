import Foundation

protocol CalculateStorageUseCaseProtocol: Sendable {
    // StorageInfo is a simple struct (Sendable implied)
    func execute() async -> StorageInfo
}

struct StorageInfo: Sendable {
    let totalCacheSize: String
    let downloadedBooksCount: Int
    let totalDownloadSize: String
}

final class CalculateStorageUseCase: CalculateStorageUseCaseProtocol, Sendable {
    // StorageMonitor is Sendable
    private let storageMonitor: StorageMonitor
    // DownloadManager is @MainActor
    private let downloadManager: DownloadManager
    
    init(
        storageMonitor: StorageMonitor,
        downloadManager: DownloadManager
    ) {
        self.storageMonitor = storageMonitor
        self.downloadManager = downloadManager
    }
    
    func execute() async -> StorageInfo {
        // Heavy IO calculation on background thread (StorageMonitor handles file system safely)
        let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let cacheSize = storageMonitor.calculateDirectorySize(at: cacheURL)
        let cacheSizeFormatted = storageMonitor.formatBytes(cacheSize)
        
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let downloadsURL = documentsURL.appendingPathComponent("Downloads")
        let downloadsSize = storageMonitor.calculateDirectorySize(at: downloadsURL)
        let downloadsSizeFormatted = storageMonitor.formatBytes(downloadsSize)
        
        // Must await access to MainActor property
        let downloadsCount = await downloadManager.downloadedBooks.count
        
        return StorageInfo(
            totalCacheSize: cacheSizeFormatted,
            downloadedBooksCount: downloadsCount,
            totalDownloadSize: downloadsSizeFormatted
        )
    }
}
