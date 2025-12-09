import Foundation

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
        case .title: return "textformat.abc"
        case .author: return "person.fill"
        case .recent: return "clock.fill"
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
        case .name: return "textformat.abc"
        case .recent: return "clock.fill"
        case .bookCount: return "books.vertical"
        case .duration: return "timer"
        }
    }
}
