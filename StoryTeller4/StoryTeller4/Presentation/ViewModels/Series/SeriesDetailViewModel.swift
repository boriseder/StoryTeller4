
import SwiftUI

@MainActor
class SeriesDetailViewModel: ObservableObject {
    @Published var seriesBooks: [Book] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showingErrorAlert = false
    
    let seriesId: String
    let seriesName: String
    let seriesTotalDuration: String?
    let onBookSelected: () -> Void
    var onDismiss: (() -> Void)?
    
    private let container: DependencyContainer
    
    var player: AudioPlayer { container.player }
    var api: AudiobookshelfClient { container.apiClient! }
    var downloadManager: DownloadManager { container.downloadManager }
    var libraryRepository: LibraryRepositoryProtocol { container.libraryRepository }

    var downloadedCount: Int {
        seriesBooks.filter { downloadManager.isBookDownloaded($0.id) }.count
    }
    
    private let fetchSeriesBooksUseCase: FetchSeriesBooksUseCaseProtocol
    private let playBookUseCase: PlayBookUseCase
    
    init(
        series: Series,
        container: DependencyContainer,
        onBookSelected: @escaping () -> Void
    ) {
        self.seriesId = series.id
        self.seriesName = series.name
        self.seriesTotalDuration = series.formattedDuration
        self.container = container
        self.onBookSelected = onBookSelected
        
        self.fetchSeriesBooksUseCase = FetchSeriesBooksUseCase(api: container.apiClient!)
        self.playBookUseCase = PlayBookUseCase()
    }
    
    init(
        seriesBook: Book,
        container: DependencyContainer,
        onBookSelected: @escaping () -> Void
    ) {
        guard let collapsedSeries = seriesBook.collapsedSeries else {
            fatalError("Book must have collapsedSeries")
        }
        
        self.seriesId = collapsedSeries.id
        self.seriesName = seriesBook.displayTitle
        self.seriesTotalDuration = nil
        self.container = container
        self.onBookSelected = onBookSelected
        
        self.fetchSeriesBooksUseCase = FetchSeriesBooksUseCase(api: container.apiClient!)
        self.playBookUseCase = PlayBookUseCase()
    }
    
    func loadSeriesBooks() async {
        do {
            // Try to get the selected library
            guard let library = try await libraryRepository.getSelectedLibrary() else {
                errorMessage = "Library not found"
                showingErrorAlert = true
                return
            }

            isLoading = true
            errorMessage = nil
            showingErrorAlert = false

            // Fetch books using library.id
            let books = try await fetchSeriesBooksUseCase.execute(
                libraryId: library.id,
                seriesId: seriesId
            )

            withAnimation(.easeInOut(duration: 0.3)) {
                seriesBooks = books
            }

            CoverPreloadHelpers.preloadIfNeeded(
                books: books,
                api: api,
                downloadManager: downloadManager
            )
        } catch {
            // Handle any errors thrown by getSelectedLibrary() or execute()
            errorMessage = error.localizedDescription
            showingErrorAlert = true
        }

        isLoading = false
    }
    
    func playBook(_ book: Book, appState: AppStateManager) async {
        isLoading = true
        
        do {
            try await playBookUseCase.execute(
                book: book,
                api: api,
                player: player,
                downloadManager: downloadManager,
                appState: appState,
                restoreState: true
            )
            onDismiss?()
            onBookSelected()
        } catch {
            errorMessage = error.localizedDescription
            showingErrorAlert = true
        }
        
        isLoading = false
    }
    
    func downloadBook(_ book: Book) async {
        await downloadManager.downloadBook(book, api: api)
    }
    
    func deleteBook(_ bookId: String) {
        downloadManager.deleteBook(bookId)
    }
}
