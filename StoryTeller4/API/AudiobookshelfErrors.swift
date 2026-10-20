import Foundation

// MARK: - Error Handling
enum AudiobookshelfError: LocalizedError {
    case invalidURL(String)
    case networkError(Error)
    case noData
    case decodingError(Error)
    case libraryNotFound(String)
    case unauthorized
    case serverError(Int, String?)
    case bookNotFound(String)
    case missingLibraryItemId
    case invalidResponse
    case noLibrarySelected
    case connectionTimeout
    case serverUnreachable
    case resourceNotFound(String)
    case invalidRequest(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .connectionTimeout:
            return "Connection timed out. Please check your network connection and server address."
        case .serverUnreachable:
            return "Cannot reach the server. Please verify the server is running and accessible."
        case .networkError(let error):
            if let urlError = error as? URLError {
                switch urlError.code {
                case .timedOut:
                    return "Connection timed out. Please check your network connection."
                case .notConnectedToInternet:
                    return "No internet connection available."
                case .cannotFindHost:
                    return "Cannot find server. Please check the server address."
                default:
                    return "Network error: \(urlError.localizedDescription)"
                }
            }
            return "Network error: \(error.localizedDescription)"
        case .noData:
            return "No data received from server"
        case .decodingError(let error):
            return "Error processing server response: \(error.localizedDescription)"
        case .libraryNotFound(let name):
            return "Library '\(name)' not found"
        case .unauthorized:
            return "Not authorized - please check your API key"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message ?? "Unknown")"
        case .bookNotFound(let id):
            return "Book with ID '\(id)' not found"
        case .missingLibraryItemId:
            return "Library Item ID missing"
        case .invalidResponse:
            return "Invalid server response"
        case .noLibrarySelected:
            return "No library selected"
        case .resourceNotFound(let resource):
            return "Resource not found: \(resource)"
        case .invalidRequest(let details):
            return "Invalid request: \(details)"

        }
    }
}
