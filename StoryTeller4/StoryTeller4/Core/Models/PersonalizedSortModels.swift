import Foundation

struct PersonalizedSection: Codable, Identifiable, Sendable {
    let id: String
    let label: String
    let labelStringKey: String?
    let type: String
    let entities: [PersonalizedEntity]
    let total: Int
    
    var sectionType: PersonalizedSectionType? { PersonalizedSectionType(rawValue: type) }
    var displayLabel: String { sectionType?.displayName ?? label }
    var icon: String { sectionType?.icon ?? "list.bullet" }
    
    enum CodingKeys: String, CodingKey { case id, label, labelStringKey, type, entities, total }
    
    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        label = try c.decode(String.self, forKey: .label)
        labelStringKey = try c.decodeIfPresent(String.self, forKey: .labelStringKey)
        type = try c.decode(String.self, forKey: .type)
        entities = try c.decode([PersonalizedEntity].self, forKey: .entities)
        total = try c.decode(Int.self, forKey: .total)
    }
    
    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(label, forKey: .label)
        try c.encodeIfPresent(labelStringKey, forKey: .labelStringKey); try c.encode(type, forKey: .type)
        try c.encode(entities, forKey: .entities); try c.encode(total, forKey: .total)
    }
}

typealias PersonalizedResponse = [PersonalizedSection]

struct PersonalizedEntity: Codable, Identifiable, Sendable {
    let id: String
    let media: Media?
    let libraryId: String?
    let collapsedSeries: Series?
    let name: String?
    let nameIgnorePrefix: String?
    let books: [LibraryItem]?
    let addedAt: Date?
    let numBooks: Int?
    let authorDescription: String?
    let imagePath: String?
    let updatedAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case id, media, libraryId, collapsedSeries, name, nameIgnorePrefix, books, addedAt, numBooks, authorDescription = "description", imagePath, updatedAt
    }
    
    var entityType: PersonalizedEntityType {
        if media != nil { return .book }
        if books != nil { return .series }
        if numBooks != nil { return .author }
        return .unknown
    }
    
    // Conversion properties omitted for brevity but should be here if needed
    
    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        media = try c.decodeIfPresent(Media.self, forKey: .media)
        libraryId = try c.decodeIfPresent(String.self, forKey: .libraryId)
        collapsedSeries = try c.decodeIfPresent(Series.self, forKey: .collapsedSeries)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        nameIgnorePrefix = try c.decodeIfPresent(String.self, forKey: .nameIgnorePrefix)
        books = try c.decodeIfPresent([LibraryItem].self, forKey: .books)
        if let ts = try c.decodeIfPresent(TimeInterval.self, forKey: .addedAt) { addedAt = TimestampConverter.dateFromServer(ts) } else { addedAt = nil }
        numBooks = try c.decodeIfPresent(Int.self, forKey: .numBooks)
        authorDescription = try c.decodeIfPresent(String.self, forKey: .authorDescription)
        imagePath = try c.decodeIfPresent(String.self, forKey: .imagePath)
        if let ts = try c.decodeIfPresent(TimeInterval.self, forKey: .updatedAt) { updatedAt = TimestampConverter.dateFromServer(ts) } else { updatedAt = nil }
    }
    
    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encodeIfPresent(media, forKey: .media)
        try c.encodeIfPresent(libraryId, forKey: .libraryId); try c.encodeIfPresent(collapsedSeries, forKey: .collapsedSeries)
        try c.encodeIfPresent(name, forKey: .name); try c.encodeIfPresent(nameIgnorePrefix, forKey: .nameIgnorePrefix)
        try c.encodeIfPresent(books, forKey: .books)
        if let addedAt = addedAt { try c.encode(TimestampConverter.serverTimestamp(from: addedAt), forKey: .addedAt) }
        try c.encodeIfPresent(numBooks, forKey: .numBooks); try c.encodeIfPresent(authorDescription, forKey: .authorDescription)
        try c.encodeIfPresent(imagePath, forKey: .imagePath)
        if let updatedAt = updatedAt { try c.encode(TimestampConverter.serverTimestamp(from: updatedAt), forKey: .updatedAt) }
    }
}

enum PersonalizedEntityType: Sendable { case book, series, author, unknown }

enum PersonalizedSectionType: String, CaseIterable, Sendable {
    case recentlyAdded = "recently-added"
    case recentSeries = "recent-series"
    case discover = "discover"
    case newestAuthors = "newest-authors"
    case continueListening = "continue-listening"
    case recentlyFinished = "recently-finished"
    
    var displayName: String { rawValue }
    var icon: String { "list.bullet" }
}

protocol SortOptionProtocol: CaseIterable, RawRepresentable where RawValue == String {
    var systemImage: String { get }
}

enum LibrarySortOption: String, CaseIterable, Hashable, Identifiable, SortOptionProtocol, Sendable {
    case title = "Title", author = "Author", recent = "Last added"
    var id: String { rawValue }
    var systemImage: String {
        switch self {
        case .title: return "textformat.abc"
        case .author: return "person.fill"
        case .recent: return "clock.fill"
        }
    }
}

enum SeriesSortOption: String, CaseIterable, SortOptionProtocol, Sendable {
    case name = "Name", recent = "Added recently", bookCount = "Number of books", duration = "Duration"
    var systemImage: String {
        switch self {
        case .name: return "textformat.abc"
        case .recent: return "clock.fill"
        case .bookCount: return "books.vertical"
        case .duration: return "timer"
        }
    }
}

extension PersonalizedEntity {
    var asLibraryItem: LibraryItem? {
        guard let media = self.media,
              let libraryId = self.libraryId else {
            return nil
        }
        
        return LibraryItem(
            id: self.id,
            media: media,
            libraryId: libraryId,
            isFile: nil,
            isMissing: nil,
            isInvalid: nil,
            collapsedSeries: self.collapsedSeries
        )
    }
}
