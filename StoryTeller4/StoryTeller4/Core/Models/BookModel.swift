import Foundation

// MARK: Book
struct Book: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let title: String
    let author: String?
    let chapters: [Chapter]
    let coverPath: String?
    let collapsedSeries: CollapsedSeries?
    
    static func == (lhs: Book, rhs: Book) -> Bool { lhs.id == rhs.id }
    
    // Hashable implementation
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    func coverURL(baseURL: String) -> URL? {
        guard let coverPath = coverPath else { return nil }
        return URL(string: "\(baseURL)\(coverPath)")
    }
    
    // ← Series Detection
    var isCollapsedSeries: Bool {
        return collapsedSeries != nil
    }
    
    // ← Series Display Name (für UI)
    var displayTitle: String {
        return collapsedSeries?.name ?? title
    }
    
    // ← Series Book Count (für Badge)
    var seriesBookCount: Int {
        return collapsedSeries?.numBooks ?? 1
    }
}
