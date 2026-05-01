import Foundation
import Combine

// MARK: - BookmarkRepository
//
// Storage strategy: one UserDefaults key per libraryItemId, matching the pattern
// used by PlaybackRepository. This avoids the single-blob problem where one
// large write silently fails and wipes all bookmarks for every book.
//
// Key scheme:
//   "bookmarks:<libraryItemId>"        → [Bookmark] for that book (JSON)
//   "all_bookmark_items"               → [String] of known libraryItemIds
//
// Size guard: individual bookmark arrays are capped at 512KB. This is generous
// (a bookmark is ~200 bytes, so this allows ~2500 bookmarks per book) while
// staying well inside UserDefaults' practical per-app limit.

@MainActor
class BookmarkRepository: ObservableObject {
    static let shared = BookmarkRepository()

    @Published var bookmarks: [String: [Bookmark]] = [:]
    @Published var isLoading: Bool = false

    private var api: AudiobookshelfClient?
    private let userDefaults = UserDefaults.standard

    // MARK: - Keys

    private static let allItemsKey = "all_bookmark_items"

    private static func bookmarkKey(for libraryItemId: String) -> String {
        "bookmarks:\(libraryItemId)"
    }

    // MARK: - Init

    private init() {
        loadCachedBookmarks()
    }

    // MARK: - Configuration

    func configure(api: AudiobookshelfClient) {
        self.api = api
        AppLogger.general.debug("[BookmarkRepo] Configured with API client")
    }

    // MARK: - Sync with Server

    func syncFromServer() async {
        guard let api = api else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let userData = try await api.bookmarks.fetchUserData()

            // Group and sort incoming bookmarks
            var grouped: [String: [Bookmark]] = [:]
            for bookmark in userData.bookmarks {
                grouped[bookmark.libraryItemId, default: []].append(bookmark)
            }
            for key in grouped.keys {
                grouped[key]?.sort { $0.time < $1.time }
            }

            self.bookmarks = grouped

            // Persist each book's bookmarks individually
            var saveErrors: [String] = []
            for (libraryItemId, bookmarksForBook) in grouped {
                if let error = saveBookmarks(bookmarksForBook, for: libraryItemId) {
                    saveErrors.append("\(libraryItemId): \(error)")
                }
            }

            if saveErrors.isEmpty {
                AppLogger.general.debug("[BookmarkRepo] ✅ Synced \(userData.bookmarks.count) bookmarks across \(grouped.count) books")
            } else {
                AppLogger.general.error("[BookmarkRepo] ⚠️ Sync completed with save errors: \(saveErrors.joined(separator: ", "))")
            }
        } catch {
            AppLogger.general.error("[BookmarkRepo] ❌ Sync failed: \(error)")
        }
    }

    // MARK: - Read

    func getBookmarks(for libraryItemId: String) -> [Bookmark] {
        bookmarks[libraryItemId] ?? []
    }

    // MARK: - Create

    func createBookmark(libraryItemId: String, time: Double, title: String) async throws {
        guard let api = api else {
            throw AudiobookshelfError.invalidResponse
        }

        let newBookmark = try await api.bookmarks.createBookmark(
            libraryItemId: libraryItemId,
            time: time,
            title: title
        )

        var existing = bookmarks[libraryItemId] ?? []
        existing.append(newBookmark)
        existing.sort { $0.time < $1.time }
        bookmarks[libraryItemId] = existing

        if let error = saveBookmarks(existing, for: libraryItemId) {
            // The in-memory state is correct; log but don't throw — the server
            // already has the bookmark so the user isn't losing data.
            AppLogger.general.error("[BookmarkRepo] ⚠️ Created bookmark on server but failed to cache locally: \(error)")
        }
    }

    // MARK: - Update

    func updateBookmark(libraryItemId: String, time: Double, newTitle: String) async throws {
        guard let api = api else { throw AudiobookshelfError.invalidResponse }

        let updatedBookmark = try await api.bookmarks.updateBookmark(
            libraryItemId: libraryItemId,
            time: time,
            title: newTitle
        )

        guard var existing = bookmarks[libraryItemId],
              let index = existing.firstIndex(where: { $0.time == time }) else {
            return
        }

        existing[index] = updatedBookmark
        bookmarks[libraryItemId] = existing

        if let error = saveBookmarks(existing, for: libraryItemId) {
            AppLogger.general.error("[BookmarkRepo] ⚠️ Updated bookmark on server but failed to cache locally: \(error)")
        }
    }

    // MARK: - Delete

    func deleteBookmark(libraryItemId: String, time: Double) async throws {
        guard let api = api else { throw AudiobookshelfError.invalidResponse }

        try await api.bookmarks.deleteBookmark(
            libraryItemId: libraryItemId,
            time: time
        )

        var existing = bookmarks[libraryItemId] ?? []
        existing.removeAll { $0.time == time }
        bookmarks[libraryItemId] = existing

        if let error = saveBookmarks(existing, for: libraryItemId) {
            AppLogger.general.error("[BookmarkRepo] ⚠️ Deleted bookmark on server but failed to update cache: \(error)")
        }
    }

    // MARK: - Cache Management

    func clearCache() {
        // Remove all individual book keys
        let allIds = userDefaults.stringArray(forKey: Self.allItemsKey) ?? []
        for id in allIds {
            userDefaults.removeObject(forKey: Self.bookmarkKey(for: id))
        }
        userDefaults.removeObject(forKey: Self.allItemsKey)
        bookmarks.removeAll()
        AppLogger.general.debug("[BookmarkRepo] Cache cleared")
    }

    // MARK: - Private: Persistence

    /// Saves bookmarks for a single book. Returns an error description on failure, nil on success.
    @discardableResult
    private func saveBookmarks(_ bookmarksForBook: [Bookmark], for libraryItemId: String) -> String? {
        let key = Self.bookmarkKey(for: libraryItemId)

        // Encode first so we can measure size before writing
        let data: Data
        do {
            data = try JSONEncoder().encode(bookmarksForBook)
        } catch {
            return "Encoding failed: \(error.localizedDescription)"
        }

        // 512KB per book is very generous; hitting this indicates something unusual
        let maxBytes = 512 * 1024
        guard data.count <= maxBytes else {
            return "Encoded size \(data.count) bytes exceeds \(maxBytes) byte limit — not writing to avoid data loss"
        }

        userDefaults.set(data, forKey: key)

        // Track the libraryItemId so we can enumerate all keys on load
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
                // Key registered but data missing — clean up the index
                corruptedIds.append(libraryItemId)
                continue
            }

            do {
                let bookmarksForBook = try JSONDecoder().decode([Bookmark].self, from: data)
                loaded[libraryItemId] = bookmarksForBook.sorted { $0.time < $1.time }
            } catch {
                AppLogger.general.error("[BookmarkRepo] ❌ Failed to decode bookmarks for \(libraryItemId): \(error)")
                corruptedIds.append(libraryItemId)
            }
        }

        // Prune any IDs whose data was missing or undecodable
        if !corruptedIds.isEmpty {
            let cleanIds = allIds.filter { !corruptedIds.contains($0) }
            userDefaults.set(cleanIds, forKey: Self.allItemsKey)
            AppLogger.general.error("[BookmarkRepo] ⚠️ Pruned \(corruptedIds.count) corrupted bookmark entries from index")
        }

        self.bookmarks = loaded

        let total = loaded.values.reduce(0) { $0 + $1.count }
        AppLogger.general.debug("[BookmarkRepo] Loaded \(total) bookmarks across \(loaded.count) books from cache")
    }
}
