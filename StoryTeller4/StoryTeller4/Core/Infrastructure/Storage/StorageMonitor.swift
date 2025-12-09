import Foundation

struct DeviceStorageInfo {
    let totalSpace: Int64
    let availableSpace: Int64
    let usedSpace: Int64
    
    var usedPercentage: Double {
        guard totalSpace > 0 else { return 0 }
        return Double(usedSpace) / Double(totalSpace)
    }
    
    var availablePercentage: Double {
        guard totalSpace > 0 else { return 0 }
        return Double(availableSpace) / Double(totalSpace)
    }
    
    func formatted(bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.includesCount = true
        return formatter.string(fromByteCount: bytes)
    }
    
    var totalSpaceFormatted: String {
        formatted(bytes: totalSpace)
    }
    
    var availableSpaceFormatted: String {
        formatted(bytes: availableSpace)
    }
    
    var usedSpaceFormatted: String {
        formatted(bytes: usedSpace)
    }
}

enum StorageWarningLevel {
    case none
    case low
    case critical
    
    var threshold: Int64 {
        switch self {
        case .none: return Int64.max
        case .low: return 500_000_000      // 500MB
        case .critical: return 100_000_000  // 100MB
        }
    }
}

protocol StorageMonitoring {
    func getStorageInfo() -> DeviceStorageInfo
    func getWarningLevel() -> StorageWarningLevel
    func hasEnoughSpace(required: Int64) -> Bool
    func calculateDirectorySize(at url: URL) -> Int64
    func formatBytes(_ bytes: Int64) -> String
}

class StorageMonitor: StorageMonitoring {
    
    private let fileManager = FileManager.default
    
    func getStorageInfo() -> DeviceStorageInfo {
        guard let systemAttributes = try? fileManager.attributesOfFileSystem(forPath: NSHomeDirectory()),
              let totalSpace = systemAttributes[.systemSize] as? Int64,
              let freeSpace = systemAttributes[.systemFreeSize] as? Int64 else {
            return DeviceStorageInfo(totalSpace: 0, availableSpace: 0, usedSpace: 0)
        }
        
        let usedSpace = totalSpace - freeSpace
        
        return DeviceStorageInfo(
            totalSpace: totalSpace,
            availableSpace: freeSpace,
            usedSpace: usedSpace
        )
    }
    
    func getWarningLevel() -> StorageWarningLevel {
        let info = getStorageInfo()
        
        if info.availableSpace < StorageWarningLevel.critical.threshold {
            return .critical
        } else if info.availableSpace < StorageWarningLevel.low.threshold {
            return .low
        } else {
            return .none
        }
    }
    
    func hasEnoughSpace(required: Int64) -> Bool {
        let info = getStorageInfo()
        return info.availableSpace >= required
    }
    
    func calculateDirectorySize(at url: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
        ) else {
            return 0
        }
        
        var totalSize: Int64 = 0
        
        for case let fileURL as URL in enumerator {
            do {
                let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                if values.isRegularFile == true, let fileSize = values.fileSize {
                    totalSize += Int64(fileSize)
                }
            } catch {
                AppLogger.general.debug("[StorageMonitor] Error reading file size: \(error)")
            }
        }
        
        return totalSize
    }
    
    func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.includesCount = true
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: bytes)
    }
}
