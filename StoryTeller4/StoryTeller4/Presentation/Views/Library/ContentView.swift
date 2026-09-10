import SwiftUI
import Combine
import AVFoundation

// MARK: - Content View
/// Root application container that orchestrates app bootstrapping and layout composition.
struct ContentView: View {
    @Environment(AppStateManager.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @Environment(DependencyContainer.self) private var dependencies
    
    @State private var homeViewModel: HomeViewModel?
    @State private var libraryViewModel: LibraryViewModel?
    @State private var seriesViewModel: SeriesViewModel?
    @State private var authorsViewModel: AuthorsViewModel?
    @State private var downloadsViewModel: DownloadsViewModel?
    @State private var bookCount = 0
    @State private var isMediaMode = true
    @State var columnVisibility: NavigationSplitViewVisibility = .automatic
    
    private var player: AudioPlayer { dependencies.player }
    private var downloadManager: DownloadManager { dependencies.downloadManager }
    private var playerStateManager: PlayerStateManager { dependencies.playerStateManager }

    var body: some View {
        RootCoordinatorView(bookCount: bookCount, setupApp: setupApp) {
            mainContent
        }
    }

    // MARK: - Main Content
    @ViewBuilder
    private var mainContent: some View {
        if let home = homeViewModel,
           let library = libraryViewModel,
           let series = seriesViewModel,
           let authors = authorsViewModel,
           let downloads = downloadsViewModel {
            PlayerContainer(
                player: player,
                playerStateManager: playerStateManager,
                api: dependencies.apiClient,
                sleepTimerService: dependencies.sleepTimerService
            ) {
                if DeviceType.current == .iPad {
                    iPadLayout(home: home, library: library, series: series, authors: authors, downloads: downloads)
                } else {
                    iPhoneLayout(home: home, library: library, series: series, authors: authors, downloads: downloads)
                }
            }
            .environment(dependencies.sleepTimerService)
        } else {
            LoadingView(message: "Loading data...")
                .padding(.bottom, 80)
        }
    }

    // MARK: - iPad Layout
    private func iPadLayout(
        home: HomeViewModel,
        library: LibraryViewModel,
        series: SeriesViewModel,
        authors: AuthorsViewModel,
        downloads: DownloadsViewModel
    ) -> some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            IPadSidebarView(library: library, series: series, downloads: downloads)
                .environment(dependencies)
        } detail: {
            selectedTabView(home: home, library: library, series: series, authors: authors, downloads: downloads)
        }
        .accentColor(theme.accent)
        .id(theme.accent)
    }

    // MARK: - iPhone Layout
    private func iPhoneLayout(
        home: HomeViewModel,
        library: LibraryViewModel,
        series: SeriesViewModel,
        authors: AuthorsViewModel,
        downloads: DownloadsViewModel
    ) -> some View {
        selectedTabView(home: home, library: library, series: series, authors: authors, downloads: downloads)
            .safeAreaInset(edge: .bottom) {
                AdaptiveMediaTabBar(
                    player: player,
                    api: dependencies.apiClient,
                    playerStateManager: playerStateManager,
                    selectedTab: Bindable(appState).selectedTab,
                    isMediaMode: $isMediaMode,
                    onTabSelected: { tab in appState.selectedTab = tab },
                    onExpandFullscreen: {
                        withAnimation(.easeInOut(duration: 0.35)) {
                            playerStateManager.showFullscreen()
                        }
                    }
                )
            }
            .accentColor(theme.accent)
            .id(theme.accent)
            .onChange(of: player.book) { _, newBook in
                if newBook != nil {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isMediaMode = true
                    }
                }
            }
    }

    // MARK: - Selected Tab View
    @ViewBuilder
    private func selectedTabView(
        home: HomeViewModel,
        library: LibraryViewModel,
        series: SeriesViewModel,
        authors: AuthorsViewModel,
        downloads: DownloadsViewModel
    ) -> some View {
        switch appState.selectedTab {
        case .home:
            NavigationStack { HomeView(viewModel: home) }
        case .library:
            NavigationStack { LibraryView(viewModel: library, columnVisibility: $columnVisibility) }
        case .series:
            NavigationStack { SeriesView(viewModel: series) }
        case .authors:
            NavigationStack { AuthorsView(viewModel: authors) }
        case .downloads:
            NavigationStack { DownloadsView(viewModel: downloads) }
        }
    }

    // MARK: - App Setup & Bootstrapping
    private func setupApp() {
        Task { @MainActor in
            appState.loadingState = .loadingCredentials

            guard let baseURL = UserDefaults.standard.string(forKey: AppStorageKey.baseURL.rawValue),
                  let username = UserDefaults.standard.string(forKey: AppStorageKey.storedUsername.rawValue) else {
                appState.loadingState = .noCredentialsSaved
                return
            }

            bookCount = await downloadManager.preloadDownloadedBooksCount()
            appState.loadingState = .credentialsFoundValidating

            do {
                let token = try KeychainService.shared.getToken(for: username)
                dependencies.configureAPI(baseURL: baseURL, token: token)

                let client = dependencies.apiClient!
                let connectionResult = await testConnection(client: client)

                switch connectionResult {
                case .success:
                    appState.isServerReachable = true
                    player.configure(baseURL: baseURL, authToken: token, downloadManager: downloadManager)
                    appState.loadingState = .loadingData
                    await initAppLibrary(client: client)
                    await dependencies.initializeSharedRepositories(isOnline: true)
                    rebuildViewModels()
                    appState.loadingState = .ready
                    setupCacheManager()

                case .networkError(let issueType):
                    appState.isServerReachable = false
                    await dependencies.initializeSharedRepositories(isOnline: false)
                    rebuildViewModels()
                    appState.loadingState = .networkError(issueType)

                case .failed, .authenticationError:
                    appState.isServerReachable = false
                    await dependencies.initializeSharedRepositories(isOnline: false)
                    rebuildViewModels()
                    appState.loadingState = connectionResult == .authenticationError
                        ? .authenticationError
                        : .networkError(.serverError)
                }

            } catch {
                AppLogger.general.error("[ContentView] Keychain error: \(error)")
                appState.loadingState = .authenticationError
                await dependencies.initializeSharedRepositories(isOnline: false)
            }
        }
    }

    private func rebuildViewModels() {
        if let home = dependencies.makeHomeViewModel(),
           let library = dependencies.makeLibraryViewModel(),
           let series = dependencies.makeSeriesViewModel(),
           let authors = dependencies.makeAuthorsViewModel(),
           let downloads = dependencies.makeDownloadsViewModel() {
            homeViewModel = home
            libraryViewModel = library
            seriesViewModel = series
            authorsViewModel = authors
            downloadsViewModel = downloads
        }
    }

    private func initAppLibrary(client: AudiobookshelfClient) async {
        guard let libraryRepository = dependencies.libraryRepository else { return }
        do {
            _ = try await libraryRepository.initializeLibrarySelection()
        } catch {
            AppLogger.general.error("[ContentView] Library init error: \(error)")
        }
    }

    private func testConnection(client: AudiobookshelfClient) async -> ConnectionTestResult {
        guard appState.isDeviceOnline else {
            return .networkError(.noInternet)
        }
        let isHealthy = await client.connection.checkHealth()
        guard isHealthy else {
            return .networkError(.serverUnreachable)
        }
        do {
            _ = try await client.libraries.fetchLibraries()
            return .success
        } catch AudiobookshelfError.unauthorized {
            return .authenticationError
        } catch AudiobookshelfError.serverError(let code, _) where code >= 500 {
            return .networkError(.serverError)
        } catch {
            return .networkError(.serverUnreachable)
        }
    }

    private func setupCacheManager() {
        Task { @MainActor in
            CoverCacheManager.shared.updateCacheLimits()
            if UserDefaults.standard.bool(forKey: "cache_optimization_enabled") {
                await CoverCacheManager.shared.optimizeCache()
            }
        }
    }
}

enum ConnectionTestResult: Equatable {
    case success
    case networkError(ConnectionIssueType)
    case authenticationError
    case failed
}
