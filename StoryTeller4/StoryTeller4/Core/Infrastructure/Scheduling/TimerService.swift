import Foundation

enum TimerState: Sendable, Equatable {
    case idle
    case running
    case paused
    case completed
    
    // Explicitly nonisolated to allow comparison in any context
    nonisolated static func == (lhs: TimerState, rhs: TimerState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.running, .running), (.paused, .paused), (.completed, .completed):
            return true
        default:
            return false
        }
    }
}

// Protocol adapted for Actor
protocol TimerManaging: Sendable {
    var state: TimerState { get async }
    var remainingTime: TimeInterval { get async }
    
    func start(duration: TimeInterval) async
    func pause() async
    func resume() async
    func cancel() async
    
    func setCallbacks(
        onTick: @escaping @Sendable (TimeInterval) -> Void,
        onComplete: @escaping @Sendable () -> Void
    ) async
}

// Actor for thread-safe timer management
actor TimerService: TimerManaging {
    
    private var timer: DispatchSourceTimer?
    
    private(set) var state: TimerState = .idle
    private(set) var remainingTime: TimeInterval = 0
    private var endDate: Date?
    
    // Sendable callbacks for crossing actor boundaries
    private var onTick: (@Sendable (TimeInterval) -> Void)?
    private var onComplete: (@Sendable () -> Void)?
    
    func setCallbacks(
        onTick: @escaping @Sendable (TimeInterval) -> Void,
        onComplete: @escaping @Sendable () -> Void
    ) {
        self.onTick = onTick
        self.onComplete = onComplete
    }
    
    func start(duration: TimeInterval) {
        guard duration > 0 else { return }
        guard state == .idle || state == .completed else { return }
        
        cancelTimerInternal()
        
        remainingTime = duration
        endDate = Date().addingTimeInterval(duration)
        state = .running
        
        startTimerInternal()
        
        AppLogger.general.debug("[TimerService] Started timer with duration: \(duration)s")
    }
    
    func pause() {
        guard state == .running else { return }
        
        timer?.cancel()
        timer = nil
        state = .paused
        
        AppLogger.general.debug("[TimerService] Timer paused")
    }
    
    func resume() {
        guard state == .paused else { return }
        
        state = .running
        startTimerInternal()
        
        AppLogger.general.debug("[TimerService] Timer resumed")
    }
    
    func cancel() {
        cancelTimerInternal()
        
        state = .idle
        remainingTime = 0
        endDate = nil
        
        AppLogger.general.debug("[TimerService] Timer cancelled")
    }
    
    private func cancelTimerInternal() {
        timer?.cancel()
        timer = nil
    }
    
    private func startTimerInternal() {
        let queue = DispatchQueue(label: "com.storyteller3.timer.internal", qos: .utility)
        let newTimer = DispatchSource.makeTimerSource(queue: queue)
        newTimer.schedule(deadline: .now(), repeating: .seconds(1), leeway: .milliseconds(100))
        
        // Use unowned(unsafe) to avoid sendability warning
        // Safe because: timer is cancelled in deinit before actor is destroyed
        newTimer.setEventHandler { [unowned(unsafe) self] in
            Task { [unowned(unsafe) self] in
                await self.handleTick()
            }
        }
        
        self.timer = newTimer
        newTimer.resume()
    }
    
    private func handleTick() async {
        guard let endDate = self.endDate else { return }
        
        let remaining = endDate.timeIntervalSinceNow
        self.remainingTime = max(0, remaining)
        
        // Call the callback - it's @Sendable so safe to call from actor
        onTick?(self.remainingTime)
        
        if remaining <= 0 {
            complete()
        }
    }
    
    private func complete() {
        cancelTimerInternal()
        state = .completed
        
        // Call completion callback
        onComplete?()
        
        AppLogger.general.debug("[TimerService] Timer completed")
    }
    
    deinit {
        timer?.cancel()
    }
}
