import Foundation

protocol AuthenticationUseCaseProtocol {
    func login(baseURL: String, username: String, password: String) async throws -> String
    func logout() async
    func validateToken(baseURL: String, token: String) async throws -> Bool
}

class AuthenticationUseCase: AuthenticationUseCaseProtocol {
    private let authService: AuthenticationService
    private let keychainService: KeychainService
    
    init(
        authService: AuthenticationService = AuthenticationService(),
        keychainService: KeychainService = KeychainService.shared
    ) {
        self.authService = authService
        self.keychainService = keychainService
    }
    
    func login(baseURL: String, username: String, password: String) async throws -> String {
        return try await authService.login(baseURL: baseURL, username: username, password: password)
    }
    
    func logout() async {
        do {
            try keychainService.clearAllCredentials()
        } catch {
            AppLogger.general.debug("Failed to clear keychain: \(error)")
        }
        
        await CoverDownloadManager.shared.shutdown()
    }
    
    func validateToken(baseURL: String, token: String) async throws -> Bool {
        return try await authService.validateToken(baseURL: baseURL, token: token)
    }
    
    func storeCredentials(username: String, password: String, token: String) throws {
        try keychainService.storePassword(password, for: username)
        try keychainService.storeToken(token, for: username)
    }
    
    func getStoredCredentials(for username: String) throws -> (password: String, token: String) {
        let password = try keychainService.getPassword(for: username)
        let token = try keychainService.getToken(for: username)
        return (password, token)
    }
}
