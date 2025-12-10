import Foundation
import SwiftUI
import Combine

@MainActor
class BookCardViewModel: ObservableObject, Identifiable {
    let book: Book
    private let container: DependencyContainer
    
    // Computed properties instead of stored references
    private var player: AudioPlayer { container.player }
    private var downloadManager: DownloadManager { container.downloadManager }
    
    // Cached playback state for non-current books
    @Published private var cachedState: PlaybackState?
    @Published private var isLoadingState = true
    
    // Identifiable conformance
    nonisolated var id: String { book.id }
    
    init(book: Book, container: DependencyContainer) {
        self.book = book
        self.container = container
        
        // Load cached state synchronously from local storage first
        // PlaybackRepository is @MainActor singleton, safe to call from here
        self.cachedState = PlaybackRepository.shared.getPlaybackState(for: book.id)
        self.isLoadingState = false
        
        // Optional: Refresh from server
        // Task { await refreshFromServer() }
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
            return player.totalBookDuration
        } else {
            return cachedState?.duration ?? calculateTotalDuration()
        }
    }
    
    var currentProgress: Double {
        if isCurrentBook {
            let totalDuration = player.totalBookDuration
            guard totalDuration > 0 else { return 0 }
            return player.absoluteCurrentTime / totalDuration
        } else {
            guard let state = cachedState, state.duration > 0 else { return 0 }
            return state.currentTime / state.duration
        }
    }
    
    // MARK: - Private Helpers
    
    private func refreshFromServer() async {
        guard cachedState == nil else { return }
        
        isLoadingState = true
        cachedState = await PlaybackRepository.shared.loadStateForBook(book.id, book: book)
        isLoadingState = false
    }
    
    private func calculateTotalDuration() -> Double {
        guard let lastChapter = book.chapters.last else { return 0 }
        return lastChapter.end ?? 0
    }
    
    // MARK: - Public refresh method
    
    func refreshState() {
        self.cachedState = PlaybackRepository.shared.getPlaybackState(for: book.id)
        Task {
            await refreshFromServer()
        }
    }
}
