import Foundation

// MARK: - Personalized Section Model
struct PersonalizedSection: Codable, Identifiable, Sendable {
    let id: String
    let label: String
    let labelStringKey: String?
    let type: String
    let entities: [PersonalizedEntity]
    let total: Int
    
    var sectionType: PersonalizedSectionType? {
        PersonalizedSectionType(rawValue: type)
    }
    
    var displayLabel: String {
        sectionType?.displayName ?? label
    }
    
    var icon: String {
        sectionType?.icon ?? "list.bullet"
    }
}

typealias PersonalizedResponse = [PersonalizedSection]

// MARK: - Personalized Entity Model
struct PersonalizedEntity: Codable, Identifiable, Sendable {
    let id: String
    let media: Media?
    let libraryId: String?
    let collapsedSeries: Series?
    
    // Series-specific properties
    let name: String?
    let nameIgnorePrefix: String?
    let books: [LibraryItem]?
    let addedAt: Date?
    
    // Author-specific properties
    let numBooks: Int?
    let authorDescription: String?
    let imagePath: String?
    let updatedAt: Date?
    
    // Coding Keys
    private enum CodingKeys: String, CodingKey {
        case id, media, libraryId, collapsedSeries
        case name, nameIgnorePrefix, books, addedAt, numBooks
        case authorDescription = "description"
        case imagePath, updatedAt
    }
    
    var entityType: PersonalizedEntityType {
        if media != nil { return .book }
        if books != nil { return .series }
        if numBooks != nil { return .author }
        return .unknown
    }
    
    // Computed Properties for conversion
    var asLibraryItem: LibraryItem? {
        guard let media = media else { return nil }
        return LibraryItem(
            id: id,
            media: media,
            libraryId: libraryId,
            isFile: nil,
            isMissing: nil,
            isInvalid: nil,
            collapsedSeries: collapsedSeries
        )
    }
    
    var asSeries: Series? {
        guard let name = name, let books = books else { return nil }
        return Series(
            id: id,
            name: name,
            nameIgnorePrefix: nameIgnorePrefix,
            nameIgnorePrefixSort: nil,
            numBooks: books.count,
            books: books,
            addedAt: addedAt ?? Date()
        )
    }
    
    var asAuthor: Author? {
        guard let name = name, let libraryId = libraryId else { return nil }
        return Author(
            id: id,
            name: name,
            description: authorDescription,
            imagePath: imagePath,
            libraryId: libraryId,
            addedAt: addedAt ?? Date(),
            updatedAt: updatedAt ?? Date(),
            numBooks: numBooks,
            lastFirst: nil,
            libraryItems: nil,
            series: nil
        )
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(String.self, forKey: .id)
        media = try container.decodeIfPresent(Media.self, forKey: .media)
        libraryId = try container.decodeIfPresent(String.self, forKey: .libraryId)
        collapsedSeries = try container.decodeIfPresent(Series.self, forKey: .collapsedSeries)
        
        name = try container.decodeIfPresent(String.self, forKey: .name)
        nameIgnorePrefix = try container.decodeIfPresent(String.self, forKey: .nameIgnorePrefix)
        books = try container.decodeIfPresent([LibraryItem].self, forKey: .books)
        
        if let timestamp = try container.decodeIfPresent(TimeInterval.self, forKey: .addedAt) {
            addedAt = TimestampConverter.dateFromServer(timestamp)
        } else {
            addedAt = nil
        }
        
        numBooks = try container.decodeIfPresent(Int.self, forKey: .numBooks)
        authorDescription = try container.decodeIfPresent(String.self, forKey: .authorDescription)
        imagePath = try container.decodeIfPresent(String.self, forKey: .imagePath)
        
        if let timestamp = try container.decodeIfPresent(TimeInterval.self, forKey: .updatedAt) {
            updatedAt = TimestampConverter.dateFromServer(timestamp)
        } else {
            updatedAt = nil
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(media, forKey: .media)
        try container.encodeIfPresent(libraryId, forKey: .libraryId)
        try container.encodeIfPresent(collapsedSeries, forKey: .collapsedSeries)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(nameIgnorePrefix, forKey: .nameIgnorePrefix)
        try container.encodeIfPresent(books, forKey: .books)
        if let addedAt = addedAt {
            try container.encode(TimestampConverter.serverTimestamp(from: addedAt), forKey: .addedAt)
        }
        try container.encodeIfPresent(numBooks, forKey: .numBooks)
        try container.encodeIfPresent(authorDescription, forKey: .authorDescription)
        try container.encodeIfPresent(imagePath, forKey: .imagePath)
        if let updatedAt = updatedAt {
            try container.encode(TimestampConverter.serverTimestamp(from: updatedAt), forKey: .updatedAt)
        }
    }
}

// Enums must be Sendable (implicitly are if purely value-typed)
enum PersonalizedEntityType: Sendable {
    case book, series, author, unknown
}

enum PersonalizedSectionType: String, CaseIterable, Sendable {
    case recentlyAdded = "recently-added"
    case recentSeries = "recent-series"
    case discover = "discover"
    case newestAuthors = "newest-authors"
    case continueListening = "continue-listening"
    case recentlyFinished = "recently-finished"
    
    var displayName: String {
        switch self {
        case .recentlyAdded: return "Recently Added"
        case .recentSeries: return "Recent Series"
        case .discover: return "Discover"
        case .newestAuthors: return "New Authors"
        case .continueListening: return "Continue Listening"
        case .recentlyFinished: return "Recently Finished"
        }
    }
    
    var icon: String {
        switch self {
        case .recentlyAdded: return "clock.fill"
        case .recentSeries: return "rectangle.stack.fill"
        case .discover: return "sparkles"
        case .newestAuthors: return "person.2.fill"
        case .continueListening: return "play.circle.fill"
        case .recentlyFinished: return "checkmark.circle.fill"
        }
    }
}
