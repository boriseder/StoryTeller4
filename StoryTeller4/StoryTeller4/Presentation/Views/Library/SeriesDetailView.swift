import SwiftUI

struct SeriesDetailView: View {
    @StateObject private var viewModel: SeriesDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppStateManager
    @EnvironmentObject private var dependencies: DependencyContainer

    init(series: Series, onBookSelected: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: SeriesDetailViewModel(
            series: series,
            container: .shared,
            onBookSelected: onBookSelected
        ))
    }
    
    init(seriesBook: Book, onBookSelected: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: SeriesDetailViewModel(
            seriesBook: seriesBook,
            container: .shared,
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
                    HStack(spacing: DSLayout.elementGap) {
                        Text("\(viewModel.seriesBooks.count) books")
                        
                        if viewModel.downloadedCount > 0 {
                            Text("• \(viewModel.downloadedCount) downloaded")
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
            
            Button {
                dismiss()
            } label: {
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
                ForEach(viewModel.seriesBooks, id: \.id) { book in
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
        }
    }
}
