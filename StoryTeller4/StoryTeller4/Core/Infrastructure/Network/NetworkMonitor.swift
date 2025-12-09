import Foundation
import Network

enum NetworkStatus: Equatable, CustomStringConvertible {
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

protocol NetworkMonitoring {
    var isOnline: Bool { get }
    var currentStatus: NetworkStatus { get }

    func startMonitoring()
    func stopMonitoring()
    func forceRefresh()
}

final class NetworkMonitor: NetworkMonitoring {
    
    private var monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.storyteller3.networkmonitor")
    private var statusHandler: ((NetworkStatus) -> Void)?
    private var watchdogTimer: DispatchSourceTimer?
    private var offlineSince: Date?
    private var isRunning = false

    private(set) var currentStatus: NetworkStatus = .unknown {
        didSet {
            if currentStatus != oldValue {
                statusHandler?(currentStatus)
                if currentStatus == .online {
                    NotificationCenter.default.post(name: .networkConnectivityChanged, object: nil)
                }
            }
        }
    }
    
    var isOnline: Bool { currentStatus == .online }
    
    func startMonitoring() {
        
        guard !isRunning else { return }
        isRunning = true

        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let newStatus: NetworkStatus = path.status == .satisfied ? .online : .offline
            Task { @MainActor in
                self.currentStatus = newStatus
                if newStatus == .offline { self.offlineSince = Date() }
                else { self.offlineSince = nil }
            }
        }
        
        monitor.start(queue: queue)
        startWatchdog()
    }
    
    func stopMonitoring() {
        monitor.cancel()
        watchdogTimer?.cancel()
        watchdogTimer = nil
    }
    
    func forceRefresh() {
        offlineSince = Date()
    }
    
    func onStatusChange(_ handler: @escaping (NetworkStatus) -> Void) {
        statusHandler = handler
    }
    
    private func startWatchdog() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 3, repeating: 3)
        
        t.setEventHandler { [weak self] in
            guard let self else { return }
            if let since = self.offlineSince {
                if Date().timeIntervalSince(since) > 6 {
                    self.resetMonitor()
                }
            }
        }
        
        watchdogTimer = t
        t.resume()
    }
    
    private func resetMonitor() {
        monitor.cancel()
        let newMonitor = NWPathMonitor()
        monitor = newMonitor
        startMonitoring()
    }
    
    deinit {
        stopMonitoring()
    }
}
