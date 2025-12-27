import Foundation
import Network

// MARK: - Network Status
enum NetworkStatus: Sendable {
    case online, offline, unknown
}

extension NetworkStatus: Equatable {
    nonisolated static func == (lhs: NetworkStatus, rhs: NetworkStatus) -> Bool {
        switch (lhs, rhs) {
        case (.online, .online), (.offline, .offline), (.unknown, .unknown): return true
        default: return false
        }
    }
}

protocol NetworkMonitoring: Sendable {
    var currentStatus: NetworkStatus { get async }
    func startMonitoring() async
    func stopMonitoring() async
    func forceRefresh() async
    func onStatusChange(_ handler: @escaping @Sendable (NetworkStatus) -> Void) async
}

actor NetworkMonitor: NetworkMonitoring {
    // FIX: Make monitor optional to handle lifecycle correctly (creation/invalidation)
    private var monitor: NWPathMonitor?
    private let queue = DispatchQueue(label: "com.storyteller3.networkmonitor")
    private var statusHandler: (@Sendable (NetworkStatus) -> Void)?
    private var offlineSince: Date?
    private var isRunning = false

    private(set) var currentStatus: NetworkStatus = .unknown {
        didSet {
            if currentStatus != oldValue {
                let status = currentStatus
                // Notify via callback
                if let handler = statusHandler {
                    Task { @MainActor in handler(status) }
                }
                // Notify via NotificationCenter
                if status == .online {
                    Task { @MainActor in NotificationCenter.default.post(name: .networkConnectivityChanged, object: nil) }
                }
            }
        }
    }
    
    func startMonitoring() {
        guard !isRunning else { return }
        
        // FIX: Always instantiate a fresh monitor.
        // Once a NWPathMonitor is cancelled, it cannot be restarted.
        monitor = NWPathMonitor()
        
        monitor?.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            let newStatus: NetworkStatus = path.status == .satisfied ? .online : .offline
            Task { await self.updateStatus(newStatus) }
        }
        
        monitor?.start(queue: queue)
        isRunning = true
    }
    
    private func updateStatus(_ newStatus: NetworkStatus) {
        self.currentStatus = newStatus
    }
    
    func stopMonitoring() {
        // FIX: Cancel and release the monitor instance to prevent NECP errors on restart
        monitor?.cancel()
        monitor = nil
        isRunning = false
    }
    
    func forceRefresh() {
        offlineSince = Date()
    }
    
    func onStatusChange(_ handler: @escaping @Sendable (NetworkStatus) -> Void) {
        statusHandler = handler
    }
}

public extension Notification.Name {
    static let networkConnectivityChanged = Notification.Name("networkConnectivityChanged")
}
