import Foundation
import SwiftUI
import Combine

// MARK: - Configuration Error
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

// Annotated with @MainActor because it holds ViewModels and Managers that are @MainActor
@MainActor
final class DependencyContainer: ObservableObject {

    // MARK: - Singleton
    static let shared = DependencyContainer()

    // MARK: - Configuration State
    @Published private(set) var isConfigured = false

    // MARK: - Core Services
    private var _apiClient: AudiobookshelfClient?
    var apiClient: AudiobookshelfClient? {
        _apiClient
    }
    
    lazy var appState: AppStateManager = AppStateManager.shared
    lazy var downloadManager: DownloadManager = DownloadManager()
    lazy var player: AudioPlayer = AudioPlayer()
    lazy var playerStateManager: PlayerStateManager = PlayerStateManager()

    lazy var sleepTimerService: SleepTimerService = {
        SleepTimerService(player: player, timerService: TimerService())
    }()
    
    // MARK: - Repositories
    private var _bookRepository: BookRepository?
    private var _libraryRepository: LibraryRepository?
    private var _downloadRepository: DownloadRepository?
    
    // Shared Repositories (Singletons)
    lazy var playbackRepository: PlaybackRepository = PlaybackRepository.shared
    lazy var bookmarkRepository: BookmarkRepository = BookmarkRepository.shared

    // MARK: - ViewModels (Lazy with Safety)
    private var _homeViewModel: HomeViewModel?
    private var _libraryViewModel: LibraryViewModel?
    private var _seriesViewModel: SeriesViewModel?
    private var _authorsViewModel: AuthorsViewModel?
    private var _downloadsViewModel: DownloadsViewModel?
    private var _settingsViewModel: SettingsViewModel?

    // MARK: - Core Infrastructure
    lazy var storageMonitor: StorageMonitor = StorageMonitor()
    lazy var connectionHealthChecker: ConnectionHealthChecker = ConnectionHealthChecker()
    lazy var keychainService: KeychainService = KeychainService.shared
    lazy var coverCacheManager: CoverCacheManager = CoverCacheManager.shared
    lazy var authService: AuthenticationService = AuthenticationService()
    lazy var serverValidator: ServerConfigValidator = ServerConfigValidator()

    // MARK: - Bookmark Enrichment Cache
    private var bookLookupCache: [String: Book] = [:]
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Configure API
    func configureAPI(baseURL: String, token: String) {
        _apiClient = AudiobookshelfClient(baseURL: baseURL, authToken: token)
        isConfigured = true
        
        // Reset ViewModels on new configuration
        resetViewModels()
        
        // Configure Shared Repositories
        if let api = _apiClient {
            // PlaybackRepository
            playbackRepository.configure(api: api)
            AppLogger.general.debug("[Container] ✅ PlaybackRepository configured")
            
            // BookmarkRepository
            bookmarkRepository.configure(api: api)
            AppLogger.general.debug("[Container] ✅ BookmarkRepository configured")
        }
        
        // Setup bookmark enrichment observers
        setupBookmarkEnrichment()
        
        AppLogger.general.info("[Container] API configured for \(baseURL)")
    }
    
    // MARK: - Initialize Shared Repositories (call after API config)
    func initializeSharedRepositories(isOnline: Bool) async {
        // Set online status
        playbackRepository.setOnlineStatus(isOnline)
        
        if isOnline {
            // Sync from server only when online
            await playbackRepository.syncFromServer()
            AppLogger.general.debug("[Container] ✅ PlaybackRepository synced")
            
            await bookmarkRepository.syncFromServer()
            AppLogger.general.debug("[Container] ✅ BookmarkRepository synced")
        } else {
            AppLogger.general.debug("[Container] ⚠️ Offline mode - using cached data")
        }
    }
    
    // MARK: - Bookmark Enrichment Setup
    private func setupBookmarkEnrichment() {
        // Clear existing subscriptions
        cancellables.removeAll()
        
        // Observe library books changes
        libraryViewModel.$books
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] books in
                self?.updateBookLookupCache(with: books)
            }
            .store(in: &cancellables)
        
        // Observe downloaded books changes
        downloadManager.$downloadedBooks
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] books in
                self?.updateBookLookupCache(with: books)
            }
            .store(in: &cancellables)
        
        AppLogger.general.debug("[Container] 🔖 Bookmark enrichment observers configured")
    }
    
    private func updateBookLookupCache(with books: [Book]) {
        for book in books {
            bookLookupCache[book.id] = book
        }
        
        // Trigger UI update by posting notification
        NotificationCenter.default.post(name: .init("BookmarkEnrichmentUpdated"), object: nil)
    }
    
    // MARK: - Enriched Bookmarks API
    
    func getAllEnrichedBookmarks(sortedBy sort: BookmarkSortOption = .dateNewest) -> [EnrichedBookmark] {
        var enriched: [EnrichedBookmark] = []
        
        for (libraryItemId, bookmarks) in bookmarkRepository.bookmarks {
            let book = bookLookupCache[libraryItemId]
            
            for bookmark in bookmarks {
                enriched.append(EnrichedBookmark(bookmark: bookmark, book: book))
            }
        }
        
        switch sort {
        case .dateNewest:
            return enriched.sorted { $0.bookmark.createdAt > $1.bookmark.createdAt }
        case .dateOldest:
            return enriched.sorted { $0.bookmark.createdAt < $1.bookmark.createdAt }
        case .timeInBook:
            return enriched.sorted { $0.bookmark.time < $1.bookmark.time }
        case .bookTitle:
            return enriched.sorted {
                guard let b1 = $0.book, let b2 = $1.book else { return false }
                return b1.title < b2.title
            }
        }
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
        guard bookLookupCache[bookId] == nil else { return }
        
        if let book = libraryViewModel.books.first(where: { $0.id == bookId }) {
            bookLookupCache[bookId] = book
            return
        }
        
        if let book = downloadManager.downloadedBooks.first(where: { $0.id == bookId }) {
            bookLookupCache[bookId] = book
            return
        }
        
        do {
            let book = try await bookRepository.fetchBookDetails(bookId: bookId)
            bookLookupCache[bookId] = book
            AppLogger.general.debug("[Container] 📚 Preloaded book: \(book.title)")
        } catch {
            AppLogger.general.debug("[Container] ⚠️ Failed to preload book \(bookId): \(error)")
        }
    }
    
    // MARK: - Repositories (Safe with Fallback)
    var bookRepository: BookRepository {
        if let existing = _bookRepository { return existing }
        
        guard let api = _apiClient else {
            return BookRepository.placeholder
        }
        
        let repo = BookRepository(api: api)
        _bookRepository = repo
        return repo
    }

    var libraryRepository: LibraryRepository {
        if let existing = _libraryRepository { return existing }
        
        guard let api = _apiClient else {
            return LibraryRepository.placeholder
        }
        
        let repo = LibraryRepository(api: api, settingsRepository: SettingsRepository())
        _libraryRepository = repo
        return repo
    }

    var downloadRepository: DownloadRepository {
        if let existing = _downloadRepository { return existing }
        
        guard let repo = downloadManager.repository else {
            fatalError("DownloadRepository not available. Ensure DownloadManager is properly initialized before accessing downloadRepository.")
        }
        
        _downloadRepository = repo
        return repo
    }

    // MARK: - ViewModels (Safe Access with Fallback)
    var homeViewModel: HomeViewModel {
        if let existing = _homeViewModel { return existing }
        
        guard let api = _apiClient else {
            return HomeViewModel.placeholder
        }
        
        let vm = HomeViewModel(
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
        
        _homeViewModel = vm
        return vm
    }

    var libraryViewModel: LibraryViewModel {
        if let existing = _libraryViewModel { return existing }
        
        guard let api = _apiClient else {
            return LibraryViewModel.placeholder
        }
        
        let vm = LibraryViewModel(
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
        
        _libraryViewModel = vm
        return vm
    }

    var seriesViewModel: SeriesViewModel {
        if let existing = _seriesViewModel { return existing }
        
        guard let api = _apiClient else {
            return SeriesViewModel.placeholder
        }
        
        let vm = SeriesViewModel(
            fetchSeriesUseCase: makeFetchSeriesUseCase(),
            downloadRepository: downloadRepository,
            libraryRepository: libraryRepository,
            api: api,
            downloadManager: downloadManager,
            player: player,
            appState: appState,
            onBookSelected: { }
        )
        
        _seriesViewModel = vm
        return vm
    }

    var authorsViewModel: AuthorsViewModel {
        if let existing = _authorsViewModel { return existing }
        
        guard let api = _apiClient else {
            return AuthorsViewModel.placeholder
        }
        
        let vm = AuthorsViewModel(
            fetchAuthorsUseCase: makeFetchAuthorsUseCase(),
            libraryRepository: libraryRepository,
            api: api
        )
        
        _authorsViewModel = vm
        return vm
    }

    var downloadsViewModel: DownloadsViewModel {
        if let existing = _downloadsViewModel { return existing }
        
        guard let api = _apiClient else {
            return DownloadsViewModel.placeholder
        }
        
        let vm = DownloadsViewModel(
            downloadManager: downloadManager,
            player: player,
            api: api,
            appState: appState,
            storageMonitor: storageMonitor,
            onBookSelected: { [weak self] in
                self?.playerStateManager.showPlayerBasedOnSettings()
            }
        )
        
        _downloadsViewModel = vm
        return vm
    }

    var settingsViewModel: SettingsViewModel {
        if let existing = _settingsViewModel { return existing }
        
        let vm = SettingsViewModel(
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
        
        _settingsViewModel = vm
        return vm
    }

    // MARK: - Use Cases
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

    // MARK: - Reset Methods
    func resetRepositories() {
        _bookRepository = nil
        _libraryRepository = nil
        _downloadRepository = nil
    }
    
    func resetViewModels() {
        _homeViewModel = nil
        _libraryViewModel = nil
        _seriesViewModel = nil
        _authorsViewModel = nil
        _downloadsViewModel = nil
    }

    @MainActor
    func reset() {
        AppLogger.general.info("[Container] Factory reset initiated")

        // Using Task prevents blocking and handles concurrency correctly
        Task {
            await bookRepository.clearCache()
        }
        
        // FIX: Removed await as clearCache is synchronous in current LibraryRepository
        Task {
            libraryRepository.clearCache()
        }
        
        bookmarkRepository.clearCache()
        
        resetRepositories()
        resetViewModels()
        
        bookLookupCache.removeAll()
        cancellables.removeAll()
        
        isConfigured = false
        _apiClient = nil

        AppLogger.general.info("[Container] All repositories and ViewModels reset")
    }
}
