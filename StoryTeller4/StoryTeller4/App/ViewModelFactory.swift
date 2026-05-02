import Foundation

// MARK: - ViewModelFactory
//
// A stateless struct that knows how to assemble ViewModels from the two
// containers. It holds no observable state of its own — there is nothing
// here that would cause a re-render. Callers own the resulting ViewModels
// via @State and are responsible for their lifetime.
//
// All methods are intentionally non-mutating. If a factory method needs
// something that isn't available yet (e.g. apiContainer is nil) the call
// site must guard before calling.

@MainActor
struct ViewModelFactory {

    let services: ServiceContainer
    let api: APIContainer

    // MARK: - Tab ViewModels

    func makeHomeViewModel() -> HomeViewModel {
        HomeViewModel(
            fetchPersonalizedSectionsUseCase: FetchPersonalizedSectionsUseCase(
                bookRepository: api.bookRepository
            ),
            downloadRepository: services.downloadManager.repository ?? DefaultDownloadRepository.placeholder,
            libraryRepository: api.libraryRepository,
            bookRepository: api.bookRepository,
            api: api.client,
            downloadManager: services.downloadManager,
            player: services.player,
            appState: AppStateManager.shared,
            onBookSelected: { services.playerStateManager.showPlayerBasedOnSettings() }
        )
    }

    func makeLibraryViewModel() -> LibraryViewModel {
        LibraryViewModel(
            fetchBooksUseCase: FetchBooksUseCase(bookRepository: api.bookRepository),
            downloadRepository: services.downloadManager.repository ?? DefaultDownloadRepository.placeholder,
            libraryRepository: api.libraryRepository,
            api: api.client,
            downloadManager: services.downloadManager,
            player: services.player,
            appState: AppStateManager.shared,
            onBookSelected: { services.playerStateManager.showPlayerBasedOnSettings() }
        )
    }

    func makeSeriesViewModel() -> SeriesViewModel {
        SeriesViewModel(
            fetchSeriesUseCase: FetchSeriesUseCase(bookRepository: api.bookRepository),
            downloadRepository: services.downloadManager.repository ?? DefaultDownloadRepository.placeholder,
            libraryRepository: api.libraryRepository,
            api: api.client,
            downloadManager: services.downloadManager,
            player: services.player,
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
            fetchLibrariesUseCase: FetchLibrariesUseCase(),
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
            logoutUseCase: LogoutUseCase(keychainService: services.keychainService),
            serverValidator: services.serverValidator,
            coverCacheManager: services.coverCacheManager,
            downloadManager: services.downloadManager,
            settingsRepository: SettingsRepository()
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
            api: api.client,
            downloadManager: services.downloadManager,
            player: services.player,
            appState: AppStateManager.shared,
            playBookUseCase: PlayBookUseCase(),
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
            container: DependencyContainer.shared,  // SeriesDetailViewModel still takes the full container for now
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
