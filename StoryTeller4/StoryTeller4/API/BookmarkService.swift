//
//  BookmarkServiceProtocol.swift
//  StoryTeller3
//
//  Created by Boris Eder on 24.11.25.
//


import Foundation

// MARK: - Protocol
protocol BookmarkServiceProtocol {
    func fetchUserData() async throws -> UserData
    func createBookmark(libraryItemId: String, time: Double, title: String) async throws -> Bookmark
    func updateBookmark(libraryItemId: String, time: Double, title: String) async throws -> Bookmark
    func deleteBookmark(libraryItemId: String, time: Double) async throws
}

// MARK: - Implementation
class DefaultBookmarkService: BookmarkServiceProtocol {
    private let config: APIConfig
    private let networkService: NetworkService
    
    init(config: APIConfig, networkService: NetworkService) {
        self.config = config
        self.networkService = networkService
    }
    
    /// Fetch complete user data including bookmarks and media progress
    func fetchUserData() async throws -> UserData {
        guard let url = URL(string: "\(config.baseURL)/api/me") else {
            throw AudiobookshelfError.invalidURL("\(config.baseURL)/api/me")
        }
        
        let request = networkService.createAuthenticatedRequest(url: url, authToken: config.authToken)
        
        AppLogger.general.debug("[BookmarkService] Fetching user data from /api/me")
        
        let userData: UserData = try await networkService.performRequest(request, responseType: UserData.self)
        
        AppLogger.general.debug("[BookmarkService] ✅ Loaded \(userData.bookmarks.count) bookmarks, \(userData.mediaProgress.count) progress items")
        
        return userData
    }
    
    /// Create a new bookmark
    func createBookmark(libraryItemId: String, time: Double, title: String) async throws -> Bookmark {
        guard let url = URL(string: "\(config.baseURL)/api/me/item/\(libraryItemId)/bookmark") else {
            throw AudiobookshelfError.invalidURL("\(config.baseURL)/api/me/item/\(libraryItemId)/bookmark")
        }
        
        let body: [String: Any] = [
            "time": time,
            "title": title
        ]
        
        var request = networkService.createAuthenticatedRequest(url: url, authToken: config.authToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw AudiobookshelfError.invalidRequest(error.localizedDescription)
        }
        
        AppLogger.general.debug("[BookmarkService] Creating bookmark: '\(title)' at \(time)s")
        
        struct BookmarkResponse: Codable {
            let bookmark: Bookmark
        }
        
        let response: BookmarkResponse = try await networkService.performRequest(request, responseType: BookmarkResponse.self)
        
        AppLogger.general.debug("[BookmarkService] ✅ Bookmark created")
        
        return response.bookmark
    }
    
    /// Update an existing bookmark's title
    func updateBookmark(libraryItemId: String, time: Double, title: String) async throws -> Bookmark {
        guard let url = URL(string: "\(config.baseURL)/api/me/item/\(libraryItemId)/bookmark") else {
            throw AudiobookshelfError.invalidURL("\(config.baseURL)/api/me/item/\(libraryItemId)/bookmark")
        }
        
        let body: [String: Any] = [
            "time": time,
            "title": title
        ]
        
        var request = networkService.createAuthenticatedRequest(url: url, authToken: config.authToken)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw AudiobookshelfError.invalidRequest(error.localizedDescription)
        }
        
        AppLogger.general.debug("[BookmarkService] Updating bookmark at \(time)s to '\(title)'")
        
        struct BookmarkResponse: Codable {
            let bookmark: Bookmark
        }
        
        let response: BookmarkResponse = try await networkService.performRequest(request, responseType: BookmarkResponse.self)
        
        AppLogger.general.debug("[BookmarkService] ✅ Bookmark updated")
        
        return response.bookmark
    }
    
    /// Delete a bookmark
    func deleteBookmark(libraryItemId: String, time: Double) async throws {
        guard let url = URL(string: "\(config.baseURL)/api/me/item/\(libraryItemId)/bookmark/\(Int(time))") else {
            throw AudiobookshelfError.invalidURL("\(config.baseURL)/api/me/item/\(libraryItemId)/bookmark/\(Int(time))")
        }
        
        var request = networkService.createAuthenticatedRequest(url: url, authToken: config.authToken)
        request.httpMethod = "DELETE"
        
        AppLogger.general.debug("[BookmarkService] Deleting bookmark at \(time)s")
        
        let _: EmptyResponse? = try? await networkService.performRequest(request, responseType: EmptyResponse.self)
        
        AppLogger.general.debug("[BookmarkService] ✅ Bookmark deleted")
    }
}

// MARK: - Helper
struct EmptyResponse: Codable {}