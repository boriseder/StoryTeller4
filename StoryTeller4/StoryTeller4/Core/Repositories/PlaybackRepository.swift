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
    
    // MARK: - Sync from Server
    //
    // Fetches all media progress from the server and merges it into local state.
    // Server wins when its lastUpdate timestamp is newer than the local record.
    // Local wins when it has pending unsynced changes (needsSync == true), since
    // those represent playback that happened offline and hasn't been pushed yet.
    func syncFromServer() async {
        guard let api = self.api, isOnline else {
            AppLogger.general.debug("[PlaybackRepository] Skipping sync — offline or not configured")
            return
        }

        isSyncing = true
        defer { isSyncing = false }

        do {
            let allProgress = try await api.progress.fetchAllMediaProgress()

            for serverProgress in allProgress {
                let itemId = serverProgress.libraryItemId

                if let localState = states[itemId] {
                    // Local has pending offline changes — push those to server instead
                    if localState.needsSync {
                        AppLogger.general.debug("[PlaybackRepository] Item \(itemId) has pending local changes, pushing to server")
                        await syncToServer(localState)
                        continue
                    }

                    // Server is newer — update local
                    if serverProgress.lastUpdate > localState.lastUpdate {
                        let newState = PlaybackState(from: serverProgress)
                        saveStateLocal(newState)
                        AppLogger.general.debug("[PlaybackRepository] Updated \(itemId) from server (server newer)")
                    }
                    // Local is newer — nothing to do, local will sync on next saveState call
                } else {
                    // No local record at all — take the server version
                    let newState = PlaybackState(from: serverProgress)
                    saveStateLocal(newState)
                    AppLogger.general.debug("[PlaybackRepository] Saved new state for \(itemId) from server")
                }
            }

            AppLogger.general.debug("[PlaybackRepository] Sync complete — \(allProgress.count) items processed")
        } catch {
            AppLogger.general.error("[PlaybackRepository] Sync failed: \(error)")
        }
    }
}
