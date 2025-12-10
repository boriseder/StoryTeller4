import Foundation
import UIKit
import Combine

actor CoverDownloadManager {
    static let shared = CoverDownloadManager()
    
    private var activeDownloads: [String: Task<UIImage?, Error>] = [:]
    
    // Dependencies should be passed in methods to avoid actor state issues
    // or stored if they are Sendable.
    
    func downloadCover(
        for bookId: String,
        coverPath: String?,
        api: AudiobookshelfClient,
        cacheManager: CoverCacheManager
    ) async -> UIImage? {
        guard let coverPath = coverPath else { return nil }
        
        // Check memory cache (MainActor access required for CoverCacheManager if it's ObservableObject)
        // We'll assume the caller might have checked, but let's check here via Task if needed.
        // Actually, for performance, memory cache check should ideally be done by caller (UI).
        // Here we handle the download logic.
        
        // Deduplicate downloads
        if let existingTask = activeDownloads[bookId] {
            return try? await existingTask.value
        }
        
        // Capture configuration values synchronously to avoid actor isolation errors
        // api is a class, so accessing properties might be restricted.
        let baseURL = api.baseURLString
        let token = api.authToken
        
        let task = Task<UIImage?, Error> {
            // Construct URL
            guard let url = URL(string: "\(baseURL)\(coverPath)") else {
                throw DownloadError.invalidCoverURL
            }
            
            // Create Request
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            // Perform Request
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw DownloadError.invalidResponse
            }
            
            guard let image = UIImage(data: data) else {
                throw DownloadError.invalidImageData
            }
            
            // Resize if needed (expensive operation off main thread)
            let processedImage = image.preparingThumbnail(of: CGSize(width: 300, height: 450)) ?? image
            
            // Cache (fire and forget on MainActor)
            Task { @MainActor in
                cacheManager.setDiskCachedImage(processedImage, for: bookId)
            }
            
            return processedImage
        }
        
        activeDownloads[bookId] = task
        
        do {
            let result = try await task.value
            activeDownloads[bookId] = nil
            return result
        } catch {
            activeDownloads[bookId] = nil
            return nil
        }
    }
    
    func cancelAllDownloads() {
        for task in activeDownloads.values {
            task.cancel()
        }
        activeDownloads.removeAll()
    }
    
    func shutdown() {
        cancelAllDownloads()
    }
}
