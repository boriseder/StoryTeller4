import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel: HomeViewModel = DependencyContainer.shared.homeViewModel
    @EnvironmentObject var appState: AppStateManager
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var dependencies: DependencyContainer

    @State private var selectedSeries: Series?
    @State private var selectedAuthor: Author?

    @State private var showBookmarks = false

    @State private var showEmptyState = false
    
    @AppStorage("open_fullscreen_player") private var playerMode = false
    @AppStorage("auto_play_on_book_tap") private var autoPlay = false

    var body: some View {
        ZStack {
            if theme.backgroundStyle == .dynamic {
                Color.accent.ignoresSafeArea()
            }
          
            contentView
                .transition(.opacity)

        }
        .navigationTitle("Personalized")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(.clear, for: .navigationBar)
        .toolbarColorScheme(theme.colorScheme, for: .navigationBar)
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
                SettingsButton()
            }
        }
        .refreshable {
            await viewModel.loadPersonalizedSections()
        }
        .task {
            await viewModel.loadPersonalizedSectionsIfNeeded()
        }
        .sheet(item: $selectedSeries) { series in
            SeriesDetailView(series: series, onBookSelected: {})
                .environmentObject(appState)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(.black.opacity(0.65))
        }
        .sheet(item: $selectedAuthor) { author in
            AuthorDetailView(
                author: author,
                onBookSelected: { }
            )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(.black.opacity(0.65))
        }
        .sheet(isPresented: $showBookmarks) {
            BookmarksView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.black.opacity(0.65))
        }
    }
        
    private var contentView: some View {
        
        ZStack {
            if theme.backgroundStyle == .dynamic {
                DynamicBackground()
            }

            ScrollView {
                LazyVStack(spacing: DSLayout.contentGap) {
                    
                    OfflineBanner()
                    
                    homeHeaderView
                        .padding(.vertical, DSLayout.elementGap)
                    
                    ForEach(Array(viewModel.personalizedSections.enumerated()), id: \.element.id) { index, section in
                        PersonalizedSectionView(
                            section: section,
                            player: viewModel.player,
                            api: viewModel.api,
                            downloadManager: viewModel.downloadManager,
                            onBookSelected: { book in
                                Task {
                                    await viewModel.playBook(
                                        book,
                                        appState: appState,
                                        autoPlay: autoPlay
                                    )
                                }
                            },
                            onSeriesSelected: { series in
                                selectedSeries = series
                            },
                            onAuthorSelected: { author in
                                selectedAuthor = author
                            }
                        )
                        .environmentObject(appState)
                    }
                }
                Spacer()
                    .frame(height: DSLayout.miniPlayerHeight)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, DSLayout.screenPadding)
        }
        .transition(.opacity)
        .onAppear {
            viewModel.contentLoaded = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                viewModel.sectionsLoaded = true
            }
        }
    }
    
    private var homeHeaderView: some View {
        
        HStack(spacing: DSLayout.elementGap) {
            HStack(spacing: DSLayout.tightGap) {
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.blue)
                    .frame(width: DSLayout.largeIcon, height: DSLayout.largeIcon)

                VStack(alignment: .center, spacing: 0) {
                    Text("Books in library")
                        .font(DSText.footnote)
                        .foregroundColor(.secondary)
                    
                    Text(String(viewModel.totalItemsCount))
                        .font(DSText.prominent)
                }
                .frame(maxWidth: .infinity, alignment: .center)

            }

            Divider()

            HStack(spacing: DSLayout.tightGap) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: DSLayout.icon))
                    .foregroundColor(.green)
                    .frame(width: DSLayout.largeIcon, height: DSLayout.largeIcon)

                VStack(alignment: .center, spacing: 0) {
                    Text("Downloads")
                        .font(DSText.footnote)
                        .foregroundColor(.secondary)
                    
                    Text(String(viewModel.downloadedCount))
                        .font(DSText.prominent)
                }
                .frame(maxWidth: .infinity, alignment: .center)

            }

            Divider()

            Button {
                Task {
                    if !appState.isDeviceOnline {
                        await appState.checkServerReachability()
                    } else {
                        appState.debugToggleDeviceOnline()
                    }
                }
            } label: {
                Image(systemName: appState.isDeviceOnline ? "icloud" : "icloud.slash")
                    .font(.system(size: DSLayout.icon))
                    .foregroundColor(appState.isDeviceOnline ? .green : .red)
                    .frame(width: DSLayout.largeIcon, height: DSLayout.largeIcon)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(DSLayout.elementPadding)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.element))
        .shadow(color: .black.opacity(0.05), radius: DSCorners.element, x: 0, y: 4)
    }
}

// MARK: - Personalized Section View
struct PersonalizedSectionView: View {
    let section: PersonalizedSection
    @ObservedObject var player: AudioPlayer
    let api: AudiobookshelfClient
    @ObservedObject var downloadManager: DownloadManager
    let onBookSelected: (Book) -> Void
    let onSeriesSelected: (Series) -> Void
    let onAuthorSelected: (Author) -> Void
    
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var dependencies: DependencyContainer

    var body: some View {
        VStack(alignment: .leading, spacing: DSLayout.contentGap) {
            sectionHeader
            
            switch section.type {
            case "book":
                bookSection
            case "series":
                seriesSection
            case "authors":
                authorsSection
            default:
                bookSection
            }
        }
    }
    
    private var sectionHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: sectionIcon)
                .font(DSText.itemTitle)
                .foregroundColor(theme.textColor)
            
            Text(section.label)
                .font(DSText.itemTitle)
                .foregroundColor(theme.textColor)
            
        }
    }
    
    private var sectionIcon: String {
        switch section.id {
        case "continue-listening": return "play.circle.fill"
        case "recently-added": return "clock.fill"
        case "recent-series": return "rectangle.stack.fill"
        case "discover": return "sparkles"
        case "newest-authors": return "person.2.fill"
        default: return "books.vertical.fill"
        }
    }
    
    private var bookSection: some View {
        let books = section.entities.compactMap { entity -> Book? in
            guard let li = entity.asLibraryItem else { return nil }
            return api.converter.convertLibraryItemToBook(li)
        }

        return ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: DSLayout.contentGap) {
                ForEach(books) { book in
                    BookCardView(
                        viewModel: BookCardViewModel(
                            book: book,
                            container: dependencies
                        ),
                        api: api,
                        onTap: { onBookSelected(book) },
                        onDownload: { Task { await downloadManager.downloadBook(book, api: api) } },
                        onDelete: { downloadManager.deleteBook(book.id) }
                    )
                }
            }
        }
    }

    private var seriesSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: DSLayout.contentGap) {
                ForEach(section.entities.indices, id: \.self) { index in
                    let entity = section.entities[index]
                    
                    SeriesCardView(
                        entity: entity,
                        api: api,
                        downloadManager: downloadManager,
                        onTap: {
                            if let series = entity.asSeries {
                                onSeriesSelected(series)
                            }
                        }
                    )
                }
            }
        }
    }
    
    private var authorsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DSLayout.contentGap) {
                ForEach(section.entities.compactMap { $0.asAuthor }, id: \.id) { author in
                    AuthorCardView(
                        author: author,
                        onTap: {
                            onAuthorSelected(author)
                        }
                    )
                }
            }
        }
    }

}

// MARK: - Series Card View
struct SeriesCardView: View {
    let entity: PersonalizedEntity
    let api: AudiobookshelfClient
    let downloadManager: DownloadManager
    let onTap: () -> Void
    
    @EnvironmentObject var theme: ThemeManager
        
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: DSLayout.contentGap) {
                Group {
                    if let series = entity.asSeries,
                       let firstBook = series.books.first,
                       let coverBook = api.converter.convertLibraryItemToBook(firstBook) {
                        
                        BookCoverView.square(
                            book: coverBook,
                            size: DSLayout.cardCoverNoPadding,
                            api: api,
                            downloadManager: downloadManager
                        )
                        .clipShape(RoundedRectangle(cornerRadius: DSCorners.element))
                    }
                }
                
                VStack(alignment: .leading, spacing: DSLayout.tightGap) {
                    
                    Text(displayName)
                        .font(DSText.detail)
                        .foregroundColor(theme.textColor)
                        .lineLimit(1)
                        .frame(maxWidth: DSLayout.cardCoverNoPadding - 2 * DSLayout.elementPadding, alignment: .leading)
                }
            }
            //.frame(width: DSLayout.cardCoverNoPadding, height: DSLayout.cardCoverNoPadding * 1.30)
            .transition(.opacity)
        }
        .buttonStyle(.plain)
    }
        
    private var displayName: String {
        return entity.name ?? entity.asSeries?.name ?? "Unknown Series"
    }
}

// MARK: - Author Card View
struct AuthorCardView: View {
    let author: Author
    let onTap: () -> Void
    
    @EnvironmentObject var theme: ThemeManager
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: DSLayout.contentGap) {
                
                AuthorImageView(
                    author: author,
                    api: DependencyContainer.shared.apiClient,
                    size: 100
                )

                
                Text(author.name)
                    .font(DSText.detail)
                    .foregroundColor(theme.textColor)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: DSLayout.avatar)
            }
            .padding(.vertical, DSLayout.elementPadding)
            .transition(.opacity)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Array Extension
extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
