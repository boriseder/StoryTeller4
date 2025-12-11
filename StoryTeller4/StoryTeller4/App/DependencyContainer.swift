import Foundation
import SwiftUI
import Combine

// Error types for dependency resolution failures
enum DependencyError: Error {
    case apiNotConfigured
    case repositoryNotInitialized(String)
    
    var localizedDescription: String {
        switch self {
        case .apiNotConfigured:
            return "API client must be configured before accessing dependencies"
        case .repositoryNotInitialized(let name):
            return "\(name) repository not initialized"
        }
    }
}

// Main container responsible for creating and vending dependencies
// Marked as MainActor to ensure thread safety for UI-related components
@MainActor
final class DependencyContainer: ObservableObject {

    // Singleton instance for global access where environment injection isn't possible
    static let shared = DependencyContainer()

    // Publishes changes when the configuration status updates
    @Published private(set) var isConfigured = false

    // MARK: - Core Services
    
    // The API client is optional and set during configuration
    private var _apiClient: AudiobookshelfClient?
    var apiClient: AudiobookshelfClient? {
        _apiClient
    }
    
    // Shared state managers and services
    // These are kept as singletons/shared instances to maintain state across the app
    lazy var appState: AppStateManager = AppStateManager.shared
    lazy var downloadManager: DownloadManager = DownloadManager()
    lazy var player: AudioPlayer = AudioPlayer()
    lazy var playerStateManager: PlayerStateManager = PlayerStateManager()

    // Sleep timer service initialized with the player instance
    lazy var sleepTimerService: SleepTimerService = {
        SleepTimerService(player: player, timerService: TimerService())
    }()
    
    // MARK: - Repositories
    
    // Private backing storage for repositories
    private var _bookRepository: BookRepository?
    private var _libraryRepository: LibraryRepository?
    private var _downloadRepository: DownloadRepository?
    
    // Shared repositories accessible globally
    lazy var playbackRepository: PlaybackRepository = PlaybackRepository.shared
    lazy var bookmarkRepository: BookmarkRepository = BookmarkRepository.shared

    // MARK: - Core Infrastructure
    
    // Infrastructure services
    lazy var storageMonitor: StorageMonitor = StorageMonitor()
    lazy var connectionHealthChecker: ConnectionHealthChecker = ConnectionHealthChecker()
    lazy var keychainService: KeychainService = KeychainService.shared
    lazy var coverCacheManager: CoverCacheManager = CoverCacheManager.shared
    lazy var authService: AuthenticationService = AuthenticationService()
    lazy var serverValidator: ServerConfigValidator = ServerConfigValidator()

    // MARK: - Bookmark Enrichment
    
    // Cache for enriching bookmarks with book data
    private var bookLookupCache: [String: Book] = [:]
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Configuration
    
    // Configures the container with API credentials
    func configureAPI(baseURL: String, token: String) {
        _apiClient = AudiobookshelfClient(baseURL: baseURL, authToken: token)
        isConfigured = true
        
        // Configure shared repositories with the new API client
        if let api = _apiClient {
            playbackRepository.configure(api: api)
            AppLogger.general.debug("[Container] PlaybackRepository configured")
            
            bookmarkRepository.configure(api: api)
            AppLogger.general.debug("[Container] BookmarkRepository configured")
        }
        
        // Start observing data changes for bookmark enrichment
        setupBookmarkEnrichment()
        
        AppLogger.general.info("[Container] API configured for \(baseURL)")
    }
    
    // Initializes repositories that require the API client
    func initializeSharedRepositories(isOnline: Bool) async {
        playbackRepository.setOnlineStatus(isOnline)
        
        if isOnline {
            await playbackRepository.syncFromServer()
            AppLogger.general.debug("[Container] PlaybackRepository synced")
            
            await bookmarkRepository.syncFromServer()
            AppLogger.general.debug("[Container] BookmarkRepository synced")
        } else {
            AppLogger.general.debug("[Container] Offline mode - using cached data")
        }
    }
    
    // MARK: - Bookmark Enrichment Logic
    
    private func setupBookmarkEnrichment() {
        cancellables.removeAll()
        
        // These subscriptions update the local book cache when data changes in Managers
        
        // Observe downloaded books to populate cache
        downloadManager.$downloadedBooks
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] books in
                self?.updateBookLookupCache(with: books)
            }
            .store(in: &cancellables)
            
        AppLogger.general.debug("[Container] Bookmark enrichment observers configured")
    }
    
    private func updateBookLookupCache(with books: [Book]) {
        for book in books {
            bookLookupCache[book.id] = book
        }
        NotificationCenter.default.post(name: .init("BookmarkEnrichmentUpdated"), object: nil)
    }
    
    // MARK: - Factory Methods for ViewModels
    
    // Creates a new instance of HomeViewModel with all dependencies injected
    func makeHomeViewModel() -> HomeViewModel {
        guard let api = _apiClient else {
            return HomeViewModel.placeholder
        }
        
        return HomeViewModel(
            fetchPersonalizedSectionsUseCase: makeFetchPersonalizedSectionsUseCase(),
            downloadRepository: downloadRepository,
            libraryRepository: libraryRepository,
            bookRepository: bookRepository,
            api: api,
            downloadManager: downloadManager,
            player: player,
            appState: appState,
            onBookSelected: { [weak self] in
                self?.playerStateManager.showPlayerBasedOnSettings()
            }
        )
    }

    // Creates a new instance of LibraryViewModel
    func makeLibraryViewModel() -> LibraryViewModel {
        guard let api = _apiClient else {
            return LibraryViewModel.placeholder
        }
        
        return LibraryViewModel(
            fetchBooksUseCase: makeFetchBooksUseCase(),
            downloadRepository: downloadRepository,
            libraryRepository: libraryRepository,
            api: api,
            downloadManager: downloadManager,
            player: player,
            appState: appState,
            onBookSelected: { [weak self] in
                self?.playerStateManager.showPlayerBasedOnSettings()
            }
        )
    }

    // Creates a new instance of SeriesViewModel
    func makeSeriesViewModel() -> SeriesViewModel {
        guard let api = _apiClient else {
            return SeriesViewModel.placeholder
        }
        
        return SeriesViewModel(
            fetchSeriesUseCase: makeFetchSeriesUseCase(),
            downloadRepository: downloadRepository,
            libraryRepository: libraryRepository,
            api: api,
            downloadManager: downloadManager,
            player: player,
            appState: appState,
            onBookSelected: { [weak self] in
                self?.playerStateManager.showPlayerBasedOnSettings()
            }
        )
    }

    // Creates a new instance of AuthorsViewModel
    func makeAuthorsViewModel() -> AuthorsViewModel {
        guard let api = _apiClient else {
            return AuthorsViewModel.placeholder
        }
        
        return AuthorsViewModel(
            fetchAuthorsUseCase: makeFetchAuthorsUseCase(),
            libraryRepository: libraryRepository,
            api: api
        )
    }

    // Creates a new instance of DownloadsViewModel
    func makeDownloadsViewModel() -> DownloadsViewModel {
        guard let api = _apiClient else {
            return DownloadsViewModel.placeholder
        }
        
        return DownloadsViewModel(
            downloadManager: downloadManager,
            player: player,
            api: api,
            appState: appState,
            storageMonitor: storageMonitor,
            onBookSelected: { [weak self] in
                self?.playerStateManager.showPlayerBasedOnSettings()
            }
        )
    }

    // Creates a new instance of SettingsViewModel
    func makeSettingsViewModel() -> SettingsViewModel {
        return SettingsViewModel(
            testConnectionUseCase: makeTestConnectionUseCase(),
            authenticationUseCase: makeAuthenticationUseCase(),
            fetchLibrariesUseCase: makeFetchLibrariesUseCase(),
            calculateStorageUseCase: makeCalculateStorageUseCase(),
            clearCacheUseCase: makeClearCacheUseCase(),
            saveCredentialsUseCase: makeSaveCredentialsUseCase(),
            loadCredentialsUseCase: makeLoadCredentialsUseCase(),
            logoutUseCase: makeLogoutUseCase(),
            serverValidator: serverValidator,
            coverCacheManager: coverCacheManager,
            downloadManager: downloadManager,
            settingsRepository: SettingsRepository()
        )
    }
    
    // MARK: - Use Case Factories
    
    func makeFetchBooksUseCase() -> FetchBooksUseCase {
        FetchBooksUseCase(bookRepository: bookRepository)
    }

    func makeFetchSeriesUseCase() -> FetchSeriesUseCase {
        FetchSeriesUseCase(bookRepository: bookRepository)
    }

    func makeFetchAuthorsUseCase() -> FetchAuthorsUseCase {
        FetchAuthorsUseCase(bookRepository: bookRepository)
    }
    
    func makeFetchPersonalizedSectionsUseCase() -> FetchPersonalizedSectionsUseCase {
        FetchPersonalizedSectionsUseCase(bookRepository: bookRepository)
    }

    func makeTestConnectionUseCase() -> TestConnectionUseCase {
        TestConnectionUseCase(connectionHealthChecker: connectionHealthChecker)
    }

    func makeAuthenticationUseCase() -> AuthenticationUseCase {
        AuthenticationUseCase(authService: authService, keychainService: keychainService)
    }

    func makeFetchLibrariesUseCase() -> FetchLibrariesUseCase {
        FetchLibrariesUseCase()
    }

    func makeCalculateStorageUseCase() -> CalculateStorageUseCase {
        CalculateStorageUseCase(storageMonitor: storageMonitor, downloadManager: downloadManager)
    }

    func makeClearCacheUseCase() -> ClearCacheUseCase {
        ClearCacheUseCase(coverCacheManager: coverCacheManager)
    }

    func makeSaveCredentialsUseCase() -> SaveCredentialsUseCase {
        SaveCredentialsUseCase(keychainService: keychainService)
    }

    func makeLoadCredentialsUseCase() -> LoadCredentialsUseCase {
        LoadCredentialsUseCase(keychainService: keychainService, authService: authService)
    }

    func makeLogoutUseCase() -> LogoutUseCase {
        LogoutUseCase(keychainService: keychainService)
    }

    // MARK: - Repository Accessors
    
    // Provides the BookRepository, creating a placeholder if API is not configured
    var bookRepository: BookRepository {
        if let existing = _bookRepository { return existing }
        
        guard let api = _apiClient else {
            return BookRepository.placeholder
        }
        
        let repo = BookRepository(api: api)
        _bookRepository = repo
        return repo
    }

    // Provides the LibraryRepository, creating a placeholder if API is not configured
    var libraryRepository: LibraryRepository {
        if let existing = _libraryRepository { return existing }
        
        guard let api = _apiClient else {
            return LibraryRepository.placeholder
        }
        
        let repo = LibraryRepository(api: api, settingsRepository: SettingsRepository())
        _libraryRepository = repo
        return repo
    }

    // Provides the DownloadRepository from the DownloadManager
    // This assumes DownloadManager has been initialized with a repository
    var downloadRepository: DownloadRepository {
        if let existing = _downloadRepository { return existing }
        
        guard let repo = downloadManager.repository else {
            // Returns a placeholder to prevent crashes if accessed before initialization
            return DefaultDownloadRepository.placeholder
        }
        
        _downloadRepository = repo
        return repo
    }
    
    // MARK: - Book Enrichment Helpers
    
    func getAllEnrichedBookmarks(sortedBy sort: BookmarkSortOption = .dateNewest) -> [EnrichedBookmark] {
        var enriched: [EnrichedBookmark] = []
        
        for (libraryItemId, bookmarks) in bookmarkRepository.bookmarks {
            let book = bookLookupCache[libraryItemId]
            
            for bookmark in bookmarks {
                enriched.append(EnrichedBookmark(bookmark: bookmark, book: book))
            }
        }
        
        return sortBookmarks(enriched, by: sort)
    }
    
    func getEnrichedBookmarks(for libraryItemId: String) -> [EnrichedBookmark] {
        let bookmarks = bookmarkRepository.getBookmarks(for: libraryItemId)
        let book = bookLookupCache[libraryItemId]
        
        return bookmarks.map { bookmark in
            EnrichedBookmark(bookmark: bookmark, book: book)
        }
    }
    
    func getGroupedEnrichedBookmarks() -> [(book: Book?, bookmarks: [EnrichedBookmark])] {
        var grouped: [String: (Book?, [EnrichedBookmark])] = [:]
        
        for (libraryItemId, bookmarks) in bookmarkRepository.bookmarks {
            let book = bookLookupCache[libraryItemId]
            let enriched = bookmarks.map { EnrichedBookmark(bookmark: $0, book: book) }
            grouped[libraryItemId] = (book, enriched)
        }
        
        return grouped.values.map { ($0.0, $0.1) }
            .sorted { first, second in
                guard let book1 = first.book, let book2 = second.book else { return false }
                return book1.title < book2.title
            }
    }
    
    func preloadBookForBookmarks(_ bookId: String) async {
        if bookLookupCache[bookId] != nil { return }
        
        // Try finding book in download manager first
        if let book = downloadManager.downloadedBooks.first(where: { $0.id == bookId }) {
            bookLookupCache[bookId] = book
            return
        }
        
        // Fetch from API if not found
        do {
            let book = try await bookRepository.fetchBookDetails(bookId: bookId)
            bookLookupCache[bookId] = book
            AppLogger.general.debug("[Container] Preloaded book for bookmark: \(book.title)")
        } catch {
            AppLogger.general.debug("[Container] Failed to preload book \(bookId): \(error)")
        }
    }
    
    private func sortBookmarks(_ bookmarks: [EnrichedBookmark], by sort: BookmarkSortOption) -> [EnrichedBookmark] {
        switch sort {
        case .dateNewest:
            return bookmarks.sorted { $0.bookmark.createdAt > $1.bookmark.createdAt }
        case .dateOldest:
            return bookmarks.sorted { $0.bookmark.createdAt < $1.bookmark.createdAt }
        case .timeInBook:
            return bookmarks.sorted { $0.bookmark.time < $1.bookmark.time }
        case .bookTitle:
            return bookmarks.sorted {
                guard let b1 = $0.book, let b2 = $1.book else { return false }
                return b1.title < b2.title
            }
        }
    }

    // MARK: - Reset State
    
    func reset() {
        AppLogger.general.info("[Container] Resetting dependency container")

        Task {
            await bookRepository.clearCache()
        }
        
        // Clear repositories
        _bookRepository = nil
        _libraryRepository = nil
        _downloadRepository = nil
        
        // Clear caches and bindings
        bookLookupCache.removeAll()
        cancellables.removeAll()
        
        isConfigured = false
        _apiClient = nil

        AppLogger.general.info("[Container] Reset complete")
    }
}
