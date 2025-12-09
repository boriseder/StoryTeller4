
import Foundation

// MARK: - CollapsedSeries Model
struct CollapsedSeries: Codable {
    let id: String
    let name: String
    let nameIgnorePrefix: String?
    let numBooks: Int
}
