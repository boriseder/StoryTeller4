import SwiftUI

// MARK: - Cover Download Manager
actor CoverDownloadManager {
    static let shared = CoverDownloadManager()
    
    private var downloadTasks: [String: Task<UIImage?, Error>] = [:]
    
    private init() {}
    
    func downloadCover(
        for bookId: String,
        hasCover: Bool, // Renamed from coverPath to reflect intent
        baseURL: String,
        authToken: String,
        cacheManager: CoverCacheManager
    ) async throws -> UIImage? {
        // Fast exit if metadata says no cover exists
        guard hasCover else { return nil }
        
        let cacheKey = "online_\(bookId)"
        
        if let existingTask = downloadTasks[cacheKey] {
            return try await existingTask.value
        }
        
        let task = Task<UIImage?, Error> {
            defer { Task { self.removeTask(for: cacheKey) } }
            
            // CLEAN CODE: Use centralized endpoint logic
            guard let url = await APIEndpoint.cover(bookId: bookId).url(baseURL: baseURL) else {
                throw CoverLoadingError.invalidURL
            }
            
            var request = URLRequest(url: url)
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 30.0
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw CoverLoadingError.downloadFailed
            }
            
            guard let image = UIImage(data: data) else {
                throw CoverLoadingError.invalidImageData
            }
            
            await MainActor.run {
                cacheManager.setDiskCachedImage(image, for: bookId)
            }
            
            return image
        }
        
        downloadTasks[cacheKey] = task
        
        do {
            return try await task.value
        } catch {
            removeTask(for: cacheKey)
            throw error
        }
    }
    
    func downloadAuthorImage(
            for authorId: String,
            baseURL: String,
            authToken: String,
            cacheManager: CoverCacheManager
        ) async throws -> UIImage? {
            let cacheKey = "author_\(authorId)"
            
            if let existingTask = downloadTasks[cacheKey] {
                return try await existingTask.value
            }
            
            let task = Task<UIImage?, Error> {
                defer { Task { self.removeTask(for: cacheKey) } }
                
                // CLEAN CODE: Use centralized endpoint logic
                guard let url = await APIEndpoint.authorImage(authorId: authorId).url(baseURL: baseURL) else {
                    throw CoverLoadingError.invalidURL
                }
                
                var request = URLRequest(url: url)
                request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
                request.timeoutInterval = 30.0
                
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    throw CoverLoadingError.downloadFailed
                }
                
                guard let image = UIImage(data: data) else {
                    throw CoverLoadingError.invalidImageData
                }
                
                await MainActor.run {
                    cacheManager.setDiskCachedImage(image, for: cacheKey)
                }
                
                return image
            }
            
            downloadTasks[cacheKey] = task
            
            do {
                return try await task.value
            } catch {
                removeTask(for: cacheKey)
                throw error
            }
        }
    private func removeTask(for cacheKey: String) {
            downloadTasks.removeValue(forKey: cacheKey)
        }
        
        func cancelAllDownloads() {
            downloadTasks.values.forEach { $0.cancel() }
            downloadTasks.removeAll()
        }
        
        func shutdown() {
            cancelAllDownloads()
        }
    }


enum CoverLoadingError: Error {
    case invalidURL
    case downloadFailed
    case invalidImageData
}
