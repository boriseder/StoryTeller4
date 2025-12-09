import Foundation

protocol SaveCredentialsUseCaseProtocol {
    func execute(credentials: UserCredentials) async throws
}

struct UserCredentials {
    let scheme: String
    let host: String
    let port: String
    let username: String
    let password: String
    let token: String
    let baseURL: String
}

class SaveCredentialsUseCase: SaveCredentialsUseCaseProtocol {
    private let keychainService: KeychainService
    
    init(keychainService: KeychainService = KeychainService.shared) {
        self.keychainService = keychainService
    }
    
    func execute(credentials: UserCredentials) async throws {
        try keychainService.storePassword(credentials.password, for: credentials.username)
        try keychainService.storeToken(credentials.token, for: credentials.username)
        
        await MainActor.run {
            UserDefaults.standard.set(credentials.scheme, forKey: "server_scheme")
            UserDefaults.standard.set(credentials.host, forKey: "server_host")
            UserDefaults.standard.set(credentials.port, forKey: "server_port")
            UserDefaults.standard.set(credentials.username, forKey: "stored_username")
            UserDefaults.standard.set(credentials.baseURL, forKey: "baseURL")
            
            NotificationCenter.default.post(name: .init("ServerSettingsChanged"), object: nil)
        }
        
        AppLogger.general.debug("[SaveCredentialsUseCase] Credentials stored successfully")
    }
}
