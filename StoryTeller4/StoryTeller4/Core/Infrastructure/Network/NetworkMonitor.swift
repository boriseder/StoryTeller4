import Foundation
import Network

// MARK: - Network Status
enum NetworkStatus: Sendable {
    case online
    case offline
    case unknown
    
    var description: String {
        switch self {
        case .online: return "online"
        case .offline: return "offline"
        case .unknown: return "unknown"
        }
    }
}

// Explicit Equatable conformance to avoid isolation issues
extension NetworkStatus: Equatable {
    nonisolated static func == (lhs: NetworkStatus, rhs: NetworkStatus) -> Bool {
        switch (lhs, rhs) {
        case (.online, .online), (.offline, .offline), (.unknown, .unknown):
            return true
        default:
            return false
        }
    }
}

// MARK: - Protocol
protocol NetworkMonitoring: Sendable {
    var currentStatus: NetworkStatus { get async }
    func startMonitoring() async
    func stopMonitoring() async
    func forceRefresh() async
    func onStatusChange(_ handler: @escaping @Sendable (NetworkStatus) -> Void) async
}

// MARK: - Network Monitor Actor
actor NetworkMonitor: NetworkMonitoring {
    
    private var monitor = NWPathMonitor()
    // Actors don't need explicit queues for isolation, but NWPathMonitor needs one for callbacks
    private let queue = DispatchQueue(label: "com.storyteller3.networkmonitor")
    private var statusHandler: (@Sendable (NetworkStatus) -> Void)?
    private var watchdogTimer: DispatchSourceTimer?
    private var offlineSince: Date?
    private var isRunning = false

    private(set) var currentStatus: NetworkStatus = .unknown {
        didSet {
            if currentStatus != oldValue {
                let status = currentStatus
                // Notify handler
                if let handler = statusHandler {
                    Task { @MainActor in handler(status) }
                }
                // Post notification
                if status == .online {
                    Task { @MainActor in
                        NotificationCenter.default.post(name: .networkConnectivityChanged, object: nil)
                    }
                }
            }
        }
    }
    
    var isOnline: Bool { currentStatus == .online }
    
    func startMonitoring() {
        guard !isRunning else { return }
        isRunning = true

        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            let newStatus: NetworkStatus = path.status == .satisfied ? .online : .offline
            
            Task {
                await self.updateStatus(newStatus)
            }
        }
        
        monitor.start(queue: queue)
        startWatchdog()
    }
    
    private func updateStatus(_ newStatus: NetworkStatus) {
        self.currentStatus = newStatus
        if newStatus == .offline { self.offlineSince = Date() }
        else { self.offlineSince = nil }
    }
    
    func stopMonitoring() {
        monitor.cancel()
        watchdogTimer?.cancel()
        watchdogTimer = nil
        isRunning = false
    }
    
    func forceRefresh() {
        offlineSince = Date()
    }
    
    func onStatusChange(_ handler: @escaping @Sendable (NetworkStatus) -> Void) {
        statusHandler = handler
    }
    
    private func startWatchdog() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 3, repeating: 3)
        
        t.setEventHandler { [weak self] in
            guard let self = self else { return }
            Task {
                await self.checkWatchdog()
            }
        }
        
        watchdogTimer = t
        t.resume()
    }
    
    private func checkWatchdog() {
        if let since = self.offlineSince {
            if Date().timeIntervalSince(since) > 6 {
                self.resetMonitor()
            }
        }
    }
    
    private func resetMonitor() {
        monitor.cancel()
        let newMonitor = NWPathMonitor()
        monitor = newMonitor
        
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            let newStatus: NetworkStatus = path.status == .satisfied ? .online : .offline
            Task { await self.updateStatus(newStatus) }
        }
        monitor.start(queue: queue)
    }
    
    deinit {
        // monitor.cancel() cannot be called safely here in deinit for an actor
    }
}

// MARK: - Notification Extension
// Defined here to ensure visibility
public extension Notification.Name {
    static let networkConnectivityChanged = Notification.Name("networkConnectivityChanged")
}
