import Foundation
import MediaPlayer
import UIKit

struct NowPlayingInfo {
    let title: String
    let artist: String
    let albumTitle: String
    let trackNumber: Int
    let trackCount: Int
    let duration: Double
    let elapsedTime: Double
    let playbackRate: Double
    let artwork: UIImage?
}

protocol MediaRemoteService {
    func setupRemoteCommands(
        onPlay: @escaping () -> Void,
        onPause: @escaping () -> Void,
        onSkipForward: @escaping () -> Void,
        onSkipBackward: @escaping () -> Void,
        onNextTrack: @escaping () -> Void,
        onPreviousTrack: @escaping () -> Void,
        onSeek: @escaping (Double) -> Void,
        onChangeRate: @escaping (Double) -> Void
    )
    func updateNowPlaying(info: NowPlayingInfo)
    func clearNowPlaying()
}

class DefaultMediaRemoteService: MediaRemoteService {
    
    func setupRemoteCommands(
        onPlay: @escaping () -> Void,
        onPause: @escaping () -> Void,
        onSkipForward: @escaping () -> Void,
        onSkipBackward: @escaping () -> Void,
        onNextTrack: @escaping () -> Void,
        onPreviousTrack: @escaping () -> Void,
        onSeek: @escaping (Double) -> Void,
        onChangeRate: @escaping (Double) -> Void
    ) {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { _ in
            onPlay()
            return .success
        }
        
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { _ in
            onPause()
            return .success
        }
        
        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipForwardCommand.preferredIntervals = [15]
        commandCenter.skipForwardCommand.addTarget { _ in
            onSkipForward()
            return .success
        }
        
        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.preferredIntervals = [15]
        commandCenter.skipBackwardCommand.addTarget { _ in
            onSkipBackward()
            return .success
        }
        
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { _ in
            onNextTrack()
            return .success
        }
        
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { _ in
            onPreviousTrack()
            return .success
        }
        
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            onSeek(positionEvent.positionTime)
            return .success
        }
        
        commandCenter.changePlaybackRateCommand.isEnabled = true
        commandCenter.changePlaybackRateCommand.supportedPlaybackRates = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
        commandCenter.changePlaybackRateCommand.addTarget { event in
            guard let rateEvent = event as? MPChangePlaybackRateCommandEvent else {
                return .commandFailed
            }
            onChangeRate(Double(rateEvent.playbackRate))
            return .success
        }
        
        AppLogger.general.debug("[MediaRemoteService] Remote command center configured")
    }
    
    func updateNowPlaying(info: NowPlayingInfo) {
        var nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyTitle: info.title,
            MPMediaItemPropertyArtist: info.artist,
            MPMediaItemPropertyAlbumTitle: info.albumTitle,
            MPMediaItemPropertyAlbumTrackNumber: info.trackNumber,
            MPMediaItemPropertyAlbumTrackCount: info.trackCount,
            MPMediaItemPropertyPlaybackDuration: info.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: info.elapsedTime,
            MPNowPlayingInfoPropertyPlaybackRate: info.playbackRate
        ]
        
        if let artwork = info.artwork {
            let artworkObject = MPMediaItemArtwork(boundsSize: artwork.size) { _ in artwork }
            nowPlayingInfo[MPMediaItemPropertyArtwork] = artworkObject
        }
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    func clearNowPlaying() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
}
