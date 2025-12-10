import SwiftUI
import Combine

// MARK: - App Loading States
enum AppLoadingState: Equatable, Sendable {
    case initial
    case loadingCredentials
    case noCredentialsSaved
    case credentialsFoundValidating
    case networkError(ConnectionIssueType)
    case authenticationError
    case loadingData
    case ready
}

// MARK: - Connection Issue Types
enum ConnectionIssueType: Equatable, Sendable {
    case noInternet
    case serverUnreachable
    case authInvalid
    case serverError

    var userMessage: String {
        switch self {
        case .noInternet: return "No internet connection"
        case .serverUnreachable: return "Cannot reach server"
        case .authInvalid: return "Authentication failed"
        case .serverError: return "Server error"
        }
    }

    var detailMessage: String {
        switch self {
        case .noInternet: return "Please check your network settings and try again."
        case .serverUnreachable: return "Verify server address and ensure it's running."
        case .authInvalid: return "Your credentials are invalid or expired."
        case .serverError: return "The server is experiencing issues. Try again later."
        }
    }

    var canRetry: Bool {
        switch self {
        case .noInternet, .serverUnreachable, .serverError: return true
        case .authInvalid: return false
        }
    }

    var systemImage: String {
        switch self {
        case .noInternet: return "wifi.slash"
        case .serverUnreachable, .serverError: return "icloud.slash"
        case .authInvalid: return "key.slash"
        }
    }

    var iconColor: Color {
        switch self {
        case .noInternet: return .orange
        case .serverUnreachable, .serverError: return .red
        case .authInvalid: return .yellow
        }
    }
}


// MARK: - App State Manager
@MainActor
class AppStateManager: ObservableObject {
    static let shared = AppStateManager()

    @Published var loadingState: AppLoadingState = .initial
    @Published var isFirstLaunch: Bool = false
    @Published var showingWelcome = false
    @Published var showingSettings = false
    @Published var showingBookmarks = false

    @Published var isDeviceOnline: Bool = true
    @Published var isServerReachable: Bool = true

    @Published var selectedTab: TabIndex = .home

    private var lastStatus: NetworkStatus?

    private let networkMonitor: NetworkMonitor
    private let connectionHealthChecker: ConnectionHealthChecking

    private init(
        networkMonitor: NetworkMonitor = NetworkMonitor(),
        connectionHealthChecker: ConnectionHealthChecking = ConnectionHealthChecker()
    ) {
        self.networkMonitor = networkMonitor
        self.connectionHealthChecker = connectionHealthChecker

        checkFirstLaunch()
        setupNetworkMonitoring()
    }

    // MARK: - Network Monitoring
    private func setupNetworkMonitoring() {
        networkMonitor.onStatusChange { [weak self] status in
            Task { @MainActor in
                guard let self = self else { return }

                if status == self.lastStatus { return }
                self.lastStatus = status

                switch status {
                case .offline:
                    self.isDeviceOnline = false
                    self.isServerReachable = false

                case .online:
                    self.networkMonitor.forceRefresh()
                    await self.checkServerReachability()
                    self.verifyConnectionHealth()

                case .unknown:
                    self.isDeviceOnline = false
                    self.isServerReachable = false
                }
            }
        }
        
        networkMonitor.startMonitoring()
        AppLogger.general.info("[AppState] Network monitoring started")
    }

    // MARK: - Self-Healing
    private func verifyConnectionHealth() {
        Task { @MainActor in
            guard networkMonitor.currentStatus == .online else { return }

            try? await Task.sleep(nanoseconds: 5_000_000_000)

            networkMonitor.forceRefresh()
            await checkServerReachability()
            
            AppLogger.general.debug("[AppState] Connection health verified after self-heal")
        }
    }

    // MARK: - Server Reachability
    func checkServerReachability() async {
        guard let api = DependencyContainer.shared.apiClient else { return }

        let monitorStatus = networkMonitor.currentStatus

        let health = await connectionHealthChecker.checkHealth(
            baseURL: api.baseURLString,
            token: api.authToken
        )

        self.isDeviceOnline = monitorStatus == .online
        self.isServerReachable = health != .unavailable
    }
    
    func clearConnectionIssue() {
        if case .networkError = loadingState {
            loadingState = .initial
        }
    }

    private func checkFirstLaunch() {
        let hasStoredCredentials = UserDefaults.standard.string(forKey: "stored_username") != nil
        isFirstLaunch = !hasStoredCredentials

        if isFirstLaunch && !UserDefaults.standard.bool(forKey: "defaults_configured") {
            UserDefaults.standard.set(true, forKey: "defaults_configured")
        }
    }
}

#if DEBUG
extension AppStateManager {
    func debugToggleDeviceOnline() {
        isDeviceOnline.toggle()
        if !isDeviceOnline { isServerReachable = false }
    }
}
#endif
