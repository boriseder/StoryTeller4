import Foundation

protocol LogoutUseCaseProtocol: Sendable {
    func execute() async throws
}

final class LogoutUseCase: LogoutUseCaseProtocol, Sendable {
    private let keychainService: KeychainService
    
    init(keychainService: KeychainService = KeychainService.shared) {
        self.keychainService = keychainService
    }
    
    func execute() async throws {
        // 1. Clear keychain credentials
        try keychainService.clearAllCredentials()
        
        // 2. Clear UserDefaults and post notification on MainActor
        await MainActor.run {
            UserDefaults.standard.removeObject(forKey: "server_scheme")
            UserDefaults.standard.removeObject(forKey: "server_host")
            UserDefaults.standard.removeObject(forKey: "server_port")
            UserDefaults.standard.removeObject(forKey: "stored_username")
            UserDefaults.standard.removeObject(forKey: "baseURL")
            UserDefaults.standard.removeObject(forKey: "apiKey")
            UserDefaults.standard.removeObject(forKey: "selected_library_id")
            UserDefaults.standard.removeObject(forKey: "has_launched_before")
            
            NotificationCenter.default.post(name: .init("ServerSettingsChanged"), object: nil)
        }
        
        // 3. Reset container (if it's NOT async, don't await)
        // Check if reset() is actually async. If not:
        await MainActor.run {
            DependencyContainer.shared.reset()
        }
        
        // 4. Shutdown cover manager
        await CoverDownloadManager.shared.shutdown()
        
        AppLogger.general.debug("[LogoutUseCase] User logged out successfully")
    }
}
