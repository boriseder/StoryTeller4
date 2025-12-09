import Foundation

protocol PlaybackSessionService {
    func createSession(for chapter: Chapter, baseURL: String, authToken: String) async throws -> PlaybackSessionResponse
}

class DefaultPlaybackSessionService: PlaybackSessionService {
    
    func createSession(for chapter: Chapter, baseURL: String, authToken: String) async throws -> PlaybackSessionResponse {
        guard let libraryItemId = chapter.libraryItemId else {
            throw AudiobookshelfError.missingLibraryItemId
        }
        
        var urlString = "\(baseURL)/api/items/\(libraryItemId)/play"
        if let episodeId = chapter.episodeId {
            urlString += "/\(episodeId)"
        }
        
        guard let url = URL(string: urlString) else {
            throw AudiobookshelfError.invalidURL(urlString)
        }
        
        let requestBody = DeviceUtils.createPlaybackRequest()
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)
        
        AppLogger.general.debug("[PlaybackSessionService] Creating playback session: \(url)")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AudiobookshelfError.invalidResponse
        }
        
        let session = try JSONDecoder().decode(PlaybackSessionResponse.self, from: data)
        AppLogger.general.debug("[PlaybackSessionService] Playback session created: \(session.id)")
        
        return session
    }
}
