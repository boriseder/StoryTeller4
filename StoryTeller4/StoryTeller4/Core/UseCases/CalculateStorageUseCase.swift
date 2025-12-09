import Foundation

protocol CalculateStorageUseCaseProtocol {
    func execute() async -> StorageInfo
}

struct StorageInfo {
    let totalCacheSize: String
    let downloadedBooksCount: Int
    let totalDownloadSize: String
}

class CalculateStorageUseCase: CalculateStorageUseCaseProtocol {
    private let storageMonitor: StorageMonitoring
    private let downloadManager: DownloadManager
    
    init(
        storageMonitor: StorageMonitoring,
        downloadManager: DownloadManager
    ) {
        self.storageMonitor = storageMonitor
        self.downloadManager = downloadManager
    }
    
    func execute() async -> StorageInfo {
        let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let cacheSize = storageMonitor.calculateDirectorySize(at: cacheURL)
        let cacheSizeFormatted = storageMonitor.formatBytes(cacheSize)
        
        let downloadsCount = downloadManager.downloadedBooks.count
        
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let downloadsURL = documentsURL.appendingPathComponent("Downloads")
        let downloadsSize = storageMonitor.calculateDirectorySize(at: downloadsURL)
        let downloadsSizeFormatted = storageMonitor.formatBytes(downloadsSize)
        
        return StorageInfo(
            totalCacheSize: cacheSizeFormatted,
            downloadedBooksCount: downloadsCount,
            totalDownloadSize: downloadsSizeFormatted
        )
    }
}
