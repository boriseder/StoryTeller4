import Foundation
import UIKit
import Combine

// MARK: - Repository Protocol
// Must be Sendable. Since implementation is @MainActor, access is safe.
protocol PlaybackRepositoryProtocol: Sendable {
    @MainActor func getPlaybackState(for bookId: String) -> PlaybackState?
    @MainActor func savePlaybackState(_ state: PlaybackState)
    @MainActor func getRecentlyPlayed(limit: Int) -> [PlaybackState]
    @MainActor func getAllPlaybackStates() -> [String: PlaybackState]
    @MainActor func deletePlaybackState(for bookId: String)
    @MainActor func clearAllPlaybackStates()
    @MainActor func syncPlaybackProgress() async throws
}



@MainActor
class PlaybackRepository: ObservableObject {
    // ... existing implementation with Combine import added ...
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
    // ... rest of implementation ...
    
    // (Include full class body as previously provided, just ensures Combine is present)
    func configure(api: AudiobookshelfClient) {
        self.api = api
    }
    
    func setOnlineStatus(_ online: Bool) {
        let wasOffline = !isOnline
        isOnline = online
        if online && wasOffline && !pendingSyncItems.isEmpty {
            Task { await syncPendingItems() }
        }
    }
    
    func loadStateForBook(_ itemId: String, book: Book) async -> PlaybackState? {
        var localState = states[itemId]
        
        var serverProgress: MediaProgress?
        if isOnline, let api = api {
            serverProgress = try? await api.progress.fetchPlaybackProgress(libraryItemId: itemId)
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
    
    private func saveStateLocal(_ state: PlaybackState) {
        let key = "playback_\(state.libraryItemId)"
        if let data = try? JSONEncoder().encode(state) {
            userDefaults.set(data, forKey: key)
            self.states[state.libraryItemId] = state
            
            var allIds = userDefaults.stringArray(forKey: "all_playback_items") ?? []
            if !allIds.contains(state.libraryItemId) {
                allIds.append(state.libraryItemId)
                userDefaults.set(allIds, forKey: "all_playback_items")
            }
        }
    }
    
    func saveState(_ state: PlaybackState) {
        saveStateLocal(state)
        if isOnline {
            Task { await syncToServer(state) }
        } else {
            pendingSyncItems.insert(state.libraryItemId)
        }
    }
    
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
        for itemId in pendingSyncItems {
            if let state = states[itemId] {
                await syncToServer(state)
            }
        }
    }
    
    func syncFromServer() async {
        guard isOnline, let api = api else { return }
        isSyncing = true
        if let allProgress = try? await api.progress.fetchAllMediaProgress() {
            for prog in allProgress {
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
    
    func calculateChapterIndex(currentTime: Double, book: Book) -> Int {
        book.chapterIndex(at: currentTime)
    }
    
    private func loadAllStates() {
        guard let allIds = userDefaults.stringArray(forKey: "all_playback_items") else { return }
        for itemId in allIds {
            if let data = userDefaults.data(forKey: "playback_\(itemId)"),
               let state = try? JSONDecoder().decode(PlaybackState.self, from: data) {
                states[itemId] = state
            }
        }
    }
}
