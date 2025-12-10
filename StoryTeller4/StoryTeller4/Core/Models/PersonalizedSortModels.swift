import Foundation

// MARK: - Personalized Section Model
/// Sendable: API response, used across views
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
/// Flexible entity that can represent books, series, or authors
/// Sendable: Part of API response, shared across views
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
    
    // MARK: - Computed Properties
    var entityType: PersonalizedEntityType {
        if media != nil {
            return .book
        } else if books != nil {
            return .series
        } else if numBooks != nil {
            return .author
        } else {
            return .unknown
        }
    }
    
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
    
    // MARK: - Coding Keys
    private enum CodingKeys: String, CodingKey {
        case id, media, libraryId, collapsedSeries
        case name, nameIgnorePrefix, books, addedAt, numBooks
        case authorDescription = "description"
        case imagePath, updatedAt
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(String.self, forKey: .id)
        media = try container.decodeIfPresent(Media.self, forKey: .media)
        libraryId = try container.decodeIfPresent(String.self, forKey: .libraryId)
        collapsedSeries = try container.decodeIfPresent(Series.self, forKey: .collapsedSeries)
        
        // Series properties
        name = try container.decodeIfPresent(String.self, forKey: .name)
        nameIgnorePrefix = try container.decodeIfPresent(String.self, forKey: .nameIgnorePrefix)
        books = try container.decodeIfPresent([LibraryItem].self, forKey: .books)
        
        if let timestamp = try container.decodeIfPresent(TimeInterval.self, forKey: .addedAt) {
            addedAt = TimestampConverter.dateFromServer(timestamp)
        } else {
            addedAt = nil
        }
        
        // Author properties
        numBooks = try container.decodeIfPresent(Int.self, forKey: .numBooks)
        authorDescription = try container.decodeIfPresent(String.self, forKey: .authorDescription)
        imagePath = try container.decodeIfPresent(String.self, forKey: .imagePath)
        
        if let timestamp = try container.decodeIfPresent(TimeInterval.self, forKey: .updatedAt) {
            updatedAt = TimestampConverter.dateFromServer(timestamp)
        } else {
            updatedAt = nil
        }
    }
}

// MARK: - Entity Type Enum
enum PersonalizedEntityType {
    case book
    case series
    case author
    case unknown
}

// MARK: - Personalized Section Types
enum PersonalizedSectionType: String, CaseIterable {
    case recentlyAdded = "recently-added"
    case recentSeries = "recent-series"
    case discover = "discover"
    case newestAuthors = "newest-authors"
    case continueListening = "continue-listening"
    case recentlyFinished = "recently-finished"
    
    var displayName: String {
        switch self {
        case .recentlyAdded:
            return "Recently Added"
        case .recentSeries:
            return "Recent Series"
        case .discover:
            return "Discover"
        case .newestAuthors:
            return "New Authors"
        case .continueListening:
            return "Continue Listening"
        case .recentlyFinished:
            return "Recently Finished"
        }
    }
    
    var icon: String {
        switch self {
        case .recentlyAdded:
            return "clock.fill"
        case .recentSeries:
            return "rectangle.stack.fill"
        case .discover:
            return "sparkles"
        case .newestAuthors:
            return "person.2.fill"
        case .continueListening:
            return "play.circle.fill"
        case .recentlyFinished:
            return "checkmark.circle.fill"
        }
    }
    
    var expectedEntityType: PersonalizedEntityType {
        switch self {
        case .recentlyAdded, .discover, .continueListening, .recentlyFinished:
            return .book
        case .recentSeries:
            return .series
        case .newestAuthors:
            return .author
        }
    }
}

// MARK: - Sort Option Protocol
protocol SortOptionProtocol: CaseIterable, RawRepresentable where RawValue == String {
    var systemImage: String { get }
}

// MARK: - Library Sort Options
enum LibrarySortOption: String, CaseIterable, Hashable, Identifiable, SortOptionProtocol {
    case title = "Title"
    case author = "Author"
    case recent = "Last added"
    
    var id: String { rawValue }
    
    var systemImage: String {
        switch self {
        case .title:
            return "textformat.abc"
        case .author:
            return "person.fill"
        case .recent:
            return "clock.fill"
        }
    }
    
    func sort(_ items: [LibraryItem]) -> [LibraryItem] {
        switch self {
        case .title:
            return items.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .author:
            return items.sorted {
                ($0.author ?? "").localizedStandardCompare($1.author ?? "") == .orderedAscending
            }
        case .recent:
            return items // Assumes items are already in recent order from API
        }
    }
}

// MARK: - Series Sort Options
enum SeriesSortOption: String, CaseIterable, SortOptionProtocol {
    case name = "Name"
    case recent = "Added recently"
    case bookCount = "Number of books"
    case duration = "Duration"
    
    var systemImage: String {
        switch self {
        case .name:
            return "textformat.abc"
        case .recent:
            return "clock.fill"
        case .bookCount:
            return "books.vertical"
        case .duration:
            return "timer"
        }
    }
    
    func sort(_ series: [Series]) -> [Series] {
        switch self {
        case .name:
            return series.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .recent:
            return series.sorted { $0.addedAt > $1.addedAt }
        case .bookCount:
            return series.sorted { $0.bookCount > $1.bookCount }
        case .duration:
            return series.sorted { $0.totalDuration > $1.totalDuration }
        }
    }
}
