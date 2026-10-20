import SwiftUI
import Combine

struct LibraryView: View {
    var viewModel: LibraryViewModel

    @Environment(AppStateManager.self) var appState
    @Environment(ThemeManager.self) var theme
    @Environment(DependencyContainer.self) var dependencies

    @State private var bookCardVMs: [BookCardViewModel] = []
    @State private var showBookmarks = false
    @State private var showEmptyState = false

    @Binding var columnVisibility: NavigationSplitViewVisibility

    @AppStorage("open_fullscreen_player") private var playerMode: Bool = false
    @AppStorage("auto_play_on_book_tap") private var autoPlay: Bool = false

    var body: some View {
        @Bindable var vm = viewModel

        ZStack {
            DynamicBackground()
            contentView
            .transition(.opacity)
        }
            
        .navigationTitle(viewModel.libraryName)
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(theme.colorScheme, for: .navigationBar)
        .searchable(
            text: $vm.filterState.searchText,
            placement: .automatic,
            prompt: "Search books..."
        )
        .refreshable { await viewModel.loadBooks() }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showBookmarks.toggle() }) {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.primary)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: DSLayout.contentGap) {
                    if !viewModel.books.isEmpty { filterAndSortMenu }
                    SettingsButton()
                }
            }
        }
        .task {
            await viewModel.loadBooksIfNeeded()
            updateBookCardViewModels()
        }
        .navigationDestination(for: Book.self) { book in
            if book.isCollapsedSeries {
                SeriesDetailView(
                    seriesBook: book,
                    container: dependencies,
                    onBookSelected: viewModel.onBookSelected
                )
                .environment(appState)
            } else if let vm = dependencies.makeBookDetailViewModel(bookId: book.id) {
                BookDetailView(viewModel: vm)
                    .environment(appState)
            }
        }
        .sheet(isPresented: $showBookmarks) {
            BookmarksView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.black.opacity(0.65))
        }
        .onChange(of: viewModel.filteredAndSortedBooks.count) {
            updateBookCardViewModels()
        }
    }

    private var contentView: some View {
        ScrollView {
            Group {
                OfflineBanner()

                if viewModel.filterState.showDownloadedOnly {
                    LibraryBannerView(
                        icon: "arrow.down.circle.fill",
                        iconColor: .orange,
                        text: "Show \(viewModel.filteredAndSortedBooks.count) of \(viewModel.downloadedBooksCount) downloaded books",
                        onDismiss: { viewModel.toggleDownloadFilter() }
                    )
                }

                if viewModel.filterState.showSeriesGrouped {
                    let seriesCount = viewModel.filteredAndSortedBooks.filter { $0.isCollapsedSeries }.count
                    let booksCount = viewModel.filteredAndSortedBooks.count - seriesCount
                    let text = seriesCount > 0 && booksCount > 0 
                        ? "Show \(seriesCount) Series • \(booksCount) Books" 
                        : (seriesCount > 0 ? "Show \(seriesCount) Series" : "Show \(booksCount) books")
                        
                    LibraryBannerView(
                        icon: "rectangle.stack.fill",
                        iconColor: .blue,
                        text: text,
                        onDismiss: { viewModel.toggleSeriesMode() }
                    )
                }

                LazyVGrid(
                    columns: DSGridColumns.two,
                    alignment: .center,
                    spacing: DSLayout.contentGap
                ) {
                    ForEach(bookCardVMs) { bookVM in
                        NavigationLink(value: bookVM.book) {
                            BookCardView(
                                viewModel: bookVM,
                                api: dependencies.apiClient,
                                onTap: { /* Handled by NavigationLink */ },
                                onDownload: { startDownload(bookVM.book) },
                                onDelete: { deleteDownload(bookVM.book) }
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer().frame(height: DSLayout.miniPlayerHeight)
            }
            .padding(.horizontal, DSLayout.screenPadding)
        }
    }

    private func updateBookCardViewModels() {
        let books = viewModel.filteredAndSortedBooks
        Task { @MainActor in
            bookCardVMs = books.map { BookCardViewModel(book: $0, container: dependencies) }
        }
    }

    // handleBookTap removed as NavigationLink handles it natively

    private func startDownload(_ book: Book) {
        guard let api = dependencies.apiClient else { return }
        Task {
            await dependencies.downloadManager.downloadBook(book, api: api)
        }
    }

    private func deleteDownload(_ book: Book) {
        dependencies.downloadManager.deleteBook(book.id)
    }

    // MARK: - Filter Menu (unverändert)

    private var filterAndSortMenu: some View {
        Menu {
            LibraryFilterControls(viewModel: viewModel)
        } label: {
            ZStack {
                Circle()
                    .fill(viewModel.filterState.hasActiveFilters
                          ? Color.accentColor.opacity(0.15) : Color.clear)
                    .frame(width: 32, height: 32)
                Image(systemName: viewModel.filterState.hasActiveFilters
                      ? "line.3.horizontal.decrease.circle.fill"
                      : "line.3.horizontal.decrease.circle")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(viewModel.filterState.hasActiveFilters ? .accentColor : .primary)
                if viewModel.filterState.hasActiveFilters {
                    Circle()
                        .fill(LinearGradient(
                            colors: [.orange, .red],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                        .offset(x: 10, y: -10)
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.7),
                       value: viewModel.filterState.hasActiveFilters)
        }
    }
}

// MARK: - Supporting Views (unverändert)

struct LibraryBannerView: View {
    let icon: String
    let iconColor: Color
    let text: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: DSLayout.tightGap) {
            Image(systemName: icon)
                .font(.system(size: DSLayout.icon))
                .foregroundColor(iconColor)
                .frame(width: DSLayout.largeIcon, height: DSLayout.largeIcon)
            
            Text(text)
                .font(DSText.footnote)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: DSLayout.smallIcon))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DSLayout.tightPadding)
        .padding(.horizontal, DSLayout.elementPadding)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.element))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
}
