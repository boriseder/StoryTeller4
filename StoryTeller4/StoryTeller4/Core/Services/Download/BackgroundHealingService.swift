import Foundation
import Combine

@MainActor
final class BackgroundHealingService: Sendable {
    
    private let storageService: DownloadStorageService
    private let validationService: DownloadValidationService
    private let onBookRemoved: @Sendable (String) -> Void
    private var timer: Timer?
    
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
        // Run every 24 hours
        timer = Timer.scheduledTimer(withTimeInterval: 86400, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.performHealing()
            }
        }
        
        // Run once on start with delay
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 10 * 1_000_000_000)
            self.performHealing()
        }
    }
    
    func stop() {
        timer?.invalidate()
        timer = nil
    }
    
    private func performHealing() {
        let books = storageService.loadDownloadedBooks()
        
        for book in books {
            let result = validationService.validateBookIntegrity(bookId: book.id, storageService: storageService)
            
            if !result.isValid {
                AppLogger.general.warn("[HealingService] Book corrupted: \(book.title)")
                
                let bookDir = storageService.bookDirectory(for: book.id)
                try? storageService.deleteBookDirectory(at: bookDir)
                onBookRemoved(book.id)
            }
        }
    }
    
    deinit {
        let timerToInvalidate = timer
        Task { @MainActor in
            timerToInvalidate?.invalidate()
        }
    }
}
