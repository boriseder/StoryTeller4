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
    var downloadManager: DownloadManager                        { services.downloadManager }
    var coverCacheManager: any CoverCacheManagerProtocol        { services.coverCacheManager }
    var appState: AppStateManager                               { AppStateManager.shared }

    var apiClient: AudiobookshelfClient?        { apiContainer?.client }
    var bookRepository: BookRepository?         { apiContainer?.bookRepository }
    var libraryRepository: LibraryRepository?   { apiContainer?.libraryRepository }

    var playbackRepository: any PlaybackRepositoryProtocol { PlaybackRepository.shared }
    var bookmarkRepository: any BookmarkRepositoryProtocol { BookmarkRepository.shared }

    // MARK: - Helpers
    private func makePlayBookUseCase() -> PlayBookUseCase {
        guard let api = apiClient else {
            return PlayBookUseCase(
                metadataService: BookMetadataService(api: AudiobookshelfClient(baseURL: "", authToken: ""), downloadManager: services.downloadManager),
                playbackService: PlaybackService(player: services.player, api: AudiobookshelfClient(baseURL: "", authToken: "")),
                downloadManager: services.downloadManager,
                appState: AppStateManager.shared
            )
        }
        return services.makePlayBookUseCase(api: api)
    }

    private func makeCoverPreloadService() -> any CoverPreloadServiceProtocol {
        guard let api = apiClient else {
            return CoverPreloadService(api: AudiobookshelfClient(baseURL: "", authToken: ""), downloadManager: services.downloadManager)
        }
        return CoverPreloadService(api: api, downloadManager: services.downloadManager)
    }

    // MARK: - ViewModel factories
    func makeHomeViewModel() -> HomeViewModel? {
        guard let api = apiContainer else { return nil }
        return HomeViewModel(
            bookRepository: api.bookRepository,
            libraryRepository: api.libraryRepository,
            playBookUseCase: makePlayBookUseCase(),
            coverPreloadService: makeCoverPreloadService(),
            appState: AppStateManager.shared,
            onBookSelected: { [weak self] in self?.services.playerStateManager.showPlayerBasedOnSettings() }
        )
    }

    func makeLibraryViewModel() -> LibraryViewModel? {
        guard let api = apiContainer else { return nil }
        return LibraryViewModel(
            bookRepository: api.bookRepository,
            playBookUseCase: makePlayBookUseCase(),
            libraryRepository: api.libraryRepository,
            coverPreloadService: makeCoverPreloadService(),
            downloadManager: services.downloadManager,
            appState: AppStateManager.shared,
            onBookSelected: { [weak self] in self?.services.playerStateManager.showPlayerBasedOnSettings() }
        )
    }


    func makeAuthorsViewModel() -> AuthorsViewModel? {
        guard let api = apiContainer else { return nil }
        return AuthorsViewModel(
            bookRepository: api.bookRepository,
            libraryRepository: api.libraryRepository,
            api: api.client
        )
    }


    func makeSettingsViewModel() -> SettingsViewModel {
        let settingsRepo = SettingsRepository()
        return SettingsViewModel(
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
            saveCredentialsUseCase: SaveCredentialsUseCase(keychainService: services.keychainService),
            loadCredentialsUseCase: LoadCredentialsUseCase(
                keychainService: services.keychainService,
                authService: services.authService
            ),
            logoutUseCase: LogoutUseCase(
                settingsRepository: settingsRepo,
                onContainerReset: { await MainActor.run { DependencyContainer.shared.reset() } }
            ),
            serverValidator: services.serverValidator,
            coverCacheManager: services.coverCacheManager,
            downloadManager: services.downloadManager,
            settingsRepository: settingsRepo,
            libraryRepositoryFactory: { baseURL, token in
                LibraryRepository(
                    api: AudiobookshelfClient(baseURL: baseURL, authToken: token),
                    settingsRepository: SettingsRepository()
                )
            }
        )
    }

    func makeBookDetailViewModel(bookId: String) -> BookDetailViewModel? {
        guard let api = apiContainer else { return nil }
        let downloadUseCase = services.downloadManager.repository.map { DownloadBookUseCase(repository: $0) }
            ?? DownloadBookUseCase(repository: DefaultDownloadRepository.placeholder)
        return BookDetailViewModel(
            bookId: bookId,
            bookRepository: api.bookRepository,
            downloadManager: services.downloadManager,
            downloadUseCase: downloadUseCase,
            api: api.client
        )
    }

    func makeAuthorDetailViewModel(
        author: Author,
        onBookSelected: @escaping () -> Void
    ) -> AuthorDetailViewModel? {
        guard let api = apiContainer else { return nil }
        return AuthorDetailViewModel(
            bookRepository: api.bookRepository,
            libraryRepository: api.libraryRepository,
            playBookUseCase: services.makePlayBookUseCase(api: api.client),
            coverPreloadService: CoverPreloadService(api: api.client, downloadManager: services.downloadManager),
            downloadManager: services.downloadManager,
            author: author,
            onBookSelected: onBookSelected
        )
    }

    func makeSeriesDetailViewModel(
        series: Series,
        onBookSelected: @escaping () -> Void
    ) -> SeriesDetailViewModel? {
        guard apiContainer != nil else { return nil }
        return SeriesDetailViewModel(
            series: series,
            container: self,
            onBookSelected: onBookSelected
        )
    }

    func makeSeriesDetailViewModel(
        seriesBook: Book,
        onBookSelected: @escaping () -> Void
    ) -> SeriesDetailViewModel? {
        guard apiContainer != nil else { return nil }
        return SeriesDetailViewModel(
            seriesBook: seriesBook,
            container: self,
            onBookSelected: onBookSelected
        )
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

// MARK: - DependencyContainer placeholder helpers
extension DependencyContainer {
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


