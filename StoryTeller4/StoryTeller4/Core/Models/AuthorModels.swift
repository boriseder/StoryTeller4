import Foundation

// MARK: - Author Model
struct Author: Codable, Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let name: String
    let description: String?
    let imagePath: String?
    let libraryId: String
    let addedAt: Date
    let updatedAt: Date
    let numBooks: Int?
    let lastFirst: String?
    let libraryItems: [LibraryItem]?
    let series: [Series]?
    
    // MARK: - Computed Properties
    var bookCount: Int {
        libraryItems?.count ?? numBooks ?? 0
    }
    
    var hasImage: Bool {
        imagePath != nil && !(imagePath?.isEmpty ?? true)
    }
    
    var displayName: String {
        name
    }
    
    func imageURL(baseURL: String) -> URL? {
        guard let imagePath = imagePath else { return nil }
        return URL(string: "\(baseURL)\(imagePath)")
    }
    
    // MARK: - Initializers
    init(
        id: String,
        name: String,
        description: String? = nil,
        imagePath: String? = nil,
        libraryId: String,
        addedAt: Date = Date(),
        updatedAt: Date = Date(),
        numBooks: Int? = nil,
        lastFirst: String? = nil,
        libraryItems: [LibraryItem]? = nil,
        series: [Series]? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.imagePath = imagePath
        self.libraryId = libraryId
        self.addedAt = addedAt
        self.updatedAt = updatedAt
        self.numBooks = numBooks
        self.lastFirst = lastFirst
        self.libraryItems = libraryItems
        self.series = series
    }
    
    // MARK: - Coding Keys
    enum CodingKeys: String, CodingKey {
        case id, name, description, imagePath, libraryId
        case addedAt, updatedAt, numBooks, lastFirst, libraryItems, series
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        imagePath = try container.decodeIfPresent(String.self, forKey: .imagePath)
        libraryId = try container.decode(String.self, forKey: .libraryId)
        numBooks = try container.decodeIfPresent(Int.self, forKey: .numBooks)
        lastFirst = try container.decodeIfPresent(String.self, forKey: .lastFirst)
        libraryItems = try container.decodeIfPresent([LibraryItem].self, forKey: .libraryItems)
        series = try container.decodeIfPresent([Series].self, forKey: .series)
        
        // Handle timestamp conversions (server uses milliseconds)
        if let addedTimestamp = try? container.decode(Int64.self, forKey: .addedAt) {
            addedAt = TimestampConverter.dateFromServer(TimeInterval(addedTimestamp))
        } else {
            addedAt = Date()
        }
        
        if let updatedTimestamp = try? container.decode(Int64.self, forKey: .updatedAt) {
            updatedAt = TimestampConverter.dateFromServer(TimeInterval(updatedTimestamp))
        } else {
            updatedAt = Date()
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(imagePath, forKey: .imagePath)
        try container.encode(libraryId, forKey: .libraryId)
        try container.encode(Int64(TimestampConverter.serverTimestamp(from: addedAt)), forKey: .addedAt)
        try container.encode(Int64(TimestampConverter.serverTimestamp(from: updatedAt)), forKey: .updatedAt)
        try container.encodeIfPresent(numBooks, forKey: .numBooks)
        try container.encodeIfPresent(lastFirst, forKey: .lastFirst)
        try container.encodeIfPresent(libraryItems, forKey: .libraryItems)
        try container.encodeIfPresent(series, forKey: .series)
    }
    
    // MARK: - Equatable & Hashable
    static func == (lhs: Author, rhs: Author) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Response Wrapper
/// Sendable: Network response model
struct AuthorsResponse: Codable, Sendable {
    let authors: [Author]
}
