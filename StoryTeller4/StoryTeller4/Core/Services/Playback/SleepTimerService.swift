import SwiftUI
import UserNotifications
import Combine

// MARK: - Sleep Timer Mode
enum SleepTimerMode: Equatable, CustomStringConvertible, Sendable {
    case duration(minutes: Int)
    case endOfChapter
    case endOfBook
    
    var displayName: String {
        switch self {
        case .duration(let minutes): return "\(minutes) minutes"
        case .endOfChapter: return "End of chapter"
        case .endOfBook: return "End of book"
        }
    }
    
    var description: String {
        switch self {
        case .duration(let minutes): return "duration(\(minutes)min)"
        case .endOfChapter: return "endOfChapter"
        case .endOfBook: return "endOfBook"
        }
    }
}

private struct SleepTimerPersistenceState: Codable {
    let endDate: Date
    let mode: String
}

// MARK: - Sleep Timer Service
@MainActor
class SleepTimerService: ObservableObject {
    @Published var selectedMinutes: Int = 30
    @Published var isTimerActive = false
    @Published var remainingTime: TimeInterval = 0
    @Published var currentMode: SleepTimerMode?
    
    let player: AudioPlayer
    private let timerOptions = [5, 10, 15, 30, 45, 60, 90, 120]
    
    private let timerService: TimerManaging
    private var observers: [NSObjectProtocol] = []
    
    init(
        player: AudioPlayer,
        timerService: TimerManaging = TimerService()
    ) {
        self.player = player
        self.timerService = timerService
        
        setupCallbacks()
        setupNotifications()
        restoreTimerState()
    }
    
    private func setupCallbacks() {
        // Configure the actor with thread-safe closures that dispatch back to MainActor
        Task {
            await timerService.setCallbacks(
                onTick: { [weak self] time in
                    Task { @MainActor in
                        self?.remainingTime = time
                    }
                },
                onComplete: { [weak self] in
                    Task { @MainActor in
                        self?.timerDidComplete()
                    }
                }
            )
        }
    }
    
    var timerOptionsArray: [Int] { timerOptions }
    
    func startTimer(mode: SleepTimerMode) {
        Task {
            await cancelTimer()
            
            let duration: TimeInterval
            switch mode {
            case .duration(let minutes):
                duration = TimeInterval(minutes * 60)
            case .endOfChapter:
                guard let chapterEnd = player.currentChapter?.end else { return }
                duration = max(0, chapterEnd - player.currentTime)
            case .endOfBook:
                duration = max(0, player.duration - player.currentTime)
            }
            
            guard duration > 0 else { return }
            
            await startTimerWithDuration(duration, mode: mode)
        }
    }
    
    func cancelTimer() async {
        await timerService.cancel()
        
        isTimerActive = false
        remainingTime = 0
        currentMode = nil
        
        clearTimerState()
        cancelTimerEndNotification()
        
        AppLogger.general.debug("[SleepTimer] Timer cancelled")
    }
    
    private func startTimerWithDuration(_ duration: TimeInterval, mode: SleepTimerMode) async {
        let endDate = Date().addingTimeInterval(duration)
        
        await timerService.start(duration: duration)
        
        isTimerActive = true
        remainingTime = duration
        currentMode = mode
        
        saveTimerState(endDate: endDate, mode: mode)
        scheduleTimerEndNotification(fireDate: endDate)
        
        AppLogger.general.debug("[SleepTimer] Timer started - duration: \(duration)s")
    }
    
    // MARK: - Logic
    
    func timerDidComplete() {
        AppLogger.general.debug("[SleepTimer] Timer finished - pausing playback")
        
        player.pause()
        
        isTimerActive = false
        remainingTime = 0
        currentMode = nil
        
        clearTimerState()
        
        #if !targetEnvironment(simulator)
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        #endif
    }
    
    // MARK: - Persistence & Notifications (Same as before)
    
    private func saveTimerState(endDate: Date, mode: SleepTimerMode) {
        let modeString: String
        switch mode {
        case .duration(let minutes): modeString = "duration:\(minutes)"
        case .endOfChapter: modeString = "endOfChapter"
        case .endOfBook: modeString = "endOfBook"
        }
        
        let state = SleepTimerPersistenceState(endDate: endDate, mode: modeString)
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: "sleep_timer_state")
        }
    }
    
    private func restoreTimerState() {
        guard let data = UserDefaults.standard.data(forKey: "sleep_timer_state"),
              let state = try? JSONDecoder().decode(SleepTimerPersistenceState.self, from: data) else { return }
        
        let remaining = state.endDate.timeIntervalSinceNow
        guard remaining > 0 else {
            clearTimerState()
            return
        }
        
        let mode: SleepTimerMode
        if state.mode.starts(with: "duration:"),
           let minutes = Int(state.mode.replacingOccurrences(of: "duration:", with: "")) {
            mode = .duration(minutes: minutes)
        } else if state.mode == "endOfChapter" {
            mode = .endOfChapter
        } else if state.mode == "endOfBook" {
            mode = .endOfBook
        } else {
            return
        }
        
        Task {
            await startTimerWithDuration(remaining, mode: mode)
        }
    }
    
    private func clearTimerState() {
        UserDefaults.standard.removeObject(forKey: "sleep_timer_state")
    }
    
    private func setupNotifications() {
        let observer = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, self.isTimerActive, let mode = self.currentMode else { return }
            let endDate = Date().addingTimeInterval(self.remainingTime)
            self.saveTimerState(endDate: endDate, mode: mode)
        }
        observers.append(observer)
    }
    
    private func scheduleTimerEndNotification(fireDate: Date) {
        let content = UNMutableNotificationContent()
        content.title = "Sleep Timer"
        content.body = "Playback paused"
        content.sound = .default
        
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireDate),
            repeats: false
        )
        
        let request = UNNotificationRequest(identifier: "sleep_timer_end", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { _ in }
    }
    
    private func cancelTimerEndNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["sleep_timer_end"])
    }
    
    deinit {
        let service = timerService
        // Fire and forget cancellation
        Task.detached {
            await service.cancel()
        }
        
        Task.detached {
            AppLogger.general.debug("[SleepTimer] Deinitialized")
        }
        
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }
}
