import SwiftUI
import Observation

@MainActor
@Observable
class SeriesViewModel {
    // MARK: - UI State
    var series: [Series] = []
    var filterState = SeriesFilterState()
    var isLoading = false
    var errorMessage: String?
    var showingErrorAlert = false

    // For smooth transitions
    var contentLoaded = false

    // MARK: - Dependencies (Domain Layer Protocols)
    private let bookRepository: any BookRepositoryProtocol
    private let playBookUseCase: any PlayBookUseCaseProtocol
    private let libraryRepository: any LibraryRepositoryProtocol

    let appState: AppStateManager
    let onBookSelected: () -> Void

    // MARK: - Computed Properties
    var filteredAndSortedSeries: [Series] {
        let filtered = series.filter { filterState.matchesSearchFilter($0) }
        return filterState.applySorting(to: filtered)
    }

    // MARK: - Init
    init(
        bookRepository: any BookRepositoryProtocol,
        playBookUseCase: any PlayBookUseCaseProtocol,
        libraryRepository: any LibraryRepositoryProtocol,
        appState: AppStateManager,
        onBookSelected: @escaping () -> Void
    ) {
        self.bookRepository = bookRepository
        self.playBookUseCase = playBookUseCase
        self.libraryRepository = libraryRepository
        self.appState = appState
        self.onBookSelected = onBookSelected
    }

    // MARK: - Actions
    func loadSeriesIfNeeded() async {
        if series.isEmpty { await loadSeries() }
    }

    func loadSeries() async {
        isLoading = true
        errorMessage = nil

        do {
            guard let selectedLibrary = try await libraryRepository.getSelectedLibrary() else {
                series = []
                isLoading = false
                return
            }

            let fetchedSeries = try await bookRepository.fetchSeries(libraryId: selectedLibrary.id)

            withAnimation(.easeInOut) {
                series = fetchedSeries
            }

        } catch let error as RepositoryError {
            handleRepositoryError(error)
        } catch {
            errorMessage = error.localizedDescription
            showingErrorAlert = true
        }

        isLoading = false
    }

    func playBook(_ book: Book, restoreState: Bool = true, autoPlay: Bool = false) async {
        isLoading = true
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
        isLoading = false
    }

    // MARK: - Private
    private func handleRepositoryError(_ error: RepositoryError) {
        errorMessage = error.localizedDescription
        showingErrorAlert = true
        AppLogger.general.debug("[SeriesViewModel] Repository error: \(error)")
    }
}
