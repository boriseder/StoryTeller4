import Foundation

// MARK: Metadata Repsonse
struct Metadata: Codable {
    let title: String
    let author: String?
    let description: String?
    let isbn: String?
    let genres: [String]?
    let publishedYear: String?
    let narrator: String?
    let publisher: String?
    
    enum CodingKeys: String, CodingKey {
        case title, description, isbn, genres, publishedYear, narrator, publisher
        case authorName      // für Library-Listing
        case authors         // für Item-Detail
    }
    
    struct Author: Codable {
        let name: String
    }
    
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Pflichtfeld
        title = try container.decode(String.self, forKey: .title)

        // Optionale Felder
        description   = try container.decodeIfPresent(String.self, forKey: .description)
        isbn          = try container.decodeIfPresent(String.self, forKey: .isbn)
        genres        = try container.decodeIfPresent([String].self, forKey: .genres)
        publishedYear = try container.decodeIfPresent(String.self, forKey: .publishedYear)
        narrator      = try container.decodeIfPresent(String.self, forKey: .narrator)
        publisher     = try container.decodeIfPresent(String.self, forKey: .publisher)

        // Use decodeIfPresent instead of try?
        if let authorName = try container.decodeIfPresent(String.self, forKey: .authorName) {
            author = authorName
        } else if let authorObjects = try container.decodeIfPresent([Author].self, forKey: .authors) {
            author = authorObjects.first?.name
        } else {
            author = nil
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(isbn, forKey: .isbn)
        try container.encodeIfPresent(genres, forKey: .genres)
        try container.encodeIfPresent(publishedYear, forKey: .publishedYear)
        try container.encodeIfPresent(narrator, forKey: .narrator)
        try container.encodeIfPresent(publisher, forKey: .publisher)
        if let author = author {
            try container.encode(author, forKey: .authorName)
        }
    }
}
