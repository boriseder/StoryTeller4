import Foundation
import AVFoundation

// MARK: - Audio Track Preloader
class AudioTrackPreloader {
    
    // MARK: - Properties
    private var preloadedItems: [Int: AVPlayerItem] = [:]
    private var preloadedAssets: [Int: AVURLAsset] = [:]
    private let queue = DispatchQueue(label: "com.storyteller.preload", qos: .utility)
    private var currentPreloadTask: Task<Void, Never>?
    
    // MARK: - Preload Next Chapter
    func preloadNext(
        chapterIndex: Int,
        book: Book,
        isOffline: Bool,
        baseURL: String,
        authToken: String,
        downloadManager: DownloadManager?,
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
            
            completion?(self.preloadedItems[nextIndex] != nil)
        }
    }
    
    // MARK: - Preload Offline Track
    private func preloadOfflineTrack(
        bookId: String,
        chapterIndex: Int,
        chapter: Chapter,
        downloadManager: DownloadManager?
    ) async {
        guard let localURL = downloadManager?.getLocalAudioURL(
            for: bookId,
            chapterIndex: chapterIndex
        ) else {
            AppLogger.general.debug("[Preloader] Failed to get local URL for chapter \(chapterIndex)")
            return
        }
        
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
            
            await MainActor.run {
                let playerItem = AVPlayerItem(asset: asset)
                self.preloadedItems[chapterIndex] = playerItem
                self.preloadedAssets[chapterIndex] = asset
                AppLogger.general.debug("[Preloader] Successfully preloaded offline chapter \(chapterIndex)")
            }
            
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
            
            let fullURL = "\(baseURL)\(audioTrack.contentUrl)"
            
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
            
            await MainActor.run {
                let playerItem = AVPlayerItem(asset: asset)
                let chapterIndex = session.audioTracks.firstIndex(where: { $0.contentUrl == audioTrack.contentUrl }) ?? 0
                self.preloadedItems[chapterIndex] = playerItem
                self.preloadedAssets[chapterIndex] = asset
                AppLogger.general.debug("[Preloader] Successfully preloaded online chapter")
            }
            
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
    private func createAuthenticatedAsset(url: URL, authToken: String) -> AVURLAsset {
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
        queue.sync {
            preloadedItems.removeAll()
            preloadedAssets.removeAll()
            AppLogger.general.debug("[Preloader] Cleared all preloaded items")
        }
    }
    
    // MARK: - Cancel Current Preload
    func cancelCurrentPreload() {
        currentPreloadTask?.cancel()
        currentPreloadTask = nil
        AppLogger.general.debug("[Preloader] Cancelled current preload task")
    }
    
    deinit {
        cancelCurrentPreload()
        clearAll()
    }
}
