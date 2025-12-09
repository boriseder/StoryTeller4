import Foundation
import UIKit

// MARK: - Repository Protocol
protocol PlaybackRepositoryProtocol {
    func getPlaybackState(for bookId: String) -> PlaybackState?
    func savePlaybackState(_ state: PlaybackState)
    func getRecentlyPlayed(limit: Int) -> [PlaybackState]
    func getAllPlaybackStates() -> [PlaybackState]
    func deletePlaybackState(for bookId: String)
    func clearAllPlaybackStates()
    func syncPlaybackProgress(to server: AudiobookshelfClient) async throws
}

// MARK: - Playback Repository Implementation

class PlaybackRepository: ObservableObject {
    static let shared = PlaybackRepository()
    
    @Published var states: [String: PlaybackState] = [:]
    @Published var isOnline: Bool = false
    @Published var isSyncing: Bool = false
    
    private let userDefaults = UserDefaults.standard
    private let queue = DispatchQueue(label: "com.storyteller.playback", attributes: .concurrent)
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
        
        AppLogger.general.debug("[PlaybackRepo] Online status: \(online)")
    }
    
    // MARK: - Load State for Book
    
    func loadStateForBook(_ itemId: String, book: Book) async -> PlaybackState? {
        AppLogger.general.debug("[PlaybackRepo] 🔍 Loading state for: \(itemId)")
        
        // 1. Fetch local state
        var localState = states[itemId]
        
        // 2. If online: Fetch remote state
        var serverProgress: MediaProgress?
        if isOnline, let api = api {
            do {
                serverProgress = try await api.progress.fetchPlaybackProgress(libraryItemId: itemId)
                AppLogger.general.debug("[PlaybackRepo] 📥 Server progress fetched: \(serverProgress != nil)")
            } catch {
                AppLogger.general.debug("[PlaybackRepo] ⚠️ Server fetch failed: \(error)")
            }
        }
        
        // 3. Merge-Logik
        if let serverProg = serverProgress {
            if var local = localState {
                // Haben beides: Merge und NEU-BERECHNUNG von chapterIndex
                let serverUpdateDate = Date(timeIntervalSince1970: serverProg.lastUpdate / 1000)
                
                if serverUpdateDate > local.lastUpdate {
                    local.currentTime = serverProg.currentTime
                    local.duration = serverProg.duration
                    local.isFinished = serverProg.isFinished
                    local.lastUpdate = serverUpdateDate
                    local.needsSync = false
                }
                
                local.chapterIndex = calculateChapterIndex(currentTime: local.currentTime, book: book)
                
                saveStateLocal(local)
                return local
            } else {
                // Nur Server hat Daten → Erstelle neuen State
                let newState = PlaybackState(
                    libraryItemId: itemId,
                    currentTime: serverProg.currentTime,
                    duration: serverProg.duration,
                    isFinished: serverProg.isFinished,
                    lastUpdate: Date(timeIntervalSince1970: serverProg.lastUpdate / 1000),
                    chapterIndex: calculateChapterIndex(currentTime: serverProg.currentTime, book: book),
                    needsSync: false
                )
                saveStateLocal(newState)
                return newState
            }
        } else if var local = localState {
            // Nur lokal hat Daten → Berechne chapterIndex neu
            local.chapterIndex = calculateChapterIndex(currentTime: local.currentTime, book: book)
            saveStateLocal(local)
            return local
        }
        
        // 4. Nichts gefunden
        AppLogger.general.debug("[PlaybackRepo] ❌ No state found for: \(itemId)")
        return nil
    }
    
    private func loadAllStates() {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard let allIds = self.userDefaults.stringArray(forKey: "all_playback_items") else { return }
            
            var loadedStates: [String: PlaybackState] = [:]
            var pending: Set<String> = []
            
            for itemId in allIds {
                let key = "playback_\(itemId)"
                guard let data = self.userDefaults.data(forKey: key) else { continue }
                
                do {
                    let state = try JSONDecoder().decode(PlaybackState.self, from: data)
                    loadedStates[itemId] = state
                    AppLogger.general.debug("[PlaybackRepo] bookID: \(state.bookId) ⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️")

                    
                    if state.needsSync {
                        pending.insert(itemId)
                    }
                } catch {
                    AppLogger.general.debug("[PlaybackRepo] ❌ Failed to decode: \(itemId)")
                }
            }
            
            DispatchQueue.main.async {
                self.states = loadedStates
                self.pendingSyncItems = pending
                AppLogger.general.debug("[PlaybackRepo] Loaded \(loadedStates.count) states (\(pending.count) pending sync)")
            }
        }
    }

    // MARK: - Synchronous Local Access (for UI)

    /// Get playback state synchronously from local cache (for immediate UI display)
    func getPlaybackState(for itemId: String) -> PlaybackState? {
        return states[itemId]
    }

    /// Get all playback states synchronously
    func getAllPlaybackStates() -> [String: PlaybackState] {
        return states
    }
    
    // MARK: - Save State
    
    func saveState(_ state: PlaybackState) {
        var stateToSave = state
        stateToSave.lastUpdate = Date() // Update timestamp
        
        // Mark as needing sync if offline
        if !isOnline {
            stateToSave.needsSync = true
            pendingSyncItems.insert(state.libraryItemId)
            AppLogger.general.debug("[PlaybackRepo] 💾 Saved offline: \(state.libraryItemId)")
        }
        
        saveStateLocal(stateToSave)
        
        // If online, sync immediately
        if isOnline {
            Task {
                await syncToServer(stateToSave)
            }
        }
    }
    
    private func saveStateLocal(_ state: PlaybackState) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            let key = "playback_\(state.libraryItemId)"
            
            do {
                let data = try JSONEncoder().encode(state)
                self.userDefaults.set(data, forKey: key)
                
                var allIds = self.userDefaults.stringArray(forKey: "all_playback_items") ?? []
                if !allIds.contains(state.libraryItemId) {
                    allIds.append(state.libraryItemId)
                    self.userDefaults.set(allIds, forKey: "all_playback_items")
                }
                
                DispatchQueue.main.async {
                    self.states[state.libraryItemId] = state
                }
                
            } catch {
                AppLogger.general.debug("[PlaybackRepo] ❌ Failed to save: \(error)")
            }
        }
    }
    
    // MARK: - Server Sync
    
    private func syncToServer(_ state: PlaybackState) async {
        guard let api = api else { return }
        guard isOnline else {
            AppLogger.general.debug("[PlaybackRepo] ⏸️ Offline - queued for sync: \(state.libraryItemId)")
            return
        }
        
        do {
            try await api.progress.updatePlaybackProgress(
                libraryItemId: state.libraryItemId,
                currentTime: state.currentTime,
                timeListened: 0, // Optional: timeListened tracken
                duration: state.duration,
                isFinished: state.isFinished
            )
            
            // Mark as synced
            var syncedState = state
            syncedState.needsSync = false
            saveStateLocal(syncedState)
            pendingSyncItems.remove(state.libraryItemId)
            
            AppLogger.general.info("[PlaybackRepo] Synced to server: \(state.libraryItemId)")
        } catch {
            AppLogger.general.error("[PlaybackRepo] Sync failed: \(state.libraryItemId) - \(error)")
            pendingSyncItems.insert(state.libraryItemId)
        }
    }
    
    /// Sync all items that have needsSync=true
    private func syncPendingItems() async {
        guard isOnline else { return }
        
        let itemsToSync = states.values.filter { $0.needsSync }
        
        guard !itemsToSync.isEmpty else {
            AppLogger.general.debug("[PlaybackRepo] No pending items to sync")
            return
        }
        
        isSyncing = true
        AppLogger.general.debug("[PlaybackRepo] Syncing \(itemsToSync.count) pending items...")
        
        for state in itemsToSync {
            await syncToServer(state)
        }
        
        isSyncing = false
        AppLogger.general.debug("[PlaybackRepo] Pending sync complete")
    }
    
    /// Optional: Kann ohne Books aufgerufen werden, dann wird chapterIndex auf 0 gesetzt
    func syncFromServer() async {
        guard isOnline, let api = api else { return }
        
        isSyncing = true
        AppLogger.general.debug("[PlaybackRepo] Syncing all progress from server...")
        
        do {
            let allServerProgress = try await api.progress.fetchAllMediaProgress()
            
            for serverProg in allServerProgress {
                if var localState = states[serverProg.libraryItemId] {
                    // Merge mit lokalem State (ohne Book-Objekt)
                    let serverUpdateDate = Date(timeIntervalSince1970: serverProg.lastUpdate / 1000)
                    
                    if serverUpdateDate > localState.lastUpdate {
                        localState.currentTime = serverProg.currentTime
                        localState.duration = serverProg.duration
                        localState.isFinished = serverProg.isFinished
                        localState.lastUpdate = serverUpdateDate
                        // chapterIndex wird später beim Öffnen des Buchs berechnet
                        localState.needsSync = false
                        
                        saveStateLocal(localState)
                    }
                } else {
                    // Neuer State vom Server (ohne Book-Objekt, chapterIndex = 0)
                    let newState = PlaybackState(
                        libraryItemId: serverProg.libraryItemId,
                        currentTime: serverProg.currentTime,
                        duration: serverProg.duration,
                        isFinished: serverProg.isFinished,
                        lastUpdate: Date(timeIntervalSince1970: serverProg.lastUpdate / 1000),
                        chapterIndex: 0, // Wird beim Öffnen des Buchs korrekt berechnet
                        needsSync: false
                    )
                    saveStateLocal(newState)
                }
            }
            
            AppLogger.general.info("[PlaybackRepo] Server sync complete: \(allServerProgress.count) items")
        } catch {
            AppLogger.general.error("[PlaybackRepo] ❌ Server sync failed: \(error)")
        }
        
        isSyncing = false
    }
    
    
    // MARK: - Convenience Methods
    
    func getRecentlyPlayed(limit: Int = 10) -> [PlaybackState] {
        let sorted = states.values.sorted { $0.lastUpdate > $1.lastUpdate }
        return Array(sorted.prefix(limit).filter { !$0.isFinished })
    }
    
    func deleteState(for itemId: String) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            let key = "playback_\(itemId)"
            self.userDefaults.removeObject(forKey: key)
            
            var allIds = self.userDefaults.stringArray(forKey: "all_playback_items") ?? []
            allIds.removeAll { $0 == itemId }
            self.userDefaults.set(allIds, forKey: "all_playback_items")
            
            DispatchQueue.main.async {
                self.states.removeValue(forKey: itemId)
                self.pendingSyncItems.remove(itemId)
            }
        }
    }
    
    // MARK: - Helper: ChapterIndex Berechnung

    private func calculateChapterIndex(currentTime: Double, book: Book) -> Int {
        for (index, chapter) in book.chapters.enumerated() {
            let start = chapter.start ?? 0
            let end = chapter.end ?? Double.greatestFiniteMagnitude
            
            if currentTime >= start && currentTime < end {
                return index
            }
        }
        
        // Fallback: Letztes Kapitel
        return max(0, book.chapters.count - 1)
    }
}

