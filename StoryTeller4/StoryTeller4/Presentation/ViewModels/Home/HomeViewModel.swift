import SwiftUI

@MainActor
class HomeViewModel: ObservableObject {
    // MARK: - Published UI State
    @Published var personalizedSections: [PersonalizedSection] = []
    @Published var libraryName: String = "Personalized"
    @Published var totalBooksInLibrary: Int = 0
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showingErrorAlert = false

    // For smooth transistions
    @Published var contentLoaded = false
    @Published var sectionsLoaded = false
    
    // MARK: - Dependencies (Use Cases & Repositories)
    private let fetchPersonalizedSectionsUseCase: FetchPersonalizedSectionsUseCaseProtocol
    private let playBookUseCase: PlayBookUseCase
    private let downloadRepository: DownloadRepository
    private let libraryRepository: LibraryRepositoryProtocol
    private let bookRepository: BookRepositoryProtocol

    let api: AudiobookshelfClient
    let downloadManager: DownloadManager
    let player: AudioPlayer
    let appState: AppStateManager
    let onBookSelected: () -> Void

    // MARK: - Computed Properties for UI
    var totalItemsCount: Int {
        totalBooksInLibrary
    }
    
    var downloadedCount: Int {
        //let allBooks = getAllBooksFromSections()
        // we do not want the number of downloaded books in personalized sections but all downloaded books
        // return allBooks.filter { downloadRepository.getDownloadStatus(for: $0.id).isDownloaded }.count
        return downloadRepository.getDownloadedBooks().count
    }

    // MARK: - Init with DI
    init(
        fetchPersonalizedSectionsUseCase: FetchPersonalizedSectionsUseCaseProtocol,
        downloadRepository: DownloadRepository,
        libraryRepository: LibraryRepositoryProtocol,
        bookRepository: BookRepositoryProtocol,  // ADD THIS
        api: AudiobookshelfClient,
        downloadManager: DownloadManager,
        player: AudioPlayer,
        appState: AppStateManager,
        onBookSelected: @escaping () -> Void
    ) {
        self.fetchPersonalizedSectionsUseCase = fetchPersonalizedSectionsUseCase
        self.playBookUseCase = PlayBookUseCase()
        self.downloadRepository = downloadRepository
        self.libraryRepository = libraryRepository
        self.bookRepository = bookRepository  // ADD THIS
        self.api = api
        self.downloadManager = downloadManager
        self.player = player
        self.appState = appState
        self.onBookSelected = onBookSelected
    }
     
    // MARK: - Actions (Delegate to Use Cases)
    func loadPersonalizedSectionsIfNeeded() async {
        //only load data if network is actually working
        guard appState.isServerReachable else {
            return
        }

        if personalizedSections.isEmpty {
            await loadPersonalizedSections()
        }
    }
    
    func loadPersonalizedSections() async {
        
        isLoading = true
        errorMessage = nil
        
        do {
            guard let selectedLibrary = try await libraryRepository.getSelectedLibrary() else {
                personalizedSections = []
                totalBooksInLibrary = 0
                isLoading = false
                return
            }
                        
            // Fetch sections and stats in parallel
            async let sectionsTask = fetchPersonalizedSectionsUseCase.execute(
                libraryId: selectedLibrary.id
            )
            async let statsTask = api.libraries.fetchLibraryStats(libraryId: selectedLibrary.id)
            
            let (fetchedSections, totalBooks) = try await (sectionsTask, statsTask)
                        
            withAnimation(.easeInOut) {
                personalizedSections = fetchedSections
                totalBooksInLibrary = totalBooks
            }
            
            CoverPreloadHelpers.preloadIfNeeded(
                books: getAllBooksFromSections(),
                api: api,
                downloadManager: downloadManager,
                limit: 10
            )
            
        } catch let error as RepositoryError {
            // On error, check if we have cached data from previous successful load
                errorMessage = error.localizedDescription
                showingErrorAlert = true
                AppLogger.general.debug("[HomeViewModel] Repository error: \(error)")
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
    
    func loadSeriesBooks(_ series: Series, appState: AppStateManager) async {
        AppLogger.general.debug("Loading series: \(series.name)")
        
        do {
            guard let library = try await libraryRepository.getSelectedLibrary() else {
                errorMessage = "No library selected"
                showingErrorAlert = true
                return
            }
            
           // let bookRepository = BookRepository(api: api, cache: BookCache())
            let seriesBooks = try await bookRepository.fetchSeriesBooks(
                libraryId: library.id,
                seriesId: series.id
            )

            if let firstBook = seriesBooks.first {
                await playBook(firstBook, appState: appState)
            }
            
        } catch {
            errorMessage = "Could not load series '\(series.name)': \(error.localizedDescription)"
            showingErrorAlert = true
            AppLogger.general.debug("Error loading series: \(error)")
        }
    }
   /*
    func searchBooksByAuthor(_ authorName: String, appState: AppStateManager) async {
        AppLogger.general.debug("Searching books by author: \(authorName)")
        
        do {
            guard let library = try await libraryRepository.getSelectedLibrary() else {
                errorMessage = "No library selected"
                showingErrorAlert = true
                return
            }
            
            //let bookRepository = BookRepository(api: api, cache: BookCache())
            let allBooks = try await bookRepository.fetchBooks(
                libraryId: library.id,
                collapseSeries: false
            )
            
            let authorBooks = allBooks.filter { book in
                book.author?.localizedCaseInsensitiveContains(authorName) == true
            }
            
            if let firstBook = authorBooks.first {
                await playBook(firstBook, appState: appState)
            } else {
                errorMessage = "No books found by '\(authorName)'"
                showingErrorAlert = true
            }
            
        } catch {
            errorMessage = "Could not search books by '\(authorName)': \(error.localizedDescription)"
            showingErrorAlert = true
            AppLogger.general.debug("Error searching books by author: \(error)")
        }
    }
    */
    // MARK: - Private Helpers
    private func getAllBooksFromSections() -> [Book] {
        var allBooks: [Book] = []
        
        for section in personalizedSections {
            let sectionBooks = section.entities
                .compactMap { $0.asLibraryItem }
                .compactMap { api.converter.convertLibraryItemToBook($0) }
            
            allBooks.append(contentsOf: sectionBooks)
        }
        
        return allBooks
    }
}

