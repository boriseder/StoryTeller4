import Foundation
import SwiftUI
import Observation

// MARK: - Bookmark View Model
//
// FIX: Removed the Combine `@ObservationIgnored private var cancellables` and the
// `.sink { }` bridges that were needed to bridge `BookmarkRepository`'s `@Published`
// properties into this `@Observable` class.
//
// Now that `BookmarkRepository` is `@Observable`, SwiftUI automatically propagates
// changes through the observation graph — no manual bridging required.

@MainActor
@Observable
class BookmarkViewModel {

    // MARK: - State
    var searchText = ""
    var sortOption: BookmarkSortOption = .dateNewest
    var groupByBook = true
    var allBookmarks: [EnrichedBookmark] = []

    // Edit State
    var editingBookmark: EnrichedBookmark?
    var editedBookmarkTitle: String = ""

    // MARK: - Dependencies
    private let dependencies: DependencyContainer
    private let repository: BookmarkRepository
    private var player: AudioPlayer { dependencies.player }

    // MARK: - Computed Properties

    var filteredBookmarks: [EnrichedBookmark] {
        allBookmarks.filter { searchFilter($0) }
    }

    var groupedBookmarks: [BookmarkGroup] {
        let grouped = Dictionary(grouping: filteredBookmarks) { $0.bookmark.libraryItemId }

        let groups = grouped.map { (itemId, bookmarks) -> BookmarkGroup in
            let book = bookmarks.first?.book
            return BookmarkGroup(id: itemId, book: book, bookmarks: bookmarks)
        }

        return groups.sorted { group1, group2 in
            guard let b1 = group1.book, let b2 = group2.book else {
                return group1.id < group2.id
            }
            return b1.title.localizedCompare(b2.title) == .orderedAscending
        }
    }

    // MARK: - Init
    init(dependencies: DependencyContainer = .shared) {
        self.dependencies = dependencies
        self.repository = dependencies.bookmarkRepository
        refreshData()
    }

    // MARK: - Data Refresh
    //
    // FIX: `refreshData()` is called from `.task {}` in the View and from explicit
    // action methods. Because `BookmarkRepository` is `@Observable`, the View's
    // body will re-evaluate automatically when `repository.bookmarks` changes —
    // making the Combine sink that previously called `refreshData()` unnecessary.
    //
    // For the `allBookmarks` array (enriched, sorted), we still need an explicit
    // refresh because it involves a transformation (enrichment + sort) that
    // can't be expressed as a simple computed property on the observable graph.
    // We call it from places where the underlying data changes.
    func refreshData() {
        allBookmarks = dependencies.getAllEnrichedBookmarks(sortedBy: sortOption)
    }

    // MARK: - Actions
    func refresh() async {
        await repository.syncFromServer()
        refreshData()
    }

    func updateSortOption(_ option: BookmarkSortOption) {
        sortOption = option
        refreshData()
    }

    func toggleGrouping() {
        withAnimation {
            groupByBook.toggle()
        }
    }

    func jumpToBookmark(_ enriched: EnrichedBookmark, dismiss: DismissAction) {
        guard let book = enriched.book else {
            AppLogger.general.debug("[BookmarkVM] Cannot jump - book not loaded yet.")
            return
        }

        Task {
            if player.book?.id != book.id {
                AppLogger.general.debug("[BookmarkVM] Loading book: \(book.title).")
                await player.load(
                    book: book,
                    isOffline: dependencies.downloadRepository.getDownloadStatus(for: book.id).isDownloaded,
                    restoreState: false,
                    autoPlay: false
                )
            }

            await MainActor.run {
                player.jumpToBookmark(enriched.bookmark)
            }

            dismiss()
        }
    }

    func deleteBookmark(_ enriched: EnrichedBookmark) {
        Task {
            do {
                try await repository.deleteBookmark(
                    libraryItemId: enriched.bookmark.libraryItemId,
                    time: enriched.bookmark.time
                )
                refreshData()
            } catch {
                AppLogger.general.error("[BookmarkVM] Delete failed: \(error).")
            }
        }
    }

    func createBookmark(libraryItemId: String, time: Double, title: String) async throws {
        try await repository.createBookmark(
            libraryItemId: libraryItemId,
            time: time,
            title: title
        )
        refreshData()
    }

    func updateBookmark(libraryItemId: String, time: Double, newTitle: String) async throws {
        try await repository.updateBookmark(
            libraryItemId: libraryItemId,
            time: time,
            newTitle: newTitle
        )
        refreshData()
    }

    // MARK: - Edit Actions

    func startEditingBookmark(_ enriched: EnrichedBookmark) {
        editingBookmark = enriched
        editedBookmarkTitle = enriched.bookmark.title
    }

    func saveEditedBookmark() {
        guard let enriched = editingBookmark else { return }

        let newTitle = editedBookmarkTitle.trimmingCharacters(in: .whitespaces)
        guard !newTitle.isEmpty else { return }

        Task {
            do {
                try await updateBookmark(
                    libraryItemId: enriched.bookmark.libraryItemId,
                    time: enriched.bookmark.time,
                    newTitle: newTitle
                )

                await MainActor.run {
                    editingBookmark = nil
                    editedBookmarkTitle = ""
                }
            } catch {
                AppLogger.general.error("[BookmarkVM] Failed to update bookmark: \(error).")
            }
        }
    }

    func cancelEditing() {
        editingBookmark = nil
        editedBookmarkTitle = ""
    }

    // MARK: - Helper
    private func searchFilter(_ enriched: EnrichedBookmark) -> Bool {
        if searchText.isEmpty { return true }

        let query = searchText.lowercased()
        if enriched.bookmark.title.lowercased().contains(query) { return true }
        if let book = enriched.book, book.title.lowercased().contains(query) { return true }

        return false
    }
}
