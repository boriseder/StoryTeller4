import Foundation

// MARK: - BookmarkEnrichmentCoordinator
//
// Observes bookmark changes and pre-fetches book metadata so the Bookmarks tab
// can display titles without a loading spinner on every row.
//
// Prefetch strategy change (actor refactor):
//
//   Before: Combine sink on `$bookmarks` (a @Published property) triggered
//           prefetching reactively whenever the repository mutated.
//
//   After:  Pull-based. BookmarkViewModel calls `prefetchIfNeeded()` after
//           every mutation (create, delete, sync, initial load). This is
//           equivalent in practice — mutations always go through the ViewModel —
//           and removes the Combine dependency entirely.
//
//   The coordinator never subscribes to anything. It only reads snapshots
//   via the protocol's synchronous `getAllBookmarks()` getter.

@MainActor
@Observable
final class BookmarkEnrichmentCoordinator {

    // MARK: - State

    private(set) var bookCache: [String: Book] = [:]

    // MARK: - Dependencies

    private let bookmarkRepository: any BookmarkRepositoryProtocol
    private let bookRepository: BookRepository
    private let downloadManager: DownloadManager

    // MARK: - Init

    init(
        bookmarkRepository: any BookmarkRepositoryProtocol,
        bookRepository: BookRepository,
        downloadManager: DownloadManager
    ) {
        self.bookmarkRepository = bookmarkRepository
        self.bookRepository = bookRepository
        self.downloadManager = downloadManager
    }

    // MARK: - Public Query API

    func enrichedBookmarks(for libraryItemId: String) -> [EnrichedBookmark] {
        let bookmarks = bookmarkRepository.getBookmarks(for: libraryItemId)
        let book = bookCache[libraryItemId]
        return bookmarks.map { EnrichedBookmark(bookmark: $0, book: book) }
    }

    func allEnrichedBookmarks(sortedBy sort: BookmarkSortOption = .dateNewest) -> [EnrichedBookmark] {
        var enriched: [EnrichedBookmark] = []
        for (id, bookmarks) in bookmarkRepository.getAllBookmarks() {
            let book = bookCache[id]
            for bookmark in bookmarks {
                enriched.append(EnrichedBookmark(bookmark: bookmark, book: book))
            }
        }
        return sort.sort(enriched)
    }

    func groupedEnrichedBookmarks() -> [BookmarkGroup] {
        bookmarkRepository.getAllBookmarks().map { (libraryItemId, bookmarks) in
            let book = bookCache[libraryItemId]
            let enriched = bookmarks.map { EnrichedBookmark(bookmark: $0, book: book) }
            return BookmarkGroup(id: libraryItemId, book: book, bookmarks: enriched)
        }
        .sorted { ($0.book?.title ?? "") < ($1.book?.title ?? "") }
    }

    // MARK: - Prefetch (called by BookmarkViewModel after every mutation)

    /// Prefetches book metadata for any libraryItemId not yet in the cache.
    /// Safe to call frequently — exits immediately for already-cached entries.
    func prefetchIfNeeded() async {
        let allBookmarks = bookmarkRepository.getAllBookmarks()
        await prefetchMissingBooks(for: allBookmarks)
    }

    /// Prefetch a single known bookId — used when jumping to a bookmark
    /// from a context where only the bookId is available.
    func prefetchBook(_ bookId: String) async {
        guard bookCache[bookId] == nil else { return }

        if let book = downloadManager.downloadedBooks.first(where: { $0.id == bookId }) {
            bookCache[bookId] = book
            return
        }

        do {
            let book = try await bookRepository.fetchBookDetails(bookId: bookId)
            bookCache[bookId] = book
        } catch {
            AppLogger.general.debug("[BookmarkEnrichment] Failed to prefetch \(bookId): \(error)")
        }
    }

    // MARK: - Private

    private func prefetchMissingBooks(for bookmarksMap: [String: [Bookmark]]) async {
        for libraryItemId in bookmarksMap.keys where bookCache[libraryItemId] == nil {
            await prefetchBook(libraryItemId)
        }
    }
}
