import Foundation
import AVFoundation
import Combine
import UIKit

// MARK: - Audio Player
@MainActor
class AudioPlayer: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    @Published var book: Book?
    @Published var currentChapterIndex: Int = 0
    @Published var isPlaying = false
    @Published var duration: Double = 0
    @Published var currentTime: Double = 0
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var playbackRate: Float = 1.0
    
    // MARK: - Dependencies
    private let avPlayerService: AVPlayerService
    private let sessionService: PlaybackSessionService
    private var audioFileService: AudioFileService
    private let mediaRemoteService: MediaRemoteService
    private let preloader: AudioTrackPreloader
    
    // MARK: - Configuration
    private var baseURL: String = ""
    private var authToken: String = ""
    private var isOfflineMode: Bool = false
    private var targetSeekTime: Double?
    private var downloadManager: DownloadManager?
    
    var downloadManagerReference: DownloadManager? {
        return downloadManager
    }
    
    // MARK: - State
    private var currentObservedItem: AVPlayerItem?
    private var hasAddedKVOObservers = false
    private var timeObserver: Any?
    private var observers: [NSObjectProtocol] = []
    
    // FIX: Context must be accessible from nonisolated context
    private nonisolated(unsafe) static var observerContext = 0
    
    // MARK: - Computed Properties
    var currentChapter: Chapter? {
        guard let book = book, currentChapterIndex < book.chapters.count else { return nil }
        return book.chapters[currentChapterIndex]
    }
    
    // MARK: - Initialization
    override init() {
        self.avPlayerService = DefaultAVPlayerService()
        self.sessionService = DefaultPlaybackSessionService()
        self.audioFileService = DefaultAudioFileService(downloadManager: nil)
        self.mediaRemoteService = DefaultMediaRemoteService()
        self.preloader = AudioTrackPreloader()
        
        super.init()
        setupPersistence()
        setupRemoteCommands()
        setupInterruptionHandling()
    }
    
    init(
        avPlayerService: AVPlayerService,
        sessionService: PlaybackSessionService,
        audioFileService: AudioFileService,
        mediaRemoteService: MediaRemoteService,
        preloader: AudioTrackPreloader = AudioTrackPreloader()
    ) {
        self.avPlayerService = avPlayerService
        self.sessionService = sessionService
        self.audioFileService = audioFileService
        self.mediaRemoteService = mediaRemoteService
        self.preloader = preloader
        
        super.init()
        setupPersistence()
        setupRemoteCommands()
        setupInterruptionHandling()
    }
    
    // MARK: Computed properties
    var absoluteCurrentTime: Double {
        guard let chapter = currentChapter else { return currentTime }
        let chapterStart = chapter.start ?? 0
        let relativeTime = avPlayerService.currentTime
        return chapterStart + relativeTime
    }

    var relativeCurrentTime: Double {
        return avPlayerService.currentTime
    }

    var chapterDuration: Double {
        return duration
    }

    var totalBookDuration: Double {
        guard let book = book else { return duration }
        guard let lastChapter = book.chapters.last else { return duration }
        return lastChapter.end ?? duration
    }

    // MARK: - Configuration
    func configure(baseURL: String, authToken: String, downloadManager: DownloadManager? = nil) {
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.authToken = authToken
        self.downloadManager = downloadManager
        
        if let downloadManager = downloadManager {
            self.audioFileService = DefaultAudioFileService(downloadManager: downloadManager)
        }
    }
    
    // MARK: - Book Loading
    func load(
        book: Book,
        isOffline: Bool = false,
        restoreState: Bool = true,
        autoPlay: Bool = false
    ) async {
        self.book = book
        self.isOfflineMode = isOffline
        
        await preloader.clearAll()
        
        if restoreState {
            if let state = await PlaybackRepository.shared.loadStateForBook(book.id, book: book) {
                self.currentChapterIndex = min(state.chapterIndex, book.chapters.count - 1)
                if let chapter = book.chapters[safe: self.currentChapterIndex] {
                    let chapterStart = chapter.start ?? 0
                    self.targetSeekTime = max(0, state.currentTime - chapterStart)
                } else {
                    self.targetSeekTime = nil
                }
            }
        } else {
            self.currentChapterIndex = 0
            self.targetSeekTime = nil
        }
        
        loadChapter(shouldResumePlayback: autoPlay)
        updateNowPlaying()
    }

    // MARK: - Chapter Loading
    func loadChapter(shouldResumePlayback: Bool = false) {
        guard let chapter = currentChapter else {
            errorMessage = "No chapter available"
            return
        }
        
        Task {
            if let preloadedItem = await preloader.getPreloadedItem(for: currentChapterIndex) {
                let chapterDuration = (chapter.end ?? 0) - (chapter.start ?? 0)
                setupPlayer(with: preloadedItem, duration: chapterDuration, shouldResumePlayback: shouldResumePlayback)
                startPreloadingNextChapter()
                return
            }
            
            isLoading = true
            errorMessage = nil
            
            if isOfflineMode {
                loadOfflineChapter(chapter, shouldResumePlayback: shouldResumePlayback)
            } else {
                loadOnlineChapter(chapter, shouldResumePlayback: shouldResumePlayback)
            }
        }
    }
    
    private func loadOnlineChapter(_ chapter: Chapter, shouldResumePlayback: Bool) {
        Task {
            do {
                let session = try await sessionService.createSession(
                    for: chapter,
                    baseURL: baseURL,
                    authToken: authToken
                )
                
                await MainActor.run {
                    self.isLoading = false
                    setupOnlinePlayer(with: session, shouldResumePlayback: shouldResumePlayback)
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
 
    internal func loadChapter(at index: Int, seekTo time: Double?, shouldResume: Bool = true) {
        guard let book = book, index >= 0 && index < book.chapters.count else { return }
        currentChapterIndex = index
        targetSeekTime = time
        loadChapter(shouldResumePlayback: shouldResume)
    }
    
    private func setupOnlinePlayer(with session: PlaybackSessionResponse, shouldResumePlayback: Bool) {
        guard currentChapterIndex < session.audioTracks.count else {
            errorMessage = "Invalid chapter index"
            return
        }
        
        let audioTrack = session.audioTracks[currentChapterIndex]
        
        guard let audioURL = audioFileService.getStreamingAudioURL(baseURL: baseURL, audioTrack: audioTrack) else {
            errorMessage = "Invalid audio URL"
            return
        }
        
        let asset = audioFileService.createAuthenticatedAsset(url: audioURL, authToken: authToken)
        let playerItem = AVPlayerItem(asset: asset)
        
        self.duration = audioTrack.duration
        setupPlayer(with: playerItem, duration: audioTrack.duration, shouldResumePlayback: shouldResumePlayback)
    }
    
    private func loadOfflineChapter(_ chapter: Chapter, shouldResumePlayback: Bool) {
        guard let book = book else {
            isLoading = false
            errorMessage = "No book loaded"
            return
        }
        
        Task { @MainActor in
            guard let localURL = audioFileService.getLocalAudioURL(bookId: book.id, chapterIndex: currentChapterIndex) else {
                self.errorMessage = "Offline audio file not found"
                self.isLoading = false
                return
            }
            
            let playerItem = AVPlayerItem(url: localURL)
            let chapterDuration = (chapter.end ?? 0) - (chapter.start ?? 0)
            
            self.isLoading = false
            setupPlayer(with: playerItem, duration: chapterDuration, shouldResumePlayback: shouldResumePlayback)
        }
    }
    
    private func setupPlayer(with item: AVPlayerItem, duration: Double, shouldResumePlayback: Bool) {
        cleanupPlayer()
        
        avPlayerService.loadAudio(item: item)
        setupPlayerItemObservers(item)
        addTimeObserver()
        
        self.duration = duration
        updateNowPlaying()
        startPreloadingNextChapter()
        
        if let seekTime = targetSeekTime {
            avPlayerService.seek(to: seekTime)
            targetSeekTime = nil
        }
        
        if shouldResumePlayback {
            play()
        }
    }
    
    // MARK: - Playback Controls
    func play() {
        avPlayerService.play()
        avPlayerService.playbackRate = playbackRate
        isPlaying = true
        updateNowPlaying()
    }
    
    func pause() {
        avPlayerService.pause()
        isPlaying = false
        updateNowPlaying()
        saveCurrentPlaybackState()
    }
    
    func setCurrentChapter(index: Int) {
        guard let book = book, index >= 0 && index < book.chapters.count else { return }
        currentChapterIndex = index
        targetSeekTime = 0
        loadChapter(shouldResumePlayback: isPlaying)
    }
    
    func nextChapter() {
        guard let book = book, currentChapterIndex + 1 < book.chapters.count else {
            pause()
            return
        }
        setCurrentChapter(index: currentChapterIndex + 1)
    }
    
    func previousChapter() {
        guard currentChapterIndex > 0 else { return }
        setCurrentChapter(index: currentChapterIndex - 1)
    }
    
    func seek15SecondsBack() {
        let newTime = max(0, currentTime - 15)
        seek(to: newTime)
    }
    
    func seek15SecondsForward() {
        let newTime = min(duration, currentTime + 15)
        seek(to: newTime)
    }
    
    func seek(to seconds: Double) {
        guard let chapter = currentChapter else { return }
        let chapterStart = chapter.start ?? 0
        let chapterDuration = (chapter.end ?? 0) - chapterStart
        
        let relativeSeekTime = seconds - chapterStart
        guard relativeSeekTime >= 0 && relativeSeekTime <= chapterDuration else { return }
        
        avPlayerService.seek(to: relativeSeekTime)
        
        if isPlaying {
            avPlayerService.playbackRate = playbackRate
        }
        updateNowPlaying()
        saveCurrentPlaybackState()
    }
    
    func setPlaybackRate(_ rate: Double) {
        let floatRate = Float(rate)
        self.playbackRate = floatRate
        if isPlaying {
            avPlayerService.playbackRate = floatRate
        }
        updateNowPlaying()
    }
    
    func togglePlayPause() {
        if isPlaying { pause() } else { play() }
    }
    
    private func setupRemoteCommands() {
        mediaRemoteService.setupRemoteCommands(
            onPlay: { [weak self] in self?.play() },
            onPause: { [weak self] in self?.pause() },
            onSkipForward: { [weak self] in self?.seek15SecondsForward() },
            onSkipBackward: { [weak self] in self?.seek15SecondsBack() },
            onNextTrack: { [weak self] in self?.nextChapter() },
            onPreviousTrack: { [weak self] in self?.previousChapter() },
            onSeek: { [weak self] time in self?.seek(to: time) },
            onChangeRate: { [weak self] rate in self?.setPlaybackRate(rate) }
        )
    }
    
    private func updateNowPlaying() {
        guard let book = book, let chapter = currentChapter else {
            mediaRemoteService.clearNowPlaying()
            return
        }
        
        var artwork: UIImage? = nil
        if let localCoverURL = audioFileService.getLocalCoverURL(bookId: book.id) {
            artwork = UIImage(contentsOfFile: localCoverURL.path)
        }
        
        let info = NowPlayingInfo(
            title: chapter.title,
            artist: book.author ?? "Unknown Author",
            albumTitle: book.title,
            trackNumber: currentChapterIndex + 1,
            trackCount: book.chapters.count,
            duration: duration,
            elapsedTime: currentTime,
            playbackRate: isPlaying ? Double(playbackRate) : 0.0,
            artwork: artwork
        )
        mediaRemoteService.updateNowPlaying(info: info)
    }
    
    private func setupInterruptionHandling() {
        let observer = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleInterruption(notification: notification)
        }
        observers.append(observer)
    }
    
    @objc private func handleInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        
        switch type {
        case .began:
            pause()
        case .ended:
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.play()
                }
            }
        @unknown default:
            break
        }
    }
    
    private func startPreloadingNextChapter() {
        guard let book = book else { return }
        Task {
            await preloader.preloadNext(
                chapterIndex: currentChapterIndex,
                book: book,
                isOffline: isOfflineMode,
                baseURL: baseURL,
                authToken: authToken,
                downloadManager: downloadManager
            ) { _ in }
        }
    }
    
    private func addTimeObserver() {
        let interval = CMTime(seconds: 1, preferredTimescale: 1)
        timeObserver = avPlayerService.addTimeObserver(interval: interval, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            self.currentTime = self.avPlayerService.currentTime
            
            if Int(self.currentTime) % 5 == 0 {
                self.updateNowPlaying()
            }
            if self.duration - self.currentTime <= 30 {
                self.startPreloadingNextChapter()
            }
        }
    }
    
    private func setupPlayerItemObservers(_ playerItem: AVPlayerItem) {
        if let previousItem = currentObservedItem {
            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: previousItem)
            if hasAddedKVOObservers {
                previousItem.removeObserver(self, forKeyPath: "status", context: &AudioPlayer.observerContext)
                previousItem.removeObserver(self, forKeyPath: "loadedTimeRanges", context: &AudioPlayer.observerContext)
            }
        }
        
        playerItem.addObserver(self, forKeyPath: "status", options: [.new], context: &AudioPlayer.observerContext)
        playerItem.addObserver(self, forKeyPath: "loadedTimeRanges", options: [.new], context: &AudioPlayer.observerContext)
        hasAddedKVOObservers = true
        
        NotificationCenter.default.addObserver(self, selector: #selector(playerItemDidFinishPlaying), name: .AVPlayerItemDidPlayToEndTime, object: playerItem)
        currentObservedItem = playerItem
    }
    
    @objc private func playerItemDidFinishPlaying(_ notification: Notification) {
        guard let book = book, currentChapterIndex + 1 < book.chapters.count else {
            DispatchQueue.main.async { [weak self] in
                self?.isPlaying = false
                self?.updateNowPlaying()
            }
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.nextChapter()
        }
    }
    
    nonisolated override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard context == &AudioPlayer.observerContext else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            return
        }
        Task { @MainActor in
            self.handleObservationChange(keyPath: keyPath, object: object)
        }
    }
    
    private func handleObservationChange(keyPath: String?, object: Any?) {
        guard let keyPath = keyPath, let playerItem = object as? AVPlayerItem else { return }
        switch keyPath {
        case "status":
            if playerItem.status == .failed {
                self.errorMessage = playerItem.error?.localizedDescription ?? "Unknown error"
            } else if playerItem.status == .readyToPlay {
                self.errorMessage = nil
            }
        default: break
        }
    }
    
    private func setupPersistence() {
        let autoSaveObserver = NotificationCenter.default.addObserver(forName: .playbackAutoSave, object: nil, queue: .main) { [weak self] _ in
            self?.saveCurrentPlaybackState()
        }
        observers.append(autoSaveObserver)
        
        let backgroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.saveCurrentPlaybackState()
        }
        observers.append(backgroundObserver)
    }
    
    private func saveCurrentPlaybackState() {
        guard let book = book, let chapter = currentChapter else { return }
        let chapterStart = chapter.start ?? 0
        let absoluteTime = chapterStart + currentTime
        
        let state = PlaybackState(
            libraryItemId: book.id,
            currentTime: absoluteTime,
            duration: totalBookDuration,
            isFinished: isBookFinished(),
            lastUpdate: Date(),
            chapterIndex: currentChapterIndex
        )
        PlaybackRepository.shared.saveState(state)
    }

    private func isBookFinished() -> Bool {
        guard let book = book else { return false }
        let isLastChapter = currentChapterIndex >= book.chapters.count - 1
        let nearEnd = duration > 0 && (currentTime / duration) > 0.95
        return isLastChapter && nearEnd
    }
    
    private func cleanupPlayer() {
        if let observer = timeObserver {
            avPlayerService.removeTimeObserver(observer)
            timeObserver = nil
        }
        if let observedItem = currentObservedItem {
            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: observedItem)
            if hasAddedKVOObservers {
                observedItem.removeObserver(self, forKeyPath: "status", context: &AudioPlayer.observerContext)
                observedItem.removeObserver(self, forKeyPath: "loadedTimeRanges", context: &AudioPlayer.observerContext)
                hasAddedKVOObservers = false
            }
        }
        currentObservedItem = nil
        avPlayerService.cleanup()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        if let observedItem = currentObservedItem, hasAddedKVOObservers {
            observedItem.removeObserver(self, forKeyPath: "status", context: &AudioPlayer.observerContext)
            observedItem.removeObserver(self, forKeyPath: "loadedTimeRanges", context: &AudioPlayer.observerContext)
        }
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }
}

extension Notification.Name {
    static let playbackAutoSave = Notification.Name("playbackAutoSave")
}
