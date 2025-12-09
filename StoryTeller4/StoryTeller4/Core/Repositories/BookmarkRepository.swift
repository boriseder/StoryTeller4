import Foundation
import Combine

// MARK: - Bookmark Repository
@MainActor
class BookmarkRepository: ObservableObject {
    static let shared = BookmarkRepository()
    
    @Published var bookmarks: [String: [Bookmark]] = [:] // Key: libraryItemId
    @Published var isLoading: Bool = false
    
    private var api: AudiobookshelfClient?
    private let userDefaults = UserDefaults.standard
    private let cacheKey = "cached_bookmarks"
    
    private init() {
        loadCachedBookmarks()
    }
    
    func configure(api: AudiobookshelfClient) {
        self.api = api
        AppLogger.general.debug("[BookmarkRepo] Configured with API client")
    }
    
    // MARK: - Sync with Server
    
    /// Initial sync from server (called at app start)
    func syncFromServer() async {
        guard let api = api else { return }
        
        isLoading = true
        
        do {
            let userData = try await api.bookmarks.fetchUserData()
            
            // Group bookmarks by libraryItemId
            var grouped: [String: [Bookmark]] = [:]
            for bookmark in userData.bookmarks {
                grouped[bookmark.libraryItemId, default: []].append(bookmark)
            }
            
            // Sort each group by time
            for (key, value) in grouped {
                grouped[key] = value.sorted { $0.time < $1.time }
            }
            
            self.bookmarks = grouped
            saveCachedBookmarks()
            
            AppLogger.general.debug("[BookmarkRepo] ✅ Synced \(userData.bookmarks.count) bookmarks")
        } catch {
            AppLogger.general.debug("[BookmarkRepo] ❌ Sync failed: \(error)")
        }
        
        isLoading = false
    }
    
    // MARK: - CRUD Operations
    
    /// Get all bookmarks for a specific book
    func getBookmarks(for libraryItemId: String) -> [Bookmark] {
        bookmarks[libraryItemId] ?? []
    }
    
    /// Create a new bookmark
    func createBookmark(libraryItemId: String, time: Double, title: String) async throws {
        guard let api = api else {
            throw AudiobookshelfError.invalidResponse
        }
        
        let newBookmark = try await api.bookmarks.createBookmark(
            libraryItemId: libraryItemId,
            time: time,
            title: title
        )
        
        // Update local cache
        var existing = bookmarks[libraryItemId] ?? []
        existing.append(newBookmark)
        existing.sort { $0.time < $1.time }
        bookmarks[libraryItemId] = existing
        
        saveCachedBookmarks()
        
        AppLogger.general.debug("[BookmarkRepo] ✅ Created bookmark: '\(title)'")
    }
    
    /// Update a bookmark's title
    func updateBookmark(libraryItemId: String, time: Double, newTitle: String) async throws {
        guard let api = api else {
            throw AudiobookshelfError.invalidResponse
        }
        
        let updatedBookmark = try await api.bookmarks.updateBookmark(
            libraryItemId: libraryItemId,
            time: time,
            title: newTitle
        )
        
        // Update local cache
        if var existing = bookmarks[libraryItemId],
           let index = existing.firstIndex(where: { $0.time == time }) {
            existing[index] = updatedBookmark
            bookmarks[libraryItemId] = existing
            saveCachedBookmarks()
        }
        
        AppLogger.general.debug("[BookmarkRepo] ✅ Updated bookmark to '\(newTitle)'")
    }
    
    /// Delete a bookmark
    func deleteBookmark(libraryItemId: String, time: Double) async throws {
        guard let api = api else {
            throw AudiobookshelfError.invalidResponse
        }
        
        try await api.bookmarks.deleteBookmark(
            libraryItemId: libraryItemId,
            time: time
        )
        
        // Update local cache
        if var existing = bookmarks[libraryItemId] {
            existing.removeAll { $0.time == time }
            bookmarks[libraryItemId] = existing
            saveCachedBookmarks()
        }
        
        AppLogger.general.debug("[BookmarkRepo] ✅ Deleted bookmark at \(time)s")
    }
    
    // MARK: - Local Cache
    
    private func saveCachedBookmarks() {
        do {
            let allBookmarks = bookmarks.values.flatMap { $0 }
            let data = try JSONEncoder().encode(allBookmarks)
            userDefaults.set(data, forKey: cacheKey)
        } catch {
            AppLogger.general.debug("[BookmarkRepo] ❌ Failed to cache: \(error)")
        }
    }
    
    private func loadCachedBookmarks() {
        guard let data = userDefaults.data(forKey: cacheKey) else { return }
        
        do {
            let allBookmarks = try JSONDecoder().decode([Bookmark].self, from: data)
            
            var grouped: [String: [Bookmark]] = [:]
            for bookmark in allBookmarks {
                grouped[bookmark.libraryItemId, default: []].append(bookmark)
            }
            
            for (key, value) in grouped {
                grouped[key] = value.sorted { $0.time < $1.time }
            }
            
            self.bookmarks = grouped
            
            AppLogger.general.debug("[BookmarkRepo] 📦 Loaded \(allBookmarks.count) cached bookmarks")
        } catch {
            AppLogger.general.debug("[BookmarkRepo] ❌ Failed to load cache: \(error)")
        }
    }
    
    func clearCache() {
        bookmarks.removeAll()
        userDefaults.removeObject(forKey: cacheKey)
        AppLogger.general.debug("[BookmarkRepo] 🗑️ Cache cleared")
    }
    
    // MARK: - Statistics & Helpers
    
    /// Gesamtanzahl aller Bookmarks
    var totalBookmarkCount: Int {
        bookmarks.values.reduce(0) { $0 + $1.count }
    }
    
    /// Anzahl Bücher mit Bookmarks
    var booksWithBookmarks: Int {
        bookmarks.count
    }
    
    /// Alle Bookmarks als flache Liste (sortiert nach Datum)
    func getAllBookmarks(sortedBy sort: BookmarkSortOption = .dateNewest) -> [Bookmark] {
        let all = bookmarks.values.flatMap { $0 }
        
        switch sort {
        case .dateNewest:
            return all.sorted { $0.createdAt > $1.createdAt }
        case .dateOldest:
            return all.sorted { $0.createdAt < $1.createdAt }
        case .timeInBook:
            return all.sorted { $0.time < $1.time }
        case .bookTitle:
            return all.sorted { $0.libraryItemId < $1.libraryItemId }
        }
    }
    
    /// Neueste Bookmarks (limit: Anzahl)
    func getRecentBookmarks(limit: Int = 10) -> [Bookmark] {
        Array(getAllBookmarks(sortedBy: .dateNewest).prefix(limit))
    }
}
