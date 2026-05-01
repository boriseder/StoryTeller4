import SwiftUI
import Combine
import AVFoundation

struct ContentView: View {
    @Environment(AppStateManager.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @Environment(DependencyContainer.self) private var dependencies

    // MARK: - ViewModels
    //
    // These are nil until setupApp() has finished configuring the API client.
    // Creating them before that point is pointless — they all receive a placeholder
    // AudiobookshelfClient(baseURL: "", authToken: "") and immediately get thrown
    // away and recreated anyway. By deferring creation we guarantee they are always
    // built with real credentials.
    @State private var homeViewModel: HomeViewModel?
    @State private var libraryViewModel: LibraryViewModel?
    @State private var seriesViewModel: SeriesViewModel?
    @State private var authorsViewModel: AuthorsViewModel?
    @State private var downloadsViewModel: DownloadsViewModel?

    @State private var selectedTab: TabIndex = .home
    @State private var bookCount = 0
    @State private var cancellables = Set<AnyCancellable>()

    private var player: AudioPlayer { dependencies.player }
    private var downloadManager: DownloadManager { dependencies.downloadManager }
    private var playerStateManager: PlayerStateManager { dependencies.playerStateManager }

    @State var columnVisibility: NavigationSplitViewVisibility = .automatic

    var body: some View {
        @Bindable var appState = appState

        ZStack {
            Color.accent.ignoresSafeArea()

            switch appState.loadingState {

            case .initial, .loadingCredentials, .credentialsFoundValidating, .loadingData:
                LoadingView(message: "Loading data...")
                    .padding(.bottom, 80)

            case .noCredentialsSaved, .authenticationError:
                Color.clear
                    .onAppear {
                        if UserDefaults.standard.string(forKey: "stored_username") != nil {
                            Task { setupApp() }
                        } else if appState.isFirstLaunch {
                            appState.showingWelcome = true
                        }
                    }

            case .networkError(_):
                if bookCount > 0 {
                    mainContent
                        .onAppear {
                            appState.selectedTab = .downloads
                            appState.loadingState = .ready
                        }
                } else {
                    NoDownloadsView()
                }

            case .ready:
                mainContent
                    .ignoresSafeArea()
            }
        }
        .onAppear(perform: setupApp)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            if UserDefaults.standard.bool(forKey: "auto_cache_cleanup") {
                Task { await CoverCacheManager.shared.optimizeCache() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("ServerSettingsChanged"))) { _ in
            appState.clearConnectionIssue()
            Task { setupApp() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("ShowSettings"))) { _ in
            appState.showingSettings = true
        }
        .onDisappear {
            cancellables.removeAll()
        }
        .sheet(isPresented: $appState.showingSettings) {
            NavigationStack {
                SettingsView()
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Done") {
                                appState.showingSettings = false
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $appState.showingWelcome) {
            WelcomeView {
                appState.showingWelcome = false
                appState.isFirstLaunch = false
                appState.showingSettings = false
            }
            .ignoresSafeArea()
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        // Guard ensures we never render tabs with nil ViewModels.
        // In practice this can't be reached before .ready, but the compiler
        // needs the explicit unwrap.
        if let home = homeViewModel,
           let library = libraryViewModel,
           let series = seriesViewModel,
           let authors = authorsViewModel,
           let downloads = downloadsViewModel {
            FullscreenPlayerContainer(
                player: player,
                playerStateManager: playerStateManager,
                api: dependencies.apiClient
            ) {
                if DeviceType.current == .iPad {
                    iPadLayout(
                        home: home,
                        library: library,
                        series: series,
                        authors: authors,
                        downloads: downloads
                    )
                } else {
                    iPhoneLayout(
                        home: home,
                        library: library,
                        series: series,
                        authors: authors,
                        downloads: downloads
                    )
                }
            }
            .environment(dependencies.sleepTimerService)
        } else {
            // setupApp() is in progress — show a spinner rather than
            // crashing or rendering a broken state.
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
            iPadSidebarContent(library: library, series: series, downloads: downloads)
                .environment(dependencies)
        } detail: {
            selectedTabView(
                home: home,
                library: library,
                series: series,
                authors: authors,
                downloads: downloads
            )
        }
        .accentColor(theme.accent)
        .id(theme.accent)
    }

    private func iPadSidebarContent(
        library: LibraryViewModel,
        series: SeriesViewModel,
        downloads: DownloadsViewModel
    ) -> some View {
        List {
            Section {
                Button(action: { appState.selectedTab = .home }) {
                    HStack {
                        Label("Explore", systemImage: "sharedwithyou")
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .listRowBackground(appState.selectedTab == .home ? Color.accentColor.opacity(0.15) : Color.clear)

                Button(action: { appState.selectedTab = .library }) {
                    HStack {
                        Label("Library", systemImage: "books.vertical.fill")
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .listRowBackground(appState.selectedTab == .library ? Color.accentColor.opacity(0.15) : Color.clear)

                Button(action: { appState.selectedTab = .series }) {
                    HStack {
                        Label("Series", systemImage: "play.square.stack.fill")
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .listRowBackground(appState.selectedTab == .series ? Color.accentColor.opacity(0.15) : Color.clear)

                Button(action: { appState.selectedTab = .downloads }) {
                    HStack {
                        Label("Downloads", systemImage: "arrow.down.circle.fill")
                        Spacer()
                        if downloadManager.downloadedBooks.count > 0 {
                            Text("\(downloadManager.downloadedBooks.count)")
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.accentColor)
                                .clipShape(Capsule())
                        }
                    }
                    .contentShape(Rectangle())
                }
                .listRowBackground(appState.selectedTab == .downloads ? Color.accentColor.opacity(0.15) : Color.clear)
            }

            Section("Quick Actions") {
                Button(action: { appState.showingSettings = true }) {
                    Label("Settings", systemImage: "gearshape")
                }

                if appState.selectedTab == .library || appState.selectedTab == .series {
                    Button(action: {
                        NotificationCenter.default.post(name: .init("RefreshCurrentView"), object: nil)
                    }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
            }

            if appState.selectedTab == .library {
                LibrarySidebarFilters(viewModel: library)
            } else if appState.selectedTab == .series {
                SeriesSidebarSort(viewModel: series)
            }

            if appState.selectedTab == .library || appState.selectedTab == .series || appState.selectedTab == .downloads {
                Section("Library Info") {
                    HStack {
                        Image(systemName: "books.vertical.fill").foregroundColor(.blue)
                        Text("Books")
                        Spacer()
                        Text("\(library.totalBooksCount)").foregroundColor(.secondary)
                    }
                    HStack {
                        Image(systemName: "arrow.down.circle").foregroundColor(.green)
                        Text("Downloaded")
                        Spacer()
                        Text("\(downloadManager.downloadedBooks.count)").foregroundColor(.secondary)
                    }
                    HStack {
                        Image(systemName: appState.isDeviceOnline ? "icloud" : "icloud.slash")
                            .foregroundColor(appState.isDeviceOnline ? .green : .red)
                        Text("Status")
                        Spacer()
                        Text(appState.isDeviceOnline ? "Online" : "Offline").foregroundColor(.secondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .navigationTitle("StoryTeller")
        .listStyle(.sidebar)
    }

    // MARK: - iPhone Layout

    private func iPhoneLayout(
        home: HomeViewModel,
        library: LibraryViewModel,
        series: SeriesViewModel,
        authors: AuthorsViewModel,
        downloads: DownloadsViewModel
    ) -> some View {
        @Bindable var appState = appState

        return TabView(selection: $appState.selectedTab) {
            NavigationStack {
                HomeView(viewModel: home)
            }
            .tabItem { Image(systemName: "sharedwithyou"); Text("Explore") }
            .tag(TabIndex.home)

            NavigationStack {
                LibraryView(viewModel: library, columnVisibility: $columnVisibility)
            }
            .tabItem { Image(systemName: "books.vertical.fill"); Text("Library") }
            .tag(TabIndex.library)

            NavigationStack {
                SeriesView(viewModel: series)
            }
            .tabItem { Image(systemName: "play.square.stack.fill"); Text("Series") }
            .tag(TabIndex.series)

            NavigationStack {
                AuthorsView(viewModel: authors)
            }
            .tabItem { Image(systemName: "person.2"); Text("Authors") }
            .tag(TabIndex.authors)

            NavigationStack {
                DownloadsView(viewModel: downloads)
            }
            .tabItem { Image(systemName: "arrow.down.circle.fill"); Text("Downloads") }
            .badge(downloadManager.downloadedBooks.count)
            .tag(TabIndex.downloads)
        }
        .accentColor(theme.accent)
        .id(theme.accent)
    }

    // MARK: - iPad Selected Tab

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

    // MARK: - App Setup

    private func setupApp() {
        Task { @MainActor in
            appState.loadingState = .loadingCredentials

            guard let baseURL = UserDefaults.standard.string(forKey: "baseURL"),
                  let username = UserDefaults.standard.string(forKey: "stored_username") else {
                appState.loadingState = .noCredentialsSaved
                return
            }

            bookCount = await downloadManager.preloadDownloadedBooksCount()

            appState.loadingState = .credentialsFoundValidating

            do {
                let token = try KeychainService.shared.getToken(for: username)

                // Configure the container — this is the single point where
                // the real API client is created. All ViewModels are built
                // after this call so they all receive valid credentials.
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

                    // Build ViewModels here — after configureAPI() — so they
                    // receive the real client, not a placeholder.
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

    /// Creates all five ViewModels from the now-configured container.
    /// Called exactly once per setup cycle, after configureAPI().
    private func rebuildViewModels() {
        homeViewModel     = dependencies.makeHomeViewModel()
        libraryViewModel  = dependencies.makeLibraryViewModel()
        seriesViewModel   = dependencies.makeSeriesViewModel()
        authorsViewModel  = dependencies.makeAuthorsViewModel()
        downloadsViewModel = dependencies.makeDownloadsViewModel()
    }

    // MARK: - Helpers

    private func initAppLibrary(client: AudiobookshelfClient) async {
        do {
            let selectedLibrary = try await dependencies.libraryRepository.initializeLibrarySelection()
            if let library = selectedLibrary {
                AppLogger.general.info("[ContentView] Library initialized: \(library.name)")
            } else {
                AppLogger.general.warn("[ContentView] No libraries available")
            }
        } catch let error as RepositoryError {
            handleRepositoryError(error)
        } catch {
            AppLogger.general.error("[ContentView] Initial data load failed: \(error)")
        }
    }

    private func handleRepositoryError(_ error: RepositoryError) {
        switch error {
        case .networkError(let urlError as URLError):
            switch urlError.code {
            case .notConnectedToInternet:
                AppLogger.general.error("[ContentView] No internet — offline mode available")
            case .timedOut:
                AppLogger.general.error("[ContentView] Timeout — server might be slow")
            default:
                AppLogger.general.error("[ContentView] Network error: \(urlError)")
            }
        case .decodingError:
            AppLogger.general.error("[ContentView] Data format error — check server version")
        case .unauthorized:
            appState.loadingState = .authenticationError
        default:
            AppLogger.general.error("[ContentView] Repository error: \(error)")
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
}

// MARK: - Library Sidebar Filters

struct LibrarySidebarFilters: View {
    @Bindable var viewModel: LibraryViewModel

    var body: some View {
        Section("Filters & Sorting") {
            Menu {
                ForEach(LibrarySortOption.allCases) { option in
                    Button {
                        viewModel.filterState.selectedSortOption = option
                        viewModel.filterState.saveToDefaults()
                    } label: {
                        HStack {
                            Text(option.rawValue)
                            if viewModel.filterState.selectedSortOption == option {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "arrow.up.arrow.down")
                    Text("Sort: \(viewModel.filterState.selectedSortOption.rawValue)")
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                }
            }

            Button {
                viewModel.filterState.sortAscending.toggle()
                viewModel.filterState.saveToDefaults()
            } label: {
                HStack {
                    Image(systemName: viewModel.filterState.sortAscending ? "arrow.up" : "arrow.down")
                    Text(viewModel.filterState.sortAscending ? "Ascending" : "Descending")
                    Spacer()
                }
            }

            Button { viewModel.toggleDownloadFilter() } label: {
                HStack {
                    Label("Downloaded Only", systemImage: "arrow.down.circle")
                    Spacer()
                    if viewModel.filterState.showDownloadedOnly {
                        Image(systemName: "checkmark").foregroundColor(.accentColor)
                    }
                }
            }

            Button { viewModel.toggleSeriesMode() } label: {
                HStack {
                    Label("Group Series", systemImage: "square.stack.3d.up")
                    Spacer()
                    if viewModel.filterState.showSeriesGrouped {
                        Image(systemName: "checkmark").foregroundColor(.accentColor)
                    }
                }
            }

            if viewModel.filterState.hasActiveFilters {
                Button(role: .destructive) {
                    withAnimation(.spring(response: 0.3)) { viewModel.resetFilters() }
                } label: {
                    Label("Reset Filters", systemImage: "arrow.counterclockwise")
                }
            }
        }
    }
}

// MARK: - Series Sidebar Sort

struct SeriesSidebarSort: View {
    @Bindable var viewModel: SeriesViewModel

    var body: some View {
        Section("Sorting") {
            Menu {
                ForEach(SeriesSortOption.allCases, id: \.self) { option in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.filterState.selectedSortOption = option
                        }
                    } label: {
                        HStack {
                            Text(option.rawValue)
                            if viewModel.filterState.selectedSortOption == option {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "arrow.up.arrow.down")
                    Text("Sort: \(viewModel.filterState.selectedSortOption.rawValue)")
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - Connection Test Result

enum ConnectionTestResult: Equatable {
    case success
    case networkError(ConnectionIssueType)
    case authenticationError
    case failed
}
