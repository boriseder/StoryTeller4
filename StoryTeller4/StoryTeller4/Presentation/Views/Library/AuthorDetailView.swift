import SwiftUI

struct AuthorDetailView: View {
    let author: Author
    let onBookSelected: () -> Void

    @StateObject private var viewModel: AuthorDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppStateManager
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject private var dependencies: DependencyContainer

    @AppStorage("open_fullscreen_player") private var playerMode = false
    @AppStorage("auto_play_on_book_tap") private var autoPlay = false

    init(author: Author, onBookSelected: @escaping () -> Void) {
        self.author = author
        self.onBookSelected = onBookSelected

        // Dependencies vom Container holen
        let container = DependencyContainer.shared
        _viewModel = StateObject(wrappedValue: AuthorDetailViewModel(
            bookRepository: container.bookRepository,
            libraryRepository: container.libraryRepository,
            api: container.apiClient!,
            downloadManager: container.downloadManager,
            player: container.player,
            appState: container.appState,
            playBookUseCase: PlayBookUseCase(),
            author: author,
            onBookSelected: onBookSelected
        ))
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                contentView(geometry: geometry)
            }
            .navigationTitle("")
            .navigationBarHidden(true)
            .task {
                viewModel.onDismiss = { dismiss() }
                await viewModel.loadAuthorDetails()
            }
        }
    }
    
    private func contentView(geometry: GeometryProxy) -> some View {
        ZStack {
                        
            VStack(alignment: .leading, spacing: DSLayout.contentGap) {
                authorHeaderView
                
                ScrollView {
                    LazyVGrid(columns: DSGridColumns.two, spacing: DSLayout.contentGap) {
                        ForEach(viewModel.authorBooks, id: \.id) { book in
                            let cardViewModel = BookCardViewModel(
                                book: book,
                                container: dependencies
                            )
                            BookCardView(
                                viewModel: cardViewModel,
                                api: viewModel.api,
                                onTap: {
                                    Task {
                                        await viewModel.playBook(book, appState: appState)
                                    }
                                },
                                onDownload: {
                                    Task {
                                        await viewModel.downloadBook(book)
                                    }
                                },
                                onDelete: {
                                    viewModel.deleteBook(book.id)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, DSLayout.contentPadding)
                    .padding(.top, DSLayout.contentPadding)
                }
            }
        }
    }
    
    private var authorHeaderView: some View {
        
        HStack(alignment: .center) {
            // Author Image
            AuthorImageView(
                author: author,
                api: DependencyContainer.shared.apiClient,
                size: DSLayout.smallAvatar
            )
            
            VStack(alignment: .leading, spacing: DSLayout.tightGap) {
                Text(viewModel.author.name)
                    .font(DSText.itemTitle)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                if !viewModel.authorBooks.isEmpty {
                    HStack(spacing: DSLayout.elementGap) {
                        Text("\(author.numBooks ?? 0) \((author.numBooks ?? 0) == 1 ? "Book" : "Books")")

                        if viewModel.downloadedCount > 0 {
                            Text(" • \(viewModel.downloadedCount) downloaded")
                        }
                        
                        if viewModel.totalDuration > 0 {
                            Text(" • \(TimeFormatter.formatTimeCompact(viewModel.totalDuration)) total")
                        }
                    }
                    .font(DSText.metadata)
                }
            }
            .layoutPriority(1)
            .padding(.leading, DSLayout.elementGap)
            
            Spacer()
            
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(DSText.itemTitle)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DSLayout.screenPadding)
        .padding(.top, DSLayout.contentGap)
    }
}
