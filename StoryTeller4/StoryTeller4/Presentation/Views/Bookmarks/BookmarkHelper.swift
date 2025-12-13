//
//  BookmarkTimelineView.swift
//  StoryTeller3
//
//  Created by Boris Eder on 24.11.25.
//


import SwiftUI

// MARK: - Bookmark Badge für BookCard
extension BookCardView {
    var bookmarkBadge: some View {
        Group {
            if BookmarkRepository.shared.getBookmarks(for: viewModel.book.id).count > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 10))
                    Text("\(BookmarkRepository.shared.getBookmarks(for: viewModel.book.id).count)")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.orange)
                .clipShape(Capsule())
            }
        }
    }
}

// MARK: - Bookmark Context Menu Extension
extension View {
    func bookmarkContextMenu(for book: Book, currentTime: Double) -> some View {
        self.contextMenu {
            Button {
                // Quick bookmark at current time
                Task {
                    do {
                        try await BookmarkRepository.shared.createBookmark(
                            libraryItemId: book.id,
                            time: currentTime,
                            title: "Bookmark at \(TimeFormatter.formatTime(currentTime))"
                        )
                    } catch {
                        AppLogger.general.debug("[ContextMenu] Bookmark creation failed: \(error)")
                    }
                }
            } label: {
                Label("Add Bookmark Here", systemImage: "bookmark")
            }
            
            if !BookmarkRepository.shared.getBookmarks(for: book.id).isEmpty {
                Button {
                    // Show bookmarks for this book
                } label: {
                    Label("View Bookmarks (\(BookmarkRepository.shared.getBookmarks(for: book.id).count))", 
                          systemImage: "bookmark.fill")
                }
            }
        }
    }
}

// MARK: - Bookmark Search Extensions
extension Bookmark {
    func matches(searchQuery: String) -> Bool {
        let query = searchQuery.lowercased()
        return title.lowercased().contains(query)
    }
}

extension Array where Element == Bookmark {
    func filtered(by query: String) -> [Bookmark] {
        guard !query.isEmpty else { return self }
        return filter { $0.matches(searchQuery: query) }
    }
    
    func sorted(by option: BookmarkSortOption) -> [Bookmark] {
        switch option {
        case .dateNewest:
            return sorted { $0.createdAt > $1.createdAt }
        case .dateOldest:
            return sorted { $0.createdAt < $1.createdAt }
        case .timeInBook:
            return sorted { $0.time < $1.time }
        case .bookTitle:
            return sorted { $0.libraryItemId < $1.libraryItemId }
        }
    }
}
