import SwiftUI

@MainActor
class SettingsViewModel: ObservableObject {

    // MARK: - State Objects
    @Published var serverConfig = ServerConfigState()
    @Published var storage = StorageState()

    // MARK: - Connection State
    @Published var connectionState: ConnectionState = .initial
    @Published var isTestingConnection = false
    @Published var isLoggedIn: Bool = false
    
    // MARK: - Library State
    @Published var libraries: [Library] = []
    @Published var selectedLibraryId: String?
    
    // MARK: - UI State
    @Published var showingClearCacheAlert = false
    @Published var showingClearDownloadsAlert = false
    @Published var showingLogoutAlert = false
    @Published var showingTestResults = false
    @Published var testResultMessage: String = ""
    @Published var showingShareSheet = false
    @Published var shareURL: URL?
    
    // MARK: - Dependencies
    private let testConnectionUseCase: TestConnectionUseCaseProtocol
    private let authenticationUseCase: AuthenticationUseCaseProtocol
    private let fetchLibrariesUseCase: FetchLibrariesUseCaseProtocol
    private let calculateStorageUseCase: CalculateStorageUseCaseProtocol
    private let clearCacheUseCase: ClearCacheUseCaseProtocol
    private let saveCredentialsUseCase: SaveCredentialsUseCaseProtocol
    private let loadCredentialsUseCase: LoadCredentialsUseCaseProtocol
    private let logoutUseCase: LogoutUseCaseProtocol
    
    private let serverValidator: ServerConfigValidating
    private let coverCacheManager: CoverCacheManager
    
    let downloadManager: DownloadManager
    
    private var settingsRepository: SettingsRepositoryProtocol
    private var apiClient: AudiobookshelfClient?
   
    init(
        testConnectionUseCase: TestConnectionUseCaseProtocol,
        authenticationUseCase: AuthenticationUseCaseProtocol,
        fetchLibrariesUseCase: FetchLibrariesUseCaseProtocol,
        calculateStorageUseCase: CalculateStorageUseCaseProtocol,
        clearCacheUseCase: ClearCacheUseCaseProtocol,
        saveCredentialsUseCase: SaveCredentialsUseCaseProtocol,
        loadCredentialsUseCase: LoadCredentialsUseCaseProtocol,
        logoutUseCase: LogoutUseCaseProtocol,
        serverValidator: ServerConfigValidating,
        coverCacheManager: CoverCacheManager,
        downloadManager: DownloadManager,
        settingsRepository: SettingsRepositoryProtocol
    ) {
        self.testConnectionUseCase = testConnectionUseCase
        self.authenticationUseCase = authenticationUseCase
        self.fetchLibrariesUseCase = fetchLibrariesUseCase
        self.calculateStorageUseCase = calculateStorageUseCase
        self.clearCacheUseCase = clearCacheUseCase
        self.saveCredentialsUseCase = saveCredentialsUseCase
        self.loadCredentialsUseCase = loadCredentialsUseCase
        self.logoutUseCase = logoutUseCase
        self.serverValidator = serverValidator
        self.coverCacheManager = coverCacheManager
        self.downloadManager = downloadManager
        self.settingsRepository = settingsRepository
        
        Task { @MainActor in
            await loadSavedCredentials()
        }

    }


    // MARK: - Computed Properties

    var canTestConnection: Bool {
        serverConfig.isServerConfigured && !isTestingConnection
    }
    
    var canLogin: Bool {
        serverConfig.canLogin && !isLoggedIn
    }
    
    
    // MARK: - Connection State
    enum ConnectionState: Equatable {
        case initial
        case testing
        case serverFound
        case authenticated
        case failed(String)
        
        var statusText: String {
            switch self {
            case .initial: return ""
            case .testing: return "Testing connection..."
            case .serverFound: return "Server found - please login"
            case .authenticated: return "Connected"
            case .failed(let error): return error
            }
        }
        
        var statusColor: Color {
            switch self {
            case .initial: return .secondary
            case .testing: return .blue
            case .serverFound: return .orange
            case .authenticated: return .green
            case .failed: return .red
            }
        }
    }
    
    // MARK: - Connection Testing
    func testConnection() {
        guard canTestConnection else { return }
        
        let config = ServerConfig(
            scheme: serverConfig.scheme,
            host: serverConfig.host,
            port: serverConfig.port
        )
        
        switch serverValidator.validateServerConfig(config) {
        case .failure(let error):
            connectionState = .failed(error.localizedDescription)
            return
        case .success:
            break
        }
        
        isTestingConnection = true
        connectionState = .testing
        
        let baseURL = serverConfig.fullServerURL
        
        Task {
            let canPing = await testConnectionUseCase.execute(baseURL: baseURL)
            
            isTestingConnection = false
            
            if canPing {
                connectionState = .serverFound
                testResultMessage = """
                Server Status: Online
                URL: \(baseURL)
                
                Please enter credentials to login.
                """
                showingTestResults = true
            } else {
                connectionState = .failed("Server unreachable")
            }
        }
    }
    
    // MARK: - Input Validation
    func sanitizeHost() {
        serverConfig.host = serverValidator.sanitizeHost(serverConfig.host)
    }
    
    // MARK: - Authentication
    func login() {
        guard canLogin else { return }
        
        isTestingConnection = true
        connectionState = .testing
        
        let baseURL = serverConfig.fullServerURL
        let username = serverConfig.username
        let password = serverConfig.password
        
        Task {
            do {
                let token = try await authenticationUseCase.login(
                    baseURL: baseURL,
                    username: username,
                    password: password
                )
                
                isTestingConnection = false
                connectionState = .authenticated
                isLoggedIn = true
                
                await saveCredentials(token: token)
                
                apiClient = AudiobookshelfClient(baseURL: baseURL, authToken: token)
                
                await fetchLibraries()
                
                testResultMessage = """
                Authentication Successful
                
                User: \(username)
                Server: \(baseURL)
                
                Loading libraries...
                """
                showingTestResults = true
                
            } catch {
                isTestingConnection = false
                connectionState = .failed("Authentication failed: \(error.localizedDescription)")
                isLoggedIn = false
            }
        }
    }
    
    func logout() {
        Task {
            do {
                try await logoutUseCase.execute()
                
                apiClient = nil
                libraries = []
                selectedLibraryId = nil
                connectionState = .initial
                isLoggedIn = false
                serverConfig.username = ""
                serverConfig.password = ""
                
            } catch {
                AppLogger.general.debug("[SettingsViewModel] Logout error: \(error)")
            }
        }
    }
    
    
    // MARK: - Storage Management
    
    func calculateStorageInfo() async {
        storage.isCalculatingStorage = true
        
        let info = await calculateStorageUseCase.execute()
        storage.updateStorage(info: info)
        
        storage.isCalculatingStorage = false
    }
    
    func clearAllCache() async {
        storage.cacheOperationInProgress = true
        
        do {
            try await clearCacheUseCase.execute()
            storage.lastCacheCleanupDate = Date()
        } catch {
            AppLogger.general.debug("[SettingsViewModel] Cache clear error: \(error)")
        }
        
        await calculateStorageInfo()
        
        storage.cacheOperationInProgress = false
    }
    
    func clearAllDownloads() async {
        downloadManager.deleteAllBooks()
        await calculateStorageInfo()
    }
    
    
    // MARK: - Library Management
    func saveSelectedLibrary(_ libraryId: String?) {
        if let id = libraryId {
            settingsRepository.saveSelectedLibraryId(libraryId)
            AppLogger.general.debug("[LibraryRepository] Selected library: \(id)")
        } else {
            settingsRepository.saveSelectedLibraryId(nil)
        }
    }
    
    // MARK: - Private Helpers
    private func loadSavedCredentials() async {
        do {
            guard let credentials = try await loadCredentialsUseCase.execute() else {
                return
            }
            
            serverConfig.scheme = credentials.scheme
            serverConfig.host = credentials.host
            serverConfig.port = credentials.port
            serverConfig.username = credentials.username
            serverConfig.password = credentials.password
            
            isLoggedIn = true
            connectionState = .authenticated
            
            apiClient = AudiobookshelfClient(
                baseURL: credentials.baseURL,
                authToken: credentials.token
            )
            
            await fetchLibraries()
            
        } catch CredentialsError.tokenExpired {
            connectionState = .failed("Token expired - please login again")
        } catch {
            connectionState = .initial
        }
    }
    
    private func saveCredentials(token: String) async {
        do {
            let credentials = UserCredentials(
                scheme: serverConfig.scheme,
                host: serverConfig.host,
                port: serverConfig.port,
                username: serverConfig.username,
                password: serverConfig.password,
                token: token,
                baseURL: serverConfig.fullServerURL
            )
            
            try await saveCredentialsUseCase.execute(credentials: credentials)
            
        } catch {
            connectionState = .failed("Failed to save credentials")
            
            testResultMessage = """
            Failed to Save Credentials
            
            Error: \(error.localizedDescription)
            
            Your login was successful, but we couldn't save the credentials securely.
            Please try logging in again.
            """
            showingTestResults = true
        }
    }
    
    private func fetchLibraries() async {
        guard let client = apiClient else { return }
        
        do {
            libraries = try await fetchLibrariesUseCase.execute(api: client)
            restoreSelectedLibrary()
        } catch {
            connectionState = .failed("Failed to load libraries")
        }
    }
    
    private func restoreSelectedLibrary() {
        if let savedId = UserDefaults.standard.string(forKey: "selected_library_id"),
           libraries.contains(where: { $0.id == savedId }) {
            selectedLibraryId = savedId
        } else if let defaultLibrary = libraries.first(where: { $0.name.lowercased().contains("default") }) {
            selectedLibraryId = defaultLibrary.id
            saveSelectedLibrary(defaultLibrary.id)
        } else if let firstLibrary = libraries.first {
            selectedLibraryId = firstLibrary.id
            saveSelectedLibrary(firstLibrary.id)
        }
    }
}
