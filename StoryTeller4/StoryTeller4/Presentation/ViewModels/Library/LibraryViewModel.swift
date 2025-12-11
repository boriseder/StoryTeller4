import Foundation
import SwiftUI
import Observation

@MainActor
@Observable
class LibraryViewModel {
    // MARK: - Published Properties
    var books: [Book] = []
    var filterState = LibraryFilterState()
    var isLoading = false
    var errorMessage: String?
    var showingErrorAlert = false
    
    // FIX: Store the current library locally since Repository access is async
    var currentLibrary: Library?
    
    // For smooth transistions
    var contentLoaded = false
    
    // MARK: - Dependencies
    private let fetchBooksUseCase: FetchBooksUseCaseProtocol
    private let downloadRepository: DownloadRepository
    private let libraryRepository: LibraryRepositoryProtocol
    
    let api: AudiobookshelfClient
    let downloadManager: DownloadManager
    let player: AudioPlayer
    let appState: AppStateManager
    let onBookSelected: () -> Void
    
    // MARK: - Computed Properties
    var libraryName: String {
        currentLibrary?.name ?? "Library"
    }
    
    var filteredAndSortedBooks: [Book] {
        // FIX: Now matches() exists on LibraryFilterState
        let filtered = books.filter { filterState.matches(book: $0, downloadManager: downloadManager) }
        return filterState.applySorting(to: filtered)
    }
    
    var totalBooksCount: Int {
        books.count
    }
    
    var downloadedBooksCount: Int {
        downloadManager.downloadedBooks.count
    }
    
    // MARK: - Init
    init(
        fetchBooksUseCase: FetchBooksUseCaseProtocol,
        downloadRepository: DownloadRepository,
        libraryRepository: LibraryRepositoryProtocol,
        api: AudiobookshelfClient,
        downloadManager: DownloadManager,
        player: AudioPlayer,
        appState: AppStateManager,
        onBookSelected: @escaping () -> Void
    ) {
        self.fetchBooksUseCase = fetchBooksUseCase
        self.downloadRepository = downloadRepository
        self.libraryRepository = libraryRepository
        self.api = api
        self.downloadManager = downloadManager
        self.player = player
        self.appState = appState
        self.onBookSelected = onBookSelected
    }
    
    // MARK: - Actions
    func loadBooksIfNeeded() async {
        if books.isEmpty {
            await loadBooks()
        }
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
            
            // Update local state
            self.currentLibrary = selectedLibrary
            
            // Try network fetch
            let fetchedBooks = try await fetchBooksUseCase.execute(
                libraryId: selectedLibrary.id,
                collapseSeries: false
            )
            
            withAnimation(.easeInOut) {
                books = fetchedBooks
            }
            
            // Preload covers for visible books (first 20)
            CoverPreloadHelpers.preloadIfNeeded(
                books: Array(fetchedBooks.prefix(20)),
                api: api,
                downloadManager: downloadManager
            )
            
        } catch let error as RepositoryError {
            handleRepositoryError(error)
        } catch {
            errorMessage = error.localizedDescription
            showingErrorAlert = true
        }
        
        isLoading = false
    }
    
    func playBook(
        _ book: Book,
        appState: AppStateManager,
        restoreState: Bool = true,
        autoPlay: Bool = false
    ) async {
        do {
            let playUseCase = PlayBookUseCase()
            try await playUseCase.execute(
                book: book,
                api: api,
                player: player,
                downloadManager: downloadManager,
                appState: appState,
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
        }
    }
    
    func toggleSeriesMode() {
        withAnimation {
            filterState.showSeriesGrouped.toggle()
        }
    }
    
    func resetFilters() {
        filterState.reset()
    }
    
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
        LibraryViewModel(
            fetchBooksUseCase: FetchBooksUseCase(bookRepository: BookRepository.placeholder),
            downloadRepository: DefaultDownloadRepository.placeholder,
            libraryRepository: LibraryRepository.placeholder,
            api: AudiobookshelfClient(baseURL: "http://placeholder", authToken: ""),
            downloadManager: DownloadManager(),
            player: AudioPlayer(),
            appState: AppStateManager.shared,
            onBookSelected: {}
        )
    }
}
