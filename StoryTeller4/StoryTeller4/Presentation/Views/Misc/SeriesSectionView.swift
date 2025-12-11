import SwiftUI

struct SeriesSectionView: View {
    // FIX: Use @State for @Observable view model
    @State private var viewModel: SeriesSectionViewModel
    @EnvironmentObject private var dependencies: DependencyContainer

    // NOTE: Preserving the correct closure signature (Book) -> Void from previous fix
    init(series: Series, api: AudiobookshelfClient, onBookSelected: @escaping (Book) -> Void) {
        // FIX: Initialize with State(initialValue:)
        self._viewModel = State(initialValue: SeriesSectionViewModel(
            series: series,
            api: api,
            onBookSelected: onBookSelected,
            container: .shared
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
            // Update container reference
            viewModel.container = dependencies
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
                        onDownload: { Task { await viewModel.downloadManager.downloadBook(book, api: viewModel.api) } },
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
