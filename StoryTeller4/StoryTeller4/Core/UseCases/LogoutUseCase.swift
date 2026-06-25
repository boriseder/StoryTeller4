import Foundation

// MARK: - CoverDownloadManagerProtocol
//
// Narrow protocol exposing only what LogoutUseCase needs.
// CoverDownloadManager (an actor) conforms to this — the use case
// never imports the concrete type or touches the singleton directly.

protocol CoverDownloadManagerProtocol: Sendable {
    func shutdown() async
}

extension CoverDownloadManager: CoverDownloadManagerProtocol {}

// MARK: - LogoutUseCaseProtocol

protocol LogoutUseCaseProtocol: Sendable {
    func execute() async throws
}

// MARK: - LogoutUseCase
//
// Infrastructure couplings removed:
//
//   Before                              After
//   ──────────────────────────────────────────────────────
//   UserDefaults directly             settingsRepository.clearAllSettings()
//   keychainService directly          settingsRepository.clearAllSettings()
//   NotificationCenter directly       moved into SettingsRepository.clearServerConfig()
//   DependencyContainer.shared        onContainerReset closure (injected)
//   CoverDownloadManager.shared       CoverDownloadManagerProtocol (injected)
//
// The use case now expresses only the logout sequence as business logic.
// It knows nothing about how settings are stored, how the container is
// wired, or what UI framework powers notifications.

final class LogoutUseCase: LogoutUseCaseProtocol, Sendable {

    private let settingsRepository: any SettingsRepositoryProtocol & Sendable
    private let coverDownloadManager: any CoverDownloadManagerProtocol
    private let onContainerReset: @Sendable () async -> Void

    init(
        settingsRepository: any SettingsRepositoryProtocol & Sendable,
        coverDownloadManager: any CoverDownloadManagerProtocol = CoverDownloadManager.shared,
        onContainerReset: @Sendable @escaping () async -> Void
    ) {
        self.settingsRepository = settingsRepository
        self.coverDownloadManager = coverDownloadManager
        self.onContainerReset = onContainerReset
    }

    func execute() async throws {
        // 1. Clear all persisted credentials and server config.
        //    SettingsRepository owns UserDefaults + Keychain + NotificationCenter.
        try settingsRepository.clearAllSettings()

        // 2. Reset the DI container (app-lifecycle concern, injected as closure).
        await onContainerReset()

        // 3. Cancel in-flight cover downloads.
        await coverDownloadManager.shutdown()

        AppLogger.general.debug("[LogoutUseCase] User logged out successfully")
    }
}
