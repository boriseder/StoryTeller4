import Foundation
import SwiftUI
import Observation
import Combine

@MainActor
@Observable
class BookmarkViewModel {
    // MARK: - State
    var searchText = ""
    var sortOption: BookmarkSortOption = .dateNewest
    var groupByBook = true
    
    // Local storage of enriched bookmarks to drive UI updates
    var allBookmarks: [EnrichedBookmark] = []
    
    // Edit State
    var editingBookmark: EnrichedBookmark?
    var editedBookmarkTitle: String = ""
    
    // MARK: - Dependencies
    private let dependencies: DependencyContainer
    private let repository: BookmarkRepository
    private var player: AudioPlayer { dependencies.player }
    
    // Keep Combine for bridging legacy repository
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Computed Properties
    
    var filteredBookmarks: [EnrichedBookmark] {
        allBookmarks.filter { searchFilter($0) }
    }
    
    var groupedBookmarks: [(book: Book?, bookmarks: [EnrichedBookmark])] {
        // Group the already enriched and sorted bookmarks
        let grouped = Dictionary(grouping: filteredBookmarks) { $0.bookmark.libraryItemId }
        
        return grouped.map { (itemId, bookmarks) in
            let book = dependencies.getGroupedEnrichedBookmarks().first(where: { $0.book?.id == itemId })?.book
            return (book, bookmarks)
        }
        .sorted {
            guard let b1 = $0.book, let b2 = $1.book else { return false }
            return b1.title < b2.title
        }
    }
    
    // MARK: - Init
    init(dependencies: DependencyContainer = .shared) {
        self.dependencies = dependencies
        self.repository = dependencies.bookmarkRepository
        setupObservers()
        refreshData()
    }
    
    // MARK: - Setup
    private func setupObservers() {
        // Bridge Combine updates to @Observable properties
        
        NotificationCenter.default.publisher(for: .init("BookmarkEnrichmentUpdated"))
            .sink { [weak self] _ in
                Task { @MainActor in self?.refreshData() }
            }
            .store(in: &cancellables)
        
        repository.$bookmarks
            .sink { [weak self] _ in
                Task { @MainActor in self?.refreshData() }
            }
            .store(in: &cancellables)
    }
    
    // Update local state from dependencies
    private func refreshData() {
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
            AppLogger.general.debug("[BookmarkVM] Cannot jump - book not loaded yet")
            return
        }
        
        Task {
            if player.book?.id != book.id {
                AppLogger.general.debug("[BookmarkVM] Loading book: \(book.title)")
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
            } catch {
                AppLogger.general.debug("[BookmarkVM] Delete failed: \(error)")
            }
        }
    }
    
    func createBookmark(libraryItemId: String, time: Double, title: String) async throws {
        try await repository.createBookmark(
            libraryItemId: libraryItemId,
            time: time,
            title: title
        )
    }
    
    func updateBookmark(libraryItemId: String, time: Double, newTitle: String) async throws {
        try await repository.updateBookmark(
            libraryItemId: libraryItemId,
            time: time,
            newTitle: newTitle
        )
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
                AppLogger.general.debug("[BookmarkVM] Failed to update bookmark: \(error)")
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
