import Foundation

// MARK: - ViewModelFactory
//
// Stateless struct. Assembles ViewModels from ServiceContainer + APIContainer.
// No observable state, no re-renders triggered here.

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
            // Repository is accessed via the manager so the protocol seam is preserved.
            // Falls back to placeholder if the manager has no repository yet (shouldn't
            // happen in production since ServiceContainer wires it at init).
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
