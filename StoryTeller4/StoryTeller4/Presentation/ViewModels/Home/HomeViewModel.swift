import SwiftUI
import Observation

@MainActor
@Observable
class HomeViewModel {
    // MARK: - UI State
    var personalizedSections: [PersonalizedSection] = []
    var libraryName: String = "Personalized"
    var totalBooksInLibrary: Int = 0
    var isLoading = false
    var errorMessage: String?
    var showingErrorAlert = false

    // For smooth transistions
    var contentLoaded = false
    var sectionsLoaded = false
    
    // MARK: - Dependencies
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

    // MARK: - Computed Properties
    var totalItemsCount: Int {
        totalBooksInLibrary
    }
    
    var downloadedCount: Int {
        downloadRepository.getDownloadedBooks().count
    }

    // MARK: - Init
    init(
        fetchPersonalizedSectionsUseCase: FetchPersonalizedSectionsUseCaseProtocol,
        downloadRepository: DownloadRepository,
        libraryRepository: LibraryRepositoryProtocol,
        bookRepository: BookRepositoryProtocol,
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
        self.bookRepository = bookRepository
        self.api = api
        self.downloadManager = downloadManager
        self.player = player
        self.appState = appState
        self.onBookSelected = onBookSelected
    }
     
    // MARK: - Actions
    func loadPersonalizedSectionsIfNeeded() async {
        guard appState.isServerReachable else { return }

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
                        
            async let sectionsTask = fetchPersonalizedSectionsUseCase.execute(libraryId: selectedLibrary.id)
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

// MARK: - Placeholder
extension HomeViewModel {
    @MainActor
    static var placeholder: HomeViewModel {
        HomeViewModel(
            fetchPersonalizedSectionsUseCase: FetchPersonalizedSectionsUseCase(bookRepository: BookRepository.placeholder),
            downloadRepository: DefaultDownloadRepository.placeholder,
            libraryRepository: LibraryRepository.placeholder,
            bookRepository: BookRepository.placeholder,
            api: AudiobookshelfClient(baseURL: "", authToken: ""),
            downloadManager: DownloadManager(),
            player: AudioPlayer(),
            appState: AppStateManager.shared,
            onBookSelected: {}
        )
    }
}
