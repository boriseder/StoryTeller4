import Foundation
import AVFoundation

protocol AudioFileService {
    func getLocalAudioURL(bookId: String, chapterIndex: Int) -> URL?
    func getStreamingAudioURL(baseURL: String, audioTrack: AudioTrack) -> URL?  // ✅ Changed
    func createAuthenticatedAsset(url: URL, authToken: String) -> AVURLAsset
    func getLocalCoverURL(bookId: String) -> URL?
}

class DefaultAudioFileService: AudioFileService {
    private let downloadManager: DownloadManager?
    
    init(downloadManager: DownloadManager?) {
        self.downloadManager = downloadManager
    }
    
    func getLocalAudioURL(bookId: String, chapterIndex: Int) -> URL? {
        return downloadManager?.getLocalAudioURL(for: bookId, chapterIndex: chapterIndex)
    }
    
    func getStreamingAudioURL(baseURL: String, audioTrack: AudioTrack) -> URL? {  // ✅ Changed
        guard let contentUrl = audioTrack.contentUrl else {
            AppLogger.general.error("[AudioFileService] AudioTrack has no contentUrl")
            return nil
        }
        
        let fullURL = "\(baseURL)\(contentUrl)"
        return URL(string: fullURL)
    }
    
    func createAuthenticatedAsset(url: URL, authToken: String) -> AVURLAsset {
        let headers = [
            "Authorization": "Bearer \(authToken)",
            "User-Agent": "AudioBook Client/1.0.0"
        ]
        
        return AVURLAsset(url: url, options: [
            "AVURLAssetHTTPHeaderFieldsKey": headers
        ])
    }
    
    func getLocalCoverURL(bookId: String) -> URL? {
        return downloadManager?.getLocalCoverURL(for: bookId)
    }
}
