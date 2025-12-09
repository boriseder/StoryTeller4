// REFACTORED: BookCardStateViewModel
// Changes: Added PlaybackRepository integration for progress display with proper async loading

import Foundation
import SwiftUI

@MainActor
class BookCardViewModel: ObservableObject {
    let book: Book
    private let container: DependencyContainer
    
    // Computed properties instead of stored references
    private var player: AudioPlayer { container.player }
    private var downloadManager: DownloadManager { container.downloadManager }
    
    // Cached playback state for non-current books
    @Published private var cachedState: PlaybackState?
    @Published private var isLoadingState = true
    
    // Identifiable conformance - nonisolated for Swift 6 compatibility
    nonisolated var id: String { book.id }
    
    init(book: Book, container: DependencyContainer) {
        self.book = book
        self.container = container
        
        // Load cached state synchronously from local storage first
        self.cachedState = PlaybackRepository.shared.getPlaybackState(for: book.id)
        self.isLoadingState = false
        
        // Then refresh from server in background if needed
        /*
        Task {
            await refreshFromServer()
        }
         */
    }
    
    var isCurrentBook: Bool {
        player.book?.id == book.id
    }
    
    var isPlaying: Bool {
        isCurrentBook && player.isPlaying
    }
    
    var isDownloaded: Bool {
        downloadManager.isBookDownloaded(book.id)
    }
    
    var downloadProgress: Double {
        downloadManager.getDownloadProgress(for: book.id)
    }
    
    var isDownloading: Bool {
        downloadManager.isDownloadingBook(book.id)
    }
    
    var duration: Double {
        if isCurrentBook {
            // For currently playing book, use total book duration
            return player.totalBookDuration
        } else {
            // For other books, use cached duration or calculate from chapters
            return cachedState?.duration ?? calculateTotalDuration()
        }
    }
    
    var currentProgress: Double {
        if isCurrentBook {
            // For currently playing book, use live player data
            let totalDuration = player.totalBookDuration
            guard totalDuration > 0 else { return 0 }
            return player.absoluteCurrentTime / totalDuration
        } else {
            // For other books, use cached state
            guard let state = cachedState, state.duration > 0 else { return 0 }
            return state.currentTime / state.duration
        }
    }
    
    // MARK: - Private Helpers
    
    private func refreshFromServer() async {
        // Only refresh from server if we don't have local data
        guard cachedState == nil else { return }
        
        isLoadingState = true
        cachedState = await PlaybackRepository.shared.loadStateForBook(book.id, book: book)
        isLoadingState = false
        
        // Debug output
        if let state = cachedState {
            print("✅ [BookCard] \(book.title) - Loaded from server: \(state.currentTime)s / \(state.duration)s = \(currentProgress * 100)%")
        }
    }
    
    private func calculateTotalDuration() -> Double {
        guard let lastChapter = book.chapters.last else { return 0 }
        return lastChapter.end ?? 0
    }
    
    // MARK: - Public refresh method
    
    func refreshState() {
        // Refresh from local storage immediately
        cachedState = PlaybackRepository.shared.getPlaybackState(for: book.id)
        
        // Then refresh from server
        Task {
            await refreshFromServer()
        }
    }
}

// Separate Identifiable conformance
extension BookCardViewModel: Identifiable {}
