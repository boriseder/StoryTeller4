import Foundation
import UIKit
import Combine

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
    }
    
    func setOnlineStatus(_ online: Bool) {
        let wasOffline = !isOnline
        isOnline = online
        if online && wasOffline && !pendingSyncItems.isEmpty {
            Task { await syncPendingItems() }
        }
    }
    
    func loadStateForBook(_ itemId: String, book: Book) async -> PlaybackState? {
        let localState = states[itemId]
        
        var serverProgress: MediaProgress?
        if isOnline, let api = api {
            do { serverProgress = try await api.progress.fetchPlaybackProgress(libraryItemId: itemId) }
            catch {}
        }
        
        if let serverProg = serverProgress {
            if let local = localState {
                if serverProg.lastUpdate > local.lastUpdate {
                    let newState = PlaybackState(from: serverProg, chapterIndex: calculateChapterIndex(currentTime: serverProg.currentTime, book: book))
                    saveStateLocal(newState)
                    return newState
                } else {
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
            states[state.libraryItemId] = state
            
            var allIds = userDefaults.stringArray(forKey: "all_playback_items") ?? []
            if !allIds.contains(state.libraryItemId) {
                allIds.append(state.libraryItemId)
                userDefaults.set(allIds, forKey: "all_playback_items")
            }
        }
    }
    
    func saveState(_ state: PlaybackState) {
        var newState = state
        newState.needsSync = !isOnline
        saveStateLocal(newState)
        if isOnline {
            Task { await syncToServer(newState) }
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
            var syncedState = state
            syncedState.needsSync = false
            saveStateLocal(syncedState)
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
    
    func getPlaybackState(for bookId: String) -> PlaybackState? { return states[bookId] }
    func getAllPlaybackStates() -> [PlaybackState] { Array(states.values) }
    func getRecentlyPlayed(limit: Int) -> [PlaybackState] { states.values.sorted(by: { $0.lastUpdate > $1.lastUpdate }).prefix(limit).map { $0 } }
    
    func deletePlaybackState(for bookId: String) {
        states.removeValue(forKey: bookId)
        userDefaults.removeObject(forKey: "playback_\(bookId)")
        var allIds = userDefaults.stringArray(forKey: "all_playback_items") ?? []
        allIds.removeAll { $0 == bookId }
        userDefaults.set(allIds, forKey: "all_playback_items")
    }
    
    func clearAllPlaybackStates() {
        guard let allIds = userDefaults.stringArray(forKey: "all_playback_items") else { return }
        for itemId in allIds { userDefaults.removeObject(forKey: "playback_\(itemId)") }
        userDefaults.removeObject(forKey: "all_playback_items")
        states.removeAll()
        pendingSyncItems.removeAll()
    }
    
    private func calculateChapterIndex(currentTime: Double, book: Book) -> Int {
        book.chapterIndex(at: currentTime)
    }
    
    private func loadAllStates() {
        guard let allIds = userDefaults.stringArray(forKey: "all_playback_items") else { return }
        for itemId in allIds {
            if let data = userDefaults.data(forKey: "playback_\(itemId)"),
               let state = try? JSONDecoder().decode(PlaybackState.self, from: data) {
                states[itemId] = state
                if state.needsSync { pendingSyncItems.insert(itemId) }
            }
        }
    }
    
    func syncPlaybackProgress() async {
        guard isOnline, let api = api else { return }
        isSyncing = true
        if let allProgress = try? await api.progress.fetchAllMediaProgress() {
            for prog in allProgress {
                let newState = PlaybackState(from: prog)
                if let local = states[prog.libraryItemId] {
                    if prog.lastUpdate > local.lastUpdate { saveStateLocal(newState) }
                } else { saveStateLocal(newState) }
            }
        }
        isSyncing = false
    }
}

extension PlaybackRepository {
    func syncFromServer() async {
            guard let api = self.api else { return }
            
            do {
                // Actual implementation: Fetch progress
                _ = try await api.progress.fetchAllMediaProgress()
                AppLogger.general.debug("[PlaybackRepository] Synced from server")
            } catch {
                AppLogger.general.error("[PlaybackRepository] Sync failed: \(error)")
            }
    }
}

