import Foundation

// MARK: - Chapter State View Model
//
// A pure value snapshot of one chapter row's display state.
// No Timer, no Combine, no subscriptions.
//
// ChaptersListView creates these with `.task(id:)` that re-fires whenever
// the two AudioPlayer properties it cares about (currentChapterIndex,
// isPlaying) change — SwiftUI's @Observable tracking does the rest.
// currentTime is only captured for the currently-playing chapter so the
// progress bar stays live; all other rows receive 0 and never cause redraws.

struct ChapterStateViewModel: Identifiable, Equatable {
    let id: Int           // chapter index, stable identity for ForEach
    let chapter: Chapter
    let isCurrent: Bool
    let isPlaying: Bool
    let currentTime: Double

    init(index: Int, chapter: Chapter, player: AudioPlayer) {
        self.id = index
        self.chapter = chapter
        self.isCurrent = (index == player.currentChapterIndex)
        self.isPlaying = (index == player.currentChapterIndex) && player.isPlaying
        // Only track live time for the active chapter — avoids re-rendering
        // every row every second while playback is running.
        self.currentTime = (index == player.currentChapterIndex) ? player.currentTime : 0
    }

    // Equality intentionally ignores sub-second time drift for non-current rows.
    // For the current row, 1-second granularity matches the player's time observer.
    static func == (lhs: ChapterStateViewModel, rhs: ChapterStateViewModel) -> Bool {
        lhs.id == rhs.id &&
        lhs.isCurrent == rhs.isCurrent &&
        lhs.isPlaying == rhs.isPlaying &&
        abs(lhs.currentTime - rhs.currentTime) < 1.0
    }
}
