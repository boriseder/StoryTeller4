import SwiftUI

// MARK: - Welcome View
struct WelcomeView: View {
    let onComplete: () -> Void
    
    @State private var currentPage = 0
    @State private var viewModel = DependencyContainer.shared.makeSettingsViewModel()
    
    private let totalPages = 4 // Erhöht auf 4 Seiten
    
    var body: some View {
        VStack(spacing: 0) {
            // Skip button - nur auf Info-Seiten anzeigen
            if currentPage < 3 {
                HStack {
                    Spacer()
                    Button("Skip") {
                        currentPage = 3 // Direkt zur Setup-Seite
                    }
                    .foregroundColor(.white.opacity(0.8))
                    .padding()
                }
            } else {
                // Spacer für konsistentes Layout
                HStack {
                    Spacer()
                }
                .frame(height: 44)
            }
            
            // Page content
            Group {
                if currentPage < 3 {
                    TabView(selection: $currentPage) {
                        WelcomePageView(
                            systemImage: "headphones.circle.fill",
                            title: "Welcome to StoryTeller",
                            description: "Your personal audiobook library, powered by Audiobookshelf"
                        )
                        .tag(0)
                        
                        WelcomePageView(
                            systemImage: "arrow.down.circle.fill",
                            title: "Download & Listen Offline",
                            description: "Download your favorite audiobooks and listen anywhere, anytime"
                        )
                        .tag(1)
                        
                        WelcomePageView(
                            systemImage: "server.rack",
                            title: "Connect Your Server",
                            description: "Connect to your Audiobookshelf server to get started"
                        )
                        .tag(2)
                    }
                    .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                } else {
                    // Setup-Seite außerhalb der TabView für volle Interaktivität
                    SetupPageView(viewModel: viewModel, onComplete: onComplete)
                }
            }
            
            // Page indicator
            HStack(spacing: 8) {
                ForEach(0..<totalPages, id: \.self) { index in
                    Circle()
                        .fill(index == currentPage ? Color.white : Color.white.opacity(0.3))
                        .frame(width: 8, height: 8)
                        .animation(.easeInOut(duration: 0.2), value: currentPage)
                }
            }
            .padding(.bottom, 32)
            
            // Action button - nur auf Info-Seiten anzeigen
            if currentPage < 3 {
                Button(action: {
                    withAnimation {
                        currentPage += 1
                    }
                }) {
                    Text(currentPage == 2 ? "Setup Server" : "Next")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.white.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            } else {
                Spacer()
                    .frame(height: 72) // Platzhalter für konsistentes Layout
            }
        }
        .background(
            LinearGradient(
                colors: [
                    Color.accentColor,
                    Color.accentColor.opacity(0.8)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

// MARK: - Welcome Page View
struct WelcomePageView: View {
    let systemImage: String
    let title: String
    let description: String
    
    var body: some View {
        VStack(spacing: 32) {
            Image(systemName: systemImage)
                .font(.system(size: 80))
                .foregroundColor(.white)
            
            VStack(spacing: 16) {
                Text(title)
                    .font(.system(.title, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                
                Text(description)
                    .font(.body)
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .padding()
    }
}

// MARK: - Setup Page View
struct SetupPageView: View {
    @Bindable var viewModel: SettingsViewModel
    let onComplete: () -> Void
    
    @FocusState private var focusedField: Field?
    @State private var setupStep: SetupStep = .server
    
    enum Field {
        case host, port, username, password
    }
    
    enum SetupStep {
        case server, credentials, libraries, complete
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: stepIcon)
                        .font(.system(size: 50))
                        .foregroundColor(.white)
                    
                    Text(stepTitle)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Text(stepDescription)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .padding(.top, 20)
                
                // Content basierend auf Setup-Schritt
                switch setupStep {
                case .server:
                    serverSetupView
                case .credentials:
                    credentialsSetupView
                case .libraries:
                    librariesSetupView
                case .complete:
                    completeSetupView
                }
                
                Spacer()
            }
            .padding(.horizontal, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }
    
    // MARK: - Step Views
    
    private var serverSetupView: some View {
        VStack(spacing: 16) {
            VStack(spacing: 12) {
                // Protocol Picker
                HStack {
                    Text("Protocol")
                        .foregroundColor(.white.opacity(0.9))
                    Spacer()
                    Picker("Protocol", selection: $viewModel.serverConfig.scheme) {
                        Text("http").tag("http")
                        Text("https").tag("https")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                }
                .padding()
                .background(Color.white.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                
                // Host
                VStack(alignment: .leading, spacing: 6) {
                    Text("Server Address")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                    TextField("e.g., 192.168.1.100 or server.com", text: $viewModel.serverConfig.host)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .keyboardType(.URL)
                        .focused($focusedField, equals: .host)
                        .padding()
                        .background(Color.white.opacity(0.15))
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .onChange(of: viewModel.serverConfig.host) { _, _ in
                            viewModel.sanitizeHost()
                        }
                }
                
                // Port
                VStack(alignment: .leading, spacing: 6) {
                    Text("Port (optional)")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                    TextField("e.g., 13378", text: $viewModel.serverConfig.port)
                        .keyboardType(.numberPad)
                        .focused($focusedField, equals: .port)
                        .padding()
                        .background(Color.white.opacity(0.15))
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                
                // Server URL Preview
                if viewModel.serverConfig.isServerConfigured {
                    HStack {
                        Text("Server URL:")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                        Text(viewModel.serverConfig.fullServerURL)
                            .font(.caption)
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 4)
                }
                
                // Warning für HTTP
                if viewModel.serverConfig.scheme == "http" {
                    Label("HTTP is not secure. Use HTTPS when possible.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.yellow)
                        .padding(.horizontal, 4)
                }
            }
            
            // Test Connection Button
            Button(action: {
                focusedField = nil
                testConnectionAndProceed()
            }) {
                HStack {
                    if viewModel.isTestingConnection {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.9)
                        Text("Testing Connection...")
                    } else {
                        Image(systemName: "wifi")
                        Text("Test Connection")
                    }
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(viewModel.canTestConnection ? Color.white.opacity(0.25) : Color.white.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(!viewModel.canTestConnection || viewModel.isTestingConnection)
            .padding(.top, 8)
            
            // Connection Status
            if viewModel.connectionState != .initial {
                HStack {
                    Image(systemName: statusIcon)
                        .foregroundColor(viewModel.connectionState.statusColor)
                    Text(viewModel.connectionState.statusText)
                        .font(.subheadline)
                        .foregroundColor(viewModel.connectionState.statusColor)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.white.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    
    private var credentialsSetupView: some View {
        VStack(spacing: 16) {
            VStack(spacing: 12) {
                // Username
                VStack(alignment: .leading, spacing: 6) {
                    Text("Username")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                    TextField("Your username", text: $viewModel.serverConfig.username)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .focused($focusedField, equals: .username)
                        .padding()
                        .background(Color.white.opacity(0.15))
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                
                // Password
                VStack(alignment: .leading, spacing: 6) {
                    Text("Password")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                    SecureField("Your password", text: $viewModel.serverConfig.password)
                        .focused($focusedField, equals: .password)
                        .padding()
                        .background(Color.white.opacity(0.15))
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            
            // Login Button
            Button(action: {
                focusedField = nil
                loginAndProceed()
            }) {
                HStack {
                    if viewModel.isTestingConnection {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.9)
                        Text("Logging in...")
                    } else {
                        Image(systemName: "person.badge.key")
                        Text("Login")
                    }
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(viewModel.canLogin ? Color.white.opacity(0.25) : Color.white.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(!viewModel.canLogin || viewModel.isTestingConnection)
            .padding(.top, 8)
            
            // Back Button
            Button(action: {
                setupStep = .server
            }) {
                HStack {
                    Image(systemName: "chevron.left")
                    Text("Back to Server")
                }
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
            }
            .padding(.top, 8)
            
            // Authentication Status
            if case .failed(let error) = viewModel.connectionState {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.red)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.white.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    
    private var librariesSetupView: some View {
        VStack(spacing: 16) {
            if viewModel.libraries.isEmpty {
                HStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    Text("Loading libraries...")
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding()
            } else {
                VStack(spacing: 12) {
                    Text("Select your default library")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                    
                    ForEach(viewModel.libraries, id: \.id) { library in
                        Button(action: {
                            viewModel.selectedLibraryId = library.id
                        }) {
                            HStack {
                                Image(systemName: "books.vertical.fill")
                                    .foregroundColor(.white)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(library.name)
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    if let mediaType = library.mediaType {
                                        Text(mediaType)
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.7))
                                    }
                                }
                                Spacer()
                                if viewModel.selectedLibraryId == library.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.white)
                                        .font(.title3)
                                }
                            }
                            .padding()
                            .background(
                                viewModel.selectedLibraryId == library.id
                                    ? Color.white.opacity(0.25)
                                    : Color.white.opacity(0.1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                
                Button(action: {
                    if let selectedId = viewModel.selectedLibraryId {
                        viewModel.saveSelectedLibrary(selectedId)
                    }
                    setupStep = .complete
                }) {
                    HStack {
                        Image(systemName: "checkmark")
                        Text("Continue")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(viewModel.selectedLibraryId != nil ? Color.white.opacity(0.25) : Color.white.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(viewModel.selectedLibraryId == nil)
                .padding(.top, 8)
                
                Button(action: {
                    setupStep = .credentials
                }) {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                }
                .padding(.top, 8)
            }
        }
    }
    
    private var completeSetupView: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.white)
            
            VStack(spacing: 12) {
                Text("All Set!")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text("Your connection to Audiobookshelf is ready.")
                    .font(.body)
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
            }
            
            VStack(spacing: 8) {
                infoRow(icon: "server.rack", label: "Server", value: viewModel.serverConfig.host)
                infoRow(icon: "person.fill", label: "User", value: viewModel.serverConfig.username)
                if let selectedLibrary = viewModel.libraries.first(where: { $0.id == viewModel.selectedLibraryId }) {
                    infoRow(icon: "books.vertical.fill", label: "Library", value: selectedLibrary.name)
                }
            }
            .padding()
            .background(Color.white.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            Button(action: onComplete) {
                HStack {
                    Text("Start Listening")
                    Image(systemName: "arrow.right")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.white.opacity(0.25))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.top, 8)
        }
        .padding(.top, 40)
    }
    
    // MARK: - Helper Views
    
    private func infoRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 24)
            Text(label)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .lineLimit(1)
        }
    }
    
    // MARK: - Computed Properties
    
    private var stepIcon: String {
        switch setupStep {
        case .server: return "server.rack"
        case .credentials: return "person.badge.key"
        case .libraries: return "books.vertical.fill"
        case .complete: return "checkmark.circle.fill"
        }
    }
    
    private var stepTitle: String {
        switch setupStep {
        case .server: return "Server Configuration"
        case .credentials: return "Authentication"
        case .libraries: return "Choose Library"
        case .complete: return "Setup Complete"
        }
    }
    
    private var stepDescription: String {
        switch setupStep {
        case .server: return "Enter your Audiobookshelf server address"
        case .credentials: return "Login with your credentials"
        case .libraries: return "Select your default audiobook library"
        case .complete: return "You're ready to start listening!"
        }
    }
    
    private var statusIcon: String {
        switch viewModel.connectionState {
        case .serverFound: return "checkmark.circle.fill"
        case .authenticated: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        default: return "info.circle.fill"
        }
    }
    
    // MARK: - Actions
    
    private func testConnectionAndProceed() {
        viewModel.testConnection()
        
        // Warte auf Ergebnis und gehe weiter
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 Sekunden
            
            while viewModel.isTestingConnection {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 Sekunden
            }
            
            if viewModel.connectionState == .serverFound {
                await MainActor.run {
                    withAnimation {
                        setupStep = .credentials
                    }
                }
            }
        }
    }
    
    private func loginAndProceed() {
        viewModel.login()
        
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            
            while viewModel.isTestingConnection {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            
            if viewModel.isLoggedIn && viewModel.connectionState == .authenticated {
                await MainActor.run {
                    withAnimation {
                        setupStep = .libraries
                    }
                }
            }
        }
    }
}
