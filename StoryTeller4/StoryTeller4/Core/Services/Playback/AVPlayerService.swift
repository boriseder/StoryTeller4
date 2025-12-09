import Foundation
import AVFoundation

protocol AVPlayerService: AnyObject {
    var isPlaying: Bool { get }
    var currentTime: Double { get }
    var duration: Double { get }
    var playbackRate: Float { get set }
    
    func loadAudio(item: AVPlayerItem)
    func play()
    func pause()
    func seek(to time: Double)
    func cleanup()
    func addTimeObserver(interval: CMTime, queue: DispatchQueue?, handler: @escaping (CMTime) -> Void) -> Any
    func removeTimeObserver(_ observer: Any)
}

class DefaultAVPlayerService: AVPlayerService {
    private var player: AVPlayer?
    
    var isPlaying: Bool {
        guard let player = player else { return false }
        return player.rate != 0
    }
    
    var currentTime: Double {
        guard let player = player else { return 0 }
        return player.currentTime().seconds
    }
    
    var duration: Double {
        guard let player = player,
              let duration = player.currentItem?.duration.seconds,
              duration.isFinite else {
            return 0
        }
        return duration
    }
    
    var playbackRate: Float = 1.0 {
        didSet {
            if isPlaying {
                player?.rate = playbackRate
            }
        }
    }
    
    func loadAudio(item: AVPlayerItem) {
        cleanup()
        player = AVPlayer(playerItem: item)
    }
    
    func play() {
        player?.play()
        player?.rate = playbackRate
    }
    
    func pause() {
        player?.pause()
    }
    
    func seek(to time: Double) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 1)
        player?.seek(to: cmTime)
        
        if isPlaying {
            player?.rate = playbackRate
        }
    }
    
    func cleanup() {
        player?.pause()
        player = nil
    }
    
    func addTimeObserver(interval: CMTime, queue: DispatchQueue?, handler: @escaping (CMTime) -> Void) -> Any {
        guard let player = player else {
            return NSObject()
        }
        return player.addPeriodicTimeObserver(forInterval: interval, queue: queue, using: handler)
    }
    
    func removeTimeObserver(_ observer: Any) {
        player?.removeTimeObserver(observer)
    }
}
