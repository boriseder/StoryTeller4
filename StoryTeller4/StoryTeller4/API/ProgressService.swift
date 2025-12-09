import Foundation

protocol ProgressServiceProtocol {
    func updatePlaybackProgress(libraryItemId: String, currentTime: Double, timeListened: Double, duration: Double, isFinished: Bool) async throws
    func fetchPlaybackProgress(libraryItemId: String) async throws -> MediaProgress?
    func fetchAllMediaProgress() async throws -> [MediaProgress]
}

class DefaultProgressService: ProgressServiceProtocol {
    private let config: APIConfig
    private let networkService: NetworkService
    
    init(config: APIConfig, networkService: NetworkService) {
        self.config = config
        self.networkService = networkService
    }
    
    func updatePlaybackProgress(
        libraryItemId: String,
        currentTime: Double,
        timeListened: Double,
        duration: Double,
        isFinished: Bool
    ) async throws {
        guard let url = URL(string: "\(config.baseURL)/api/me/progress/\(libraryItemId)") else {
            throw AudiobookshelfError.invalidURL("\(config.baseURL)/api/me/progress/\(libraryItemId)")
        }
        
        let body: [String: Any] = [
            "currentTime": currentTime,
            "timeListened": timeListened,
            "duration": duration,
            "isFinished": isFinished
        ]
        
        var request = networkService.createAuthenticatedRequest(url: url, authToken: config.authToken)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw AudiobookshelfError.invalidRequest(error.localizedDescription)
        }
        
        AppLogger.general.debug("[ProgressService] Updating progress: \(libraryItemId), time: \(currentTime)s, finished: \(isFinished)")
        
        // Server antwortet mit aktualisiertem MediaProgress
        let _: MediaProgress? = try? await networkService.performRequest(request, responseType: MediaProgress.self)
    }
    
    func fetchPlaybackProgress(libraryItemId: String) async throws -> MediaProgress? {
        guard let url = URL(string: "\(config.baseURL)/api/me/progress/\(libraryItemId)") else {
            throw AudiobookshelfError.invalidURL("\(config.baseURL)/api/me/progress/\(libraryItemId)")
        }
        
        let request = networkService.createAuthenticatedRequest(url: url, authToken: config.authToken)
        
        AppLogger.general.debug("[ProgressService] Fetching progress for item: \(libraryItemId)")
        
        do {
            let progress: MediaProgress = try await networkService.performRequest(request, responseType: MediaProgress.self)
            return progress
        } catch AudiobookshelfError.resourceNotFound {
            AppLogger.general.debug("[ProgressService] No progress found for item: \(libraryItemId)")
            return nil
        }
    }
    
    func fetchAllMediaProgress() async throws -> [MediaProgress] {
        guard let url = URL(string: "\(config.baseURL)/api/me") else {
            throw AudiobookshelfError.invalidURL("\(config.baseURL)/api/me")
        }
        
        let request = networkService.createAuthenticatedRequest(url: url, authToken: config.authToken)
        
        AppLogger.general.debug("[ProgressService] Fetching all media progress from /api/me")
        
        struct UserMeResponse: Codable {
            let mediaProgress: [MediaProgress]
        }
        
        let response: UserMeResponse = try await networkService.performRequest(request, responseType: UserMeResponse.self)
        return response.mediaProgress
    }
}
