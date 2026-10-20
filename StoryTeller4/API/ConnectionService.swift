import Foundation

protocol ConnectionServiceProtocol {
    func testConnection() async throws -> ConnectionTestResult
    func checkHealth() async -> Bool
}

class DefaultConnectionService: ConnectionServiceProtocol {
    private let config: APIConfig
    private let networkService: NetworkService
    
    init(config: APIConfig, networkService: NetworkService) {
        self.config = config
        self.networkService = networkService
    }
    
    func testConnection() async throws -> ConnectionTestResult {
        guard let url = URL(string: "\(config.baseURL)/api/libraries") else {
            throw AudiobookshelfError.invalidURL(config.baseURL)
        }
        
        let request = networkService.createAuthenticatedRequest(url: url, authToken: config.authToken)
        
        do {
            let _: LibrariesResponse = try await networkService.performRequest(request, responseType: LibrariesResponse.self)
            return .success
        } catch AudiobookshelfError.unauthorized {
            var unauthenticatedRequest = URLRequest(url: url)
            unauthenticatedRequest.timeoutInterval = 10.0
            
            do {
                let (_, response) = try await URLSession.shared.data(for: unauthenticatedRequest)
                if let httpResponse = response as? HTTPURLResponse {
                    return httpResponse.statusCode == 401 ? .authenticationError : .failed
                }
            } catch {
                return .failed
            }
            
            return .failed
        } catch {
            return .failed
        }
    }
    
    func checkHealth() async -> Bool {
        guard let url = URL(string: "\(config.baseURL)/ping") else {
            return false
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 10.0
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200
            }
            return false
        } catch {
            return false
        }
    }
}
