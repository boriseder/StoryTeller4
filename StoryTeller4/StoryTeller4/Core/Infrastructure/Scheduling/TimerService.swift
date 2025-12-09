import Foundation

protocol TimerDelegate: AnyObject {
    func timerDidTick(remainingTime: TimeInterval)
    func timerDidComplete()
}

enum TimerState {
    case idle
    case running
    case paused
    case completed
}

protocol TimerManaging {
    var state: TimerState { get }
    var remainingTime: TimeInterval { get }
    
    func start(duration: TimeInterval)
    func pause()
    func resume()
    func cancel()
}

class TimerService: TimerManaging {
    
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.storyteller3.timer", qos: .utility)
    
    private(set) var state: TimerState = .idle
    private(set) var remainingTime: TimeInterval = 0
    private var endDate: Date?
    
    weak var delegate: TimerDelegate?
    
    func start(duration: TimeInterval) {
        guard duration > 0 else { return }
        guard state == .idle || state == .completed else { return }
        
        cancel()
        
        remainingTime = duration
        endDate = Date().addingTimeInterval(duration)
        state = .running
        
        startTimer()
        
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
        startTimer()
        
        AppLogger.general.debug("[TimerService] Timer resumed")
    }
    
    func cancel() {
        timer?.cancel()
        timer = nil
        
        state = .idle
        remainingTime = 0
        endDate = nil
        
        AppLogger.general.debug("[TimerService] Timer cancelled")
    }
    
    private func startTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .seconds(1), leeway: .milliseconds(100))
        
        timer.setEventHandler { [weak self] in
            guard let self = self,
                  let endDate = self.endDate else { return }
            
            let remaining = endDate.timeIntervalSinceNow
            
            Task { @MainActor in
                self.remainingTime = max(0, remaining)
                self.delegate?.timerDidTick(remainingTime: self.remainingTime)
                
                if remaining <= 0 {
                    self.complete()
                }
            }
        }
        
        self.timer = timer
        timer.resume()
    }
    
    private func complete() {
        cancel()
        state = .completed
        
        Task { @MainActor in
            delegate?.timerDidComplete()
        }
        
        AppLogger.general.debug("[TimerService] Timer completed")
    }
    
    deinit {
        cancel()
    }
}
