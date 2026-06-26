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

    // DependencyContainer bleibt vorerst – separater Befund, nicht in scope
    private let container: DependencyContainer

    var player: AudioPlayer              { container.player }
    var downloadManager: DownloadManager { container.downloadManager }

    var downloadedCount: Int {
        seriesBooks.filter { downloadManager.isBookDownloaded($0.id) }.count
    }
    private var coverPreloadService: CoverPreloadServiceProtocol? {
        guard let api = container.apiClient else { return nil }
        return CoverPreloadService(api: api, downloadManager: container.downloadManager)
    }

    private var libraryRepository: LibraryRepositoryProtocol? { container.libraryRepository }

    private let fetchSeriesBooksUseCase: FetchSeriesBooksUseCaseProtocol
    private let playBookUseCase: PlayBookUseCaseProtocol

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

        let bookRepository = container.bookRepository
            ?? BookRepository(api: AudiobookshelfClient(baseURL: "", authToken: ""))
        self.fetchSeriesBooksUseCase = FetchSeriesBooksUseCase(bookRepository: bookRepository)
        self.playBookUseCase = container.services.makePlayBookUseCase(
            api: container.apiClient ?? AudiobookshelfClient(baseURL: "", authToken: "")
        )
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

        let bookRepository = container.bookRepository
            ?? BookRepository(api: AudiobookshelfClient(baseURL: "", authToken: ""))
        self.fetchSeriesBooksUseCase = FetchSeriesBooksUseCase(bookRepository: bookRepository)
        self.playBookUseCase = container.services.makePlayBookUseCase(
            api: container.apiClient ?? AudiobookshelfClient(baseURL: "", authToken: "")
        )
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

            coverPreloadService?.preloadCovers(for: books, limit: books.count)

        } catch {
            errorMessage = error.localizedDescription
            showingErrorAlert = true
        }

        isLoading = false
    }

    func playBook(_ book: Book, appState: AppStateManager) async {
        isLoading = true
        do {
            try await playBookUseCase.execute(book: book, restoreState: true, autoPlay: false)
            onDismiss?()
            onBookSelected()
        } catch {
            errorMessage = error.localizedDescription
            showingErrorAlert = true
        }
        isLoading = false
    }

    func downloadBook(_ book: Book) async {
        guard let api = container.apiClient else { return }
        await downloadManager.downloadBook(book, api: api)
    }

    func deleteBook(_ bookId: String) {
        downloadManager.deleteBook(bookId)
    }
}
