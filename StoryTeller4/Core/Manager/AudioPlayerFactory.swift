import Foundation

class AudioPlayerFactory {
    
    static func create(downloadManager: DownloadManager? = nil) -> AudioPlayer {
        let avPlayerService = DefaultAVPlayerService()
        let sessionService = DefaultPlaybackSessionService()
        let audioFileService = DefaultAudioFileService(downloadManager: downloadManager)
        let mediaRemoteService = DefaultMediaRemoteService()
        let preloader = AudioTrackPreloader()
        
        return AudioPlayer(
            avPlayerService: avPlayerService,
            sessionService: sessionService,
            audioFileService: audioFileService,
            mediaRemoteService: mediaRemoteService,
            preloader: preloader
        )
    }
}
