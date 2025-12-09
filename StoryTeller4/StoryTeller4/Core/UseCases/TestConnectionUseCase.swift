import Foundation

protocol TestConnectionUseCaseProtocol {
    func execute(baseURL: String) async -> Bool
}

class TestConnectionUseCase: TestConnectionUseCaseProtocol {
    private let connectionHealthChecker: ConnectionHealthChecking
    
    init(connectionHealthChecker: ConnectionHealthChecking) {
        self.connectionHealthChecker = connectionHealthChecker
    }
    
    func execute(baseURL: String) async -> Bool {
        return await connectionHealthChecker.ping(baseURL: baseURL)
    }
}
