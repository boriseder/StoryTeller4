import Foundation

enum ConnectionHealth {
    case healthy
    case degraded
    case unavailable
}

protocol ConnectionHealthChecking {
    func checkHealth(baseURL: String, token: String) async -> ConnectionHealth
    func ping(baseURL: String) async -> Bool
}

class ConnectionHealthChecker: ConnectionHealthChecking {
    
    private let timeout: TimeInterval
    
    init(timeout: TimeInterval = 10.0) {
        self.timeout = timeout
    }
    
    func checkHealth(baseURL: String, token: String) async -> ConnectionHealth {
        guard let url = URL(string: "\(baseURL)/api/ping") else {
            return .unavailable
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = timeout
        
        do {
            let startTime = Date()
            let (_, response) = try await URLSession.shared.data(for: request)
            let responseTime = Date().timeIntervalSince(startTime)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return .unavailable
            }
            
            switch httpResponse.statusCode {
            case 200:
                return responseTime < 2.0 ? .healthy : .degraded
            case 401, 403:
                return .unavailable
            default:
                return .degraded
            }
            
        } catch {
            AppLogger.general.debug("[ConnectionHealth] Check failed: \(error)")
            return .unavailable
        }
    }
    
    func ping(baseURL: String) async -> Bool {
        guard let url = URL(string: "\(baseURL)/ping") else {
            return false
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return false
            }
            
            return httpResponse.statusCode == 200
            
        } catch {
            return false
        }
    }
}
