import Foundation
import SwiftUI
import Observation
import Combine

// Configuration Error
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

// Main container - Migrated to @Observable
@MainActor
@Observable
final class DependencyContainer {

    // Singleton
    static let shared = DependencyContainer()

    // Configuration State
    private(set) var isConfigured = false

    // MARK: - Core Services
    private var _apiClient: AudiobookshelfClient?
    var apiClient: AudiobookshelfClient? { _apiClient }
    
    var appState: AppStateManager = AppStateManager.shared
    
    // FIX: Removed 'lazy' and initialization closures.
    // These are now standard properties initialized in init().
    var downloadManager: DownloadManager
    var player: AudioPlayer
    var playerStateManager: PlayerStateManager
    var sleepTimerService: SleepTimerService
    
    // MARK: - Repositories
    private var _bookRepository: BookRepository?
    private var _libraryRepository: LibraryRepository?
    private var _downloadRepository: DownloadRepository?
    
    var playbackRepository: PlaybackRepository = PlaybackRepository.shared
    var bookmarkRepository: BookmarkRepository = BookmarkRepository.shared

    // MARK: - Core Infrastructure
    var storageMonitor = StorageMonitor()
    var connectionHealthChecker = ConnectionHealthChecker()
    var keychainService = KeychainService.shared
    var coverCacheManager = CoverCacheManager.shared
    var authService = AuthenticationService()
    var serverValidator = ServerConfigValidator()

    // MARK: - Bookmark Enrichment
    private var bookLookupCache: [String: Book] = [:]
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Init
    private init() {
        // 1. Initialize Player System
        let player = AudioPlayer()
        self.player = player
        self.playerStateManager = PlayerStateManager()
        
        // SleepTimer depends on player, so we inject it here directly
        self.sleepTimerService = SleepTimerService(player: player, timerService: TimerService())
        
        // 2. Initialize Download System
        let manager = DownloadManager()
        
        let networkService = DefaultDownloadNetworkService()
        let storageService = DefaultDownloadStorageService()
        let retryPolicy = ExponentialBackoffRetryPolicy()
        let validationService = DefaultDownloadValidationService()
        
        let orchestrationService = DefaultDownloadOrchestrationService(
            networkService: networkService,
            storageService: storageService,
            retryPolicy: retryPolicy,
            validationService: validationService
        )
        
        // Circular dependency handled via closure capture
        let healingService = DefaultBackgroundHealingService(
            storageService: storageService,
            validationService: validationService,
            onBookRemoved: { [weak manager] bookId in
                Task { @MainActor in
                    manager?.downloadedBooks.removeAll { $0.id == bookId }
                }
            }
        )
        
        let repository = DefaultDownloadRepository(
            orchestrationService: orchestrationService,
            storageService: storageService,
            validationService: validationService,
            healingService: healingService,
            downloadManager: manager
        )
        
        manager.configure(repository: repository)
        self.downloadManager = manager
    }
    
    // MARK: - Configure API
    func configureAPI(baseURL: String, token: String) {
        _apiClient = AudiobookshelfClient(baseURL: baseURL, authToken: token)
        isConfigured = true
        
        if let api = _apiClient {
            playbackRepository.configure(api: api)
            AppLogger.general.debug("[Container] PlaybackRepository configured")
            
            bookmarkRepository.configure(api: api)
            AppLogger.general.debug("[Container] BookmarkRepository configured")
        }
        
        setupBookmarkEnrichment()
        AppLogger.general.info("[Container] API configured for \(baseURL)")
    }
    
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
    
    // MARK: - Bookmark Enrichment Setup
    private func setupBookmarkEnrichment() {
        AppLogger.general.debug("[Container] Bookmark enrichment observers configured")
    }
    
    private func updateBookLookupCache(with books: [Book]) {
        for book in books {
            bookLookupCache[book.id] = book
        }
        NotificationCenter.default.post(name: .init("BookmarkEnrichmentUpdated"), object: nil)
    }
    
    // MARK: - Factory Methods
    func makeHomeViewModel() -> HomeViewModel {
        HomeViewModel(
            fetchPersonalizedSectionsUseCase: makeFetchPersonalizedSectionsUseCase(),
            downloadRepository: downloadRepository,
            libraryRepository: libraryRepository,
            bookRepository: bookRepository,
            api: _apiClient ?? AudiobookshelfClient(baseURL: "", authToken: ""),
            downloadManager: downloadManager,
            player: player,
            appState: appState,
            onBookSelected: { [weak self] in self?.playerStateManager.showPlayerBasedOnSettings() }
        )
    }

    func makeLibraryViewModel() -> LibraryViewModel {
        LibraryViewModel(
            fetchBooksUseCase: makeFetchBooksUseCase(),
            downloadRepository: downloadRepository,
            libraryRepository: libraryRepository,
            api: _apiClient ?? AudiobookshelfClient(baseURL: "", authToken: ""),
            downloadManager: downloadManager,
            player: player,
            appState: appState,
            onBookSelected: { [weak self] in self?.playerStateManager.showPlayerBasedOnSettings() }
        )
    }

    func makeSeriesViewModel() -> SeriesViewModel {
        SeriesViewModel(
            fetchSeriesUseCase: makeFetchSeriesUseCase(),
            downloadRepository: downloadRepository,
            libraryRepository: libraryRepository,
            api: _apiClient ?? AudiobookshelfClient(baseURL: "", authToken: ""),
            downloadManager: downloadManager,
            player: player,
            appState: appState,
            onBookSelected: { [weak self] in self?.playerStateManager.showPlayerBasedOnSettings() }
        )
    }

    func makeAuthorsViewModel() -> AuthorsViewModel {
        AuthorsViewModel(
            fetchAuthorsUseCase: makeFetchAuthorsUseCase(),
            libraryRepository: libraryRepository,
            api: _apiClient ?? AudiobookshelfClient(baseURL: "", authToken: "")
        )
    }

    func makeDownloadsViewModel() -> DownloadsViewModel {
        DownloadsViewModel(
            downloadManager: downloadManager,
            player: player,
            api: _apiClient ?? AudiobookshelfClient(baseURL: "", authToken: ""),
            appState: appState,
            storageMonitor: storageMonitor,
            onBookSelected: { [weak self] in self?.playerStateManager.showPlayerBasedOnSettings() }
        )
    }

    func makeSettingsViewModel() -> SettingsViewModel {
        SettingsViewModel(
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
    func makeFetchBooksUseCase() -> FetchBooksUseCase { FetchBooksUseCase(bookRepository: bookRepository) }
    func makeFetchSeriesUseCase() -> FetchSeriesUseCase { FetchSeriesUseCase(bookRepository: bookRepository) }
    func makeFetchAuthorsUseCase() -> FetchAuthorsUseCase { FetchAuthorsUseCase(bookRepository: bookRepository) }
    func makeFetchPersonalizedSectionsUseCase() -> FetchPersonalizedSectionsUseCase { FetchPersonalizedSectionsUseCase(bookRepository: bookRepository) }
    
    func makeTestConnectionUseCase() -> TestConnectionUseCase { TestConnectionUseCase(connectionHealthChecker: connectionHealthChecker) }
    func makeAuthenticationUseCase() -> AuthenticationUseCase { AuthenticationUseCase(authService: authService, keychainService: keychainService) }
    func makeFetchLibrariesUseCase() -> FetchLibrariesUseCase { FetchLibrariesUseCase() }
    func makeCalculateStorageUseCase() -> CalculateStorageUseCase { CalculateStorageUseCase(storageMonitor: storageMonitor, downloadManager: downloadManager) }
    func makeClearCacheUseCase() -> ClearCacheUseCase { ClearCacheUseCase(coverCacheManager: coverCacheManager) }
    func makeSaveCredentialsUseCase() -> SaveCredentialsUseCase { SaveCredentialsUseCase(keychainService: keychainService) }
    func makeLoadCredentialsUseCase() -> LoadCredentialsUseCase { LoadCredentialsUseCase(keychainService: keychainService, authService: authService) }
    func makeLogoutUseCase() -> LogoutUseCase { LogoutUseCase(keychainService: keychainService) }

    // MARK: - Repository Accessors
    var bookRepository: BookRepository {
        if let existing = _bookRepository { return existing }
        let repo = BookRepository(api: _apiClient ?? AudiobookshelfClient(baseURL: "", authToken: ""))
        _bookRepository = repo
        return repo
    }

    var libraryRepository: LibraryRepository {
        if let existing = _libraryRepository { return existing }
        let repo = LibraryRepository(api: _apiClient ?? AudiobookshelfClient(baseURL: "", authToken: ""), settingsRepository: SettingsRepository())
        _libraryRepository = repo
        return repo
    }

    var downloadRepository: DownloadRepository {
        if let existing = _downloadRepository { return existing }
        guard let repo = downloadManager.repository else { return DefaultDownloadRepository.placeholder }
        _downloadRepository = repo
        return repo
    }
    
    // MARK: - Book Enrichment Helpers
    func getEnrichedBookmarks(for libraryItemId: String) -> [EnrichedBookmark] {
        let bookmarks = bookmarkRepository.getBookmarks(for: libraryItemId)
        let book = bookLookupCache[libraryItemId]
        return bookmarks.map { EnrichedBookmark(bookmark: $0, book: book) }
    }
    
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
    
    func getGroupedEnrichedBookmarks() -> [(book: Book?, bookmarks: [EnrichedBookmark])] {
        var grouped: [String: (Book?, [EnrichedBookmark])] = [:]
        for (libraryItemId, bookmarks) in bookmarkRepository.bookmarks {
            let book = bookLookupCache[libraryItemId]
            let enriched = bookmarks.map { EnrichedBookmark(bookmark: $0, book: book) }
            grouped[libraryItemId] = (book, enriched)
        }
        return grouped.values.map { ($0.0, $0.1) }.sorted { ($0.0?.title ?? "") < ($1.0?.title ?? "") }
    }
    
    func preloadBookForBookmarks(_ bookId: String) async {
        if bookLookupCache[bookId] != nil { return }
        if let book = downloadManager.downloadedBooks.first(where: { $0.id == bookId }) {
            bookLookupCache[bookId] = book
            return
        }
        do {
            let book = try await bookRepository.fetchBookDetails(bookId: bookId)
            bookLookupCache[bookId] = book
        } catch {
            AppLogger.general.debug("[Container] Failed to preload book \(bookId): \(error)")
        }
    }
    
    private func sortBookmarks(_ bookmarks: [EnrichedBookmark], by sort: BookmarkSortOption) -> [EnrichedBookmark] {
        switch sort {
        case .dateNewest: return bookmarks.sorted { $0.bookmark.createdAt > $1.bookmark.createdAt }
        case .dateOldest: return bookmarks.sorted { $0.bookmark.createdAt < $1.bookmark.createdAt }
        case .timeInBook: return bookmarks.sorted { $0.bookmark.time < $1.bookmark.time }
        case .bookTitle: return bookmarks.sorted { ($0.book?.title ?? "") < ($1.book?.title ?? "") }
        }
    }

    // MARK: - Reset State
    func reset() {
        Task { await bookRepository.clearCache() }
        _bookRepository = nil
        _libraryRepository = nil
        _downloadRepository = nil
        bookLookupCache.removeAll()
        isConfigured = false
        _apiClient = nil
    }
}
