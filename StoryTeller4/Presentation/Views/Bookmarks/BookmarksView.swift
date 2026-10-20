import SwiftUI

struct BookmarksView: View {
    @State private var viewModel = BookmarkViewModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) var theme

    var body: some View {
        NavigationStack {
            ZStack {
                DynamicBackground()

                VStack(spacing: 0) {
                    if viewModel.allBookmarks.isEmpty {
                        emptyState
                    } else {
                        bookmarksList
                    }
                }
            }
            .navigationTitle("Bookmarks")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $viewModel.searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search bookmarks...")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }

                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: viewModel.toggleGrouping) {
                        Image(systemName: viewModel.groupByBook ? "list.bullet" : "square.grid.2x2")
                    }
                }
            }
            .task {
                viewModel.refreshData()
            }
            .refreshable {
                await viewModel.refresh()
            }
            .sheet(item: $viewModel.editingBookmark) { enriched in
                NavigationStack {
                    Form {
                        TextField("Title", text: $viewModel.editedBookmarkTitle)
                            .autocorrectionDisabled()
                    }
                    .navigationTitle("Edit Bookmark")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { viewModel.cancelEditing() }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") { viewModel.saveEditedBookmark() }
                        }
                    }
                }
                .presentationDetents([.height(200)])
            }
        }
    }

    private var bookmarksList: some View {
        List {
            if viewModel.groupByBook {
                ForEach(viewModel.groupedBookmarks) { group in
                    Section(header: Text(group.title)) {
                        ForEach(group.bookmarks) { enriched in
                            bookmarkCell(enriched)
                        }
                    }
                }
            } else {
                ForEach(viewModel.filteredBookmarks) { enriched in
                    bookmarkCell(enriched)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func bookmarkCell(_ enriched: EnrichedBookmark) -> some View {
        Button {
            viewModel.jumpToBookmark(enriched, dismiss: dismiss)
        } label: {
            BookmarkRow(enriched: enriched)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                viewModel.deleteBookmark(enriched)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            
            Button {
                viewModel.startEditingBookmark(enriched)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "bookmark.slash")
                .font(.system(size: 50))
                .foregroundColor(.secondary)
            Text("No bookmarks found")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
