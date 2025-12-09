import Foundation

struct Chapter: Codable, Identifiable {
    let id: String
    let title: String
    let start: Double?
    let end: Double?
    let libraryItemId: String?
    let episodeId: String?
    
    init(id: String, title: String, start: Double? = nil, end: Double? = nil, 
         libraryItemId: String? = nil, episodeId: String? = nil) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.libraryItemId = libraryItemId
        self.episodeId = episodeId
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Flexible ID handling
        if let intId = try? container.decode(Int.self, forKey: .id) {
            self.id = String(intId)
        } else {
            self.id = (try? container.decode(String.self, forKey: .id)) ?? UUID().uuidString
        }
        
        self.title = (try? container.decode(String.self, forKey: .title)) ?? "Untitled"
        self.start = try? container.decode(Double.self, forKey: .start)
        self.end = try? container.decode(Double.self, forKey: .end)
        self.libraryItemId = try? container.decode(String.self, forKey: .libraryItemId)
        self.episodeId = try? container.decode(String.self, forKey: .episodeId)
    }
}
