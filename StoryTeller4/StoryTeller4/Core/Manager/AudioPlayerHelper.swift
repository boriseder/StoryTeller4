import Foundation

// MARK: - LockedState (Thread-Safe Helper)
final class LockedState<T>: @unchecked Sendable {
    private nonisolated(unsafe) var state: T
    private let lock = NSLock()
    
    nonisolated init(_ state: T) {
        self.state = state
    }
    
    nonisolated func withLock<R>(_ body: (inout T) -> R) -> R {
        lock.lock()
        defer { lock.unlock() }
        return body(&state)
    }
}

// MARK: - Notification Observer Wrapper (Safe Deinit)
final class NotificationObserverWrapper: Sendable {
    private let observers: LockedState<[NSObjectProtocol]>
    
    nonisolated init() {
        self.observers = LockedState([])
    }
    
    nonisolated func add(_ observer: NSObjectProtocol) {
        observers.withLock { $0.append(observer) }
    }
    
    deinit {
        let items = observers.withLock { $0 }
        if !items.isEmpty {
            items.forEach { NotificationCenter.default.removeObserver($0) }
        }
    }
}
