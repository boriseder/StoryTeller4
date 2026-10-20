import Foundation

// MARK: - BookmarkServiceProtocol
//
// Sendable required so implementations can be stored inside actors and called
// across isolation boundaries without Swift 6 concurrency warnings.

protocol BookmarkServiceProtocol: Sendable {
    func fetchUserData() async throws -> UserData
    func createBookmark(libraryItemId: String, time: Double, title: String) async throws -> Bookmark
    func updateBookmark(libraryItemId: String, time: Double, title: String) async throws -> Bookmark
    func deleteBookmark(libraryItemId: String, time: Double) async throws
}

// MARK: - Implementation
//
// @unchecked Sendable: all stored properties are immutable after init.

final class DefaultBookmarkService: BookmarkServiceProtocol, @unchecked Sendable {
    private let config: APIConfig
    private let networkService: NetworkService

    init(config: APIConfig, networkService: NetworkService) {
        self.config = config
        self.networkService = networkService
    }

    func fetchUserData() async throws -> UserData {
        guard let url = URL(string: "\(config.baseURL)/api/me") else {
            throw AudiobookshelfError.invalidURL("\(config.baseURL)/api/me")
        }

        let request = networkService.createAuthenticatedRequest(url: url, authToken: config.authToken)

        AppLogger.general.debug("[BookmarkService] Fetching user data from /api/me")

        let userData: UserData = try await networkService.performRequest(request, responseType: UserData.self)

        AppLogger.general.debug("[BookmarkService] Loaded \(userData.bookmarks.count) bookmarks, \(userData.mediaProgress.count) progress items")

        return userData
    }

    func createBookmark(libraryItemId: String, time: Double, title: String) async throws -> Bookmark {
        guard let url = URL(string: "\(config.baseURL)/api/me/item/\(libraryItemId)/bookmark") else {
            throw AudiobookshelfError.invalidURL("\(config.baseURL)/api/me/item/\(libraryItemId)/bookmark")
        }

        let body: [String: Any] = ["time": time, "title": title]

        var request = networkService.createAuthenticatedRequest(url: url, authToken: config.authToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw AudiobookshelfError.invalidRequest(error.localizedDescription)
        }

        AppLogger.general.debug("[BookmarkService] Creating bookmark: '\(title)' at \(time)s")

        let bookmark = try await networkService.performRequest(request, responseType: Bookmark.self)

        AppLogger.general.debug("[BookmarkService] Bookmark created")

        return bookmark
    }

    func updateBookmark(libraryItemId: String, time: Double, title: String) async throws -> Bookmark {
        guard let url = URL(string: "\(config.baseURL)/api/me/item/\(libraryItemId)/bookmark") else {
            throw AudiobookshelfError.invalidURL("\(config.baseURL)/api/me/item/\(libraryItemId)/bookmark")
        }

        let body: [String: Any] = ["time": time, "title": title]

        var request = networkService.createAuthenticatedRequest(url: url, authToken: config.authToken)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw AudiobookshelfError.invalidRequest(error.localizedDescription)
        }

        AppLogger.general.debug("[BookmarkService] Updating bookmark at \(time)s to '\(title)'")

        let bookmark = try await networkService.performRequest(request, responseType: Bookmark.self)

        AppLogger.general.debug("[BookmarkService] Bookmark updated")

        return bookmark
    }

    func deleteBookmark(libraryItemId: String, time: Double) async throws {
        guard let url = URL(string: "\(config.baseURL)/api/me/item/\(libraryItemId)/bookmark/\(Int(time))") else {
            throw AudiobookshelfError.invalidURL("\(config.baseURL)/api/me/item/\(libraryItemId)/bookmark/\(Int(time))")
        }

        var request = networkService.createAuthenticatedRequest(url: url, authToken: config.authToken)
        request.httpMethod = "DELETE"

        AppLogger.general.debug("[BookmarkService] Deleting bookmark at \(time)s")

        let _: EmptyResponse? = try? await networkService.performRequest(request, responseType: EmptyResponse.self)

        AppLogger.general.debug("[BookmarkService] Bookmark deleted")
    }
}

// MARK: - Helper

struct EmptyResponse: Codable {}
