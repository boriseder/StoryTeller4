//
//  BookmarkViewModel.swift
//  StoryTeller3
//
//  Created by Boris Eder on 25.11.25.
//

import Foundation
import SwiftUI
import Combine

@MainActor
class BookmarkViewModel: ObservableObject {
    // MARK: - Published State
    @Published var searchText = ""
    @Published var sortOption: BookmarkSortOption = .dateNewest
    @Published var groupByBook = true
    @Published private var refreshTrigger = false
    
    // MARK: - Dependencies
    private let dependencies: DependencyContainer
    private let repository: BookmarkRepository
    private var player: AudioPlayer { dependencies.player }
    private var cancellables = Set<AnyCancellable>()
    
    var editingBookmark: EnrichedBookmark?
    var editedBookmarkTitle: String
    
    // MARK: - Computed Properties
    var allBookmarks: [EnrichedBookmark] {
        dependencies.getAllEnrichedBookmarks(sortedBy: sortOption)
            .filter { searchFilter($0) }
    }
    
    var groupedBookmarks: [(book: Book?, bookmarks: [EnrichedBookmark])] {
        dependencies.getGroupedEnrichedBookmarks()
            .map { group in
                let filtered = group.bookmarks.filter { searchFilter($0) }
                return (group.book, filtered)
            }
            .filter { !$0.bookmarks.isEmpty }
    }
    
    // MARK: - Init
    init(dependencies: DependencyContainer = .shared) {
        self.dependencies = dependencies
        self.repository = dependencies.bookmarkRepository
        self.editingBookmark = nil
        self.editedBookmarkTitle = ""
        setupObservers()
    }
    
    // MARK: - Setup
    private func setupObservers() {
        // React to bookmark enrichment updates
        NotificationCenter.default.publisher(for: .init("BookmarkEnrichmentUpdated"))
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        // React to bookmark repository changes
        repository.$bookmarks
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Actions
    func refresh() async {
        await repository.syncFromServer()
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
            // ✅ FIX: Load book if it's not currently playing
            if player.book?.id != book.id {
                AppLogger.general.debug("[BookmarkVM] Loading book: \(book.title)")
                await player.load(
                    book: book,
                    isOffline: dependencies.downloadRepository.getDownloadStatus(for: book.id).isDownloaded,
                    restoreState: false,  // Don't restore - we'll jump to bookmark
                    autoPlay: false
                )
            }
            
            // ✅ Now jump to the bookmark position
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
        
        // Search in bookmark title
        if enriched.bookmark.title.lowercased().contains(query) {
            return true
        }
        
        // Search in book title
        if let book = enriched.book, book.title.lowercased().contains(query) {
            return true
        }
        
        return false
    }
}
