import SwiftUI

struct LibraryView: View {
    
    @StateObject private var viewModel: LibraryViewModel = DependencyContainer.shared.libraryViewModel
    @EnvironmentObject var appState: AppStateManager
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var dependencies: DependencyContainer

    @State private var selectedSeries: Book?
    @State private var bookCardVMs: [BookCardViewModel] = []
    @State private var showBookmarks = false

    @Binding var columnVisibility: NavigationSplitViewVisibility

    // Workaround to hide nodata at start of app
    @State private var showEmptyState = false

    @AppStorage("open_fullscreen_player") private var playerMode: Bool = false
    @AppStorage("auto_play_on_book_tap") private var autoPlay: Bool = false
    
    private var isSidebarVisible: Bool {
        columnVisibility == .all || columnVisibility == .doubleColumn
    }
    
    var body: some View {
        ZStack {
            
            if theme.backgroundStyle == .dynamic {
                Color.accent.ignoresSafeArea()
            }
            
            contentView
                .transition(.opacity)
        }
        .navigationTitle(viewModel.libraryName)
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(.clear, for: .navigationBar)
        .toolbarColorScheme(theme.colorScheme, for: .navigationBar)
        .searchable(
            text: $viewModel.filterState.searchText,
            placement: .automatic,
            prompt: "Search books..."
        )
        .refreshable {
            await viewModel.loadBooks()
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showBookmarks.toggle()
                }){
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.primary)
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: DSLayout.contentGap) {
                    if !viewModel.books.isEmpty {
                        filterAndSortMenu
                    }
                    SettingsButton()
                }
            }
        }
        .task {
            await viewModel.loadBooksIfNeeded()
            updateBookCardViewModels()
        }
        .sheet(item: $selectedSeries) { series in
            SeriesDetailView(
                seriesBook: series,
                onBookSelected: viewModel.onBookSelected
            )
            .environmentObject(appState)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
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
        .onReceive(viewModel.player.$currentTime.throttle(for: .seconds(2), scheduler: RunLoop.main, latest: true)) { _ in
            updateCurrentBookOnly()
        }
        .onReceive(viewModel.downloadManager.$downloadProgress.throttle(for: .milliseconds(500), scheduler: RunLoop.main, latest: true)) { _ in
            updateDownloadingBooksOnly()
        }
    }

        
    private var contentView: some View {

        ZStack {
            if theme.backgroundStyle == .dynamic {
                DynamicBackground()
            }
            
            ScrollView {
                OfflineBanner()
                
                if viewModel.filterState.showDownloadedOnly {
                    FilterStatusBannerView(
                        count: viewModel.filteredAndSortedBooks.count,
                        totalDownloaded: viewModel.downloadedBooksCount,
                        onDismiss: { viewModel.toggleDownloadFilter() }
                    )
                }
                
                if viewModel.filterState.showSeriesGrouped {
                    SeriesStatusBannerView(
                        books: viewModel.filteredAndSortedBooks,
                        onDismiss: { viewModel.toggleSeriesMode() }
                    )
                }
                
                LazyVGrid(
                    columns: DSGridColumns.two,
                    alignment: .center,
                    spacing: DSLayout.contentGap
                ) {
                ForEach(bookCardVMs) { bookVM in
                        BookCardView(
                            viewModel: bookVM,
                            api: viewModel.api,
                            onTap: { handleBookTap(bookVM.book) },
                            onDownload: { startDownload(bookVM.book) },
                            onDelete: { deleteDownload(bookVM.book) }
                        )
                    }
                }

                Spacer()
                    .frame(height: DSLayout.miniPlayerHeight)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, DSLayout.screenPadding)
        }
    }
    
    // MARK: - Update Logic (unchanged)
    
    private func updateBookCardViewModels() {
        let books = viewModel.filteredAndSortedBooks
        Task { @MainActor in
            let newVMs = books.map { book in
                BookCardViewModel(book: book, container: dependencies)
            }
            self.bookCardVMs = newVMs
        }
    }
    
    private func updateCurrentBookOnly() {
        guard let currentBookId = viewModel.player.book?.id,
              let index = bookCardVMs.firstIndex(where: { $0.id == currentBookId }) else {
            return
        }
        bookCardVMs[index] = BookCardViewModel(book: bookCardVMs[index].book, container: dependencies )
    }
    
    private func updateDownloadingBooksOnly() {
        let downloadingIds = Set(viewModel.downloadManager.downloadProgress.keys)
        for (index, vm) in bookCardVMs.enumerated() {
            if downloadingIds.contains(vm.id) {
                bookCardVMs[index] = BookCardViewModel(book: vm.book, container: dependencies)
            }
        }
    }
    
    // MARK: - Actions (unchanged)
    
    private func handleBookTap(_ book: Book) {
        if book.isCollapsedSeries {
            selectedSeries = book
        } else {
            Task {
                await viewModel.playBook(
                    book,
                    appState: appState,
                    autoPlay: autoPlay
                    )
            }
        }
    }
    
    private func startDownload(_ book: Book) {
        Task {
            await viewModel.downloadManager.downloadBook(book, api: viewModel.api)
        }
    }
    
    private func deleteDownload(_ book: Book) {
        viewModel.downloadManager.deleteBook(book.id)
    }
    
    // MARK: - Toolbar Components (unchanged)
    
    private var filterAndSortMenu: some View {
        Menu {
            Section("SORTING") {
                ForEach(LibrarySortOption.allCases) { option in
                    Button {
                        viewModel.filterState.selectedSortOption = option
                        viewModel.filterState.saveToDefaults()
                    } label: {
                        if viewModel.filterState.selectedSortOption == option {
                            Label(option.rawValue, systemImage: "checkmark")
                        } else {
                            Text(option.rawValue)
                        }
                    }
                }
                
                Button {
                    viewModel.filterState.sortAscending.toggle()
                    viewModel.filterState.saveToDefaults()
                } label: {
                    Label(
                        viewModel.filterState.sortAscending ? "Ascending" : "Descending",
                        systemImage: viewModel.filterState.sortAscending ? "arrow.up" : "arrow.down"
                    )
                }
            }
            
            Divider()
            
            Section("FILTER") {
                Button {
                    viewModel.toggleDownloadFilter()
                } label: {
                    if viewModel.filterState.showDownloadedOnly {
                        Label("Show all books", systemImage: "books.vertical")
                    } else {
                        Label("Downloaded only", systemImage: "arrow.down.circle")
                    }
                }
            }
            
            Divider()
            
            Section("VIEW") {
                Button {
                    viewModel.toggleSeriesMode()
                } label: {
                    Label(
                        "Group series",
                        systemImage: viewModel.filterState.showSeriesGrouped
                        ? "square.stack.3d.up.fill"
                        : "square.stack.3d.up"
                    )
                }
            }
            
            if viewModel.filterState.hasActiveFilters {
                Divider()
                Button(role: .destructive) {
                    withAnimation(.spring(response: 0.3)) {
                        viewModel.resetFilters()
                    }
                } label: {
                    Label("Reset all filters", systemImage: "arrow.counterclockwise")
                }
            }
        } label: {
            ZStack {
                Circle()
                    .fill(viewModel.filterState.hasActiveFilters
                          ? Color.accentColor.opacity(0.15)
                          : Color.clear)
                    .frame(width: 32, height: 32)
                
                Image(systemName: viewModel.filterState.hasActiveFilters
                      ? "line.3.horizontal.decrease.circle.fill"
                      : "line.3.horizontal.decrease.circle")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(viewModel.filterState.hasActiveFilters ? .accentColor : .primary)
                
                if viewModel.filterState.hasActiveFilters {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.orange, .red],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                        .offset(x: 10, y: -10)
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.filterState.hasActiveFilters)
        }
    }
}

// Banner Views bleiben unverändert...
struct FilterStatusBannerView: View {
    let count: Int
    let totalDownloaded: Int
    let onDismiss: () -> Void
    
    var body: some View {
        HStack(spacing: DSLayout.tightGap) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: DSLayout.icon))
                .foregroundColor(.orange)
                .frame(width: DSLayout.largeIcon, height: DSLayout.largeIcon)
            
            Text("Show \(count) of \(totalDownloaded) downloaded books")
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

struct SeriesStatusBannerView: View {
    let books: [Book]
    let onDismiss: () -> Void
    
    private var seriesCount: Int {
        books.lazy.filter { $0.isCollapsedSeries }.count
    }
    
    private var booksCount: Int {
        books.count - seriesCount
    }
    
    var body: some View {
        HStack(spacing: DSLayout.contentGap) {
            Image(systemName: "rectangle.stack.fill")
                .font(.system(size: 16))
                .foregroundColor(.blue)
            
            if seriesCount > 0 && booksCount > 0 {
                Text("Show \(seriesCount) Series • \(booksCount) Books")
                    .font(.subheadline)
                    .foregroundColor(.primary)
            } else if seriesCount > 0 {
                Text("Show \(seriesCount) Series")
                    .font(.subheadline)
                    .foregroundColor(.primary)
            } else {
                Text("Show \(booksCount) books")
                    .font(.subheadline)
                    .foregroundColor(.primary)
            }
            
            Spacer()
            
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, DSLayout.screenPadding)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(.separator)),
            alignment: .bottom
        )
    }
}
