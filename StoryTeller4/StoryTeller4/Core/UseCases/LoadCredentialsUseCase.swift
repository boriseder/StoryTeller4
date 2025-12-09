import Foundation

protocol LoadCredentialsUseCaseProtocol {
    func execute() async throws -> LoadedCredentials?
}

struct LoadedCredentials {
    let scheme: String
    let host: String
    let port: String
    let username: String
    let password: String
    let token: String
    let baseURL: String
}

class LoadCredentialsUseCase: LoadCredentialsUseCaseProtocol {
    private let keychainService: KeychainService
    private let authService: AuthenticationService
    
    init(
        keychainService: KeychainService = KeychainService.shared,
        authService: AuthenticationService = AuthenticationService()
    ) {
        self.keychainService = keychainService
        self.authService = authService
    }
    
    func execute() async throws -> LoadedCredentials? {
        guard let scheme = UserDefaults.standard.string(forKey: "server_scheme"),
              let host = UserDefaults.standard.string(forKey: "server_host"),
              let port = UserDefaults.standard.string(forKey: "server_port"),
              let savedUsername = UserDefaults.standard.string(forKey: "stored_username"),
              let baseURL = UserDefaults.standard.string(forKey: "baseURL") else {
            AppLogger.general.debug("[LoadCredentialsUseCase] No saved credentials found")
            return nil
        }
        
        let password = try keychainService.getPassword(for: savedUsername)
        let token = try keychainService.getToken(for: savedUsername)
        
        let isValid = try await authService.validateToken(baseURL: baseURL, token: token)
        
        guard isValid else {
            AppLogger.general.debug("[LoadCredentialsUseCase] Token expired")
            throw CredentialsError.tokenExpired
        }
        
        AppLogger.general.debug("[LoadCredentialsUseCase] Credentials loaded and validated successfully")
        
        return LoadedCredentials(
            scheme: scheme,
            host: host,
            port: port,
            username: savedUsername,
            password: password,
            token: token,
            baseURL: baseURL
        )
    }
}

enum CredentialsError: Error {
    case tokenExpired
    case notFound
}
