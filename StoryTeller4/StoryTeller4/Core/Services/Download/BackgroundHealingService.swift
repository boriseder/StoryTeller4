import Foundation
import Combine

@MainActor
final class BackgroundHealingService: Sendable {
    
    private let storageService: DownloadStorageService
    private let validationService: DownloadValidationService
    private let onBookRemoved: @Sendable (String) -> Void
    
    private var healingTask: Task<Void, Never>?
    
    init(
        storageService: DownloadStorageService,
        validationService: DownloadValidationService,
        onBookRemoved: @escaping @Sendable (String) -> Void
    ) {
        self.storageService = storageService
        self.validationService = validationService
        self.onBookRemoved = onBookRemoved
    }
    
    func start() {
        stop()
        
        healingTask = Task { [weak self] in
            // Wait for app to settle
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            
            // Loop combining periodic checks and network observation
            await withTaskGroup(of: Void.self) { group in
                // 1. Periodic Check (Every 24h)
                group.addTask {
                    while !Task.isCancelled {
                        await self?.healNow()
                        // Sleep 24 hours
                        try? await Task.sleep(nanoseconds: 24 * 60 * 60 * 1_000_000_000)
                    }
                }
                
                // 2. Network Observation
                group.addTask {
                    // Note: In a real app we might want to debounce this.
                    // Accessing NotificationCenter is thread-safe.
                    let changes = NotificationCenter.default.notifications(named: .networkConnectivityChanged)
                    for await _ in changes {
                        try? await Task.sleep(nanoseconds: 5_000_000_000) // Debounce
                        await self?.healNow()
                    }
                }
            }
        }
        
        AppLogger.general.debug("[BackgroundHealing] Started")
    }
    
    func stop() {
        healingTask?.cancel()
        healingTask = nil
        AppLogger.general.debug("[BackgroundHealing] Stopped")
    }
    
    func healNow() async {
        let books = storageService.loadDownloadedBooks()
        
        AppLogger.general.debug("[BackgroundHealing] Validating \(books.count) books")
        
        for book in books {
            if Task.isCancelled { return }
            
            let result = validationService.validateBookIntegrity(bookId: book.id, storageService: storageService)
            
            if !result.isValid {
                let reason = result.failureReason ?? "Unknown"
                AppLogger.general.warn("[BackgroundHealing] Book corrupted: \(book.title) - \(reason)")
                
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
