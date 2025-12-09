import Foundation

// MARK: - Protocol

protocol DownloadStorageService {
    func createBookDirectory(for bookId: String) throws -> URL
    func saveBookMetadata(_ book: Book, to directory: URL) throws
    func saveAudioInfo(_ audioInfo: AudioInfo, to directory: URL) throws
    func loadAudioInfo(for bookId: String) -> AudioInfo?
    func saveAudioFile(_ data: Data, to url: URL) throws
    func saveCoverImage(_ data: Data, to url: URL) throws
    func deleteBookDirectory(at url: URL) throws
    func bookDirectory(for bookId: String) -> URL
    func audioDirectory(for bookId: String) -> URL
    func getLocalAudioURL(for bookId: String, chapterIndex: Int) -> URL?
    func getLocalCoverURL(for bookId: String) -> URL?
    func loadDownloadedBooks() -> [Book]
    func checkAvailableStorage(requiredSpace: Int64) -> Bool
    func getTotalDownloadSize() -> Int64
    func getBookStorageSize(_ bookId: String) -> Int64
    
    // NEW: Explicit sync operation
    func syncDirectory(at url: URL) throws
}

// MARK: - Default Implementation

final class DefaultDownloadStorageService: DownloadStorageService {
    
    private let fileManager: FileManager
    private let downloadsURL: URL
    
    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.downloadsURL = documentsURL.appendingPathComponent("Downloads", isDirectory: true)
        
        createDownloadsDirectoryIfNeeded()
    }
    
    private func createDownloadsDirectoryIfNeeded() {
        if !fileManager.fileExists(atPath: downloadsURL.path) {
            do {
                try fileManager.createDirectory(at: downloadsURL, withIntermediateDirectories: true)
                AppLogger.general.debug("[DownloadStorage] Created downloads directory")
            } catch {
                AppLogger.general.error("[DownloadStorage] Failed to create downloads directory: \(error)")
            }
        }
    }
    
    // MARK: - Safe Write Operations with fsync
    
    /// Writes data atomically and forces sync to disk
    private func writeDataSafely(_ data: Data, to url: URL) throws {
        // Step 1: Write atomically (creates temp file, then renames)
        try data.write(to: url, options: [.atomic])
        
        // Step 2: Force sync to disk using fsync
        try syncFile(at: url)
        
        AppLogger.general.debug("[DownloadStorage] Safely wrote \(data.count) bytes to \(url.lastPathComponent)")
    }
    
    /// Forces a file to be synced to disk using fsync()
    private func syncFile(at url: URL) throws {
        let path = url.path
        let fd = open(path, O_RDONLY)
        
        guard fd != -1 else {
            throw NSError(
                domain: "DownloadStorageService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to open file for sync: \(path)"]
            )
        }
        
        defer { close(fd) }
        
        // fsync() blocks until data is physically written to disk
        let result = fsync(fd)
        guard result == 0 else {
            throw NSError(
                domain: "DownloadStorageService",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Failed to sync file to disk: \(path)"]
            )
        }
    }
    
    /// Syncs an entire directory (and its parent) to ensure metadata is persisted
    func syncDirectory(at url: URL) throws {
        let path = url.path
        let fd = open(path, O_RDONLY)
        
        guard fd != -1 else {
            throw NSError(
                domain: "DownloadStorageService",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "Failed to open directory for sync: \(path)"]
            )
        }
        
        defer { close(fd) }
        
        // On Darwin/iOS, fsync on directory syncs its metadata
        let result = fsync(fd)
        guard result == 0 else {
            throw NSError(
                domain: "DownloadStorageService",
                code: -4,
                userInfo: [NSLocalizedDescriptionKey: "Failed to sync directory to disk: \(path)"]
            )
        }
        
        AppLogger.general.debug("[DownloadStorage] Synced directory: \(url.lastPathComponent)")
    }
    
    // MARK: - DownloadStorageService Implementation
    
    func createBookDirectory(for bookId: String) throws -> URL {
        let bookDir = bookDirectory(for: bookId)
        try fileManager.createDirectory(at: bookDir, withIntermediateDirectories: true)
        
        // Sync the parent directory to ensure the new directory entry is persisted
        try syncDirectory(at: downloadsURL)
        
        return bookDir
    }
    
    func saveBookMetadata(_ book: Book, to directory: URL) throws {
        let metadataURL = directory.appendingPathComponent("metadata.json")
        let metadataData = try JSONEncoder().encode(book)
        
        // Use safe write with fsync
        try writeDataSafely(metadataData, to: metadataURL)
        
        // Sync directory to persist file entry
        try syncDirectory(at: directory)
        
        AppLogger.general.debug("[DownloadStorage] Saved metadata for book: \(book.id)")
    }
    
    func saveAudioInfo(_ audioInfo: AudioInfo, to directory: URL) throws {
        let audioInfoURL = directory.appendingPathComponent("audio_info.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let audioInfoData = try encoder.encode(audioInfo)
        
        // ✅ FIX: Use safe write with fsync
        try writeDataSafely(audioInfoData, to: audioInfoURL)
        
        // ✅ FIX: Sync directory to persist file entry
        try syncDirectory(at: directory)
        
        AppLogger.general.debug("[DownloadStorage] Saved audio info: \(audioInfo.audioTrackCount) tracks")
    }
    
    func loadAudioInfo(for bookId: String) -> AudioInfo? {
        let audioInfoFile = bookDirectory(for: bookId).appendingPathComponent("audio_info.json")
        
        guard let data = try? Data(contentsOf: audioInfoFile) else {
            return nil
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(AudioInfo.self, from: data)
    }
    
    func saveAudioFile(_ data: Data, to url: URL) throws {
        // ✅ FIX: Use safe write with fsync for audio files
        try writeDataSafely(data, to: url)
        
        // ✅ FIX: Sync parent directory to persist file entry
        try syncDirectory(at: url.deletingLastPathComponent())
    }
    
    func saveCoverImage(_ data: Data, to url: URL) throws {
        // ✅ FIX: Use safe write with fsync for cover images
        try writeDataSafely(data, to: url)
        
        // ✅ FIX: Sync parent directory to persist file entry
        try syncDirectory(at: url.deletingLastPathComponent())
    }
    
    func deleteBookDirectory(at url: URL) throws {
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
            
            // Sync parent directory to persist deletion
            try syncDirectory(at: url.deletingLastPathComponent())
            
            AppLogger.general.debug("[DownloadStorage] Deleted directory: \(url.lastPathComponent)")
        }
    }
    
    func bookDirectory(for bookId: String) -> URL {
        downloadsURL.appendingPathComponent(bookId, isDirectory: true)
    }
    
    func audioDirectory(for bookId: String) -> URL {
        bookDirectory(for: bookId).appendingPathComponent("audio", isDirectory: true)
    }
    
    func getLocalAudioURL(for bookId: String, chapterIndex: Int) -> URL? {
        let audioFile = audioDirectory(for: bookId).appendingPathComponent("chapter_\(chapterIndex).mp3")
        guard fileManager.fileExists(atPath: audioFile.path) else { return nil }
        return audioFile
    }
    
    func getLocalCoverURL(for bookId: String) -> URL? {
        let coverFile = bookDirectory(for: bookId).appendingPathComponent("cover.jpg")
        guard fileManager.fileExists(atPath: coverFile.path) else { return nil }
        return coverFile
    }
    
    func loadDownloadedBooks() -> [Book] {
        guard fileManager.fileExists(atPath: downloadsURL.path) else {
            return []
        }
        
        do {
            let contents = try fileManager.contentsOfDirectory(
                at: downloadsURL,
                includingPropertiesForKeys: nil
            )
            
            var loadedBooks: [Book] = []
            
            for bookDir in contents where bookDir.hasDirectoryPath {
                let metadataFile = bookDir.appendingPathComponent("metadata.json")
                
                if let data = try? Data(contentsOf: metadataFile),
                   let book = try? JSONDecoder().decode(Book.self, from: data) {
                    loadedBooks.append(book)
                }
            }
            
            AppLogger.general.debug("[DownloadStorage] Loaded \(loadedBooks.count) books from disk")
            return loadedBooks
            
        } catch {
            AppLogger.general.error("[DownloadStorage] Failed to load books: \(error)")
            return []
        }
    }
    
    func checkAvailableStorage(requiredSpace: Int64 = 500_000_000) -> Bool {
        guard let systemAttributes = try? fileManager.attributesOfFileSystem(forPath: NSHomeDirectory()),
              let freeSpace = systemAttributes[.systemFreeSize] as? Int64 else {
            return false
        }
        
        return freeSpace > requiredSpace
    }
    
    func getTotalDownloadSize() -> Int64 {
        guard fileManager.fileExists(atPath: downloadsURL.path) else {
            return 0
        }
        
        guard let enumerator = fileManager.enumerator(
            at: downloadsURL,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
        ) else {
            return 0
        }
        
        var totalSize: Int64 = 0
        
        for case let fileURL as URL in enumerator {
            do {
                let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                if values.isRegularFile == true, let fileSize = values.fileSize {
                    totalSize += Int64(fileSize)
                }
            } catch {
                continue
            }
        }
        
        return totalSize
    }
    
    func getBookStorageSize(_ bookId: String) -> Int64 {
        let bookDir = bookDirectory(for: bookId)
        
        guard fileManager.fileExists(atPath: bookDir.path) else {
            return 0
        }
        
        guard let enumerator = fileManager.enumerator(
            at: bookDir,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
        ) else {
            return 0
        }
        
        var totalSize: Int64 = 0
        
        for case let fileURL as URL in enumerator {
            do {
                let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                if values.isRegularFile == true, let fileSize = values.fileSize {
                    totalSize += Int64(fileSize)
                }
            } catch {
                continue
            }
        }
        
        return totalSize
    }
}
