import Foundation

struct ServerConfigState {
    var scheme: String = "http"
    var host: String = ""
    var port: String = ""
    var username: String = ""
    var password: String = ""
    
    var fullServerURL: String {
        let portString = port.isEmpty ? "" : ":\(port)"
        return "\(scheme)://\(host)\(portString)"
    }
    
    var isServerConfigured: Bool {
        !host.isEmpty
    }
    
    var canLogin: Bool {
        isServerConfigured && !username.isEmpty && !password.isEmpty
    }
        
    func saveToDefaults() {
        UserDefaults.standard.set(scheme, forKey: "server_scheme")
        UserDefaults.standard.set(host, forKey: "server_host")
        UserDefaults.standard.set(port, forKey: "server_port")
        UserDefaults.standard.set(username, forKey: "stored_username")
    }
    
    func clearFromDefaults() {
        UserDefaults.standard.removeObject(forKey: "server_scheme")
        UserDefaults.standard.removeObject(forKey: "server_host")
        UserDefaults.standard.removeObject(forKey: "server_port")
        UserDefaults.standard.removeObject(forKey: "stored_username")
        UserDefaults.standard.removeObject(forKey: "baseURL")
        UserDefaults.standard.removeObject(forKey: "apiKey")
        UserDefaults.standard.removeObject(forKey: "selected_library_id")
    }
}
