/*
import Foundation

/// Factory for creating download services with proper dependency injection
/// Makes it easy to configure different implementations for production, testing, or debugging
final class DownloadServiceFactory {
    
    // MARK: - Configuration
    
    enum Configuration {
        case production
        case testing
        case debug
        
        var retryPolicy: RetryPolicyService {
            switch self {
            case .production:
                return ExponentialBackoffRetryPolicy(maxRetries: 3)
            case .testing:
                return ExponentialBackoffRetryPolicy(maxRetries: 1, baseDelay: 100_000_000) // Fast retries for tests
            case .debug:
                return FixedDelayRetryPolicy(maxRetries: 5, delays: [1_000_000_000, 2_000_000_000, 3_000_000_000])
            }
        }
    }
    
    // MARK: - Factory Methods
    
    /// Creates a complete DownloadManager with all dependencies configured
    /// - Parameter configuration: The configuration to use
    /// - Returns: A fully configured DownloadManager
    static func createDownloadManager(configuration: Configuration = .production) -> DownloadManager {
        let repository = createRepository(configuration: configuration)
        return DownloadManager(repository: repository)
    }
    
    /// Creates a DownloadRepository with all dependencies
    /// - Parameter configuration: The configuration to use
    /// - Returns: A configured DownloadRepository
    static func createRepository(configuration: Configuration = .production) -> DownloadRepository {
        let networkService = createNetworkService()
        let storageService = createStorageService()
        let retryPolicy = configuration.retryPolicy
        let validationService = createValidationService()
        
        let orchestrationService = createOrchestrationService(
            networkService: networkService,
            storageService: storageService,
            retryPolicy: retryPolicy,
            validationService: validationService
        )
        
        // Create a temporary download manager for the repository
        // The repository will update its properties
        let downloadManager = DownloadManager(repository: nil)
        
        let healingService = createHealingService(
            storageService: storageService,
            validationService: validationService,
            onBookRemoved: { [weak downloadManager] bookId in
                Task { @MainActor in
                    downloadManager?.downloadedBooks.removeAll { $0.id == bookId }
                }
            }
        )
        
        return DefaultDownloadRepository(
            orchestrationService: orchestrationService,
            storageService: storageService,
            validationService: validationService,
            healingService: healingService,
            downloadManager: downloadManager
        )
    }
    
    // MARK: - Individual Service Creation
    
    static func createNetworkService() -> DownloadNetworkService {
        return DefaultDownloadNetworkService()
    }
    
    static func createStorageService() -> DownloadStorageService {
        return DefaultDownloadStorageService()
    }
    
    static func createValidationService() -> DownloadValidationService {
        return DefaultDownloadValidationService()
    }
    
    static func createOrchestrationService(
        networkService: DownloadNetworkService,
        storageService: DownloadStorageService,
        retryPolicy: RetryPolicyService,
        validationService: DownloadValidationService
    ) -> DownloadOrchestrationService {
        return DefaultDownloadOrchestrationService(
            networkService: networkService,
            storageService: storageService,
            retryPolicy: retryPolicy,
            validationService: validationService
        )
    }
    
    static func createHealingService(
        storageService: DownloadStorageService,
        validationService: DownloadValidationService,
        onBookRemoved: @escaping (String) -> Void
    ) -> BackgroundHealingService {
        return DefaultBackgroundHealingService(
            storageService: storageService,
            validationService: validationService,
            onBookRemoved: onBookRemoved
        )
    }
}
*/
