import SwiftUI

@MainActor
class LibraryViewModel: ObservableObject {
    // MARK: - Published UI State
    @Published var books: [Book] = []
    @Published var filterState = LibraryFilterState()
    @Published var libraryName: String = "Library"
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showingErrorAlert = false
    
    // For smooth transistions
    @Published var contentLoaded = false
   
    private var hasLoadedOnce = false

    // MARK: - Dependencies (Use Cases & Repositories)
    private let fetchBooksUseCase: FetchBooksUseCaseProtocol
    private let playBookUseCase: PlayBookUseCase
    private let downloadRepository: DownloadRepository
    private let libraryRepository: LibraryRepositoryProtocol
    
    let api: AudiobookshelfClient
    let downloadManager: DownloadManager
    let player: AudioPlayer
    let appState: AppStateManager
    let onBookSelected: () -> Void
    
    // MARK: - Computed Properties for UI
    var filteredAndSortedBooks: [Book] {
        let searchFiltered = books.filter { filterState.matchesSearchFilter($0) }
        
        let downloadFiltered = searchFiltered.filter { book in
            filterState.matchesDownloadFilter(
                book,
                isDownloaded: downloadRepository.getDownloadStatus(for: book.id).isDownloaded
            )
        }
        
        return filterState.applySorting(to: downloadFiltered)
    }
    
    var downloadedBooksCount: Int {
        books.filter { downloadRepository.getDownloadStatus(for: $0.id).isDownloaded }.count
    }
    
    var totalBooksCount: Int {
        books.count
    }
    
    var seriesCount: Int {
        books.filter { $0.isCollapsedSeries }.count
    }
    
    var individualBooksCount: Int {
        books.filter { !$0.isCollapsedSeries }.count
    }
    
    // MARK: - Init with DI
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
        self.playBookUseCase = PlayBookUseCase()
        self.downloadRepository = downloadRepository
        self.libraryRepository = libraryRepository
        self.api = api
        self.downloadManager = downloadManager
        self.player = player
        self.appState = appState
        self.onBookSelected = onBookSelected
        
        filterState.loadFromDefaults()
        
        Task {
            await loadBooksIfNeeded()
        }

    }
    
    // MARK: - Actions (Delegate to Use Cases)
    /// Load books only if not already loaded
    func loadBooksIfNeeded() async {
        guard !hasLoadedOnce && !isLoading else { return }
        await loadBooks()
    }
    
    func loadBooks() async {
        isLoading = true
        errorMessage = nil
        
        do {
            guard let library = try await libraryRepository.getSelectedLibrary() else {
                books = []
                isLoading = false
                return
            }
            
            // Try network fetch
            let fetchedBooks = try await fetchBooksUseCase.execute(
                libraryId: library.id,
                collapseSeries: filterState.showSeriesGrouped  // ← DIFFERENT: collapseSeries param
            )
            
            withAnimation(.easeInOut) {
                books = fetchedBooks
            }
            
            CoverPreloadHelpers.preloadIfNeeded(
                books: fetchedBooks,
                api: api,
                downloadManager: downloadManager,
                limit: 10
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
        autoPlay: Bool = false,
    ) async {
        isLoading = true
        
        do {
            try await playBookUseCase.execute(
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
        
        isLoading = false
    }
    
    // MARK: - Filter Management (UI State Changes)
    func toggleSeriesMode() {
        withAnimation(.easeInOut(duration: 0.2)) {
            filterState.showSeriesGrouped.toggle()
        }
        
        filterState.saveToDefaults()
        
        Task {
            await loadBooks()
        }
    }
    
    func toggleDownloadFilter() {
        withAnimation(.easeInOut(duration: 0.2)) {
            filterState.showDownloadedOnly.toggle()
        }
        filterState.saveToDefaults()
    }
    
    func resetFilters() {
        withAnimation(.easeInOut(duration: 0.2)) {
            filterState.reset()
        }
        
        Task {
            await loadBooks()
        }
    }
    
    // MARK: - Error Handling
    private func handleRepositoryError(_ error: RepositoryError) {
        switch error {
        case .networkError(let urlError as URLError):
            switch urlError.code {
            case .timedOut:
                errorMessage = "Connection timed out. Your library might be very large. Try again or check your network."
            case .notConnectedToInternet:
                errorMessage = "No internet connection. Please check your network settings."
            case .cannotFindHost:
                errorMessage = "Cannot reach server. Please verify your server address in settings."
            default:
                errorMessage = "Network error: \(urlError.localizedDescription)"
            }
            
        case .decodingError:
            errorMessage = """
            Failed to load library data.
            
            Some books couldn't be loaded due to data format issues.
            Please contact your Audiobookshelf administrator.
            """
            
        case .notFound:
            errorMessage = "Library not found"
            
        case .invalidData:
            errorMessage = "Invalid library data"
            
        case .unauthorized:
            errorMessage = "Authentication required. Please login again."
            
        case .serverError(let code):
            errorMessage = "Server error (code: \(code)). Please try again later."
            
        default:
            errorMessage = error.localizedDescription
        }
        
        showingErrorAlert = true
        AppLogger.general.debug("[LibraryViewModel] Repository error: \(error)")
    }
}
