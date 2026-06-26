import Foundation
import SwiftUI
import Observation

@MainActor
@Observable
class LibraryViewModel {
    // MARK: - UI State
    var books: [Book] = []
    var filterState = LibraryFilterState()
    var isLoading = false
    var errorMessage: String?
    var showingErrorAlert = false
    var currentLibrary: Library?

    // For smooth transitions
    var contentLoaded = false

    // MARK: - Dependencies (alle Domain-Layer Protocols)
    private let fetchBooksUseCase: FetchBooksUseCaseProtocol
    private let playBookUseCase: PlayBookUseCaseProtocol
    private let libraryRepository: LibraryRepositoryProtocol
    private let coverPreloadService: CoverPreloadServiceProtocol
    private let downloadManager: DownloadManager // bleibt für filteredAndSortedBooks

    let appState: AppStateManager
    let onBookSelected: () -> Void

    // MARK: - Computed Properties
    var libraryName: String {
        currentLibrary?.name ?? "Library"
    }

    var filteredAndSortedBooks: [Book] {
        let filtered = books.filter { filterState.matches(book: $0, downloadManager: downloadManager) }
        return filterState.applySorting(to: filtered)
    }

    var totalBooksCount: Int { books.count }

    var downloadedBooksCount: Int { downloadManager.downloadedBooks.count }

    // MARK: - Init
    init(
        fetchBooksUseCase: FetchBooksUseCaseProtocol,
        playBookUseCase: PlayBookUseCaseProtocol,
        libraryRepository: LibraryRepositoryProtocol,
        coverPreloadService: CoverPreloadServiceProtocol,
        downloadManager: DownloadManager,
        appState: AppStateManager,
        onBookSelected: @escaping () -> Void
    ) {
        self.fetchBooksUseCase = fetchBooksUseCase
        self.playBookUseCase = playBookUseCase
        self.libraryRepository = libraryRepository
        self.coverPreloadService = coverPreloadService
        self.downloadManager = downloadManager
        self.appState = appState
        self.onBookSelected = onBookSelected
    }

    // MARK: - Actions
    func loadBooksIfNeeded() async {
        if books.isEmpty { await loadBooks() }
    }

    func loadBooks() async {
        isLoading = true
        errorMessage = nil

        do {
            guard let selectedLibrary = try await libraryRepository.getSelectedLibrary() else {
                books = []
                currentLibrary = nil
                isLoading = false
                return
            }

            currentLibrary = selectedLibrary

            let fetchedBooks = try await fetchBooksUseCase.execute(
                libraryId: selectedLibrary.id,
                collapseSeries: false
            )

            withAnimation(.easeInOut) {
                books = fetchedBooks
            }

            coverPreloadService.preloadCovers(for: Array(fetchedBooks.prefix(20)), limit: 20)

        } catch let error as RepositoryError {
            handleRepositoryError(error)
        } catch {
            errorMessage = error.localizedDescription
            showingErrorAlert = true
        }

        isLoading = false
    }

    func playBook(_ book: Book, restoreState: Bool = true, autoPlay: Bool = false) async {
        do {
            try await playBookUseCase.execute(
                book: book,
                restoreState: restoreState,
                autoPlay: autoPlay
            )
            onBookSelected()
        } catch {
            errorMessage = error.localizedDescription
            showingErrorAlert = true
        }
    }

    // MARK: - Filters
    func toggleDownloadFilter() {
        withAnimation { filterState.showDownloadedOnly.toggle() }
    }

    func toggleSeriesMode() {
        withAnimation { filterState.showSeriesGrouped.toggle() }
    }

    func resetFilters() { filterState.reset() }

    // MARK: - Private
    private func handleRepositoryError(_ error: RepositoryError) {
        errorMessage = error.localizedDescription
        showingErrorAlert = true
        AppLogger.general.debug("[LibraryViewModel] Repository error: \(error)")
    }
}

// MARK: - Placeholder
extension LibraryViewModel {
    @MainActor
    static var placeholder: LibraryViewModel {
        let api = AudiobookshelfClient(baseURL: "", authToken: "")
        let downloadManager = DownloadManager()
        return LibraryViewModel(
            fetchBooksUseCase: FetchBooksUseCase(bookRepository: BookRepository.placeholder),
            playBookUseCase: PlayBookUseCase(
                metadataService: BookMetadataService(api: api, downloadManager: downloadManager),
                playbackService: PlaybackService(player: AudioPlayer(), api: api),
                downloadManager: downloadManager,
                appState: AppStateManager.shared
            ),
            libraryRepository: LibraryRepository.placeholder,
            coverPreloadService: CoverPreloadService.placeholder,
            downloadManager: downloadManager,
            appState: AppStateManager.shared,
            onBookSelected: {}
        )
    }
}
