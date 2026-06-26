import Foundation

// MARK: - ViewModelFactory
//
// Stateless struct. Assembles ViewModels from ServiceContainer + APIContainer.
// No observable state, no re-renders triggered here.
// AudiobookshelfClient bleibt hier – Factory ist Teil der Composition Root (Data Layer).

@MainActor
struct ViewModelFactory {

    let services: ServiceContainer
    let api: APIContainer

    // MARK: - Shared helpers
    // Zentraler Konstruktionspunkt – nicht in jedem make* duplizieren.

    private func makeCoverPreloadService() -> CoverPreloadService {
        CoverPreloadService(api: api.client, downloadManager: services.downloadManager)
    }

    private func makePlayBookUseCase() -> PlayBookUseCase {
        services.makePlayBookUseCase(api: api.client)
    }

    // MARK: - Tab ViewModels

    func makeHomeViewModel() -> HomeViewModel {
        HomeViewModel(
            fetchPersonalizedSectionsUseCase: FetchPersonalizedSectionsUseCase(
                bookRepository: api.bookRepository
            ),
            fetchLibraryStatsUseCase: FetchLibraryStatsUseCase(
                libraryStatsRepository: LibraryStatsRepository(api: api.client)
            ),
            playBookUseCase: makePlayBookUseCase(),
            libraryRepository: api.libraryRepository,
            coverPreloadService: makeCoverPreloadService(),
            appState: AppStateManager.shared,
            onBookSelected: { services.playerStateManager.showPlayerBasedOnSettings() }
        )
    }

    func makeLibraryViewModel() -> LibraryViewModel {
        LibraryViewModel(
            fetchBooksUseCase: FetchBooksUseCase(bookRepository: api.bookRepository),
            playBookUseCase: makePlayBookUseCase(),
            libraryRepository: api.libraryRepository,
            coverPreloadService: makeCoverPreloadService(),
            downloadManager: services.downloadManager,
            appState: AppStateManager.shared,
            onBookSelected: { services.playerStateManager.showPlayerBasedOnSettings() }
        )
    }

    func makeSeriesViewModel() -> SeriesViewModel {
        SeriesViewModel(
            fetchSeriesUseCase: FetchSeriesUseCase(bookRepository: api.bookRepository),
            playBookUseCase: makePlayBookUseCase(),
            libraryRepository: api.libraryRepository,
            appState: AppStateManager.shared,
            onBookSelected: { services.playerStateManager.showPlayerBasedOnSettings() }
        )
    }

    func makeAuthorsViewModel() -> AuthorsViewModel {
        AuthorsViewModel(
            fetchAuthorsUseCase: FetchAuthorsUseCase(bookRepository: api.bookRepository),
            libraryRepository: api.libraryRepository,
            api: api.client
        )
    }

    func makeDownloadsViewModel() -> DownloadsViewModel {
        DownloadsViewModel(
            downloadManager: services.downloadManager,
            player: services.player,
            api: api.client,
            appState: AppStateManager.shared,
            storageMonitor: services.storageMonitor,
            onBookSelected: { services.playerStateManager.showPlayerBasedOnSettings() }
        )
    }

    // MARK: - Detail ViewModels

    func makeSettingsViewModel() -> SettingsViewModel {
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
            libraryRepositoryFactory: { baseURL, token in
                LibraryRepository(
                    api: AudiobookshelfClient(baseURL: baseURL, authToken: token),
                    settingsRepository: SettingsRepository()
                )
            }
        )
    }

    func makeBookDetailViewModel(bookId: String) -> BookDetailViewModel {
        BookDetailViewModel(
            bookId: bookId,
            bookRepository: api.bookRepository,
            downloadManager: services.downloadManager,
            api: api.client
        )
    }

    func makeAuthorDetailViewModel(
        author: Author,
        onBookSelected: @escaping () -> Void
    ) -> AuthorDetailViewModel {
        AuthorDetailViewModel(
            bookRepository: api.bookRepository,
            libraryRepository: api.libraryRepository,
            playBookUseCase: makePlayBookUseCase(),
            coverPreloadService: makeCoverPreloadService(),
            downloadManager: services.downloadManager,
            author: author,
            onBookSelected: onBookSelected
        )
    }

    func makeSeriesDetailViewModel(
        series: Series,
        onBookSelected: @escaping () -> Void
    ) -> SeriesDetailViewModel {
        SeriesDetailViewModel(
            series: series,
            container: DependencyContainer.shared,
            onBookSelected: onBookSelected
        )
    }

    func makeSeriesDetailViewModel(
        seriesBook: Book,
        onBookSelected: @escaping () -> Void
    ) -> SeriesDetailViewModel {
        SeriesDetailViewModel(
            seriesBook: seriesBook,
            container: DependencyContainer.shared,
            onBookSelected: onBookSelected
        )
    }
}
