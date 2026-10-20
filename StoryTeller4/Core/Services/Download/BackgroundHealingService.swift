import Foundation
import Combine

protocol BackgroundHealingService: Sendable {
    func start()
    func stop()
    func healNow() async
}

@MainActor
final class DefaultBackgroundHealingService: BackgroundHealingService {
    
    private let storageService: DownloadStorageService
    private let validationService: DownloadValidationService
    private let onBookRemoved: @Sendable (String) -> Void
    private var healingTask: Task<Void, Never>?
    
    init(storageService: DownloadStorageService, validationService: DownloadValidationService, onBookRemoved: @escaping @Sendable (String) -> Void) {
        self.storageService = storageService
        self.validationService = validationService
        self.onBookRemoved = onBookRemoved
    }
    
    func start() {
        stop()
        healingTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await self?.healNow()
            let notifications = NotificationCenter.default.notifications(named: .networkConnectivityChanged)
            for await _ in notifications {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await self?.healNow()
            }
        }
        AppLogger.general.debug("[BackgroundHealing] Started")
    }
    
    func stop() {
        healingTask?.cancel()
        healingTask = nil
    }
    
    func healNow() async {
        let books = storageService.loadDownloadedBooks()
        for book in books {
            if Task.isCancelled { return }
            let result = validationService.validateBookIntegrity(bookId: book.id, storageService: storageService)
            if !result.isValid {
                let reason = result.failureReason ?? "Unknown"
                AppLogger.general.warn("[HealingService] Book corrupted: \(book.title) - \(reason)")
                let bookDir = storageService.bookDirectory(for: book.id)
                try? storageService.deleteBookDirectory(at: bookDir)
                onBookRemoved(book.id)
            }
        }
    }
    
    deinit {
        healingTask?.cancel()
    }
}
