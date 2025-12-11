// Add @preconcurrency to silence Sendable warnings for system frameworks if needed
@preconcurrency import Foundation
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
private struct SleepTimerPersistenceState: Codable, Sendable {
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
    
    // ✅ FIX: Use wrapper to handle observer cleanup safely
    private let observerWrapper = ObserverWrapper()
    
    init(
        player: AudioPlayer,
        timerService: TimerManaging = TimerService()
    ) {
        self.player = player
        self.timerService = timerService
        
        // Setup callbacks asynchronously
        Task { @MainActor in
            if let service = timerService as? TimerService {
                await service.setCallbacks(
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
        
        setupNotifications()
        restoreTimerState()
    }
    
    var timerOptionsArray: [Int] {
        timerOptions
    }
    
    func startTimer(mode: SleepTimerMode) {
        Task {
            await cancelTimer()
            
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
    
    // MARK: - Timer Implementation
    
    private func startTimerWithDuration(_ duration: TimeInterval, mode: SleepTimerMode) async {
        let endDate = Date().addingTimeInterval(duration)
        
        await timerService.start(duration: duration)
        
        isTimerActive = true
        remainingTime = duration
        currentMode = mode
        
        saveTimerState(endDate: endDate, mode: mode)
        scheduleTimerEndNotification(fireDate: endDate)
        
        AppLogger.general.debug("[SleepTimer] Timer started - duration: \(duration)s, mode: \(mode)")
    }
    
    // MARK: - Persistence
    
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
        
        Task {
            await startTimerWithDuration(remaining, mode: mode)
            AppLogger.general.debug("[SleepTimer] Restored timer state - remaining: \(remaining)s")
        }
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
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                guard self.isTimerActive, let mode = self.currentMode else { return }
                
                let endDate = Date().addingTimeInterval(self.remainingTime)
                self.saveTimerState(endDate: endDate, mode: mode)
            }
        }
        // ✅ FIX: Use wrapper to store observer
        observerWrapper.add(backgroundObserver)
        
        requestNotificationPermission()
    }
    
    private nonisolated func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                AppLogger.general.debug("[SleepTimer] Notification permission error: \(error)")
            } else if granted {
                AppLogger.general.debug("[SleepTimer] Notification permission granted")
            }
        }
    }
    
    private nonisolated func scheduleTimerEndNotification(fireDate: Date) {
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
    
    private nonisolated func cancelTimerEndNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["sleep_timer_end"]
        )
    }
    
    // MARK: - Timer Completion Logic
    
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
        
        AppLogger.general.debug("[SleepTimer] Sleep timer completed successfully")
    }
    
    deinit {
        let service = timerService
        Task.detached {
            await service.cancel()
        }
        
        // Use Task.detached for logging since we're in deinit
        Task.detached {
            AppLogger.general.debug("[SleepTimer] Deinitialized")
        }
        
        // ✅ FIX: No manual observer removal here.
        // observerWrapper will be deinitialized automatically, cleaning up observers.
    }
}

// MARK: - Observer Wrapper
private final class ObserverWrapper {
    private var observers: [NSObjectProtocol] = []
    
    func add(_ observer: NSObjectProtocol) {
        observers.append(observer)
    }
    
    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }
}
