// Add @preconcurrency to silence Sendable warnings for system frameworks
@preconcurrency import Foundation
import AVFoundation
import UIKit
import Observation

// MARK: - Audio Player
@MainActor
@Observable
class AudioPlayer: NSObject {

    // MARK: - Properties
    var book: Book?
    var currentChapterIndex: Int = 0
    var isPlaying = false
    var duration: Double = 0
    var currentTime: Double = 0
    var isLoading = false
    var errorMessage: String?
    var playbackRate: Float = 1.0

    // MARK: - Sync & Heartbeat Properties
    private var lastSyncTime: Double = 0
    private let syncInterval: Double = 30

    // MARK: - Dependencies
    private let avPlayerService: AVPlayerService
    private let sessionService: PlaybackSessionService
    private var audioFileService: AudioFileService
    private let mediaRemoteService: MediaRemoteService
    private let preloader: AudioTrackPreloader

    // MARK: - Configuration
    // FIX: Track whether configure() has been called before allowing playback.
    // The player is valid to create but inert until configured.
    private var isConfigured = false
    private var baseURL: String = ""
    private var authToken: String = ""
    private var isOfflineMode: Bool = false
    private var targetSeekTime: Double?
    private var downloadManager: DownloadManager?

    var downloadManagerReference: DownloadManager? {
        return downloadManager
    }

    // MARK: - State
    private var keyValueObservations: [NSKeyValueObservation] = []
    private var timeObserver: Any?
    private let notificationWrapper = NotificationObserverWrapper()

    // MARK: - Computed Properties
    var currentChapter: Chapter? {
        guard let book = book, currentChapterIndex < book.chapters.count else { return nil }
        return book.chapters[currentChapterIndex]
    }

    // MARK: - Initialization
    // FIX: init() no longer activates the audio session.
    // The session is activated lazily in configure() when real credentials exist.
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
        setupRouteChangeHandling()
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
        setupRouteChangeHandling()
    }

    // MARK: - Computed Properties
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
    // FIX: configure() is now the single point of activation.
    // It sets up the AVAudioSession (only once credentials are known) and marks the player ready.
    func configure(baseURL: String, authToken: String, downloadManager: DownloadManager? = nil) {
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.authToken = authToken
        self.downloadManager = downloadManager

        if let downloadManager = downloadManager {
            self.audioFileService = DefaultAudioFileService(downloadManager: downloadManager)
        }

        // Only activate the audio session when we actually have a real configuration.
        // This avoids activating the session at app launch before the user is logged in.
        if !isConfigured {
            setupAudioSession()
            isConfigured = true
        }
    }

    // MARK: - Audio Session Setup
    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [])
            try session.setActive(true)
            AppLogger.audio.info("[AudioPlayer] AVAudioSession configured and active.")
        } catch {
            AppLogger.audio.error("[AudioPlayer] Failed to configure audio session: \(error.localizedDescription)")
        }
    }

    // MARK: - Book Loading
    func load(
        book: Book,
        isOffline: Bool = false,
        restoreState: Bool = true,
        autoPlay: Bool = false
    ) async {
        // FIX: Guard against loading before configure() is called.
        // This prevents a silent failure where the player loads but can never stream.
        guard isConfigured else {
            AppLogger.audio.error("[AudioPlayer] load() called before configure(). Call configure(baseURL:authToken:) first.")
            errorMessage = "Player not configured. Please connect to a server first."
            return
        }

        self.book = book
        self.isOfflineMode = isOffline

        if autoPlay {
            self.isPlaying = true
        }

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

        loadChapter(shouldResumePlayback: false)
        updateNowPlaying()
    }

    // MARK: - Chapter Loading
    func loadChapter(shouldResumePlayback: Bool = false) {
        guard let chapter = currentChapter else {
            errorMessage = "No chapter available"
            return
        }

        if shouldResumePlayback {
            isPlaying = true
        }

        Task {
            if let preloadedItem = await preloader.getPreloadedItem(for: currentChapterIndex) {
                let chapterDuration = (chapter.end ?? 0) - (chapter.start ?? 0)
                setupPlayer(with: preloadedItem, duration: chapterDuration, shouldResumePlayback: false)
                startPreloadingNextChapter()
                return
            }

            isLoading = true
            errorMessage = nil

            if isOfflineMode {
                loadOfflineChapter(chapter, shouldResumePlayback: false)
            } else {
                loadOnlineChapter(chapter, shouldResumePlayback: false)
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
                    setupOnlinePlayer(with: session, shouldResumePlayback: false)
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
        setupPlayer(with: playerItem, duration: audioTrack.duration, shouldResumePlayback: false)
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
            setupPlayer(with: playerItem, duration: chapterDuration, shouldResumePlayback: false)
        }
    }

    private func setupPlayer(with item: AVPlayerItem, duration: Double, shouldResumePlayback: Bool) {
        cleanupPlayer()

        self.duration = duration

        avPlayerService.loadAudio(item: item)
        setupPlayerItemObservers(item)
        addTimeObserver()

        updateNowPlaying()
        startPreloadingNextChapter()
    }

    // MARK: - Playback Controls
    func play() {
        // FIX: Guard playback if player has never been configured.
        guard isConfigured else {
            AppLogger.audio.error("[AudioPlayer] play() called before configure(). Ignoring.")
            return
        }
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
        seekRelative(to: newTime)
    }

    func seek15SecondsForward() {
        let newTime = min(duration, currentTime + 15)
        seekRelative(to: newTime)
    }

    private func seekRelative(to seconds: Double) {
        guard let chapter = currentChapter else { return }
        let chapterDuration = (chapter.end ?? 0) - (chapter.start ?? 0)

        guard seconds >= 0 && seconds <= chapterDuration else { return }

        avPlayerService.seek(to: seconds)

        if isPlaying {
            avPlayerService.playbackRate = playbackRate
        }

        lastSyncTime = seconds
        updateNowPlaying()
        saveCurrentPlaybackState()
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

        lastSyncTime = relativeSeekTime

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

    // MARK: - Remote Commands
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
        mediaRemoteService.updateNowPlaying(info: info)
    }

    // MARK: - Interruption Handling
    private func setupInterruptionHandling() {
        let observer = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

            let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt

            Task { @MainActor [weak self] in
                self?.handleInterruption(type: type, optionsValue: optionsValue)
            }
        }
        notificationWrapper.add(observer)
    }

    private func handleInterruption(type: AVAudioSession.InterruptionType, optionsValue: UInt?) {
        switch type {
        case .began:
            pause()

        case .ended:
            do {
                try AVAudioSession.sharedInstance().setActive(true)
                AppLogger.audio.info("[AudioPlayer] Audio session reactivated after interruption.")
            } catch {
                AppLogger.audio.error("[AudioPlayer] Failed to reactivate audio session: \(error)")
            }

            guard let optionsValue = optionsValue else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) {
                Task {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    self.play()
                }
            }

        @unknown default:
            break
        }
    }

    // MARK: - Route Change Handling
    private func setupRouteChangeHandling() {
        let observer = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }

            Task { @MainActor in
                if reason == .oldDeviceUnavailable {
                    self?.pause()
                }
            }
        }
        notificationWrapper.add(observer)
    }

    // MARK: - Preloading
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

    // MARK: - Time Observer
    private func addTimeObserver() {
        let interval = CMTime(seconds: 1, preferredTimescale: 1)

        timeObserver = avPlayerService.addTimeObserver(interval: interval, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let current = self.avPlayerService.currentTime
                self.currentTime = current

                if abs(current - self.lastSyncTime) >= self.syncInterval {
                    AppLogger.audio.debug("[AudioPlayer] Heartbeat sync triggered at \(current)s")
                    self.saveCurrentPlaybackState()
                    self.lastSyncTime = current
                }

                if self.duration - self.currentTime <= 30 {
                    self.startPreloadingNextChapter()
                }
            }
        }
    }

    // MARK: - Player Item Observers
    private func setupPlayerItemObservers(_ playerItem: AVPlayerItem) {
        keyValueObservations.removeAll()

        let statusObs = playerItem.observe(\.status) { [weak self] item, _ in
            Task { @MainActor in
                self?.handleStatusChange(item)
            }
        }
        keyValueObservations.append(statusObs)

        let timeObs = playerItem.observe(\.loadedTimeRanges) { _, _ in }
        keyValueObservations.append(timeObs)

        let finishObs = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.playerItemDidFinishPlaying()
            }
        }
        notificationWrapper.add(finishObs)
    }

    private func playerItemDidFinishPlaying() {
        guard let book = book, currentChapterIndex + 1 < book.chapters.count else {
            isPlaying = false
            updateNowPlaying()
            return
        }
        nextChapter()
    }

    private func handleStatusChange(_ item: AVPlayerItem) {
        if item.status == .failed {
            self.errorMessage = item.error?.localizedDescription ?? "Unknown error"
            isLoading = false
        } else if item.status == .readyToPlay {
            self.errorMessage = nil
            isLoading = false

            if let seekTime = targetSeekTime {
                AppLogger.audio.debug("[AudioPlayer] Seeking to \(seekTime)s after item ready.")
                avPlayerService.seek(to: seekTime)
                targetSeekTime = nil
                updateNowPlaying()
            }

            if isPlaying {
                AppLogger.audio.debug("[AudioPlayer] Starting playback after item ready.")
                avPlayerService.play()
                avPlayerService.playbackRate = playbackRate
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
            Task { @MainActor [weak self] in
                self?.saveCurrentPlaybackState()
            }
        }
        notificationWrapper.add(autoSaveObserver)

        let backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.saveCurrentPlaybackState()
            }
        }
        notificationWrapper.add(backgroundObserver)
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

    // MARK: - Cleanup
    private func cleanupPlayer() {
        if let observer = timeObserver {
            avPlayerService.removeTimeObserver(observer)
            timeObserver = nil
        }

        keyValueObservations.removeAll()
        avPlayerService.cleanup()
    }

    deinit {
        // NotificationObserverWrapper deinit automatically removes observers
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let playbackAutoSave = Notification.Name("playbackAutoSave")
}
