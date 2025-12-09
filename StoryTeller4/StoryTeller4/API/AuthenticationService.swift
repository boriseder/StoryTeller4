
import Foundation

struct LoginCredentials: Codable {
    let username: String
    let password: String
    let type: String
    
    init(username: String, password: String) {
        self.username = username
        self.password = password
        self.type = "login"
    }
}

struct LoginResponse: Codable {
    let user: UserInfo
    
    struct UserInfo: Codable {
        let id: String
        let username: String
        let token: String
    }
}

class AuthenticationService {
    private let networkService: NetworkService
    
    init(networkService: NetworkService = DefaultNetworkService()) {
        self.networkService = networkService
    }
    
    func login(baseURL: String, username: String, password: String) async throws -> String {
        guard let url = URL(string: "\(baseURL)/login") else {
            throw AudiobookshelfError.invalidURL("\(baseURL)/login")
        }
        
        let credentials = LoginCredentials(username: username, password: password)
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30.0
        
        do {
            let jsonData = try JSONEncoder().encode(credentials)
            request.httpBody = jsonData
        } catch {
            throw AudiobookshelfError.decodingError(error)
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AudiobookshelfError.invalidResponse
        }
        
        AppLogger.general.debug("############ USER LOGGED IN #######")
        
        switch httpResponse.statusCode {
        case 200:
            do {
                let loginResponse = try JSONDecoder().decode(LoginResponse.self, from: data)
                return loginResponse.user.token
            } catch {
                throw AudiobookshelfError.decodingError(error)
            }
        case 401:
            throw AudiobookshelfError.unauthorized
        case 400:
            throw AudiobookshelfError.serverError(400, "Invalid credentials")
        default:
            let errorMessage = String(data: data, encoding: .utf8)
            throw AudiobookshelfError.serverError(httpResponse.statusCode, errorMessage)
        }
    }
    
    func validateToken(baseURL: String, token: String) async throws -> Bool {
        guard let url = URL(string: "\(baseURL)/api/me") else {
            throw AudiobookshelfError.invalidURL("\(baseURL)/api/me")
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30.0
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AudiobookshelfError.invalidResponse
        }
        
        return httpResponse.statusCode == 200
    }
}
