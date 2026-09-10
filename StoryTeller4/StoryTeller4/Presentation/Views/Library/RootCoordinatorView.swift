import SwiftUI

// MARK: - Root Coordinator View
/// Handles app bootstrapping, credential validation, network status routing, and global sheet orchestration.
struct RootCoordinatorView<Content: View>: View {
    @Environment(AppStateManager.self) private var appState
    @Environment(DependencyContainer.self) private var dependencies
    
    let bookCount: Int
    let setupApp: () -> Void
    let content: Content

    init(
        bookCount: Int,
        setupApp: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.bookCount = bookCount
        self.setupApp = setupApp
        self.content = content()
    }

    var body: some View {
        @Bindable var appState = appState

        ZStack {
            DynamicBackground()

            switch appState.loadingState {
            case .initial, .loadingCredentials, .credentialsFoundValidating, .loadingData:
                LoadingView(message: "Loading data...")
                    .padding(.bottom, 80)

            case .noCredentialsSaved, .authenticationError:
                Color.clear
                    .onAppear {
                        if UserDefaults.standard.string(forKey: "stored_username") != nil {
                            setupApp()
                        } else if appState.isFirstLaunch {
                            appState.showingWelcome = true
                        }
                    }

            case .networkError(_):
                if bookCount > 0 {
                    content
                        .onAppear {
                            appState.selectedTab = .downloads
                            appState.loadingState = .ready
                        }
                } else {
                    ContentUnavailableView(
                        "No Downloaded Books",
                        systemImage: "arrow.down.circle",
                        description: Text("Download books to enjoy them offline.")
                    )
                }

            case .ready:
                content
            }
        }
        .onAppear(perform: setupApp)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            if UserDefaults.standard.bool(forKey: "auto_cache_cleanup") {
                Task { await CoverCacheManager.shared.optimizeCache() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .serverSettingsChanged)) { _ in
            appState.clearConnectionIssue()
            setupApp()
        }
        .onReceive(NotificationCenter.default.publisher(for: .showSettings)) { _ in
            appState.showingSettings = true
        }
        .sheet(isPresented: $appState.showingSettings) {
            NavigationStack {
                SettingsView(viewModel: dependencies.makeSettingsViewModel())
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
            WelcomeView(viewModel: dependencies.makeSettingsViewModel()) {
                appState.showingWelcome = false
                appState.isFirstLaunch = false
                appState.showingSettings = false
            }
        }
    }
}
