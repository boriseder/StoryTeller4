import Foundation

// MARK: - Protocol

/// Service responsible for network operations related to downloads
protocol DownloadNetworkService {
    /// Downloads a file from a URL with authentication
    /// - Parameters:
    ///   - url: The URL to download from
    ///   - authToken: Authentication token
    /// - Returns: The downloaded data
    func downloadFile(from url: URL, authToken: String) async throws -> Data
    
    /// Downloads a book cover image
    /// - Parameters:
    ///   - bookId: The book ID
    ///   - api: The AudiobookshelfAPI instance
    /// - Returns: The cover image data
    func downloadCover(bookId: String, api: AudiobookshelfClient) async throws -> Data
    
    /// Creates a playback session for downloading audio files
    /// - Parameters:
    ///   - libraryItemId: The library item ID
    ///   - api: The AudiobookshelfAPI instance
    /// - Returns: PlaybackSessionResponse containing audio track URLs
    func createPlaybackSession(libraryItemId: String, api: AudiobookshelfClient) async throws -> PlaybackSessionResponse
}

// MARK: - Default Implementation

final class DefaultDownloadNetworkService: DownloadNetworkService {
    
    // MARK: - Properties
    private let urlSession: URLSession
    private let timeout: TimeInterval
    
    // MARK: - Initialization
    init(urlSession: URLSession = .shared, timeout: TimeInterval = 300.0) {
        self.urlSession = urlSession
        self.timeout = timeout
    }
    
    // MARK: - DownloadNetworkService
    
    func downloadFile(from url: URL, authToken: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = timeout
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DownloadError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw DownloadError.httpError(statusCode: httpResponse.statusCode)
        }
        
        guard data.count > 1024 else {
            throw DownloadError.fileTooSmall
        }
        
        return data
    }
    
    /// Downloads cover using the correct API endpoint
    /// Uses /api/items/{id}/cover which is the canonical endpoint for covers
    func downloadCover(bookId: String, api: AudiobookshelfClient) async throws -> Data {
        // Construct the correct cover endpoint
        let coverURLString = "\(api.baseURLString)/api/items/\(bookId)/cover"
        
        guard let coverURL = URL(string: coverURLString) else {
            AppLogger.general.error("[DownloadNetwork] Invalid cover URL: \(coverURLString)")
            throw DownloadError.invalidCoverURL
        }
        
        AppLogger.general.debug("[DownloadNetwork] Downloading cover from: \(coverURLString)")
        
        // Use the standard downloadFile method
        let data = try await downloadFile(from: coverURL, authToken: api.authToken)
        
        // Validate it's actually an image
        guard isValidImageData(data) else {
            AppLogger.general.error("[DownloadNetwork] Downloaded cover is not a valid image")
            throw DownloadError.invalidImageData
        }
        
        AppLogger.general.debug("[DownloadNetwork] Cover downloaded successfully (\(data.count) bytes)")
        return data
    }
    
    func createPlaybackSession(libraryItemId: String, api: AudiobookshelfClient) async throws -> PlaybackSessionResponse {
        let url = URL(string: "\(api.baseURLString)/api/items/\(libraryItemId)/play")!
        let requestBody = DeviceUtils.createPlaybackRequest()
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(api.authToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)
        request.timeoutInterval = 30.0
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AudiobookshelfError.invalidResponse
        }
        
        return try JSONDecoder().decode(PlaybackSessionResponse.self, from: data)
    }
    
    // MARK: - Private Helpers
    
    /// Validates that data contains a valid image
    private func isValidImageData(_ data: Data) -> Bool {
        // Check for common image signatures
        guard data.count >= 12 else { return false }
        
        let bytes = [UInt8](data.prefix(12))
        
        // JPEG: FF D8 FF
        if bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF {
            return true
        }
        
        // PNG: 89 50 4E 47 0D 0A 1A 0A
        if bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 {
            return true
        }
        
        // WebP: RIFF ... WEBP
        if bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 &&
           bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50 {
            return true
        }
        
        // GIF: GIF87a or GIF89a
        if bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 {
            return true
        }
        
        return false
    }
}
