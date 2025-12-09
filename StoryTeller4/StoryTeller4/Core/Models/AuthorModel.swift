import Foundation

// MARK: - Authors Response

// Wrapper for Authors-response
struct AuthorsResponse: Codable {
    let authors: [Author]
}

struct Author: Codable, Identifiable {
    let id: String
    // let asin: String?
    let name: String
    let description: String?
    let imagePath: String?
    let libraryId: String
    let addedAt: Int64
    let updatedAt: Int64
    
    // Nur in Author-Liste vorhanden:
    let numBooks: Int?
    let lastFirst: String?
    
    // Nur in Author-Details vorhanden:
    let libraryItems: [LibraryItem]?
    let series: [AuthorSeries]?  // Falls du Series auch brauchst
}

struct AuthorSeries: Codable, Identifiable {
    let id: String
    let name: String
    // ... weitere Felder
}


