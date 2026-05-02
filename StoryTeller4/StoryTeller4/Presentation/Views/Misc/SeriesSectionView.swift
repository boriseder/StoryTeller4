import SwiftUI

struct SeriesSectionView: View {
    @State private var viewModel: SeriesSectionViewModel

    @Environment(DependencyContainer.self) private var dependencies

    init(series: Series, api: AudiobookshelfClient, onBookSelected: @escaping (Book) -> Void) {
        // Player and downloadManager are read from the environment at body time.
        // We can't access @Environment in init, so we use a temporary AudioPlayer()
        // and DownloadManager() — these are immediately replaced in .task below
        // before any playback or download action can be triggered.
        //
        // The books list is populated synchronously from series.books in the
        // ViewModel init, so nothing depends on player/downloadManager at init time.
        self._viewModel = State(initialValue: SeriesSectionViewModel(
            series: series,
            api: api,
            onBookSelected: onBookSelected,
            player: AudioPlayer(),
            downloadManager: DownloadManager()
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(viewModel.series.name)
                .font(DSText.itemTitle)
                .padding(.horizontal, DSLayout.tightPadding)

            if viewModel.books.isEmpty {
                emptyView
            } else {
                booksScrollView
            }
        }
        .task {
            // Replace the placeholder dependencies with the real ones from the
            // environment. This runs before the user can interact with any
            // book card, so player/downloadManager are always valid by then.
            viewModel.updateDependencies(
                player: dependencies.player,
                downloadManager: dependencies.downloadManager
            )
        }
    }

    private var booksScrollView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 16) {
                ForEach(viewModel.books) { book in
                    BookCardView(
                        viewModel: BookCardViewModel(book: book, container: dependencies),
                        api: viewModel.api,
                        onTap: { viewModel.onBookSelected(book) },
                        onDownload: {
                            Task {
                                await viewModel.downloadManager.downloadBook(book, api: viewModel.api)
                            }
                        },
                        onDelete: { viewModel.downloadManager.deleteBook(book.id) }
                    )
                }
            }
        }
    }

    private var emptyView: some View {
        Text("No books in this series")
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity)
            .padding()
    }
}
