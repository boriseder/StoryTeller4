import Foundation

struct Media: Codable {
    let metadata: Metadata
    let chapters: [Chapter]?
    let duration: Double?
    let size: Int64?
    let tracks: [AudioTrack]?
    let coverPath: String? 
}
