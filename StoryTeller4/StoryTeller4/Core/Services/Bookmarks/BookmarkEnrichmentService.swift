//
//  BookmarkEnrichmentService.swift
//  StoryTeller3
//
//  Created by Boris Eder on 25.11.25.
//

import Foundation
import Combine

@MainActor
class BookmarkEnrichmentService: ObservableObject {
    
    // MARK: - Dependencies
    private let bookmarkRepository: BookmarkRepository
    private let bookRepository: BookRepositoryProtocol
    private let libraryRepository: LibraryRepositoryProtocol
    private let downloadManager: DownloadManager
    
    // MARK: - Cache
    private var bookCache: [String: Book] = [:]
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Init
    init(
        bookmarkRepository: BookmarkRepository,
        bookRepository: BookRepositoryProtocol,
        libraryRepository: LibraryRepositoryProtocol,
        downloadManager: DownloadManager
    ) {
        self.bookmarkRepository = bookmarkRepository
        self.bookRepository = bookRepository
        self.libraryRepository = libraryRepository
        self.downloadManager = downloadManager
        
        setupObservers()
        preloadBooksForBookmarks()
    }
    
    // MARK: - Setup
    private func setupObservers() {
        // React to bookmark changes - preload books for new bookmarks
        bookmarkRepository.$bookmarks
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.preloadBooksForBookmarks()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public API
    
    /// Get enriched bookmarks (sorted)
    func getEnrichedBookmarks(sortedBy sort: BookmarkSortOption = .dateNewest) -> [EnrichedBookmark] {
        var enriched: [EnrichedBookmark] = []
        
        for (libraryItemId, bookmarks) in bookmarkRepository.bookmarks {
            let book = bookCache[libraryItemId]
            
            for bookmark in bookmarks {
                enriched.append(EnrichedBookmark(bookmark: bookmark, book: book))
            }
        }
        
        return sortEnrichedBookmarks(enriched, by: sort)
    }
    
    /// Get enriched bookmarks for specific book
    func getEnrichedBookmarks(for bookId: String) -> [EnrichedBookmark] {
        let bookmarks = bookmarkRepository.getBookmarks(for: bookId)
        let book = bookCache[bookId]
        
        return bookmarks.map { EnrichedBookmark(bookmark: $0, book: book) }
    }
    
    /// Get grouped enriched bookmarks
    func getGroupedEnrichedBookmarks() -> [(book: Book?, bookmarks: [EnrichedBookmark])] {
        var grouped: [String: (Book?, [EnrichedBookmark])] = [:]
        
        for (libraryItemId, bookmarks) in bookmarkRepository.bookmarks {
            let book = bookCache[libraryItemId]
            let enriched = bookmarks.map { EnrichedBookmark(bookmark: $0, book: book) }
            grouped[libraryItemId] = (book, enriched)
        }
        
        return grouped.values.map { ($0.0, $0.1) }
            .sorted { first, second in
                guard let book1 = first.book, let book2 = second.book else { return false }
                return book1.title < book2.title
            }
    }
    
    /// Load full book details (with all chapters) - used before jumping to bookmark
    func loadFullBookDetails(bookId: String) async throws -> Book {
        // Check cache first
        if let cached = bookCache[bookId], cached.chapters.count > 0 {
            return cached
        }
        
        // Fetch from API with full details
        let book = try await bookRepository.fetchBookDetails(bookId: bookId)
        
        // Update cache
        bookCache[bookId] = book
        objectWillChange.send()
        
        AppLogger.general.debug("[BookmarkEnrichment] ✅ Loaded full book: \(book.title) (\(book.chapters.count) chapters)")
        
        return book
    }
    
    // MARK: - Private Helpers
    
    private func preloadBooksForBookmarks() {
        Task {
            let bookIds = Set(bookmarkRepository.bookmarks.keys)
            
            for bookId in bookIds {
                // Skip if already cached
                guard bookCache[bookId] == nil else { continue }
                
                // Try to load basic info (lightweight)
                if let book = await loadBookBasicInfo(bookId: bookId) {
                    bookCache[bookId] = book
                    objectWillChange.send()
                }
            }
        }
    }
    
    private func loadBookBasicInfo(bookId: String) async -> Book? {
        // Try downloaded books first (fast)
        if let downloaded = downloadManager.downloadedBooks.first(where: { $0.id == bookId }) {
            return downloaded
        }
        
        // Try library cache (if available)
        // Note: We'd need access to LibraryViewModel.books here
        // For now, fallback to API
        
        do {
            let book = try await bookRepository.fetchBookDetails(bookId: bookId)
            return book
        } catch {
            AppLogger.general.debug("[BookmarkEnrichment] Failed to load book \(bookId): \(error)")
            return nil
        }
    }
    
    private func sortEnrichedBookmarks(_ bookmarks: [EnrichedBookmark], by sort: BookmarkSortOption) -> [EnrichedBookmark] {
        switch sort {
        case .dateNewest:
            return bookmarks.sorted { $0.bookmark.createdAt > $1.bookmark.createdAt }
        case .dateOldest:
            return bookmarks.sorted { $0.bookmark.createdAt < $1.bookmark.createdAt }
        case .timeInBook:
            return bookmarks.sorted { $0.bookmark.time < $1.bookmark.time }
        case .bookTitle:
            return bookmarks.sorted {
                guard let b1 = $0.book, let b2 = $1.book else { return false }
                return b1.title < b2.title
            }
        }
    }
}
