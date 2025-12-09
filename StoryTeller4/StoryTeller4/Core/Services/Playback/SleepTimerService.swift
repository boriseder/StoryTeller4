import SwiftUI
import UserNotifications

// MARK: - Sleep Timer Mode
enum SleepTimerMode: Equatable, CustomStringConvertible {
    case duration(minutes: Int)
    case endOfChapter
    case endOfBook
    
    var displayName: String {
        switch self {
        case .duration(let minutes):
            return "\(minutes) minutes"
        case .endOfChapter:
            return "End of chapter"
        case .endOfBook:
            return "End of book"
        }
    }
    
    var description: String {
        switch self {
        case .duration(let minutes):
            return "duration(\(minutes)min)"
        case .endOfChapter:
            return "endOfChapter"
        case .endOfBook:
            return "endOfBook"
        }
    }
}

// MARK: - Sleep Timer Persistence State
private struct SleepTimerPersistenceState: Codable {
    let endDate: Date
    let mode: String
    
    enum CodingKeys: String, CodingKey {
        case endDate, mode
    }
}

// MARK: - Sleep Timer ViewModel
@MainActor
class SleepTimerService: ObservableObject {
    @Published var selectedMinutes: Int = 30
    @Published var isTimerActive = false
    @Published var remainingTime: TimeInterval = 0
    @Published var currentMode: SleepTimerMode?
    
    let player: AudioPlayer
    private let timerOptions = [5, 10, 15, 30, 45, 60, 90, 120]
    
    // Dependencies
    private let timerService: TimerManaging
    private var observers: [NSObjectProtocol] = []
    
    init(
        player: AudioPlayer,
        timerService: TimerManaging = TimerService()
    ) {
        self.player = player
        self.timerService = timerService
        
        setupTimerDelegate()
        setupNotifications()
        restoreTimerState()
    }
    
    // MARK: - Public Interface
    
    var timerOptionsArray: [Int] {
        timerOptions
    }
    
    func startTimer(mode: SleepTimerMode) {
        cancelTimer()
        
        let duration: TimeInterval
        
        switch mode {
        case .duration(let minutes):
            duration = TimeInterval(minutes * 60)
            
        case .endOfChapter:
            guard let chapterEnd = player.currentChapter?.end else {
                AppLogger.general.debug("[SleepTimer] Cannot start end-of-chapter timer - no chapter info")
                return
            }
            duration = max(0, chapterEnd - player.currentTime)
            
        case .endOfBook:
            duration = max(0, player.duration - player.currentTime)
        }
        
        guard duration > 0 else {
            AppLogger.general.debug("[SleepTimer] Invalid timer duration: \(duration)")
            return
        }
        
        startTimerWithDuration(duration, mode: mode)
    }
    
    func cancelTimer() {
        timerService.cancel()
        
        isTimerActive = false
        remainingTime = 0
        currentMode = nil
        
        clearTimerState()
        cancelTimerEndNotification()
        
        AppLogger.general.debug("[SleepTimer] Timer cancelled")
    }
    
    // MARK: - Timer Implementation
    
    private func startTimerWithDuration(_ duration: TimeInterval, mode: SleepTimerMode) {
        let endDate = Date().addingTimeInterval(duration)
        
        timerService.start(duration: duration)
        
        isTimerActive = true
        remainingTime = duration
        currentMode = mode
        
        saveTimerState(endDate: endDate, mode: mode)
        scheduleTimerEndNotification(fireDate: endDate)
        
        AppLogger.general.debug("[SleepTimer] Timer started - duration: \(duration)s, mode: \(mode)")
    }
    
    private func setupTimerDelegate() {
        if let timer = timerService as? TimerService {
            timer.delegate = self
        }
    }
    
    // MARK: - Persistence
    
    private func saveTimerState(endDate: Date, mode: SleepTimerMode) {
        let modeString: String
        switch mode {
        case .duration(let minutes):
            modeString = "duration:\(minutes)"
        case .endOfChapter:
            modeString = "endOfChapter"
        case .endOfBook:
            modeString = "endOfBook"
        }
        
        let state = SleepTimerPersistenceState(endDate: endDate, mode: modeString)
        
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: "sleep_timer_state")
        }
    }
    
    private func restoreTimerState() {
        guard let data = UserDefaults.standard.data(forKey: "sleep_timer_state"),
              let state = try? JSONDecoder().decode(SleepTimerPersistenceState.self, from: data) else {
            return
        }
        
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
            clearTimerState()
            return
        }
        
        startTimerWithDuration(remaining, mode: mode)
        
        AppLogger.general.debug("[SleepTimer] Restored timer state - remaining: \(remaining)s")
    }
    
    private func clearTimerState() {
        UserDefaults.standard.removeObject(forKey: "sleep_timer_state")
    }
    
    // MARK: - Notifications
    
    private func setupNotifications() {
        let backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Run on MainActor since we're accessing @MainActor properties
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if self.isTimerActive {
                    self.saveCurrentTimerState()
                }
            }
        }
        observers.append(backgroundObserver)
        
        requestNotificationPermission()
    }
    
    private func saveCurrentTimerState() {
        guard isTimerActive, let mode = currentMode else { return }
        let endDate = Date().addingTimeInterval(remainingTime)
        saveTimerState(endDate: endDate, mode: mode)
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                AppLogger.general.debug("[SleepTimer] Notification permission error: \(error)")
            } else if granted {
                AppLogger.general.debug("[SleepTimer] Notification permission granted")
            }
        }
    }
    
    private func scheduleTimerEndNotification(fireDate: Date) {
        let content = UNMutableNotificationContent()
        content.title = "Sleep Timer"
        content.body = "Playback has been paused"
        content.sound = .default
        
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: fireDate
            ),
            repeats: false
        )
        
        let request = UNNotificationRequest(
            identifier: "sleep_timer_end",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                AppLogger.general.debug("[SleepTimer] Failed to schedule notification: \(error)")
            }
        }
    }
    
    private func cancelTimerEndNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["sleep_timer_end"]
        )
    }
    
    // MARK: - Cleanup
    
    deinit {
        timerService.cancel()
        observers.forEach { observer in
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        AppLogger.general.debug("[SleepTimer] ViewModel deinitialized")
    }
}

// MARK: - Timer Delegate
extension SleepTimerService: TimerDelegate {
    nonisolated func timerDidTick(remainingTime: TimeInterval) {
        Task { @MainActor in
            self.remainingTime = remainingTime
        }
    }
    
    nonisolated func timerDidComplete() {
        Task { @MainActor in
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
            
            AppLogger.general.debug("[SleepTimer] Sleep timer completed successfully")
        }
    }
}
