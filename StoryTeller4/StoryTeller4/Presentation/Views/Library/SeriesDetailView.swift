import SwiftUI

struct SeriesDetailView: View {
    @State private var viewModel: SeriesDetailViewModel
    @Environment(\.dismiss) private var dismiss

    @Environment(AppStateManager.self) private var appState
    @Environment(DependencyContainer.self) private var dependencies

    // Computed property auf View-Ebene – außerhalb jedes @ViewBuilder-Kontexts.
    // Das umgeht das Swift/SwiftUI Bug mit @Observable + @State + dynamicMember in ViewBuilder.
    private var downloadedCount: Int { _viewModel.wrappedValue.downloadedCount }
    private var seriesBookCount: Int  { _viewModel.wrappedValue.seriesBooks.count }

    init(series: Series, container: DependencyContainer, onBookSelected: @escaping () -> Void) {
        _viewModel = State(initialValue: SeriesDetailViewModel(
            series: series,
            container: container,
            onBookSelected: onBookSelected
        ))
    }

    init(seriesBook: Book, container: DependencyContainer, onBookSelected: @escaping () -> Void) {
        _viewModel = State(initialValue: SeriesDetailViewModel(
            seriesBook: seriesBook,
            container: container,
            onBookSelected: onBookSelected
        ))
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: DSLayout.contentGap) {
                seriesHeaderView
                Divider()
                booksGridView
            }
            .navigationTitle("")
            .navigationBarHidden(true)
            .task {
                viewModel.onDismiss = { dismiss() }
                await viewModel.loadSeriesBooks()
            }
        }
    }

    private var seriesHeaderView: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.seriesName)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .lineLimit(2)

                if !viewModel.seriesBooks.isEmpty {
                    let bookCount = seriesBookCount
                    let downloaded = downloadedCount
                    HStack(spacing: DSLayout.elementGap) {
                        Text("\(bookCount) books")

                        if downloaded > 0 {
                            Text("• \(downloaded) downloaded")
                        }

                        if let duration = viewModel.seriesTotalDuration {
                            Text("• \(duration)")
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
            .layoutPriority(1)

            Spacer()

            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DSLayout.screenPadding)
        .padding(.top, DSLayout.comfortPadding)
    }

    private var booksGridView: some View {
        ScrollView {
            LazyVGrid(columns: DSGridColumns.two, spacing: 0) {
                // ForEach über Array-Value, kein Binding
                ForEach(viewModel.seriesBooks, id: \.id) { book in
                    let cardViewModel = BookCardViewModel(book: book, container: dependencies)
                    BookCardView(
                        viewModel: cardViewModel,
                        api: dependencies.apiClient,
                        onTap: {
                            Task { await viewModel.playBook(book, appState: appState) }
                        },
                        onDownload: {
                            Task { await viewModel.downloadBook(book) }
                        },
                        onDelete: {
                            viewModel.deleteBook(book.id)
                        }
                    )
                }
            }
            .padding(.horizontal, DSLayout.contentPadding)
        }
    }
}
