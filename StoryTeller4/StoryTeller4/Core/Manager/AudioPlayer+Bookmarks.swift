// AudioPlayer+Bookmarks.swift
// Separate Extension File für Bookmark-Funktionalität

import Foundation

extension AudioPlayer {
    
    /// Jump to a specific bookmark (handles chapter switching and absolute/relative time conversion)
    func jumpToBookmark(_ bookmark: Bookmark) {
        guard let book = book else {
            AppLogger.general.debug("[AudioPlayer] Cannot jump to bookmark - no book loaded")
            return
        }
        
        // 🔍 DEBUG: Print all chapters
        AppLogger.general.debug("[AudioPlayer] Book has \(book.chapters.count) chapters:")
        for (idx, ch) in book.chapters.enumerated() {
            let start = ch.start ?? 0
            let end = ch.end ?? 0
            AppLogger.general.debug("[AudioPlayer]   Chapter \(idx): '\(ch.title)' | start: \(start)s, end: \(end)s")
        }
        
        let absoluteTime = bookmark.time
        AppLogger.general.debug("[AudioPlayer] Looking for chapter containing \(absoluteTime)s (\(bookmark.formattedTime))")
        
        // Find the correct chapter for this absolute time
        guard let targetChapterIndex = findChapterIndex(for: absoluteTime, in: book) else {
            AppLogger.general.debug("[AudioPlayer] Cannot find chapter for bookmark at \(absoluteTime)s")
            return
        }
        
        guard let targetChapter = book.chapters[safe: targetChapterIndex] else {
            AppLogger.general.debug("[AudioPlayer] Invalid chapter index: \(targetChapterIndex)")
            return
        }
        
        // Calculate relative time in chapter
        let chapterStart = targetChapter.start ?? 0
        let relativeTime = absoluteTime - chapterStart
        
        AppLogger.general.debug("""
            [AudioPlayer] Jumping to bookmark '\(bookmark.title)'
            - Absolute time: \(absoluteTime)s (\(bookmark.formattedTime))
            - Target chapter: \(targetChapterIndex) (starts at \(chapterStart)s)
            - Relative time in chapter: \(relativeTime)s
        """)
        
        if targetChapterIndex != currentChapterIndex {
            // Different chapter - need to load it first
            AppLogger.general.debug("[AudioPlayer] Switching from chapter \(currentChapterIndex) to \(targetChapterIndex)")
            loadChapter(at: targetChapterIndex, seekTo: relativeTime, shouldResume: true)
        } else {
            // Same chapter - reload with seek time for reliable seeking
            // ✅ FIX: Always use loadChapter for bookmarks to ensure seek works
            AppLogger.general.debug("[AudioPlayer] Reloading chapter \(targetChapterIndex) with seek to \(relativeTime)s")
            loadChapter(at: targetChapterIndex, seekTo: relativeTime, shouldResume: true)
        }
    }
    
    /// Find which chapter contains a given absolute timestamp
    private func findChapterIndex(for absoluteTime: Double, in book: Book) -> Int? {
        // Handle single-chapter books
        if book.chapters.count == 1 {
            AppLogger.general.debug("[AudioPlayer] Single chapter book - using chapter 0")
            return 0
        }
        
        for (index, chapter) in book.chapters.enumerated() {
            let chapterStart = chapter.start ?? 0
            let chapterEnd = chapter.end ?? Double.infinity
            
            // Check if time falls within this chapter
            if absoluteTime >= chapterStart && absoluteTime < chapterEnd {
                AppLogger.general.debug("[AudioPlayer] Found chapter \(index) for time \(absoluteTime)s")
                return index
            }
        }
        
        // Fallback: if time is at or beyond last chapter
        if let lastChapter = book.chapters.last, absoluteTime >= (lastChapter.start ?? 0) {
            AppLogger.general.debug("[AudioPlayer] Time beyond chapters, using last chapter")
            return book.chapters.count - 1
        }
        
        // If still not found, default to first chapter
        AppLogger.general.warn("[AudioPlayer] Time \(absoluteTime)s not found in any chapter, defaulting to chapter 0")
        return 0
    }
    
    /// Get enriched bookmarks for current book
    @MainActor
    func getCurrentBookEnrichedBookmarks() -> [EnrichedBookmark] {
        guard let book = book else { return [] }
        return DependencyContainer.shared.getEnrichedBookmarks(for: book.id)
    }
    
    /// Get bookmarks for current book (raw)
    @MainActor
    func getCurrentBookBookmarks() -> [Bookmark] {
        guard let book = book else { return [] }
        return BookmarkRepository.shared.getBookmarks(for: book.id)
    }
    
    /// Check if there's a bookmark near current time
    @MainActor
    func checkForNearbyBookmark(tolerance: Double = 5.0) -> Bookmark? {
        guard let book = book else { return nil }
        
        let currentAbsoluteTime = absoluteCurrentTime
        let bookmarks = BookmarkRepository.shared.getBookmarks(for: book.id)
        
        return bookmarks.first { abs($0.time - currentAbsoluteTime) < tolerance }
    }
    
    /// Get count of bookmarks for current book
    @MainActor
    func getCurrentBookBookmarkCount() -> Int {
        guard let book = book else { return 0 }
        return BookmarkRepository.shared.getBookmarks(for: book.id).count
    }
    
    /// Create a bookmark at current playback position
    @MainActor
    func createBookmarkAtCurrentPosition(title: String? = nil) async throws {
        guard let book = book else {
            throw AudioPlayerError.noBookLoaded
        }
        
        let currentAbsoluteTime = absoluteCurrentTime
        let bookmarkTitle = title ?? "Bookmark at \(TimeFormatter.formatTime(currentAbsoluteTime))"
        
        try await BookmarkRepository.shared.createBookmark(
            libraryItemId: book.id,
            time: currentAbsoluteTime,
            title: bookmarkTitle
        )
        
        AppLogger.general.debug("[AudioPlayer] Created bookmark '\(bookmarkTitle)' at \(currentAbsoluteTime)s")
    }
}

// MARK: - Helper Extensions
extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Audio Player Error
enum AudioPlayerError: LocalizedError {
    case noBookLoaded
    
    var errorDescription: String? {
        switch self {
        case .noBookLoaded:
            return "No book is currently loaded"
        }
    }
}
