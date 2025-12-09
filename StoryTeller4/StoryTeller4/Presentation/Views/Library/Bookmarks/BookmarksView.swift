//
//  BookmarksView.swift
//  StoryTeller3
//
//  Created by Boris Eder on 24.11.25.
//

import SwiftUI

// MARK: - All Bookmarks View
struct BookmarksView: View {
    @StateObject private var viewModel: BookmarkViewModel
    @EnvironmentObject var dependencies: DependencyContainer
    @Environment(\.dismiss) private var dismiss

    init() {
        _viewModel = StateObject(wrappedValue: BookmarkViewModel())
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: DSLayout.tightGap) {
                    if viewModel.groupByBook {
                        groupedView
                    } else {
                        flatView
                    }
                }
                .padding(.horizontal, DSLayout.screenPadding)
                .padding(.bottom, DSLayout.screenPadding)
            }
            .navigationTitle("Bookmarks")
            .searchable(text: $viewModel.searchText, prompt: "Search bookmarks...")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        sortMenu
                        Divider()
                        groupingMenu
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .refreshable {
                await viewModel.refresh()
            }
            .alert("Edit Bookmark", isPresented: .constant(viewModel.editingBookmark != nil)) {
                TextField("Bookmark name", text: $viewModel.editedBookmarkTitle)
                    .autocorrectionDisabled()
                
                Button("Cancel", role: .cancel) {
                    viewModel.cancelEditing()
                }
                
                Button("Save") {
                    viewModel.saveEditedBookmark()
                }
                .disabled(viewModel.editedBookmarkTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            } message: {
                Text("Enter a new name for this bookmark")
            }
        }
    }
    
    // MARK: - Flat View
    
    private var flatView: some View {
        ForEach(viewModel.allBookmarks) { enriched in
            BookmarkRow(
                enriched: enriched,
                showBookInfo: true,
                onTap: { viewModel.jumpToBookmark(enriched, dismiss: dismiss) },
                onEdit: { viewModel.startEditingBookmark(enriched) },
                onDelete: { viewModel.deleteBookmark(enriched) }
            )
            .environmentObject(viewModel)
        }
    }
    
    // MARK: - Grouped View
    
    private var groupedView: some View {
        ForEach(Array(viewModel.groupedBookmarks.enumerated()), id: \.offset) { index, group in
            VStack(alignment: .leading, spacing: DSLayout.tightGap) {
                // Section Header
                if let book = group.book {
                    BookSectionHeader(book: book, bookmarkCount: group.bookmarks.count)
                        .padding(.top, index == 0 ? 0 : DSLayout.contentGap)
                } else {
                    HStack(spacing: DSLayout.elementGap) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading book info...")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(group.bookmarks.count) bookmark\(group.bookmarks.count == 1 ? "" : "s")")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, DSLayout.tightPadding)
                    .padding(.top, index == 0 ? 0 : DSLayout.contentGap)
                }
                
                // Bookmarks in group
                ForEach(group.bookmarks) { enriched in
                    BookmarkRow(
                        enriched: enriched,
                        showBookInfo: false,
                        onTap: { viewModel.jumpToBookmark(enriched, dismiss: dismiss) },
                        onEdit: { viewModel.startEditingBookmark(enriched) },
                        onDelete: { viewModel.deleteBookmark(enriched) }
                    )
                    .environmentObject(viewModel)
                }
            }
        }
    }
    
    // MARK: - Sort Menu
    
    private var sortMenu: some View {
        Section("Sort By") {
            ForEach(BookmarkSortOption.allCases) { option in
                Button {
                    viewModel.sortOption = option
                } label: {
                    HStack {
                        Text(option.rawValue)
                        if viewModel.sortOption == option {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }
    }
    
    private var groupingMenu: some View {
        Section("View") {
            Button {
                viewModel.toggleGrouping()
            } label: {
                HStack {
                    Text(viewModel.groupByBook ? "Show All" : "Group by Book")
                    if viewModel.groupByBook {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
    }
}


// MARK: - Book Section Header
struct BookSectionHeader: View {
    let book: Book
    let bookmarkCount: Int
    
    var body: some View {
        HStack(spacing: DSLayout.elementGap) {
            Text(book.title)
                .font(.headline)
                .lineLimit(1)
            
            Spacer()
            
            Text("\(bookmarkCount) bookmark\(bookmarkCount == 1 ? "" : "s")")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, DSLayout.tightPadding)
    }
}
