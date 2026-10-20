import Foundation

protocol CalculateStorageUseCaseProtocol: Sendable {
    func execute() async -> StorageInfo
}

struct StorageInfo: Sendable {
    let totalCacheSize: String
    let downloadedBooksCount: Int
    let totalDownloadSize: String
}

final class CalculateStorageUseCase: CalculateStorageUseCaseProtocol, Sendable {
    private let storageMonitor: StorageMonitor
    private let downloadManager: DownloadManager
    
    init(
        storageMonitor: StorageMonitor,
        downloadManager: DownloadManager
    ) {
        self.storageMonitor = storageMonitor
        self.downloadManager = downloadManager
    }
    
    func execute() async -> StorageInfo {
        let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let cacheSize = storageMonitor.calculateDirectorySize(at: cacheURL)
        let cacheSizeFormatted = storageMonitor.formatBytes(cacheSize)
        
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let downloadsURL = documentsURL.appendingPathComponent("Downloads")
        let downloadsSize = storageMonitor.calculateDirectorySize(at: downloadsURL)
        let downloadsSizeFormatted = storageMonitor.formatBytes(downloadsSize)
        
        // FIX: Access MainActor isolated property safely
        let downloadsCount = await MainActor.run {
            downloadManager.downloadedBooks.count
        }
        
        return StorageInfo(
            totalCacheSize: cacheSizeFormatted,
            downloadedBooksCount: downloadsCount,
            totalDownloadSize: downloadsSizeFormatted
        )
    }
}
