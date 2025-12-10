import Foundation

// MARK: - Validation Result

/// Result of validation
enum ValidationResult: Sendable {
    case valid
    case invalid(reason: String)
    
    var isValid: Bool {
        if case .valid = self { return true }
        return false
    }
    
    /// Helper to access the failure reason
    var failureReason: String? {
        if case .invalid(let reason) = self { return reason }
        return nil
    }
    
    // Backward compatibility for the specific error message
    var missingFiles: String {
        failureReason ?? "Unknown error"
    }
}

// MARK: - Protocol

/// Service responsible for validating downloaded content
protocol DownloadValidationService: Sendable {
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
            return .invalid(reason: "Metadata file missing")
        }
        
        // Load and validate book metadata
        guard let data = try? Data(contentsOf: metadataFile),
              let book = try? JSONDecoder().decode(Book.self, from: data) else {
            return .invalid(reason: "Invalid metadata file")
        }
        
        // Load audio info (technical metadata)
        guard let audioInfo = storageService.loadAudioInfo(for: bookId) else {
            return .invalid(reason: "Audio info missing")
        }
        
        // Validate all audio files exist and have minimum size
        let audioDir = storageService.audioDirectory(for: bookId)
        for index in 0..<audioInfo.audioTrackCount {
            let audioFile = audioDir.appendingPathComponent("chapter_\(index).mp3")
            
            if !fileManager.fileExists(atPath: audioFile.path) {
                return .invalid(reason: "Missing audio track \(index + 1)")
            }
            
            if !validateFile(at: audioFile, minimumSize: minimumAudioSize) {
                return .invalid(reason: "Audio track \(index + 1) is corrupted")
            }
        }
        
        // Validate cover
        let coverFile = bookDir.appendingPathComponent("cover.jpg")
        if fileManager.fileExists(atPath: coverFile.path) {
            if !validateFile(at: coverFile, minimumSize: minimumCoverSize) {
                return .invalid(reason: "Cover image is corrupted")
            }
        } else if let coverPath = book.coverPath, !coverPath.isEmpty {
            return .invalid(reason: "Cover image missing")
        }

        return .valid
    }
    
    func validateFile(at url: URL, minimumSize: Int64) -> Bool {
        guard fileManager.fileExists(atPath: url.path) else { return false }
        
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            if let fileSize = attributes[.size] as? Int64 {
                return fileSize >= minimumSize
            }
        } catch {
            // Log error if needed, but validation simply returns false
        }
        return false
    }
}
