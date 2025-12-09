import Foundation

struct StorageState {
    var totalCacheSize: String = "Calculating..."
    var downloadedBooksCount: Int = 0
    var totalDownloadSize: String = "Calculating..."
    var isCalculatingStorage: Bool = false
    var lastCacheCleanupDate: Date?
    var cacheOperationInProgress: Bool = false
    
    mutating func updateStorage(info: StorageInfo) {
        totalCacheSize = info.totalCacheSize
        downloadedBooksCount = info.downloadedBooksCount
        totalDownloadSize = info.totalDownloadSize
    }
}
