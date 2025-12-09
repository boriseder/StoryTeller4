import Foundation

// MARK: - Protocol

/// Service responsible for validating and repairing downloads in the background
protocol BackgroundHealingService {
    /// Starts the background healing process
    func start()
    
    /// Stops the background healing process
    func stop()
    
    /// Manually triggers a validation and repair cycle
    func healNow() async
}

// MARK: - Default Implementation

final class DefaultBackgroundHealingService: BackgroundHealingService {
    
    // MARK: - Properties
    private let storageService: DownloadStorageService
    private let validationService: DownloadValidationService
    private var healingTask: Task<Void, Never>?
    private let onBookRemoved: (String) -> Void
    
    // MARK: - Initialization
    init(
        storageService: DownloadStorageService,
        validationService: DownloadValidationService,
        onBookRemoved: @escaping (String) -> Void
    ) {
        self.storageService = storageService
        self.validationService = validationService
        self.onBookRemoved = onBookRemoved
    }
    
    // MARK: - BackgroundHealingService
    
    func start() {
        healingTask = Task { [weak self] in
            guard let self = self else { return }
            
            // Wait for app to settle
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            
            await self.healNow()
            
            // Monitor network changes for healing opportunities
            for await _ in NotificationCenter.default.notifications(named: .networkConnectivityChanged) {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await self.healNow()
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
            let validation = validationService.validateBookIntegrity(
                bookId: book.id,
                storageService: storageService
            )
            
            if !validation.isValid {
                AppLogger.general.debug("[BackgroundHealing] Found corrupt download: \(book.id)")
                
                // Delete incomplete/corrupt downloads
                let bookDir = storageService.bookDirectory(for: book.id)
                do {
                    try storageService.deleteBookDirectory(at: bookDir)
                    onBookRemoved(book.id)
                    AppLogger.general.debug("[BackgroundHealing] Removed corrupt book: \(book.id)")
                } catch {
                    AppLogger.general.error("[BackgroundHealing] Failed to delete corrupt book: \(error)")
                }
            }
        }
    }
    
    deinit {
        stop()
    }
}
