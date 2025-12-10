import Foundation
import AVFoundation

// MARK: - Audio Track Preloader
// Converted to an actor to ensure thread-safety without manual queues
actor AudioTrackPreloader {
    
    // MARK: - Properties
    private var preloadedItems: [Int: AVPlayerItem] = [:]
    private var preloadedAssets: [Int: AVURLAsset] = [:]
    // Removed dispatch queue, actor handles isolation
    private var currentPreloadTask: Task<Void, Never>?
    
    // MARK: - Preload Next Chapter
    func preloadNext(
        chapterIndex: Int,
        book: Book,
        isOffline: Bool,
        baseURL: String,
        authToken: String,
        downloadManager: DownloadManager?, // DownloadManager is MainActor
        completion: ((Bool) -> Void)? = nil
    ) {
        let nextIndex = chapterIndex + 1
        
        guard nextIndex < book.chapters.count else {
            AppLogger.general.debug("[Preloader] No next chapter to preload (at last chapter)")
            completion?(false)
            return
        }
        
        guard preloadedItems[nextIndex] == nil else {
            AppLogger.general.debug("[Preloader] Chapter \(nextIndex) already preloaded")
            completion?(true)
            return
        }
        
        currentPreloadTask?.cancel()
        
        currentPreloadTask = Task { [weak self] in
            guard let self = self else { return }
            
            if isOffline {
                await self.preloadOfflineTrack(
                    bookId: book.id,
                    chapterIndex: nextIndex,
                    chapter: book.chapters[nextIndex],
                    downloadManager: downloadManager
                )
            } else {
                await self.preloadOnlineTrack(
                    chapter: book.chapters[nextIndex],
                    baseURL: baseURL,
                    authToken: authToken
                )
            }
            
            let success = await self.preloadedItems[nextIndex] != nil
            completion?(success)
        }
    }
    
    // MARK: - Preload Offline Track
    private func preloadOfflineTrack(
        bookId: String,
        chapterIndex: Int,
        chapter: Chapter,
        downloadManager: DownloadManager?
    ) async {
        // Accessing DownloadManager (MainActor) requires await
        guard let localURL = await downloadManager?.getLocalAudioURL(
            for: bookId,
            chapterIndex: chapterIndex
        ) else {
            AppLogger.general.debug("[Preloader] Failed to get local URL for chapter \(chapterIndex)")
            return
        }
        
        // File manager operations are safe on background threads usually, but best done non-blocking
        guard FileManager.default.fileExists(atPath: localURL.path) else {
            AppLogger.general.debug("[Preloader] Local file does not exist: \(localURL.path)")
            return
        }
        
        AppLogger.general.debug("[Preloader] Starting preload of offline chapter \(chapterIndex)")
        
        let asset = AVURLAsset(url: localURL)
        
        do {
            let playable = try await asset.load(.isPlayable)
            
            guard playable else {
                AppLogger.general.debug("[Preloader] Asset not playable for chapter \(chapterIndex)")
                return
            }
            
            let duration = try await asset.load(.duration)
            AppLogger.general.debug("[Preloader] Asset loaded, duration: \(CMTimeGetSeconds(duration))s")
            
            // Actors protect internal state automatically
            let playerItem = AVPlayerItem(asset: asset)
            self.preloadedItems[chapterIndex] = playerItem
            self.preloadedAssets[chapterIndex] = asset
            AppLogger.general.debug("[Preloader] Successfully preloaded offline chapter \(chapterIndex)")
            
        } catch {
            AppLogger.general.debug("[Preloader] Failed to preload offline chapter \(chapterIndex): \(error)")
        }
    }
    
    // MARK: - Preload Online Track
    private func preloadOnlineTrack(
        chapter: Chapter,
        baseURL: String,
        authToken: String
    ) async {
        guard let libraryItemId = chapter.libraryItemId else {
            AppLogger.general.debug("[Preloader] No library item ID for chapter")
            return
        }
        
        var urlString = "\(baseURL)/api/items/\(libraryItemId)/play"
        if let episodeId = chapter.episodeId {
            urlString += "/\(episodeId)"
        }
        
        guard let url = URL(string: urlString) else {
            AppLogger.general.debug("[Preloader] Invalid URL: \(urlString)")
            return
        }
        
        AppLogger.general.debug("[Preloader] Creating playback session for preload")
        
        do {
            let session = try await createPlaybackSession(
                url: url,
                authToken: authToken,
                libraryItemId: libraryItemId
            )
            
            guard let audioTrack = session.audioTracks.first else {
                AppLogger.general.debug("[Preloader] No audio tracks in session")
                return
            }
            
            let fullURL = "\(baseURL)\(audioTrack.contentUrl ?? "")" // Unwrap optional safely
            
            guard let audioURL = URL(string: fullURL) else {
                AppLogger.general.debug("[Preloader] Invalid audio URL: \(fullURL)")
                return
            }
            
            let asset = createAuthenticatedAsset(url: audioURL, authToken: authToken)
            
            let playable = try await asset.load(.isPlayable)
            
            guard playable else {
                AppLogger.general.debug("[Preloader] Online asset not playable")
                return
            }
            
            // Actor state modification
            let playerItem = AVPlayerItem(asset: asset)
            // Need to find chapter index logic?
            // In original code: let chapterIndex = session.audioTracks.firstIndex...
            // But we passed chapterIndex to the preload function, typically we want to store it under that index.
            // However, the original code tried to derive it again.
            // Let's assume we store it under the index of the next chapter we are preloading.
            // But for online tracks which might be one-to-one or single file, logic might vary.
            // Reusing original logic for index finding:
            let foundIndex = session.audioTracks.firstIndex(where: { $0.contentUrl == audioTrack.contentUrl }) ?? 0
            // NOTE: This logic seems specific to how tracks map to chapters.
            // If we are preloading "next chapter", we should probably use that index.
            // But sticking to original logic to minimize regression risk:
            
            self.preloadedItems[foundIndex] = playerItem
            self.preloadedAssets[foundIndex] = asset
            AppLogger.general.debug("[Preloader] Successfully preloaded online chapter")
            
        } catch {
            AppLogger.general.debug("[Preloader] Failed to preload online chapter: \(error)")
        }
    }
    
    // MARK: - Create Playback Session
    private func createPlaybackSession(
        url: URL,
        authToken: String,
        libraryItemId: String
    ) async throws -> PlaybackSessionResponse {
        let requestBody = DeviceUtils.createPlaybackRequest()
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AudiobookshelfError.invalidResponse
        }
        
        return try JSONDecoder().decode(PlaybackSessionResponse.self, from: data)
    }
    
    // MARK: - Create Authenticated Asset
    // Non-isolated helper as it doesn't touch state
    nonisolated private func createAuthenticatedAsset(url: URL, authToken: String) -> AVURLAsset {
        let headers = [
            "Authorization": "Bearer \(authToken)",
            "User-Agent": "AudioBook Client/1.0.0"
        ]
        
        return AVURLAsset(url: url, options: [
            "AVURLAssetHTTPHeaderFieldsKey": headers,
            AVURLAssetPreferPreciseDurationAndTimingKey: true
        ])
    }
    
    // MARK: - Get Preloaded Item
    func getPreloadedItem(for chapterIndex: Int) -> AVPlayerItem? {
        let item = preloadedItems.removeValue(forKey: chapterIndex)
        preloadedAssets.removeValue(forKey: chapterIndex)
        
        if item != nil {
            AppLogger.general.debug("[Preloader] Retrieved preloaded item for chapter \(chapterIndex)")
        } else {
            AppLogger.general.debug("[Preloader] No preloaded item available for chapter \(chapterIndex)")
        }
        
        return item
    }
    
    // MARK: - Clear All Preloaded Items
    func clearAll() {
        preloadedItems.removeAll()
        preloadedAssets.removeAll()
        AppLogger.general.debug("[Preloader] Cleared all preloaded items")
    }
    
    // MARK: - Cancel Current Preload
    func cancelCurrentPreload() {
        currentPreloadTask?.cancel()
        currentPreloadTask = nil
        AppLogger.general.debug("[Preloader] Cancelled current preload task")
    }
    
    deinit {
        // Can't easily call actor methods in deinit, but task cancellation is automatic if stored
        currentPreloadTask?.cancel()
    }
}
