import Foundation

protocol ClearCacheUseCaseProtocol {
    func execute() async throws
}

class ClearCacheUseCase: ClearCacheUseCaseProtocol {
    private let coverCacheManager: CoverCacheManager
    
    init(coverCacheManager: CoverCacheManager) {
        self.coverCacheManager = coverCacheManager
    }
    
    func execute() async throws {
        let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        
        let contents = try FileManager.default.contentsOfDirectory(
            at: cacheURL,
            includingPropertiesForKeys: nil
        )
        
        for item in contents {
            try? FileManager.default.removeItem(at: item)
        }
        
        await MainActor.run {
            coverCacheManager.clearAllCache()
        }
        
        AppLogger.general.debug("[ClearCacheUseCase] Cache cleared successfully")
    }
}
