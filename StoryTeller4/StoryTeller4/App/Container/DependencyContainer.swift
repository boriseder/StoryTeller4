import Foundation
import SwiftUI
import Observation

// MARK: - DependencyContainer
@MainActor
@Observable
final class DependencyContainer {

    // MARK: - Singleton
    static let shared = DependencyContainer()

    // MARK: - Containers
    let services: ServiceContainer
    private(set) var apiContainer: APIContainer?
    private(set) var isConfigured = false

    // MARK: - Init
    private init() {
        self.services = ServiceContainer()
    }

    // MARK: - Configuration
    func configureAPI(baseURL: String, token: String) {
        apiContainer = APIContainer(
            baseURL: baseURL,
            token: token,
            downloadManager: services.downloadManager
        )
        isConfigured = true
        AppLogger.general.info("[Container] API configured for \(baseURL)")
    }

    func initializeSharedRepositories(isOnline: Bool) async {
        await apiContainer?.initialise(isOnline: isOnline)
    }

    func reset() {
        apiContainer = nil
        isConfigured = false
        Task { await services.bookRepository?.clearCache() }
        AppLogger.general.debug("[Container] Reset")
    }

    // MARK: - Convenience pass-throughs
    var player: AudioPlayer                     { services.player }
    var playerStateManager: PlayerStateManager  { services.playerStateManager }
    var sleepTimerService: SleepTimerService    { services.sleepTimerService }
    var downloadManager: DownloadManager        { services.downloadManager }
    var coverCacheManager: CoverCacheManager    { services.coverCacheManager }
    var appState: AppStateManager               { AppStateManager.shared }

    var apiClient: AudiobookshelfClient?        { apiContainer?.client }
    var bookRepository: BookRepository?         { apiContainer?.bookRepository }
    var libraryRepository: LibraryRepository?   { apiContainer?.libraryRepository }

    var playbackRepository: any PlaybackRepositoryProtocol { PlaybackRepository.shared }
    var bookmarkRepository: any BookmarkRepositoryProtocol { BookmarkRepository.shared }

    // MARK: - Factory
    var factory: ViewModelFactory? {
        guard let api = apiContainer else { return nil }
        return ViewModelFactory(services: services, api: api)
    }

    // MARK: - ViewModel factories
    func makeHomeViewModel() -> HomeViewModel {
        factory?.makeHomeViewModel() ?? HomeViewModel.placeholder
    }

    func makeLibraryViewModel() -> LibraryViewModel {
        factory?.makeLibraryViewModel() ?? LibraryViewModel.placeholder
    }

    func makeSeriesViewModel() -> SeriesViewModel {
        factory?.makeSeriesViewModel() ?? SeriesViewModel.placeholder
    }

    func makeAuthorsViewModel() -> AuthorsViewModel {
        factory?.makeAuthorsViewModel() ?? AuthorsViewModel.placeholder
    }

    func makeDownloadsViewModel() -> DownloadsViewModel {
        factory?.makeDownloadsViewModel() ?? DownloadsViewModel.placeholder
    }

    func makeSettingsViewModel() -> SettingsViewModel {
        factory?.makeSettingsViewModel()
            ?? ViewModelFactory.makePlaceholderSettingsViewModel(services: services)
    }

    func makeBookDetailViewModel(bookId: String) -> BookDetailViewModel {
        factory?.makeBookDetailViewModel(bookId: bookId)
            ?? BookDetailViewModel.placeholder(bookId: bookId, downloadManager: services.downloadManager)
    }

    func makeAuthorDetailViewModel(
        author: Author,
        onBookSelected: @escaping () -> Void
    ) -> AuthorDetailViewModel {
        factory?.makeAuthorDetailViewModel(author: author, onBookSelected: onBookSelected)
            ?? AuthorDetailViewModel.placeholder(author: author, services: services)
    }

    func makeSeriesDetailViewModel(
        series: Series,
        onBookSelected: @escaping () -> Void
    ) -> SeriesDetailViewModel {
        factory?.makeSeriesDetailViewModel(series: series, onBookSelected: onBookSelected)
            ?? SeriesDetailViewModel.placeholder(series: series)
    }

    func makeSeriesDetailViewModel(
        seriesBook: Book,
        onBookSelected: @escaping () -> Void
    ) -> SeriesDetailViewModel {
        factory?.makeSeriesDetailViewModel(seriesBook: seriesBook, onBookSelected: onBookSelected)
            ?? SeriesDetailViewModel.placeholder(seriesBook: seriesBook)
    }

    // MARK: - Bookmark Enrichment
    func getEnrichedBookmarks(for libraryItemId: String) -> [EnrichedBookmark] {
        apiContainer?.bookmarkEnrichment.enrichedBookmarks(for: libraryItemId) ?? []
    }

    func getAllEnrichedBookmarks(sortedBy sort: BookmarkSortOption = .dateNewest) -> [EnrichedBookmark] {
        apiContainer?.bookmarkEnrichment.allEnrichedBookmarks(sortedBy: sort) ?? []
    }

    func getGroupedEnrichedBookmarks() -> [BookmarkGroup] {
        apiContainer?.bookmarkEnrichment.groupedEnrichedBookmarks() ?? []
    }

    func preloadBookForBookmarks(_ bookId: String) async {
        await apiContainer?.bookmarkEnrichment.prefetchBook(bookId)
    }
}

// MARK: - ServiceContainer convenience
private extension DependencyContainer { }

extension ServiceContainer {
    var bookRepository: BookRepository? { nil }
}

// MARK: - Shared PlayBookUseCase factory
// Zentraler Ort um PlayBookUseCase mit den richtigen Services zu bauen.
// Verhindert Streuung von BookMetadataService/PlaybackService-Konstruktion.
extension ServiceContainer {
    @MainActor
    func makePlayBookUseCase(api: AudiobookshelfClient) -> PlayBookUseCase {
        PlayBookUseCase(
            metadataService: BookMetadataService(api: api, downloadManager: downloadManager),
            playbackService: PlaybackService(player: player, api: api),
            downloadManager: downloadManager,
            appState: AppStateManager.shared
        )
    }
}

// MARK: - ViewModelFactory placeholder helpers
extension ViewModelFactory {
    static func makePlaceholderSettingsViewModel(services: ServiceContainer) -> SettingsViewModel {
        SettingsViewModel(
            testConnectionUseCase: TestConnectionUseCase(
                connectionHealthChecker: services.connectionHealthChecker
            ),
            authenticationUseCase: AuthenticationUseCase(
                authService: services.authService,
                keychainService: services.keychainService
            ),
            calculateStorageUseCase: CalculateStorageUseCase(
                storageMonitor: services.storageMonitor,
                downloadManager: services.downloadManager
            ),
            clearCacheUseCase: ClearCacheUseCase(coverCacheManager: services.coverCacheManager),
            saveCredentialsUseCase: SaveCredentialsUseCase(keychainService: services.keychainService),
            loadCredentialsUseCase: LoadCredentialsUseCase(
                keychainService: services.keychainService,
                authService: services.authService
            ),
            logoutUseCase: LogoutUseCase(
                settingsRepository: SettingsRepository(),
                onContainerReset: { await MainActor.run { DependencyContainer.shared.reset() } }
            ),
            serverValidator: services.serverValidator,
            coverCacheManager: services.coverCacheManager,
            downloadManager: services.downloadManager,
            settingsRepository: SettingsRepository(),
            // Factory erzeugt ein frisches LibraryRepository wenn Credentials bekannt sind
            libraryRepositoryFactory: { baseURL, token in
                LibraryRepository(
                    api: AudiobookshelfClient(baseURL: baseURL, authToken: token),
                    settingsRepository: SettingsRepository()
                )
            }
        )
    }
}

// MARK: - ViewModel placeholder stubs
extension BookDetailViewModel {
    static func placeholder(bookId: String, downloadManager: DownloadManager) -> BookDetailViewModel {
        let placeholderApi = AudiobookshelfClient(baseURL: "", authToken: "")
        return BookDetailViewModel(
            bookId: bookId,
            bookRepository: BookRepository(api: placeholderApi),
            downloadManager: downloadManager,
            downloadUseCase: DownloadBookUseCase(repository: downloadManager.repository!),
            api: placeholderApi
        )
    }
}

extension AuthorDetailViewModel {
    static func placeholder(author: Author, services: ServiceContainer) -> AuthorDetailViewModel {
        let placeholderApi = AudiobookshelfClient(baseURL: "", authToken: "")
        return AuthorDetailViewModel(
            bookRepository: BookRepository(api: placeholderApi),
            libraryRepository: LibraryRepository.placeholder,
            playBookUseCase: services.makePlayBookUseCase(api: placeholderApi),
            coverPreloadService: CoverPreloadService(api: placeholderApi, downloadManager: services.downloadManager),
            downloadManager: services.downloadManager,
            author: author,
            onBookSelected: {}
        )
    }
}

extension SeriesDetailViewModel {
    static func placeholder(series: Series) -> SeriesDetailViewModel {
        SeriesDetailViewModel(series: series, container: DependencyContainer.shared, onBookSelected: {})
    }

    static func placeholder(seriesBook: Book) -> SeriesDetailViewModel {
        SeriesDetailViewModel(seriesBook: seriesBook, container: DependencyContainer.shared, onBookSelected: {})
    }
}
