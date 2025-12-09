import Foundation
import AVFoundation
import Combine
import UIKit

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
    
    // MARK: - Dependencies (Injected Services)
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
    
    // MARK: - Backward Compatibility
    private var downloadManager: DownloadManager?
    
    var downloadManagerReference: DownloadManager? {
        return downloadManager
    }
    
    // MARK: - State
    private var currentObservedItem: AVPlayerItem?
    private var hasAddedKVOObservers = false
    private var timeObserver: Any?
    private var observers: [NSObjectProtocol] = []
    private static var observerContext = 0
    
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
    
    /// Absolute Zeit im gesamten Buch (für UI-Anzeige)
    var absoluteCurrentTime: Double {
        guard let chapter = currentChapter else { return currentTime }
        let chapterStart = chapter.start ?? 0
        let relativeTime = avPlayerService.currentTime
        return chapterStart + relativeTime
    }

    /// Relative Zeit im aktuellen Kapitel
    var relativeCurrentTime: Double {
        return avPlayerService.currentTime
    }

    /// Dauer des aktuellen Kapitels
    var chapterDuration: Double {
        return duration  // Dies ist bereits die Kapitel-Duration
    }

    /// Gesamtdauer des Buchs
    var totalBookDuration: Double {
        guard let book = book else { return duration }
        // Berechne aus letztem Kapitel
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

    @MainActor
    func load(
        book: Book,
        isOffline: Bool = false,
        restoreState: Bool = true,
        autoPlay: Bool = false
    ) async {
        self.book = book
        self.isOfflineMode = isOffline
        
        preloader.clearAll()
        
        if restoreState {
            // Load states with improved merge logic
            // In AudioPlayer.load() Methode
            if let state = await PlaybackRepository.shared.loadStateForBook(book.id, book: book) {
                self.currentChapterIndex = min(state.chapterIndex, book.chapters.count - 1)
                
                // ✅ FIX: Konvertiere absolute Zeit zu relativer Kapitelzeit
                if let chapter = book.chapters[safe: self.currentChapterIndex] {
                    let chapterStart = chapter.start ?? 0
                    self.targetSeekTime = max(0, state.currentTime - chapterStart)
                    
                    AppLogger.general.debug("""
                        [AudioPlayer] Restored: Chapter \(self.currentChapterIndex), \
                        Absolute: \(state.currentTime)s, \
                        Chapter starts at: \(chapterStart)s, \
                        Seeking to: \(self.targetSeekTime ?? 0)s within chapter
                    """)
                } else {
                    self.targetSeekTime = nil
                }
            }
        } else {
            // State wird ignoriert (z.B. bei manuellem Neustart)
            self.currentChapterIndex = 0
            self.targetSeekTime = nil
            AppLogger.general.debug("[AudioPlayer] ⏮️ Starting from beginning (restoreState=false)")
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
        
        AppLogger.general.debug("[AudioPlayer] Loading chapter: \(chapter.title)")
        
        if let preloadedItem = preloader.getPreloadedItem(for: currentChapterIndex) {
            AppLogger.general.debug("[AudioPlayer] Using preloaded item")
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
    
    // MARK: - Online Chapter Loading
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
                    AppLogger.general.debug("[AudioPlayer] Failed to create session: \(error)")
                }
            }
        }
    }
 
    // MARK: - Chapter Loading (Internal for Extensions)

    /// Load a chapter with optional seek time (for internal use and extensions)
    internal func loadChapter(at index: Int, seekTo time: Double?, shouldResume: Bool = true) {
        guard let book = book, index >= 0 && index < book.chapters.count else {
            AppLogger.general.debug("[AudioPlayer] Invalid chapter index: \(index)")
            return
        }
        
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
    
    // MARK: - Offline Chapter Loading
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
    
    // MARK: - Player Setup
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
        AppLogger.general.debug("[AudioPlayer] Playing at rate: \(playbackRate)x")
    }
    
    func pause() {
        avPlayerService.pause()
        isPlaying = false
        updateNowPlaying()
        saveCurrentPlaybackState()
        AppLogger.general.debug("[AudioPlayer] Paused")
    }
    
    func setCurrentChapter(index: Int) {
        guard let book = book, index >= 0 && index < book.chapters.count else {
            AppLogger.general.debug("[AudioPlayer] Invalid chapter index: \(index)")
            return
        }
        
        currentChapterIndex = index
        targetSeekTime = 0
        loadChapter(shouldResumePlayback: isPlaying)
    }
    
    func nextChapter() {
        guard let book = book, currentChapterIndex + 1 < book.chapters.count else {
            AppLogger.general.debug("[AudioPlayer] No next chapter available")
            pause()
            return
        }
        
        AppLogger.general.debug("[AudioPlayer] Moving to next chapter: \(currentChapterIndex + 1)")
        setCurrentChapter(index: currentChapterIndex + 1)
    }
    
    func previousChapter() {
        guard currentChapterIndex > 0 else {
            AppLogger.general.debug("[AudioPlayer] Already at first chapter")
            return
        }
        
        AppLogger.general.debug("[AudioPlayer] Moving to previous chapter: \(currentChapterIndex - 1)")
        setCurrentChapter(index: currentChapterIndex - 1)
    }
    
    func seek15SecondsBack() {
        let newTime = max(0, currentTime - 15)
        AppLogger.general.debug("[AudioPlayer] Seeking back 15s: \(currentTime) -> \(newTime)")
        seek(to: newTime)
    }
    
    func seek15SecondsForward() {
        let newTime = min(duration, currentTime + 15)
        AppLogger.general.debug("[AudioPlayer] Seeking forward 15s: \(currentTime) -> \(newTime)")
        seek(to: newTime)
    }
    
    func seek(to seconds: Double) {
        // Diese Methode erhält bereits absolute Zeit vom Slider
        // und muss sie in relative Kapitelzeit umwandeln
        
        guard let chapter = currentChapter else { return }
        let chapterStart = chapter.start ?? 0
        let chapterDuration = (chapter.end ?? 0) - chapterStart
        
        // Konvertiere absolute Zeit zu relativer Kapitelzeit
        let relativeSeekTime = seconds - chapterStart
        
        guard relativeSeekTime >= 0 && relativeSeekTime <= chapterDuration else {
            AppLogger.general.debug("[AudioPlayer] Invalid seek time: \(seconds) (chapter range: \(chapterStart)-\(chapter.end ?? 0))")
            return
        }
        
        AppLogger.general.debug("[AudioPlayer] Seeking to absolute: \(seconds)s (relative in chapter: \(relativeSeekTime)s)")
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
        AppLogger.general.debug("[AudioPlayer] Playback rate set to: \(rate)x")
    }
    
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    // MARK: - Remote Commands Setup
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
    
    // MARK: - Now Playing Info
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
        AppLogger.network.debug("Updating Now Playing: \(info)")
        mediaRemoteService.updateNowPlaying(info: info)
    }
    
    // MARK: - Interruption Handling
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
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            pause()
        case .ended:
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else {
                return
            }
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
    
    // MARK: - Preloading
    private func startPreloadingNextChapter() {
        guard let book = book else { return }
        
        preloader.preloadNext(
            chapterIndex: currentChapterIndex,
            book: book,
            isOffline: isOfflineMode,
            baseURL: baseURL,
            authToken: authToken,
            downloadManager: downloadManager
        ) { success in
            if success {
                AppLogger.general.debug("[AudioPlayer] Next chapter preloaded")
            }
        }
    }
    
    // MARK: - Time Observer
    private func addTimeObserver() {
        let interval = CMTime(seconds: 1, preferredTimescale: 1)
        timeObserver = avPlayerService.addTimeObserver(interval: interval, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            self.currentTime = self.avPlayerService.currentTime
                        

            // we only use relative time here
            // Calculate absolute time: chapter start + + current position in chapter
            /*
             
             let relativeTime = self.avPlayerService.currentTime

            if let chapter = self.currentChapter {
                let chapterStart = chapter.start ?? 0
                self.currentTime = chapterStart + relativeTime  // Absolute Zeit für Speicherung
            } else {
                self.currentTime = relativeTime
            }
             */

            
            
            if Int(self.currentTime) % 5 == 0 {
                self.updateNowPlaying()
            }
            
            if self.duration - self.currentTime <= 30 {
                self.startPreloadingNextChapter()
            }
        }
    }
    
    // MARK: - Player Item Observers
    private func setupPlayerItemObservers(_ playerItem: AVPlayerItem) {
        if let previousItem = currentObservedItem {
            NotificationCenter.default.removeObserver(
                self,
                name: .AVPlayerItemDidPlayToEndTime,
                object: previousItem
            )
            if hasAddedKVOObservers {
                previousItem.removeObserver(self, forKeyPath: "status", context: &AudioPlayer.observerContext)
                previousItem.removeObserver(self, forKeyPath: "loadedTimeRanges", context: &AudioPlayer.observerContext)
            }
        }
        
        playerItem.addObserver(self, forKeyPath: "status", options: [.new], context: &AudioPlayer.observerContext)
        playerItem.addObserver(self, forKeyPath: "loadedTimeRanges", options: [.new], context: &AudioPlayer.observerContext)
        hasAddedKVOObservers = true
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemDidFinishPlaying),
            name: .AVPlayerItemDidPlayToEndTime,
            object: playerItem
        )
        
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
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard context == &AudioPlayer.observerContext else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            return
        }
        
        guard let keyPath = keyPath, let playerItem = object as? AVPlayerItem else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            switch keyPath {
            case "status":
                switch playerItem.status {
                case .readyToPlay:
                    self.errorMessage = nil
                case .failed:
                    let errorDescription = playerItem.error?.localizedDescription ?? "Unknown error"
                    self.errorMessage = errorDescription
                case .unknown:
                    break
                @unknown default:
                    break
                }
            case "loadedTimeRanges":
                break
            default:
                break
            }
        }
    }
    
    // MARK: - Persistence
    private func setupPersistence() {
        let autoSaveObserver = NotificationCenter.default.addObserver(
            forName: .playbackAutoSave,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.saveCurrentPlaybackState()
        }
        observers.append(autoSaveObserver)
        
        let backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.saveCurrentPlaybackState()
        }
        observers.append(backgroundObserver)
    }
    
    // In AudioPlayer.swift

    private func saveCurrentPlaybackState() {
            
        guard let book = book, let chapter = currentChapter else { return }
        
        // Berechne absolute Zeit für Server-Sync
        let chapterStart = chapter.start ?? 0
        let absoluteTime = chapterStart + currentTime  // currentTime ist jetzt relativ
        
        let state = PlaybackState(
            libraryItemId: book.id,
            currentTime: absoluteTime,  // absolute time for abs
            duration: totalBookDuration,  // total duration
            isFinished: isBookFinished(),
            lastUpdate: Date(),
            chapterIndex: currentChapterIndex,
            needsSync: false
        )

        AppLogger.audio.debug("[AudioPlayer] Saving playback state: time=\(currentTime)s, chapter=\(currentChapterIndex), finished=\(state.isFinished)")
        
        // PlaybackRepository kümmert sich um:
        // - Lokales Speichern
        // - Online/Offline Detection
        // - Sofortiges Server-Sync wenn online
        // - Queuing für später wenn offline
        PlaybackRepository.shared.saveState(state)
    }

    private func isBookFinished() -> Bool {
        guard let book = book else { return false }
        
        // Buch ist "fertig" wenn:
        // 1. Wir im letzten Kapitel sind UND
        // 2. Wir > 95% durch sind (um Credits/Outro zu überspringen)
        let isLastChapter = currentChapterIndex >= book.chapters.count - 1
        let nearEnd = duration > 0 && (currentTime / duration) > 0.95
        
        return isLastChapter && nearEnd
    }
    
    // MARK: - Cleanup
    private func cleanupPlayer() {
        if let observer = timeObserver {
            avPlayerService.removeTimeObserver(observer)
            timeObserver = nil
        }
        
        if let observedItem = currentObservedItem {
            NotificationCenter.default.removeObserver(
                self,
                name: .AVPlayerItemDidPlayToEndTime,
                object: observedItem
            )
            
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
        if let observer = timeObserver {
            avPlayerService.removeTimeObserver(observer)
            timeObserver = nil
        }
        
        NotificationCenter.default.removeObserver(self)
        
        if let observedItem = currentObservedItem, hasAddedKVOObservers {
            observedItem.removeObserver(self, forKeyPath: "status", context: &AudioPlayer.observerContext)
            observedItem.removeObserver(self, forKeyPath: "loadedTimeRanges", context: &AudioPlayer.observerContext)
        }
        
        avPlayerService.cleanup()
        preloader.clearAll()
        
        observers.forEach { observer in
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        
        mediaRemoteService.clearNowPlaying()
        
        AppLogger.general.debug("[AudioPlayer] Deinitialized")
    }
}
