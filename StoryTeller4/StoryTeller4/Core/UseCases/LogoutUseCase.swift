import Foundation

protocol LogoutUseCaseProtocol {
    func execute() async throws
}

class LogoutUseCase: LogoutUseCaseProtocol {
    private let keychainService: KeychainService
    
    init(keychainService: KeychainService = KeychainService.shared) {
        self.keychainService = keychainService
    }
    
    func execute() async throws {
        try keychainService.clearAllCredentials()
        
        await MainActor.run {
            UserDefaults.standard.removeObject(forKey: "server_scheme")
            UserDefaults.standard.removeObject(forKey: "server_host")
            UserDefaults.standard.removeObject(forKey: "server_port")
            UserDefaults.standard.removeObject(forKey: "stored_username")
            UserDefaults.standard.removeObject(forKey: "baseURL")
            UserDefaults.standard.removeObject(forKey: "apiKey")
            UserDefaults.standard.removeObject(forKey: "selected_library_id")
            
            // Reset DependencyContainer to clear all repositories
            DependencyContainer.shared.reset()
            
            NotificationCenter.default.post(name: .init("ServerSettingsChanged"), object: nil)
        }
        
        await CoverDownloadManager.shared.shutdown()
        
        AppLogger.general.debug("[LogoutUseCase] User logged out successfully")
    }}
