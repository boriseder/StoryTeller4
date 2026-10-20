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

    // MARK: - Dependencies (Domain Layer Protocols)
    private let bookRepository: any BookRepositoryProtocol
    private let playBookUseCase: any PlayBookUseCaseProtocol
    private let libraryRepository: any LibraryRepositoryProtocol
    private let coverPreloadService: any CoverPreloadServiceProtocol
    private let downloadManager: DownloadManager

    let appState: AppStateManager
    let onBookSelected: () -> Void

    // MARK: - Computed Properties
    var libraryName: String {
        currentLibrary?.name ?? "Library"
    }

    var filteredAndSortedBooks: [Book] {
        let isOffline = !appState.isDeviceOnline || !appState.isServerReachable
        let filtered = books.filter { book in
            if isOffline {
                return downloadManager.isBookDownloaded(book.id)
            }
            return filterState.matches(book: book, downloadManager: downloadManager)
        }
        return filterState.applySorting(to: filtered)
    }

    var totalBooksCount: Int { books.count }

    var downloadedBooksCount: Int { downloadManager.downloadedBooks.count }

    // MARK: - Init
    init(
        bookRepository: any BookRepositoryProtocol,
        playBookUseCase: any PlayBookUseCaseProtocol,
        libraryRepository: any LibraryRepositoryProtocol,
        coverPreloadService: any CoverPreloadServiceProtocol,
        downloadManager: DownloadManager,
        appState: AppStateManager,
        onBookSelected: @escaping () -> Void
    ) {
        self.bookRepository = bookRepository
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

            let fetchedBooks = try await bookRepository.fetchBooks(
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
        withAnimation { 
            filterState.showDownloadedOnly.toggle() 
            filterState.saveToDefaults()
        }
    }

    func toggleSeriesMode() {
        withAnimation { 
            filterState.showSeriesGrouped.toggle() 
            filterState.saveToDefaults()
        }
    }

    func toggleSeriesOnlyFilter() {
        withAnimation { 
            filterState.showSeriesOnly.toggle() 
            filterState.saveToDefaults()
        }
    }

    func resetFilters() { filterState.reset() }

    // MARK: - Private
    private func handleRepositoryError(_ error: RepositoryError) {
        errorMessage = error.localizedDescription
        showingErrorAlert = true
        AppLogger.general.debug("[LibraryViewModel] Repository error: \(error)")
    }
}
