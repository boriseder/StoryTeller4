import Foundation

// MARK: - BookmarkRepository
//
// actor: thread-safe, no @MainActor, no ObservableObject, no @Published.
//
// Static key helpers are nonisolated — they are pure string computations
// with no state, so there is no reason to tie them to any actor executor.
// Marking them nonisolated makes them callable from any context (actor
// body, nonisolated methods, init) without an isolation conflict.
//
// Init strategy: same as PlaybackRepository — defer the actor-isolated
// loadCachedBookmarks() call via Task so the actor's executor picks it up.

actor BookmarkRepository: BookmarkRepositoryProtocol {

    // MARK: - Singleton

    static let shared = BookmarkRepository()

    // MARK: - Private State

    private var bookmarks: [String: [Bookmark]] = [:]
    private var api: AudiobookshelfClient?
    private let userDefaults = UserDefaults.standard

    // MARK: - Synchronous snapshot (nonisolated bridge)

    private nonisolated(unsafe) var _syncBookmarksSnapshot: [String: [Bookmark]] = [:]

    // MARK: - Keys (nonisolated — pure string computation, no actor state)

    private nonisolated static let allItemsKey = "all_bookmark_items"

    private nonisolated static func bookmarkKey(for libraryItemId: String) -> String {
        "bookmarks:\(libraryItemId)"
    }

    // MARK: - Init

    private init() {
        Task { await loadCachedBookmarks() }
    }

    // MARK: - Configuration

    nonisolated func configure(api: AudiobookshelfClient) {
        Task { await _configure(api: api) }
        AppLogger.general.debug("[BookmarkRepository] Configured with API client")
    }

    private func _configure(api: AudiobookshelfClient) {
        self.api = api
    }

    // MARK: - Read (synchronous via snapshot)

    nonisolated func getBookmarks(for libraryItemId: String) -> [Bookmark] {
        _syncBookmarksSnapshot[libraryItemId] ?? []
    }

    nonisolated func getAllBookmarks() -> [String: [Bookmark]] {
        _syncBookmarksSnapshot
    }

    // MARK: - Server Sync

    func syncFromServer() async throws {
        guard let api = api else {
            AppLogger.general.debug("[BookmarkRepository] Sync skipped — API not configured")
            return
        }

        do {
            let userData = try await api.bookmarks.fetchUserData()

            var grouped: [String: [Bookmark]] = [:]
            for bookmark in userData.bookmarks {
                grouped[bookmark.libraryItemId, default: []].append(bookmark)
            }
            for key in grouped.keys {
                grouped[key]?.sort { $0.time < $1.time }
            }

            bookmarks = grouped
            _syncBookmarksSnapshot = grouped

            var saveErrors: [String] = []
            for (libraryItemId, bookmarksForBook) in grouped {
                if let error = saveBookmarks(bookmarksForBook, for: libraryItemId) {
                    saveErrors.append("\(libraryItemId): \(error)")
                }
            }

            if saveErrors.isEmpty {
                AppLogger.general.debug("[BookmarkRepository] Synced \(userData.bookmarks.count) bookmarks across \(grouped.count) books")
            } else {
                AppLogger.general.error("[BookmarkRepository] ⚠️ Sync completed with save errors: \(saveErrors.joined(separator: ", "))")
            }
        } catch {
            AppLogger.general.error("[BookmarkRepository] ❌ Sync failed: \(error)")
            throw error
        }
    }

    // MARK: - CRUD

    func createBookmark(libraryItemId: String, time: Double, title: String) async throws -> Bookmark {
        guard let api = api else { throw AudiobookshelfError.invalidResponse }

        let newBookmark = try await api.bookmarks.createBookmark(
            libraryItemId: libraryItemId,
            time: time,
            title: title
        )

        var existing = bookmarks[libraryItemId] ?? []
        existing.append(newBookmark)
        existing.sort { $0.time < $1.time }
        bookmarks[libraryItemId] = existing
        _syncBookmarksSnapshot[libraryItemId] = existing

        if let error = saveBookmarks(existing, for: libraryItemId) {
            AppLogger.general.error("[BookmarkRepository] ⚠️ Created bookmark on server but failed to cache locally: \(error)")
        }

        return newBookmark
    }

    func updateBookmark(libraryItemId: String, time: Double, newTitle: String) async throws -> Bookmark {
        guard let api = api else { throw AudiobookshelfError.invalidResponse }

        let updatedBookmark = try await api.bookmarks.updateBookmark(
            libraryItemId: libraryItemId,
            time: time,
            title: newTitle
        )

        guard var existing = bookmarks[libraryItemId],
              let index = existing.firstIndex(where: { $0.time == time }) else {
            return updatedBookmark
        }

        existing[index] = updatedBookmark
        bookmarks[libraryItemId] = existing
        _syncBookmarksSnapshot[libraryItemId] = existing

        if let error = saveBookmarks(existing, for: libraryItemId) {
            AppLogger.general.error("[BookmarkRepository] ⚠️ Updated bookmark on server but failed to cache locally: \(error)")
        }

        return updatedBookmark
    }

    func deleteBookmark(libraryItemId: String, time: Double) async throws {
        guard let api = api else { throw AudiobookshelfError.invalidResponse }

        try await api.bookmarks.deleteBookmark(
            libraryItemId: libraryItemId,
            time: time
        )

        var existing = bookmarks[libraryItemId] ?? []
        existing.removeAll { $0.time == time }
        bookmarks[libraryItemId] = existing
        _syncBookmarksSnapshot[libraryItemId] = existing

        if let error = saveBookmarks(existing, for: libraryItemId) {
            AppLogger.general.error("[BookmarkRepository] ⚠️ Deleted bookmark on server but failed to update cache: \(error)")
        }
    }

    // MARK: - Cache

    func clearCache() async {
        let allIds = userDefaults.stringArray(forKey: Self.allItemsKey) ?? []
        for id in allIds {
            userDefaults.removeObject(forKey: Self.bookmarkKey(for: id))
        }
        userDefaults.removeObject(forKey: Self.allItemsKey)
        bookmarks.removeAll()
        _syncBookmarksSnapshot.removeAll()
        AppLogger.general.debug("[BookmarkRepository] Cache cleared")
    }

    // MARK: - Private: Persistence

    @discardableResult
    private func saveBookmarks(_ bookmarksForBook: [Bookmark], for libraryItemId: String) -> String? {
        let key = Self.bookmarkKey(for: libraryItemId)

        let data: Data
        do {
            data = try JSONEncoder().encode(bookmarksForBook)
        } catch {
            return "Encoding failed: \(error.localizedDescription)"
        }

        let maxBytes = 512 * 1024
        guard data.count <= maxBytes else {
            return "Encoded size \(data.count) bytes exceeds \(maxBytes) byte limit"
        }

        userDefaults.set(data, forKey: key)

        var allIds = userDefaults.stringArray(forKey: Self.allItemsKey) ?? []
        if !allIds.contains(libraryItemId) {
            allIds.append(libraryItemId)
            userDefaults.set(allIds, forKey: Self.allItemsKey)
        }

        return nil
    }

    private func loadCachedBookmarks() {
        let allIds = userDefaults.stringArray(forKey: Self.allItemsKey) ?? []

        var loaded: [String: [Bookmark]] = [:]
        var corruptedIds: [String] = []

        for libraryItemId in allIds {
            let key = Self.bookmarkKey(for: libraryItemId)

            guard let data = userDefaults.data(forKey: key) else {
                corruptedIds.append(libraryItemId)
                continue
            }

            do {
                let decoded = try JSONDecoder().decode([Bookmark].self, from: data)
                loaded[libraryItemId] = decoded.sorted { $0.time < $1.time }
            } catch {
                AppLogger.general.error("[BookmarkRepository] ❌ Failed to decode bookmarks for \(libraryItemId): \(error)")
                corruptedIds.append(libraryItemId)
            }
        }

        if !corruptedIds.isEmpty {
            let cleanIds = allIds.filter { !corruptedIds.contains($0) }
            userDefaults.set(cleanIds, forKey: Self.allItemsKey)
            AppLogger.general.error("[BookmarkRepository] ⚠️ Pruned \(corruptedIds.count) corrupted bookmark entries")
        }

        bookmarks = loaded
        _syncBookmarksSnapshot = loaded

        let total = loaded.values.reduce(0) { $0 + $1.count }
        AppLogger.general.debug("[BookmarkRepository] Loaded \(total) bookmarks across \(loaded.count) books from cache")
    }
}
