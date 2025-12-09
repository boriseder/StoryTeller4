import Foundation

struct APIConfig {
    let baseURL: String
    let authToken: String
    
    init(baseURL: String, authToken: String) {
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.authToken = authToken
    }
}
