import Foundation

struct Metadata: Codable, Hashable, Sendable {
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
        case authorName
        case authors
    }
    
    struct Author: Codable, Sendable {
        let name: String
    }
    
    init(
        title: String,
        author: String? = nil,
        description: String? = nil,
        isbn: String? = nil,
        genres: [String]? = nil,
        publishedYear: String? = nil,
        narrator: String? = nil,
        publisher: String? = nil
    ) {
        self.title = title
        self.author = author
        self.description = description
        self.isbn = isbn
        self.genres = genres
        self.publishedYear = publishedYear
        self.narrator = narrator
        self.publisher = publisher
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        isbn = try container.decodeIfPresent(String.self, forKey: .isbn)
        genres = try container.decodeIfPresent([String].self, forKey: .genres)
        publishedYear = try container.decodeIfPresent(String.self, forKey: .publishedYear)
        narrator = try container.decodeIfPresent(String.self, forKey: .narrator)
        publisher = try container.decodeIfPresent(String.self, forKey: .publisher)
        
        if let authorName = try container.decodeIfPresent(String.self, forKey: .authorName) {
            author = authorName
        } else if let authorObjects = try container.decodeIfPresent([Author].self, forKey: .authors) {
            author = authorObjects.first?.name
        } else {
            author = nil
        }
    }
    
    // Explicit conformance required for Sendable optimization in some contexts
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(isbn, forKey: .isbn)
        try container.encodeIfPresent(genres, forKey: .genres)
        try container.encodeIfPresent(publishedYear, forKey: .publishedYear)
        try container.encodeIfPresent(narrator, forKey: .narrator)
        try container.encodeIfPresent(publisher, forKey: .publisher)
        try container.encodeIfPresent(author, forKey: .authorName)
    }
}
