import Foundation
import UIKit
import Combine

// MARK: - Repository Protocol
protocol PlaybackRepositoryProtocol: Sendable {
    @MainActor func getPlaybackState(for bookId: String) -> PlaybackState?
    @MainActor func savePlaybackState(_ state: PlaybackState)
    @MainActor func getRecentlyPlayed(limit: Int) -> [PlaybackState]
    @MainActor func getAllPlaybackStates() -> [PlaybackState]
    @MainActor func deletePlaybackState(for bookId: String)
    @MainActor func clearAllPlaybackStates()
    @MainActor func syncPlaybackProgress() async
}

// MARK: - Playback Repository Implementation
@MainActor
class PlaybackRepository: ObservableObject {
    static let shared = PlaybackRepository()
    
    @Published var states: [String: PlaybackState] = [:]
    @Published var isOnline: Bool = false
    @Published var isSyncing: Bool = false
    
    private let userDefaults = UserDefaults.standard
    private var api: AudiobookshelfClient?
    private var pendingSyncItems: Set<String> = []
    
    private init() {
        loadAllStates()
    }
    
    func configure(api: AudiobookshelfClient) {
        self.api = api
        AppLogger.general.debug("[PlaybackRepo] Configured with API client")
    }

    func setOnlineStatus(_ online: Bool) {
        let wasOffline = !isOnline
        isOnline = online
        
        if online && wasOffline && !pendingSyncItems.isEmpty {
            Task {
                await syncPendingItems()
            }
        }
    }
    
    // MARK: - Load State for Book
    func loadStateForBook(_ itemId: String, book: Book) async -> PlaybackState? {
        var localState = states[itemId]
        
        var serverProgress: MediaProgress?
        if isOnline, let api = api {
            do {
                serverProgress = try await api.progress.fetchPlaybackProgress(libraryItemId: itemId)
            } catch {
                // Ignore failure
            }
        }
        
        if let serverProg = serverProgress {
            if var local = localState {
                if serverProg.lastUpdate > local.lastUpdate {
                    local = PlaybackState(from: serverProg, chapterIndex: calculateChapterIndex(currentTime: serverProg.currentTime, book: book))
                    saveStateLocal(local)
                    return local
                }
            } else {
                let newState = PlaybackState(from: serverProg, chapterIndex: calculateChapterIndex(currentTime: serverProg.currentTime, book: book))
                saveStateLocal(newState)
                return newState
            }
        }
        
        return localState
    }
    
    private func loadAllStates() {
        guard let allIds = userDefaults.stringArray(forKey: "all_playback_items") else { return }
        
        for itemId in allIds {
            let key = "playback_\(itemId)"
            if let data = userDefaults.data(forKey: key),
               let state = try? JSONDecoder().decode(PlaybackState.self, from: data) {
                states[itemId] = state
                if state.needsSync {
                    pendingSyncItems.insert(itemId)
                }
            }
        }
    }

    // MARK: - Public Accessors
    
    /// Get playback state synchronously (for UI)
    func getPlaybackState(for bookId: String) -> PlaybackState? {
        return states[bookId]
    }

    func getAllPlaybackStates() -> [PlaybackState] {
        return Array(states.values)
    }
    
    func getRecentlyPlayed(limit: Int) -> [PlaybackState] {
        return states.values.sorted(by: { $0.lastUpdate > $1.lastUpdate }).prefix(limit).map { $0 }
    }
    
    // MARK: - Save State
    
    func saveState(_ state: PlaybackState) {
        saveStateLocal(state)
        
        if isOnline {
            Task {
                await syncToServer(state)
            }
        } else {
            pendingSyncItems.insert(state.libraryItemId)
        }
    }
    
    func savePlaybackState(_ state: PlaybackState) {
        saveState(state)
    }
    
    private func saveStateLocal(_ state: PlaybackState) {
        let key = "playback_\(state.libraryItemId)"
        if let data = try? JSONEncoder().encode(state) {
            userDefaults.set(data, forKey: key)
            states[state.libraryItemId] = state
            
            var allIds = userDefaults.stringArray(forKey: "all_playback_items") ?? []
            if !allIds.contains(state.libraryItemId) {
                allIds.append(state.libraryItemId)
                userDefaults.set(allIds, forKey: "all_playback_items")
            }
        }
    }
    
    // MARK: - Sync Logic
    
    private func syncToServer(_ state: PlaybackState) async {
        guard let api = api, isOnline else { return }
        
        do {
            try await api.progress.updatePlaybackProgress(
                libraryItemId: state.libraryItemId,
                currentTime: state.currentTime,
                timeListened: 0,
                duration: state.duration,
                isFinished: state.isFinished
            )
            pendingSyncItems.remove(state.libraryItemId)
        } catch {
            pendingSyncItems.insert(state.libraryItemId)
        }
    }
    
    private func syncPendingItems() async {
        guard isOnline else { return }
        for itemId in pendingSyncItems {
            if let state = states[itemId] {
                await syncToServer(state)
            }
        }
    }
    
    func syncPlaybackProgress() async {
        guard isOnline, let api = api else { return }
        isSyncing = true
        
        if let allProgress = try? await api.progress.fetchAllMediaProgress() {
            for prog in allProgress {
                // We create a temp state to check timestamps; real merge happens when book is loaded ideally,
                // but we can update cache here if server is newer.
                let newState = PlaybackState(from: prog)
                if let local = states[prog.libraryItemId] {
                    if prog.lastUpdate > local.lastUpdate {
                        saveStateLocal(newState)
                    }
                } else {
                    saveStateLocal(newState)
                }
            }
        }
        isSyncing = false
    }
    
    func deletePlaybackState(for bookId: String) {
        states.removeValue(forKey: bookId)
        userDefaults.removeObject(forKey: "playback_\(bookId)")
        
        var allIds = userDefaults.stringArray(forKey: "all_playback_items") ?? []
        allIds.removeAll { $0 == bookId }
        userDefaults.set(allIds, forKey: "all_playback_items")
    }
    
    func clearAllPlaybackStates() {
        guard let allIds = userDefaults.stringArray(forKey: "all_playback_items") else { return }
        for itemId in allIds {
            userDefaults.removeObject(forKey: "playback_\(itemId)")
        }
        userDefaults.removeObject(forKey: "all_playback_items")
        states.removeAll()
        pendingSyncItems.removeAll()
    }
    
    private func calculateChapterIndex(currentTime: Double, book: Book) -> Int {
        book.chapterIndex(at: currentTime)
    }
}
