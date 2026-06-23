import SwiftUI
import Observation

@MainActor
@Observable
final class AppStateManager {
    
    // MARK: - Singleton
    static let shared = AppStateManager()
    
    // MARK: - App State
    var selectedTab: TabIndex = .home
    var loadingState: AppLoadingState = .initial
    var showingSettings = false
    var showingWelcome = false
    
    // FIX: Added missing isFirstLaunch property with persistence
    var isFirstLaunch: Bool {
        didSet {
            // When set to false, save that we have launched before
            if !isFirstLaunch {
                UserDefaults.standard.set(true, forKey: "has_launched_before")
            }
        }
    }
    
    // MARK: - Connectivity
    var isDeviceOnline = true
    var isServerReachable = true
    
    var connectionError: String?
    
    // MARK: - Init
    private init() {
        // Initialize isFirstLaunch from UserDefaults (default false -> isFirstLaunch = true)
        let hasLaunched = UserDefaults.standard.bool(forKey: "has_launched_before")
        self.isFirstLaunch = !hasLaunched
    }
    
    // MARK: - Actions
    func checkServerReachability() async {
        // Implementation for reachability check
        // In a real app, use NetworkMonitor or simple HTTP request
    }
    
    func debugToggleDeviceOnline() {
        isDeviceOnline.toggle()
        AppLogger.general.debug("[AppState] Device online forced to: \(isDeviceOnline)")
    }
    
    func clearConnectionIssue() {
        loadingState = .ready
        isServerReachable = true
    }
}

// MARK: - Support Enums
enum AppLoadingState: Equatable {
    case initial
    case loadingCredentials
    case noCredentialsSaved
    case credentialsFoundValidating
    case loadingData
    case ready
    case authenticationError
    case networkError(ConnectionIssueType)
}

enum ConnectionIssueType: Equatable {
    case noInternet
    case serverUnreachable
    case serverError
}
