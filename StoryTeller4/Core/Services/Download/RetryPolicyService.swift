
import Foundation

// MARK: - Protocol

/// Service responsible for retry logic and policies
protocol RetryPolicyService {
    /// Maximum number of retry attempts
    var maxRetries: Int { get }
    
    /// Determines if a retry should be attempted
    func shouldRetry(attempt: Int, error: Error) -> Bool
    
    /// Calculates delay before next retry (in nanoseconds)
    func delay(for attempt: Int) -> UInt64
}

// MARK: - Exponential Backoff Implementation

final class ExponentialBackoffRetryPolicy: RetryPolicyService {
    
    // MARK: - Properties
    let maxRetries: Int
    private let baseDelay: UInt64
    private let retryableStatusCodes: Set<Int>
    
    // MARK: - Initialization
    init(
        maxRetries: Int = 3,
        baseDelay: UInt64 = 2_000_000_000, // 2 seconds
        retryableStatusCodes: Set<Int> = [408, 429, 500, 502, 503, 504]
    ) {
        self.maxRetries = maxRetries
        self.baseDelay = baseDelay
        self.retryableStatusCodes = retryableStatusCodes
    }
    
    // MARK: - RetryPolicyService
    
    func shouldRetry(attempt: Int, error: Error) -> Bool {
        // Don't retry if max attempts reached
        guard attempt < maxRetries else {
            return false
        }
        
        // Check if error is retryable
        if let downloadError = error as? DownloadError {
            switch downloadError {
            case .httpError(let statusCode):
                return retryableStatusCodes.contains(statusCode)
            case .invalidResponse, .fileTooSmall:
                return true
            default:
                return false
            }
        }
        
        // Retry network errors
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .notConnectedToInternet,
                 .cannotConnectToHost, .cannotFindHost:
                return true
            default:
                return false
            }
        }
        
        return false
    }
    
    func delay(for attempt: Int) -> UInt64 {
        // Exponential backoff: base * 2^attempt
        // Attempt 0: 2s, Attempt 1: 4s, Attempt 2: 8s
        let multiplier = UInt64(1 << attempt)
        return baseDelay * multiplier
    }
}

// MARK: - Fixed Delay Implementation

/// A retry policy that uses fixed delays
final class FixedDelayRetryPolicy: RetryPolicyService {
    
    let maxRetries: Int
    private let delays: [UInt64]
    
    init(maxRetries: Int = 3, delays: [UInt64] = [2_000_000_000, 5_000_000_000, 10_000_000_000]) {
        self.maxRetries = maxRetries
        self.delays = delays
    }
    
    func shouldRetry(attempt: Int, error: Error) -> Bool {
        attempt < maxRetries
    }
    
    func delay(for attempt: Int) -> UInt64 {
        guard attempt < delays.count else {
            return delays.last ?? 10_000_000_000
        }
        return delays[attempt]
    }
}
