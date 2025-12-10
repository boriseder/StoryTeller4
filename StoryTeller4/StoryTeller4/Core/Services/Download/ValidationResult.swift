import Foundation

enum ValidationResult: Sendable {
    case valid
    case invalid(reason: String)
    
    var isValid: Bool {
        if case .valid = self { return true }
        return false
    }
    
    var missingFiles: String {
        if case .invalid(let reason) = self { return reason }
        return "Unknown error"
    }
}

protocol DownloadValidationService: Sendable {
    func validateBookIntegrity(bookId: String, storageService: DownloadStorageService) -> ValidationResult
    func validateFile(at url: URL, minimumSize: Int64) -> Bool
}

final class DefaultDownloadValidationService: DownloadValidationService {
    private let fileManager: FileManager
    private let minimumCoverSize: Int64 = 1024
    private let minimumAudioSize: Int64 = 10_240
    
    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }
    
    func validateBookIntegrity(bookId: String, storageService: DownloadStorageService) -> ValidationResult {
        let bookDir = storageService.bookDirectory(for: bookId)
        let metadataFile = bookDir.appendingPathComponent("metadata.json")
        
        guard fileManager.fileExists(atPath: metadataFile.path) else {
            return .invalid(reason: "Metadata file missing")
        }
        
        guard let data = try? Data(contentsOf: metadataFile),
              (try? JSONDecoder().decode(Book.self, from: data)) != nil else {
            return .invalid(reason: "Invalid metadata file")
        }
        
        guard let audioInfo = storageService.loadAudioInfo(for: bookId) else {
            return .invalid(reason: "Audio info missing")
        }
        
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
        
        return .valid
    }
    
    func validateFile(at url: URL, minimumSize: Int64) -> Bool {
        guard fileManager.fileExists(atPath: url.path) else { return false }
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            if let fileSize = attributes[.size] as? Int64 {
                return fileSize >= minimumSize
            }
        } catch {}
        return false
    }
}
