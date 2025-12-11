import SwiftUI

struct BookmarksView: View {
    @State private var viewModel = BookmarkViewModel()
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var theme: ThemeManager
    
    var body: some View {
        NavigationStack {
            ZStack {
                if theme.backgroundStyle == .dynamic {
                    Color.accent.ignoresSafeArea()
                    DynamicBackground()
                }
                
                VStack(spacing: 0) {
                    searchBar
                    
                    if viewModel.allBookmarks.isEmpty {
                        emptyState
                    } else {
                        bookmarksList
                    }
                }
            }
            .navigationTitle("Bookmarks")
            .navigationBarTitleDisplayMode(.inline)
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
    
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Search bookmarks...", text: $viewModel.searchText)
                .textFieldStyle(.plain)
            
            if !viewModel.searchText.isEmpty {
                Button(action: { viewModel.searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding()
    }
    
    private var bookmarksList: some View {
        List {
            if viewModel.groupByBook {
                ForEach(viewModel.groupedBookmarks, id: \.book?.id) { group in
                    Section(header: Text(group.book?.title ?? "Unknown Book")) {
                        ForEach(group.bookmarks) { enriched in
                            BookmarkRow(
                                enriched: enriched,
                                // FIX: Changed 'onJump' to 'onTap' to match BookmarkRow definition
                                onTap: { viewModel.jumpToBookmark(enriched, dismiss: dismiss) },
                                onEdit: { viewModel.startEditingBookmark(enriched) },
                                onDelete: { viewModel.deleteBookmark(enriched) }
                            )
                        }
                    }
                }
            } else {
                ForEach(viewModel.filteredBookmarks) { enriched in
                    BookmarkRow(
                        enriched: enriched,
                        // FIX: Changed 'onJump' to 'onTap'
                        onTap: { viewModel.jumpToBookmark(enriched, dismiss: dismiss) },
                        onEdit: { viewModel.startEditingBookmark(enriched) },
                        onDelete: { viewModel.deleteBookmark(enriched) }
                    )
                }
            }
        }
        .scrollContentBackground(.hidden)
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
