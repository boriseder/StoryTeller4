import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = DependencyContainer.shared.settingsViewModel
    @EnvironmentObject var theme: ThemeManager

    @State private var selectedColor: Color = .blue

    @AppStorage("open_fullscreen_player") private var openFullscreenPlayer = false
    @AppStorage("auto_play_on_book_tap") private var autoPlayOnBookTap = false

    let colors: [Color] = [.red, .orange, .green, .blue, .purple, .pink]

    
    
    var body: some View {
        NavigationStack {
            formContent
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.large)
                .task {
                    await viewModel.calculateStorageInfo()
                }
                .modifier(AlertsModifier(viewModel: viewModel))
        }
    }
    
    private var formContent: some View {
        Form {
            themeSection
            playbackSection
            
            if viewModel.isLoggedIn {
                librariesSection
            }

            storageSection

            serverSection
            
            credentialsSection

            if viewModel.serverConfig.isServerConfigured {
                connectionSection
            }
            
            
            
            aboutSection
            advancedSection
        }
    }
    
    // MARK: Theme Settings
    
    private var themeSection: some View {
            Section {
                // Background Style
                Picker("Select Theme", selection: $theme.backgroundStyle) {
                    ForEach(UserBackgroundStyle.allCases, id: \.self) { option in
                        Text(option.rawValue.capitalized).tag(option)
                    }
                }
                .pickerStyle(.menu)
                    
                HStack {
                    Text("Accent Color")
                    Spacer()
                    Menu {
                        ForEach(UserAccentColor.allCases) { colorOption in
                            Button {
                                theme.accentColor = colorOption
                            } label: {
                                Label(colorOption.rawValue.capitalized, systemImage: "circle.fill")
                                if theme.accentColor == colorOption {
                                    Image(systemName: "checkmark")
                                }
                            }
                            .tint(colorOption.color)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "circle.fill")
                                .foregroundStyle(theme.accent)
                            Text(theme.accentColor.rawValue.capitalized)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

            } header: {
                Label("Appearance", systemImage: "paintbrush")
            }
    }
    
    
    // MARK:  Playback Settings

    private var playbackSection: some View {
        Section {
            // Background Style
                Toggle("Fullscreen-Player on Play", isOn: $openFullscreenPlayer)
                Toggle("Enable Autoplay on Book Tap", isOn: $autoPlayOnBookTap)


        } header: {
            Label("Playback modes", systemImage: "play.rectangle.on.rectangle")
        }

    }
    
    
    // MARK: - Libraries Section
    
    private var librariesSection: some View {
        Section {
            if viewModel.libraries.isEmpty {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading libraries...")
                        .font(DSText.detail)

                }
            } else {
                Picker("Active Library", selection: $viewModel.selectedLibraryId) {
                    Text("No selection").tag(nil as String?)
                        .font(DSText.detail)

                    ForEach(viewModel.libraries, id: \.id) { library in
                        HStack {
                            Text(library.name)
                            .font(DSText.detail)

                        }
                        .tag(library.id as String?)
                    }
                }
                .onChange(of: viewModel.selectedLibraryId) { _, newId in
                    viewModel.saveSelectedLibrary(newId)
                }
                
                HStack {
                    Text("Total Libraries")
                        .font(DSText.footnote)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(viewModel.libraries.count)")
                        .font(DSText.footnote)
                        .foregroundColor(.secondary)
                }
            }
        } header: {
            Label("Libraries", systemImage: "books.vertical")
        } footer: { }
    }

    // MARK: - Server Section
    
    private var serverSection: some View {
        Section {
            Picker("Protocol", selection: $viewModel.serverConfig.scheme) {
                Text("http").tag("http")
                Text("https").tag("https")
            }
            .disabled(viewModel.isLoggedIn)
            
            TextField("Host", text: $viewModel.serverConfig.host)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .keyboardType(.URL)
                .disabled(viewModel.isLoggedIn)
                .onChange(of: viewModel.serverConfig.host) { _, _ in
                    viewModel.sanitizeHost()
                }
            
            TextField("Port", text: $viewModel.serverConfig.port)
                .keyboardType(.numberPad)
                .disabled(viewModel.isLoggedIn)
            
            if viewModel.serverConfig.isServerConfigured {
                HStack {
                    Text("Server URL")
                        .font(DSText.footnote)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(viewModel.serverConfig.fullServerURL)
                        .font(DSText.footnote)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        } header: {
            Label("Audiobookshelf Server", systemImage: "server.rack")
        } footer: {
            if viewModel.serverConfig.scheme == "http" {
                Label("HTTP is not secure. Use HTTPS when possible.", systemImage: "exclamationmark.triangle.fill")
                    .font(DSText.footnote)
                    .foregroundColor(.orange)
            } else {
                Text("Enter the address of your Audiobookshelf server")
                    .font(DSText.footnote)
            }
        }
    }
    
    // MARK: - Connection Section
    
    private var connectionSection: some View {
        Section {
            if viewModel.isTestingConnection {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Testing connection...")
                        .foregroundColor(.secondary)
                }
            } else if viewModel.connectionState != .initial {
                HStack {
                    Text(viewModel.connectionState.statusText)
                        .foregroundColor(viewModel.connectionState.statusColor)
                    Spacer()
                    if viewModel.connectionState == .authenticated {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else if case .failed = viewModel.connectionState {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                    }
                }
            }
            
            if !viewModel.isLoggedIn {
                Button("Test Connection") {
                    viewModel.testConnection()
                }
                .disabled(!viewModel.canTestConnection)
            }
        } header: {
            Label("Connection Status", systemImage: "wifi")
        }
    }

    
    // MARK: - Credentials Section

    private var credentialsSection: some View {
        Section {
            if viewModel.isLoggedIn {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Logged in as")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(viewModel.serverConfig.username)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
                
                Button("Logout") {
                    viewModel.showingLogoutAlert = true
                }
                .foregroundColor(.red)
            } else {
                TextField("Username", text: $viewModel.serverConfig.username)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                
                SecureField("Password", text: $viewModel.serverConfig.password)
                
                Button("Login") {
                    viewModel.login()
                }
                .disabled(!viewModel.canLogin)
                
                // NEW: Show loading state after login
                if viewModel.isTestingConnection {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Logging in and setting up...")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        } header: {
            Label("Authentication", systemImage: "person.badge.key")
        } footer: {
            if !viewModel.isLoggedIn && !viewModel.isTestingConnection {
                Text("Enter your Audiobookshelf credentials to connect")
                    .font(.caption2)
            } else if viewModel.isTestingConnection {
                Text("Please wait while we validate your credentials and load your libraries")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
        }
    }
    
    
    // MARK: - Storage Section
    
    private var storageSection: some View {
        Section {
            if viewModel.storage.isCalculatingStorage {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Calculating storage...")
                        .foregroundColor(.secondary)
                }
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Cache")
                            .font(.subheadline)
                        Text("Metadata, cover images and other temp. files")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(viewModel.storage.totalCacheSize)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
                
                if viewModel.storage.cacheOperationInProgress {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Clearing cache...")
                            .foregroundColor(.secondary)
                    }
                } else {
                    Button("Clear All Cache") {
                        viewModel.showingClearCacheAlert = true
                    }
                    .foregroundColor(.orange)
                    
                    if let lastCleanup = viewModel.storage.lastCacheCleanupDate {
                        HStack {
                            Text("Last cleared")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(lastCleanup, style: .relative)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Downloads")
                            .font(.subheadline)
                        Text("\(viewModel.storage.downloadedBooksCount) books available offline")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(viewModel.storage.totalDownloadSize)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
                
                if viewModel.storage.downloadedBooksCount > 0 {
                    Button("Delete All Downloads") {
                        viewModel.showingClearDownloadsAlert = true
                    }
                    .foregroundColor(.red)
                }
            }
        } header: {
            Label("Storage & Downloads", systemImage: "internaldrive")
        } footer: {
            Text("Cache contains temporary files and can be safely cleared. Downloaded books are stored separately.")
                .font(.caption2)
        }
    }
    
    
    // MARK: - About Section
    
    private var aboutSection: some View {
        Section {
            HStack {
                Text("App Version")
                Spacer()
                Text(getAppVersion())
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            
            HStack {
                Text("Build")
                Spacer()
                Text(getBuildNumber())
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            
            Link(destination: URL(string: "https://github.com/yourusername/storyteller")!) {
                HStack {
                    Text("GitHub Repository")
                    Spacer()
                    Image(systemName: "arrow.up.forward")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Link(destination: URL(string: "https://www.audiobookshelf.org")!) {
                HStack {
                    Text("Audiobookshelf Project")
                    Spacer()
                    Image(systemName: "arrow.up.forward")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        } header: {
            Label("About", systemImage: "info.circle")
        }
    }
    
    // MARK: - Advanced Section
    
    private var advancedSection: some View {
        Group {
            
            Section {
                NavigationLink(destination: DebugView()) {
                    Label("Debug Settings", systemImage: "gearshape.2")
                }
            } footer: {
                Text("Enable or disable various features for development purposes")
                    .font(.caption2)
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func getAppVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }
    
    private func getBuildNumber() -> String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }
}

private struct AlertsModifier: ViewModifier {
    @ObservedObject var viewModel: SettingsViewModel
    
    func body(content: Content) -> some View {
        content
            .alert("Clear All Cache?", isPresented: $viewModel.showingClearCacheAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Clear \(viewModel.storage.totalCacheSize)", role: .destructive) {
                    Task { await viewModel.clearAllCache() }
                }
            } message: {
                Text("This will clear all cached data including cover images and metadata. Downloaded books are not affected.")
            }
            .alert("Delete All Downloads?", isPresented: $viewModel.showingClearDownloadsAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Delete All", role: .destructive) {
                    Task { await viewModel.clearAllDownloads() }
                }
            } message: {
                Text("This will permanently delete all \(viewModel.storage.downloadedBooksCount) downloaded books. You can re-download them anytime when online.")
            }
            .alert("Logout?", isPresented: $viewModel.showingLogoutAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Logout", role: .destructive) {
                    viewModel.logout()
                }
            } message: {
                Text("You will need to enter your credentials again to reconnect.")
            }
            .alert("Connection Test", isPresented: $viewModel.showingTestResults) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.testResultMessage)
            }
    }
}

struct AccentColorSettings: View {
    @Binding var selectedColor: Color
    let colors: [Color] = [.red, .orange, .green, .blue, .purple, .pink]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Accent Color")
                .font(.headline)

            HStack(spacing: 16) {
                ForEach(colors, id: \.self) { color in
                    Circle()
                        .fill(color)
                        .frame(width: 36, height: 36)
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: selectedColor == color ? 3 : 0)
                        )
                        .onTapGesture {
                            selectedColor = color
                        }
                }
            }
        }
        .padding()
    }
}

