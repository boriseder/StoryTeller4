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
    
    func syncFromServer() async {
        guard let api = api else { return }
        
        isLoading = true
        
        do {
            let userData = try await api.bookmarks.fetchUserData()
            
            var grouped: [String: [Bookmark]] = [:]
            for bookmark in userData.bookmarks {
                grouped[bookmark.libraryItemId, default: []].append(bookmark)
            }
            
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
    
    func getBookmarks(for libraryItemId: String) -> [Bookmark] {
        bookmarks[libraryItemId] ?? []
    }
    
    func createBookmark(libraryItemId: String, time: Double, title: String) async throws {
        guard let api = api else {
            throw AudiobookshelfError.invalidResponse
        }
        
        let newBookmark = try await api.bookmarks.createBookmark(
            libraryItemId: libraryItemId,
            time: time,
            title: title
        )
        
        // Update local cache immediately
        var existing = bookmarks[libraryItemId] ?? []
        existing.append(newBookmark)
        existing.sort { $0.time < $1.time }
        bookmarks[libraryItemId] = existing
        
        saveCachedBookmarks()
    }
    
    func updateBookmark(libraryItemId: String, time: Double, newTitle: String) async throws {
        guard let api = api else { throw AudiobookshelfError.invalidResponse }
        
        let updatedBookmark = try await api.bookmarks.updateBookmark(
            libraryItemId: libraryItemId,
            time: time,
            title: newTitle
        )
        
        if var existing = bookmarks[libraryItemId],
           let index = existing.firstIndex(where: { $0.time == time }) {
            existing[index] = updatedBookmark
            bookmarks[libraryItemId] = existing
            saveCachedBookmarks()
        }
    }
    
    func deleteBookmark(libraryItemId: String, time: Double) async throws {
        guard let api = api else { throw AudiobookshelfError.invalidResponse }
        
        try await api.bookmarks.deleteBookmark(
            libraryItemId: libraryItemId,
            time: time
        )
        
        if var existing = bookmarks[libraryItemId] {
            existing.removeAll { $0.time == time }
            bookmarks[libraryItemId] = existing
            saveCachedBookmarks()
        }
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
        } catch {
            AppLogger.general.debug("[BookmarkRepo] ❌ Failed to load cache: \(error)")
        }
    }
    
    func clearCache() {
        bookmarks.removeAll()
        userDefaults.removeObject(forKey: cacheKey)
    }
}
