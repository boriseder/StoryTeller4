import Foundation
import SwiftUI
import Observation

// MARK: - ServiceContainer
//
// Holds every service that exists independently of whether the user is logged in.
// Created once when the app launches and never replaced.
//
// Rule: nothing in here should depend on an API client or auth token.
// If it needs a baseURL or token it belongs in APIContainer instead.

@MainActor
@Observable
final class ServiceContainer {

    // MARK: - Playback
    let player: AudioPlayer
    let playerStateManager: PlayerStateManager
    let sleepTimerService: SleepTimerService

    // MARK: - Downloads
    let downloadManager: DownloadManager

    // MARK: - Infrastructure
    let keychainService: KeychainService
    let coverCacheManager: CoverCacheManager
    let storageMonitor: StorageMonitor
    let authService: AuthenticationService
    let serverValidator: ServerConfigValidator
    let connectionHealthChecker: ConnectionHealthChecker

    // MARK: - Init

    init() {
        // 1. Player stack
        let player = AudioPlayer()
        self.player = player
        self.playerStateManager = PlayerStateManager()
        self.sleepTimerService = SleepTimerService(player: player, timerService: TimerService())

        // 2. Download stack
        let downloadManager = DownloadManager()
        let networkService = DefaultDownloadNetworkService()
        let storageService = DefaultDownloadStorageService()
        let retryPolicy = ExponentialBackoffRetryPolicy()
        let validationService = DefaultDownloadValidationService()

        let orchestrationService = DefaultDownloadOrchestrationService(
            networkService: networkService,
            storageService: storageService,
            retryPolicy: retryPolicy,
            validationService: validationService
        )

        let healingService = DefaultBackgroundHealingService(
            storageService: storageService,
            validationService: validationService,
            onBookRemoved: { [weak downloadManager] bookId in
                Task { @MainActor in
                    downloadManager?.downloadedBooks.removeAll { $0.id == bookId }
                }
            }
        )

        let downloadRepository = DefaultDownloadRepository(
            orchestrationService: orchestrationService,
            storageService: storageService,
            validationService: validationService,
            healingService: healingService,
            downloadManager: downloadManager
        )

        downloadManager.configure(repository: downloadRepository)
        self.downloadManager = downloadManager

        // 3. Infrastructure
        self.keychainService = KeychainService.shared
        self.coverCacheManager = CoverCacheManager.shared
        self.storageMonitor = StorageMonitor()
        self.authService = AuthenticationService()
        self.serverValidator = ServerConfigValidator()
        self.connectionHealthChecker = ConnectionHealthChecker()
    }
}
