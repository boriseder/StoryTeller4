import Foundation

enum ValidationError: LocalizedError {
    case emptyHost
    case invalidHostFormat
    case invalidPort
    case invalidScheme
    case emptyUsername
    case emptyPassword
    
    var errorDescription: String? {
        switch self {
        case .emptyHost:
            return "Host address cannot be empty"
        case .invalidHostFormat:
            return "Invalid host address format"
        case .invalidPort:
            return "Port must be between 1 and 65535"
        case .invalidScheme:
            return "Scheme must be http or https"
        case .emptyUsername:
            return "Username cannot be empty"
        case .emptyPassword:
            return "Password cannot be empty"
        }
    }
}

struct ServerConfig {
    let scheme: String
    let host: String
    let port: String
    
    var fullURL: String {
        let portString = port.isEmpty ? "" : ":\(port)"
        return "\(scheme)://\(host)\(portString)"
    }
}

struct Credentials {
    let username: String
    let password: String
}

protocol ServerConfigValidating {
    func validateHost(_ host: String) -> Result<String, ValidationError>
    func validatePort(_ port: String) -> Result<String, ValidationError>
    func validateScheme(_ scheme: String) -> Result<String, ValidationError>
    func validateServerConfig(_ config: ServerConfig) -> Result<ServerConfig, ValidationError>
    func validateCredentials(_ credentials: Credentials) -> Result<Credentials, ValidationError>
    func sanitizeHost(_ host: String) -> String
}

class ServerConfigValidator: ServerConfigValidating {
    
    func validateHost(_ host: String) -> Result<String, ValidationError> {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmed.isEmpty else {
            return .failure(.emptyHost)
        }
        
        guard trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            return .failure(.invalidHostFormat)
        }
        
        let hostPattern = "^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$"
        let ipPattern = "^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"
        
        let isValidHost = trimmed.range(of: hostPattern, options: .regularExpression) != nil
        let isValidIP = trimmed.range(of: ipPattern, options: .regularExpression) != nil
        let isLocalhost = trimmed == "localhost"
        
        guard isValidHost || isValidIP || isLocalhost else {
            return .failure(.invalidHostFormat)
        }
        
        return .success(trimmed)
    }
    
    func validatePort(_ port: String) -> Result<String, ValidationError> {
        guard !port.isEmpty else {
            return .success(port)
        }
        
        guard let portNumber = Int(port) else {
            return .failure(.invalidPort)
        }
        
        guard portNumber > 0 && portNumber <= 65535 else {
            return .failure(.invalidPort)
        }
        
        return .success(port)
    }
    
    func validateScheme(_ scheme: String) -> Result<String, ValidationError> {
        guard scheme == "http" || scheme == "https" else {
            return .failure(.invalidScheme)
        }
        
        return .success(scheme)
    }
    
    func validateServerConfig(_ config: ServerConfig) -> Result<ServerConfig, ValidationError> {
        switch validateScheme(config.scheme) {
        case .failure(let error):
            return .failure(error)
        case .success:
            break
        }
        
        switch validateHost(config.host) {
        case .failure(let error):
            return .failure(error)
        case .success:
            break
        }
        
        switch validatePort(config.port) {
        case .failure(let error):
            return .failure(error)
        case .success:
            break
        }
        
        return .success(config)
    }
    
    func validateCredentials(_ credentials: Credentials) -> Result<Credentials, ValidationError> {
        let trimmedUsername = credentials.username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUsername.isEmpty else {
            return .failure(.emptyUsername)
        }
        
        guard !credentials.password.isEmpty else {
            return .failure(.emptyPassword)
        }
        
        return .success(Credentials(
            username: trimmedUsername,
            password: credentials.password
        ))
    }
    
    func sanitizeHost(_ host: String) -> String {
        return host
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "/", with: "")
    }
}
