//
//  BookmarkEnrichmentCoordinator.swift
//  StoryTeller4
//
//  Created by Boris Eder on 02.05.26.
//

import Foundation
import Combine

// MARK: - BookmarkEnrichmentCoordinator
//
// Moved out of DependencyContainer where it was tangled with unrelated concerns.
// Observes bookmark changes and pre-fetches book metadata so the Bookmarks tab
// can display titles without a loading spinner on every row.

@MainActor
@Observable
final class BookmarkEnrichmentCoordinator {

    private(set) var bookCache: [String: Book] = [:]

    private let bookmarkRepository: BookmarkRepository
    private let bookRepository: BookRepository
    private let downloadManager: DownloadManager

    @ObservationIgnored private var cancellables = Set<AnyCancellable>()

    init(
        bookmarkRepository: BookmarkRepository,
        bookRepository: BookRepository,
        downloadManager: DownloadManager
    ) {
        self.bookmarkRepository = bookmarkRepository
        self.bookRepository = bookRepository
        self.downloadManager = downloadManager

        bookmarkRepository.$bookmarks
            .sink { [weak self] bookmarksMap in
                Task { [weak self] in
                    await self?.prefetchMissingBooks(for: bookmarksMap)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Public Query API

    func enrichedBookmarks(for libraryItemId: String) -> [EnrichedBookmark] {
        let bookmarks = bookmarkRepository.getBookmarks(for: libraryItemId)
        let book = bookCache[libraryItemId]
        return bookmarks.map { EnrichedBookmark(bookmark: $0, book: book) }
    }

    func allEnrichedBookmarks(sortedBy sort: BookmarkSortOption = .dateNewest) -> [EnrichedBookmark] {
        var enriched: [EnrichedBookmark] = []
        for (id, bookmarks) in bookmarkRepository.bookmarks {
            let book = bookCache[id]
            for bookmark in bookmarks {
                enriched.append(EnrichedBookmark(bookmark: bookmark, book: book))
            }
        }
        return sort.sort(enriched)
    }

    func groupedEnrichedBookmarks() -> [BookmarkGroup] {
        var groups: [String: BookmarkGroup] = [:]
        for (libraryItemId, bookmarks) in bookmarkRepository.bookmarks {
            let book = bookCache[libraryItemId]
            let enriched = bookmarks.map { EnrichedBookmark(bookmark: $0, book: book) }
            groups[libraryItemId] = BookmarkGroup(id: libraryItemId, book: book, bookmarks: enriched)
        }
        return groups.values.sorted { ($0.book?.title ?? "") < ($1.book?.title ?? "") }
    }

    // MARK: - Pre-fetch

    func prefetchBook(_ bookId: String) async {
        guard bookCache[bookId] == nil else { return }

        // Downloads first — no network needed
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
