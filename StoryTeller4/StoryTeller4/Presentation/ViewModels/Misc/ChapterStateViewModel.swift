import Foundation

// MARK: - Chapter State View Model
struct ChapterStateViewModel: Identifiable, Equatable {
    let id: Int
    let chapter: Chapter
    let isCurrent: Bool
    let isPlaying: Bool
    let currentTime: Double
    
    init(index: Int, chapter: Chapter, player: AudioPlayer) {
        self.id = index
        self.chapter = chapter
        self.isCurrent = index == player.currentChapterIndex
        self.isPlaying = isCurrent && player.isPlaying
        self.currentTime = isCurrent ? player.currentTime : 0
    }
    
    static func == (lhs: ChapterStateViewModel, rhs: ChapterStateViewModel) -> Bool {
        return lhs.id == rhs.id &&
               lhs.isCurrent == rhs.isCurrent &&
               lhs.isPlaying == rhs.isPlaying &&
               abs(lhs.currentTime - rhs.currentTime) < 1.0
    }
}
