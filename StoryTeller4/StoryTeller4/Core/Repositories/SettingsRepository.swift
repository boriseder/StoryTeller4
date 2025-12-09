import Foundation

// MARK: - Server Configuration
struct StoredServerConfig {
    let scheme: String
    let host: String
    let port: String
    let username: String
    
    var fullURL: String {
        let portString = port.isEmpty ? "" : ":\(port)"
        return "\(scheme)://\(host)\(portString)"
    }
}


// MARK: - Repository Protocol
protocol SettingsRepositoryProtocol {
    func getServerConfig() -> StoredServerConfig?
    func saveServerConfig(_ config: ServerConfig)
    func clearServerConfig()
    
    func getCredentials(for username: String) throws -> (password: String, token: String)
    func saveCredentials(username: String, password: String, token: String) throws
    func clearCredentials(for username: String) throws
        
    func getSelectedLibraryId() -> String?
    func saveSelectedLibraryId(_ libraryId: String?)
}

// MARK: - Settings Repository Implementation
class SettingsRepository: SettingsRepositoryProtocol {
    
    private let userDefaults: UserDefaults
    private let keychainService: KeychainService
    
    init(
        userDefaults: UserDefaults = .standard,
        keychainService: KeychainService = .shared
    ) {
        self.userDefaults = userDefaults
        self.keychainService = keychainService
    }
    
    // MARK: - Server Configuration
    
    func getServerConfig() -> StoredServerConfig? {
        guard let host = userDefaults.string(forKey: "server_host"),
              !host.isEmpty else {
            return nil
        }
        
        return StoredServerConfig(
            scheme: userDefaults.string(forKey: "server_scheme") ?? "http",
            host: host,
            port: userDefaults.string(forKey: "server_port") ?? "",
            username: userDefaults.string(forKey: "stored_username") ?? ""
        )
    }
    
    func saveServerConfig(_ config: ServerConfig) {
        userDefaults.set(config.scheme, forKey: "server_scheme")
        userDefaults.set(config.host, forKey: "server_host")
        userDefaults.set(config.port, forKey: "server_port")
        userDefaults.set(config.fullURL, forKey: "baseURL")
        
        AppLogger.general.debug("[SettingsRepository] Saved server config: \(config.fullURL)")
    }
    
    func clearServerConfig() {
        userDefaults.removeObject(forKey: "server_scheme")
        userDefaults.removeObject(forKey: "server_host")
        userDefaults.removeObject(forKey: "server_port")
        userDefaults.removeObject(forKey: "stored_username")
        userDefaults.removeObject(forKey: "baseURL")
        userDefaults.removeObject(forKey: "apiKey")
        
        AppLogger.general.debug("[SettingsRepository] Cleared server config")
    }
    
    // MARK: - Credentials Management
    
    func getCredentials(for username: String) throws -> (password: String, token: String) {
        let password = try keychainService.getPassword(for: username)
        let token = try keychainService.getToken(for: username)
        return (password, token)
    }
    
    func saveCredentials(username: String, password: String, token: String) throws {
        try keychainService.storePassword(password, for: username)
        try keychainService.storeToken(token, for: username)
        
        userDefaults.set(username, forKey: "stored_username")
        
        AppLogger.general.debug("[SettingsRepository] Saved credentials for user: \(username)")
    }
    
    func clearCredentials(for username: String) throws {
        try keychainService.clearAllCredentials()
        userDefaults.removeObject(forKey: "stored_username")
        
        AppLogger.general.debug("[SettingsRepository] Cleared credentials")
    }
    
    
    // MARK: - Library Selection
    
    func getSelectedLibraryId() -> String? {
        userDefaults.string(forKey: "selected_library_id")
    }
    
    func saveSelectedLibraryId(_ libraryId: String?) {
        if let id = libraryId {
            userDefaults.set(id, forKey: "selected_library_id")
            AppLogger.general.debug("[SettingsRepository] Saved library selection: \(id)")
        } else {
            userDefaults.removeObject(forKey: "selected_library_id")
            AppLogger.general.debug("[SettingsRepository] Cleared library selection")
        }
    }
}

// MARK: - Helper Extensions
private extension Double {
    func orDefault(_ defaultValue: Double) -> Double {
        self == 0 ? defaultValue : self
    }
}

private extension Int {
    func orDefault(_ defaultValue: Int) -> Int {
        self == 0 ? defaultValue : self
    }
}

// MARK: - Settings Errors
enum SettingsError: LocalizedError {
    case credentialsNotFound
    case keychainError(Error)
    case invalidConfiguration
    
    var errorDescription: String? {
        switch self {
        case .credentialsNotFound:
            return "No saved credentials found"
        case .keychainError(let error):
            return "Keychain error: \(error.localizedDescription)"
        case .invalidConfiguration:
            return "Invalid server configuration"
        }
    }
}
