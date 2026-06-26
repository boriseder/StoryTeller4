import SwiftUI

struct AuthorDetailView: View {
    @State private var viewModel: AuthorDetailViewModel
    @Environment(\.dismiss) private var dismiss

    @Environment(AppStateManager.self) private var appState
    @Environment(ThemeManager.self) var theme
    @Environment(DependencyContainer.self) private var dependencies

    @AppStorage("open_fullscreen_player") private var playerMode = false
    @AppStorage("auto_play_on_book_tap") private var autoPlay = false

    // View-level properties umgehen @State + @Observable dynamicMember-Bug
    private var downloadedCount: Int  { _viewModel.wrappedValue.downloadedCount }
    private var totalDuration: Double { _viewModel.wrappedValue.totalDuration }
    private var authorBooks: [Book]   { _viewModel.wrappedValue.authorBooks }

    init(viewModel: AuthorDetailViewModel) {
        _viewModel = State(initialValue: viewModel)
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
                    // Lokale Kopie umgeht ForEach-Binding-Ambiguität mit @State @Observable
                    let books = authorBooks
                    LazyVGrid(columns: DSGridColumns.two, spacing: DSLayout.contentGap) {
                        ForEach(books, id: \.id) { book in
                            let cardViewModel = BookCardViewModel(
                                book: book,
                                container: dependencies
                            )
                            BookCardView(
                                viewModel: cardViewModel,
                                api: dependencies.apiClient,
                                onTap: {
                                    Task { await viewModel.playBook(book, autoPlay: autoPlay) }
                                },
                                onDownload: {
                                    guard let api = dependencies.apiClient else { return }
                                    Task { await viewModel.downloadBook(book, api: api) }
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
        let downloaded = downloadedCount
        let duration   = totalDuration
        let numBooks   = viewModel.author.numBooks ?? 0

        return HStack(alignment: .center) {
            AuthorImageView(
                author: viewModel.author,
                api: dependencies.apiClient,
                size: DSLayout.smallAvatar
            )

            VStack(alignment: .leading, spacing: DSLayout.tightGap) {
                Text(viewModel.author.name)
                    .font(DSText.itemTitle)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if !authorBooks.isEmpty {
                    HStack(spacing: DSLayout.elementGap) {
                        Text("\(numBooks) \(numBooks == 1 ? "Book" : "Books")")

                        if downloaded > 0 {
                            Text(" • \(downloaded) downloaded")
                        }

                        if duration > 0 {
                            Text(" • \(TimeFormatter.formatTimeCompact(duration)) total")
                        }
                    }
                    .font(DSText.metadata)
                }
            }
            .layoutPriority(1)
            .padding(.leading, DSLayout.elementGap)

            Spacer()

            Button { dismiss() } label: {
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
