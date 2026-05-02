import SwiftUI
import Observation

@MainActor
@Observable
class SeriesDetailViewModel {
    var seriesBooks: [Book] = []
    var isLoading = false
    var errorMessage: String?
    var showingErrorAlert = false

    let seriesId: String
    let seriesName: String
    let seriesTotalDuration: String?
    let onBookSelected: () -> Void
    var onDismiss: (() -> Void)?

    private let container: DependencyContainer

    var player: AudioPlayer          { container.player }
    var downloadManager: DownloadManager { container.downloadManager }

    // libraryRepository is Optional on DependencyContainer now —
    // guard at the call site rather than force-unwrapping.
    private var libraryRepository: LibraryRepositoryProtocol? { container.libraryRepository }

    var api: AudiobookshelfClient {
        // Fall back to a placeholder client if called before login;
        // in practice SeriesDetailView is only reachable after .ready.
        container.apiClient ?? AudiobookshelfClient(baseURL: "", authToken: "")
    }

    var downloadedCount: Int {
        seriesBooks.filter { downloadManager.isBookDownloaded($0.id) }.count
    }

    private let fetchSeriesBooksUseCase: FetchSeriesBooksUseCaseProtocol
    private let playBookUseCase: PlayBookUseCase

    // MARK: - Init from Series

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
        self.fetchSeriesBooksUseCase = FetchSeriesBooksUseCase(
            api: container.apiClient ?? AudiobookshelfClient(baseURL: "", authToken: "")
        )
        self.playBookUseCase = PlayBookUseCase()
    }

    // MARK: - Init from collapsed-series Book

    init(
        seriesBook: Book,
        container: DependencyContainer,
        onBookSelected: @escaping () -> Void
    ) {
        guard let collapsedSeries = seriesBook.collapsedSeries else {
            fatalError("SeriesDetailViewModel(seriesBook:) requires a book with collapsedSeries")
        }
        self.seriesId = collapsedSeries.id
        self.seriesName = seriesBook.displayTitle
        self.seriesTotalDuration = nil
        self.container = container
        self.onBookSelected = onBookSelected
        self.fetchSeriesBooksUseCase = FetchSeriesBooksUseCase(
            api: container.apiClient ?? AudiobookshelfClient(baseURL: "", authToken: "")
        )
        self.playBookUseCase = PlayBookUseCase()
    }

    // MARK: - Actions

    func loadSeriesBooks() async {
        guard let libraryRepository else {
            errorMessage = "Not logged in — cannot load series"
            showingErrorAlert = true
            AppLogger.general.error("[SeriesDetailVM] libraryRepository is nil — API not configured yet")
            return
        }

        do {
            guard let library = try await libraryRepository.getSelectedLibrary() else {
                errorMessage = "No library selected"
                showingErrorAlert = true
                return
            }

            isLoading = true
            errorMessage = nil
            showingErrorAlert = false

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
