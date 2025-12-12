import SwiftUI
import Combine
import AVFoundation

struct ContentView: View {
    @Environment(AppStateManager.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @Environment(DependencyContainer.self) private var dependencies
    
    // MARK: - Hoisted ViewModels (All migrated to @Observable)
    @State private var homeViewModel: HomeViewModel
    @State private var libraryViewModel: LibraryViewModel
    @State private var seriesViewModel: SeriesViewModel
    @State private var authorsViewModel: AuthorsViewModel
    @State private var downloadsViewModel: DownloadsViewModel
    
    @State private var selectedTab: TabIndex = .home
    @State private var bookCount = 0
    @State private var cancellables = Set<AnyCancellable>()
    
    // Dependencies accessed via Environment
    private var player: AudioPlayer { dependencies.player }
    private var downloadManager: DownloadManager { dependencies.downloadManager }
    private var playerStateManager: PlayerStateManager { dependencies.playerStateManager }
    
    @State var columnVisibility: NavigationSplitViewVisibility = .automatic
    
    // Accessed directly from shared for init (before environment is available)
    let api = DependencyContainer.shared.apiClient
    
    init() {
        let container = DependencyContainer.shared
        
        // ViewModels initialized via State(initialValue:)
        _homeViewModel = State(initialValue: container.makeHomeViewModel())
        _libraryViewModel = State(initialValue: container.makeLibraryViewModel())
        _seriesViewModel = State(initialValue: container.makeSeriesViewModel())
        _authorsViewModel = State(initialValue: container.makeAuthorsViewModel())
        _downloadsViewModel = State(initialValue: container.makeDownloadsViewModel())
    }
    
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
                        } else {
                            appState.showingSettings = true
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
            Task {
                setupApp()
            }
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
                                Task { setupApp() }
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $appState.showingWelcome) {
            WelcomeView {
                appState.showingWelcome = false
                appState.isFirstLaunch = false
                appState.showingSettings = true
            }
            .ignoresSafeArea()
        }
    }
    
    private var mainContent: some View {
        FullscreenPlayerContainer(
            player: player,
            playerStateManager: playerStateManager,
            api: api
        ) {
            if DeviceType.current == .iPad {
                iPadLayout
            } else {
                iPhoneLayout
            }
        }
        // FIX: Update from .environmentObject() to .environment()
        .environment(dependencies.sleepTimerService)
    }
    // MARK: - iPad Layout (Sidebar)
    
    private var iPadLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            iPadSidebarContent
                // FIX: Use .environment() for @Observable objects, NOT .environmentObject()
                .environment(dependencies)
        } detail: {
            selectedTabView
        }
        .accentColor(theme.accent)
        .id(theme.accent)
    }
    
    private var iPadSidebarContent: some View {
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
                Button(action: {
                    appState.showingSettings = true
                }) {
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
                LibrarySidebarFilters(viewModel: libraryViewModel)
            } else if appState.selectedTab == .series {
                SeriesSidebarSort(viewModel: seriesViewModel)
            }
            
            if appState.selectedTab == .library || appState.selectedTab == .series || appState.selectedTab == .downloads {
                Section("Library Info") {
                    HStack {
                        Image(systemName: "books.vertical.fill")
                            .foregroundColor(.blue)
                        Text("Books")
                        Spacer()
                        Text("\(libraryViewModel.totalBooksCount)")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Image(systemName: "arrow.down.circle")
                            .foregroundColor(.green)
                        Text("Downloaded")
                        Spacer()
                        Text("\(downloadManager.downloadedBooks.count)")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Image(systemName: appState.isDeviceOnline ? "icloud" : "icloud.slash")
                            .foregroundColor(appState.isDeviceOnline ? .green : .red)
                        Text("Status")
                        Spacer()
                        Text(appState.isDeviceOnline ? "Online" : "Offline")
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .navigationTitle("StoryTeller")
        .listStyle(.sidebar)
    }
    
    private var iPhoneLayout: some View {
        @Bindable var appState = appState
        
        return TabView(selection: $appState.selectedTab) {
            homeTab
            libraryTab
            seriesTab
            authorsTab
            downloadsTab
        }
        .accentColor(theme.accent)
        .id(theme.accent)
    }
    
    @ViewBuilder
    private var selectedTabView: some View {
        switch appState.selectedTab {
        case .home:
            NavigationStack {
                HomeView(viewModel: homeViewModel)
            }
        case .library:
            NavigationStack {
                LibraryView(viewModel: libraryViewModel, columnVisibility: $columnVisibility)
            }
        case .series:
            NavigationStack {
                SeriesView(viewModel: seriesViewModel)
            }
        case .authors:
            NavigationStack {
                AuthorsView(viewModel: authorsViewModel)
            }
        case .downloads:
            NavigationStack {
                DownloadsView(viewModel: downloadsViewModel)
            }
        }
    }
    
    private var homeTab: some View {
        NavigationStack {
            HomeView(viewModel: homeViewModel)
        }
        .tabItem {
            Image(systemName: "sharedwithyou")
            Text("Explore")
        }
        .tag(TabIndex.home)
    }
    
    private var libraryTab: some View {
        NavigationStack {
            LibraryView(viewModel: libraryViewModel, columnVisibility: $columnVisibility)
        }
        .tabItem {
            Image(systemName: "books.vertical.fill")
            Text("Library")
        }
        .tag(TabIndex.library)
    }
    
    private var seriesTab: some View {
        NavigationStack {
            SeriesView(viewModel: seriesViewModel)
        }
        .tabItem {
            Image(systemName: "play.square.stack.fill")
            Text("Series")
        }
        .tag(TabIndex.series)
    }
    
    private var authorsTab: some View {
        NavigationStack {
            AuthorsView(viewModel: authorsViewModel)
        }
        .tabItem {
            Image(systemName: "person.2")
            Text("Authors")
        }
        .tag(TabIndex.authors)
    }
    
    private var downloadsTab: some View {
        NavigationStack {
            DownloadsView(viewModel: downloadsViewModel)
        }
        .tabItem {
            Image(systemName: "arrow.down.circle.fill")
            Text("Downloads")
        }
        .badge(downloadManager.downloadedBooks.count)
        .tag(TabIndex.downloads)
    }
    
    private func setupApp() {
        Task { @MainActor in
            appState.loadingState = .loadingCredentials
            
            guard let baseURL = UserDefaults.standard.string(forKey: "baseURL"),
                  let username = UserDefaults.standard.string(forKey: "stored_username") else {
                appState.loadingState = .noCredentialsSaved
                return
            }
            
            self.bookCount = await downloadManager.preloadDownloadedBooksCount()
            
            appState.loadingState = .credentialsFoundValidating
            
            do {
                let token = try KeychainService.shared.getToken(for: username)
                dependencies.configureAPI(baseURL: baseURL, token: token)
                
                // FIX: Recreate ViewModels now that dependencies are configured
                // This ensures they use the valid API client instead of the placeholder
                homeViewModel = dependencies.makeHomeViewModel()
                libraryViewModel = dependencies.makeLibraryViewModel()
                seriesViewModel = dependencies.makeSeriesViewModel()
                authorsViewModel = dependencies.makeAuthorsViewModel()
                downloadsViewModel = dependencies.makeDownloadsViewModel()
                
                let client = dependencies.apiClient!
                let connectionResult = await testConnection(client: client)
                
                switch connectionResult {
                
                case .success:
                    appState.isServerReachable = true
                    player.configure(baseURL: baseURL, authToken: token, downloadManager: downloadManager)
                    appState.loadingState = .loadingData
                    await initAppLibrary(client: client)
                    await dependencies.initializeSharedRepositories(isOnline: true)
                    appState.loadingState = .ready
                    configureAudioSession()
                    setupCacheManager()
                    
                case .networkError(let issueType):
                    appState.isServerReachable = false
                    appState.loadingState = .networkError(issueType)
                    await dependencies.initializeSharedRepositories(isOnline: false)
                    
                case .failed:
                    appState.isServerReachable = false
                    appState.loadingState = .networkError(ConnectionIssueType.serverError)
                    await dependencies.initializeSharedRepositories(isOnline: false)
                    
                case .authenticationError:
                    appState.loadingState = .authenticationError
                    await dependencies.initializeSharedRepositories(isOnline: false)
                }
            } catch {
                AppLogger.general.error("[ContentView] Keychain error: \(error)")
                appState.loadingState = .authenticationError
                await dependencies.initializeSharedRepositories(isOnline: false)
            }
        }
    }
    
    private func initAppLibrary(client: AudiobookshelfClient) async {
        let libraryRepository = dependencies.libraryRepository
        do {
            let selectedLibrary = try await libraryRepository.initializeLibrarySelection()
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
                AppLogger.general.error("[ContentView] No internet - offline mode available")
            case .timedOut:
                AppLogger.general.error("[ContentView] Timeout - server might be slow")
            default:
                AppLogger.general.error("[ContentView] Network error: \(urlError)")
            }
        case .decodingError:
            AppLogger.general.error("[ContentView] Data format error - check server version")
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
    
    private func configureAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .spokenAudio)
            try audioSession.setActive(true)
        } catch {
            AppLogger.general.error("[App] ❌ Failed to configure audio session: \(error)")
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
            // Sort Options
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
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Sort Direction
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
            
            // Downloaded Only Filter
            Button {
                viewModel.toggleDownloadFilter()
            } label: {
                HStack {
                    Label("Downloaded Only", systemImage: "arrow.down.circle")
                    Spacer()
                    if viewModel.filterState.showDownloadedOnly {
                        Image(systemName: "checkmark")
                            .foregroundColor(.accentColor)
                    }
                }
            }
            
            // Series Grouped
            Button {
                viewModel.toggleSeriesMode()
            } label: {
                HStack {
                    Label("Group Series", systemImage: "square.stack.3d.up")
                    Spacer()
                    if viewModel.filterState.showSeriesGrouped {
                        Image(systemName: "checkmark")
                            .foregroundColor(.accentColor)
                    }
                }
            }
            
            // Reset Filters
            if viewModel.filterState.hasActiveFilters {
                Button(role: .destructive) {
                    withAnimation(.spring(response: 0.3)) {
                        viewModel.resetFilters()
                    }
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
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

enum ConnectionTestResult {
    case success
    case networkError(ConnectionIssueType)
    case authenticationError
    case failed
}
