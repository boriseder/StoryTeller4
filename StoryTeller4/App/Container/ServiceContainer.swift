import Foundation

// MARK: - ServiceContainer
//
// Owns all long-lived, auth-independent services.
// This is the only place where DownloadManager and DownloadRepository
// are constructed and wired together. The wiring is one-directional:
//
//   DefaultDownloadRepository  ──onStateChanged──►  DownloadManager
//
// Neither class references the other after configure() returns.

@MainActor
final class ServiceContainer {

    // MARK: - Download stack (constructed and wired here, owned here)

    let downloadManager: DownloadManager

    // Retained so the repository is not deallocated.
    // External callers always go through downloadManager.repository (protocol).
    private let downloadRepository: DefaultDownloadRepository

    // MARK: - Other services

    let player: AudioPlayer
    let playerStateManager: PlayerStateManager
    let sleepTimerService: SleepTimerService
    let coverCacheManager: CoverCacheManager
    let storageMonitor: StorageMonitor
    let connectionHealthChecker: ConnectionHealthChecker
    let authService: AuthenticationService
    let keychainService: KeychainService
    let serverValidator: ServerConfigValidator

    // MARK: - Init

    init() {
        // 1. Build all leaf services (no cross-dependencies)
        let storageService    = DefaultDownloadStorageService()
        let networkService    = DefaultDownloadNetworkService()
        let validationService = DefaultDownloadValidationService()
        let retryPolicy       = ExponentialBackoffRetryPolicy()

        let orchestrationService = DefaultDownloadOrchestrationService(
            networkService: networkService,
            storageService: storageService,
            retryPolicy: retryPolicy,
            validationService: validationService
        )

        // 2. Build DownloadManager first — no dependencies yet
        let manager = DownloadManager()

        // 3. Build the repository — no DownloadManager reference needed.
        //    The healing service receives a weak repository reference so
        //    it can call deleteBook(), which fires onStateChanged, which
        //    causes DownloadManager to refresh downloadedBooks via its own
        //    callback. We never mutate downloadedBooks (private(set)) from
        //    outside DownloadManager directly.
        let repository = DefaultDownloadRepository(
            orchestrationService: orchestrationService,
            storageService: storageService,
            validationService: validationService,
            // Healing service is built inside the repository init with a
            // factory closure so the weak capture is safe.
            healingService: DefaultBackgroundHealingService(
                storageService: storageService,
                validationService: validationService,
                onBookRemoved: { bookId in
                    // Resolved on MainActor via the Task below.
                    // deleteBook() is @MainActor on the protocol so this
                    // hop is required.
                    Task { @MainActor in
                        // We reach the repository through the manager's
                        // repository property to avoid a capture cycle.
                        manager.repository?.deleteBook(bookId)
                    }
                }
            ),
            startHealing: true
        )

        // 4. Wire the callback: repository → manager (one direction only)
        manager.configure(repository: repository)

        self.downloadManager    = manager
        self.downloadRepository = repository

        // 5. Build remaining services.
        //    CoverCacheManager and KeychainService use private inits with
        //    shared singletons — always access via .shared.
        self.player               = AudioPlayer()
        self.playerStateManager   = PlayerStateManager()  // TODO: pass player: player if PlayerStateManager.init requires it
        self.sleepTimerService    = SleepTimerService(player: player)
        self.coverCacheManager    = CoverCacheManager.shared
        self.storageMonitor       = StorageMonitor()
        self.connectionHealthChecker = ConnectionHealthChecker()
        self.authService          = AuthenticationService()
        self.keychainService      = KeychainService.shared
        self.serverValidator      = ServerConfigValidator()
    }
}
