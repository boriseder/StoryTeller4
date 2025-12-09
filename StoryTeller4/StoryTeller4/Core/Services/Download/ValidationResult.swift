import Foundation

// MARK: - Validation Result

/// Result of validation
enum ValidationResult {
    case valid
    case invalid(reason: String)
    
    var isValid: Bool {
        if case .valid = self { return true }
        return false
    }
}

// MARK: - Protocol

/// Service responsible for validating downloaded content
protocol DownloadValidationService {
    /// Validates the integrity of a downloaded book
    func validateBookIntegrity(bookId: String, storageService: DownloadStorageService) -> ValidationResult
    
    /// Validates a single file
    func validateFile(at url: URL, minimumSize: Int64) -> Bool
}

// MARK: - Default Implementation

final class DefaultDownloadValidationService: DownloadValidationService {
    
    // MARK: - Properties
    private let fileManager: FileManager
    private let minimumCoverSize: Int64 = 1024 // 1KB
    private let minimumAudioSize: Int64 = 10_240 // 10KB
    
    // MARK: - Initialization
    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }
    
    // MARK: - DownloadValidationService
    
    func validateBookIntegrity(bookId: String, storageService: DownloadStorageService) -> ValidationResult {
        let bookDir = storageService.bookDirectory(for: bookId)              
        let metadataFile = bookDir.appendingPathComponent("metadata.json")
        
        // Check metadata exists
        guard fileManager.fileExists(atPath: metadataFile.path) else {
            AppLogger.cache.error("[DefaultDownloadValidationService] Metadata file missing")
            return .invalid(reason: "Metadata file missing")
        }
        
        // Load and validate book metadata
        guard let data = try? Data(contentsOf: metadataFile),
              let book = try? JSONDecoder().decode(Book.self, from: data) else {
            AppLogger.cache.error("[DefaultDownloadValidationService] Invalid metadata file")
            return .invalid(reason: "Invalid metadata file")
        }
        
        // Load audio info (technical metadata)
        guard let audioInfo = storageService.loadAudioInfo(for: bookId) else {
            AppLogger.cache.error("[DefaultDownloadValidationService] Audio info missing")
            return .invalid(reason: "Audio info missing")
        }
        
        // Validate all audio files exist and have minimum size
        // Use audioTrackCount (physical files) instead of chapters (logical structure)
        let audioDir = storageService.audioDirectory(for: bookId)
        for index in 0..<audioInfo.audioTrackCount {
            let audioFile = audioDir.appendingPathComponent("chapter_\(index).mp3")
            
            if !fileManager.fileExists(atPath: audioFile.path) {
                AppLogger.cache.error("[DefaultDownloadValidationService] Missing audio track")
                return .invalid(reason: "Missing audio track \(index + 1)")
            }
            
            if !validateFile(at: audioFile, minimumSize: minimumAudioSize) {
                AppLogger.cache.error("[DefaultDownloadValidationService] Audio track \(index + 1) is corrupted")
                return .invalid(reason: "Audio track \(index + 1) is corrupted")
            }
        }
        
        // FIXED: Validate cover only if it was supposed to be downloaded
        // Check if book has a coverPath - if so, the cover should exist
        let coverFile = bookDir.appendingPathComponent("cover.jpg")

        // If cover file exists, validate it
        if fileManager.fileExists(atPath: coverFile.path) {
            if !validateFile(at: coverFile, minimumSize: minimumCoverSize) {
                AppLogger.cache.error("[DefaultDownloadValidationService] Cover image is corrupted")
                return .invalid(reason: "Cover image is corrupted")
            }
        } else {
            // Cover doesn't exist - this is only OK if the book has no coverPath
            // We need to check the book metadata to know if cover was expected
            if let coverPath = book.coverPath, !coverPath.isEmpty {
                // Book has coverPath but file is missing - this is an error
                AppLogger.cache.error("[DefaultDownloadValidationService] Cover image missing (expected)")
                return .invalid(reason: "Cover image missing")
            } else {
                // Book has no coverPath - cover not expected, this is fine
                AppLogger.cache.debug("[DefaultDownloadValidationService] No cover image (book has no cover)")
            }
        }

        return .valid
    }
    
    func validateFile(at url: URL, minimumSize: Int64) -> Bool {
        guard fileManager.fileExists(atPath: url.path) else {
            return false
        }
        
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            if let fileSize = attributes[.size] as? Int64 {
                return fileSize >= minimumSize
            }
        } catch {
            AppLogger.general.error("[DownloadValidation] Failed to get file attributes: \(error)")
        }
        
        return false
    }
}
