import Foundation

// Delegate needs to be AnyObject to be weak, and usually UI related (MainActor)
@MainActor
protocol TimerDelegate: AnyObject {
    func timerDidTick(remainingTime: TimeInterval)
    func timerDidComplete()
}

enum TimerState: Sendable {
    case idle
    case running
    case paused
    case completed
}

// Protocol adapted for Actor
protocol TimerManaging: Sendable {
    var state: TimerState { get async }
    var remainingTime: TimeInterval { get async }
    
    func start(duration: TimeInterval) async
    func pause() async
    func resume() async
    func cancel() async
}

// Converted to Actor
actor TimerService: TimerManaging {
    
    private var timer: DispatchSourceTimer?
    // Removed queue (actor is the queue)
    
    private(set) var state: TimerState = .idle
    private(set) var remainingTime: TimeInterval = 0
    private var endDate: Date?
    
    // Delegate access is tricky in actors.
    // We store it as weak MainActor-isolated reference.
    @MainActor weak var delegate: TimerDelegate?
    
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
        // DispatchSourceTimer needs a queue. Even within an actor, the timer fires on a queue.
        // We use a private queue for the timer mechanism, but synchronize state updates back to the actor.
        let queue = DispatchQueue(label: "com.storyteller3.timer.internal", qos: .utility)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .seconds(1), leeway: .milliseconds(100))
        
        timer.setEventHandler { [weak self] in
            Task {
                await self?.handleTick()
            }
        }
        
        self.timer = timer
        timer.resume()
    }
    
    private func handleTick() async {
        guard let endDate = self.endDate else { return }
        
        let remaining = endDate.timeIntervalSinceNow
        self.remainingTime = max(0, remaining)
        
        // Notify delegate on MainActor
        await MainActor.run {
            self.delegate?.timerDidTick(remainingTime: self.remainingTime)
        }
        
        if remaining <= 0 {
            complete()
        }
    }
    
    private func complete() {
        cancelTimerInternal()
        state = .completed
        
        Task { @MainActor in
            delegate?.timerDidComplete()
        }
        
        AppLogger.general.debug("[TimerService] Timer completed")
    }
    
    deinit {
        // Deinit in actors is constrained, but we can try to cancel the timer object if it exists
        // Note: You can't access `timer` here if it implies isolation check, but checking optional storage is mostly safe.
    }
}
