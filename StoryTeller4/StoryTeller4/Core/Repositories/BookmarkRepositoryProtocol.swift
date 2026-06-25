//
//  BookmarkRepositoryProtocol.swift
//  StoryTeller4
//
//  Created by Boris Eder on 24.06.26.
//


import Foundation

// MARK: - BookmarkRepositoryProtocol
//
// Pure domain interface for bookmark persistence and server sync.
// No ObservableObject, no @Published, no @MainActor.
//
// All mutations are async and throw on API failure. The caller (ViewModel)
// decides how to present errors — the repository never touches the UI layer.

protocol BookmarkRepositoryProtocol: AnyObject, Sendable {

    // MARK: - Configuration

    func configure(api: AudiobookshelfClient)

    // MARK: - Read

    /// All bookmarks for a specific library item, sorted by time ascending.
    func getBookmarks(for libraryItemId: String) -> [Bookmark]

    /// The full bookmark dictionary keyed by libraryItemId.
    /// ViewModels snapshot this; they don't observe it reactively.
    func getAllBookmarks() -> [String: [Bookmark]]

    // MARK: - Server Sync

    /// Fetches all bookmarks from the server and replaces local cache.
    func syncFromServer() async throws

    // MARK: - CRUD (server-authoritative; cache updated on success)

    func createBookmark(libraryItemId: String, time: Double, title: String) async throws -> Bookmark
    func updateBookmark(libraryItemId: String, time: Double, newTitle: String) async throws -> Bookmark
    func deleteBookmark(libraryItemId: String, time: Double) async throws

    // MARK: - Cache

    func clearCache() async
}
