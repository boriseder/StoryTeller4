import Foundation

// MARK: - PlaybackRepository
//
// actor: thread-safe, no @MainActor pinning, no ObservableObject, no @Published.
// ViewModels own all observable state; this class is pure data layer.
//
// Init strategy: actors cannot call their own isolated methods synchronously
// from init when the caller is on a different executor. We defer the load
// via Task so the actor's executor picks it up asynchronously.
//
// Codable / PlaybackState isolation: PlaybackState.init(from:) and .updating()
// are explicitly nonisolated in PlaybackModels.swift so they are callable from
// any context without a MainActor hop.

actor PlaybackRepository: PlaybackRepositoryProtocol {

    // MARK: - Singleton

    static let shared = PlaybackRepository()

    // MARK: - Private State

    private var states: [String: PlaybackState] = [:]
    private var isOnline: Bool = false
    private var pendingSyncItems: Set<String> = []
    private let userDefaults = UserDefaults.standard
    private var api: AudiobookshelfClient?

    // MARK: - Synchronous snapshot (nonisolated bridge)
    //
    // Updated on every write inside the actor. Lets the synchronous protocol
    // getters work without requiring callers to be async.

    private nonisolated(unsafe) var _syncStatesSnapshot: [String: PlaybackState] = [:]

    // MARK: - Init

    private init() {
        // Defer actor-isolated work: Task picks it up on the actor's executor.
        Task { await loadAllStates() }
    }

    // MARK: - Configuration

    nonisolated func configure(api: AudiobookshelfClient) {
        Task { await _configure(api: api) }
    }

    private func _configure(api: AudiobookshelfClient) {
        self.api = api
    }

    func setOnlineStatus(_ online: Bool) async {
        let wasOffline = !isOnline
        isOnline = online
        if online && wasOffline && !pendingSyncItems.isEmpty {
            await syncPendingItems()
        }
    }

    // MARK: - Read (synchronous via snapshot)

    nonisolated func getPlaybackState(for bookId: String) -> PlaybackState? {
        _syncStatesSnapshot[bookId]
    }

    nonisolated func getAllPlaybackStates() -> [PlaybackState] {
        Array(_syncStatesSnapshot.values)
    }

    nonisolated func getRecentlyPlayed(limit: Int) -> [PlaybackState] {
        _syncStatesSnapshot.values
            .sorted { $0.lastUpdate > $1.lastUpdate }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Write

    func saveState(_ state: PlaybackState) async {
        // .updating() is nonisolated on PlaybackState — callable here safely.
        let newState = state.updating(needsSync: !isOnline)
        saveStateLocal(newState)
        if isOnline {
            await syncToServer(newState)
        } else {
            pendingSyncItems.insert(state.libraryItemId)
        }
    }

    // MARK: - Fetch + Merge

    func loadStateForBook(_ itemId: String, book: Book) async -> PlaybackState? {
        let localState = states[itemId]

        var serverProgress: MediaProgress?
        if isOnline, let api = api {
            do {
                serverProgress = try await api.progress.fetchPlaybackProgress(libraryItemId: itemId)
            } catch {
                AppLogger.general.debug("[PlaybackRepository] Could not fetch server progress for \(itemId): \(error)")
            }
        }

        guard let serverProg = serverProgress else { return localState }

        // chapterIndex(at:) may be @MainActor on Book — we capture what we
        // need before constructing PlaybackState inside the actor.
        let chapterIdx = await MainActor.run { book.chapterIndex(at: serverProg.currentTime) }

        if let local = localState {
            guard serverProg.lastUpdate > local.lastUpdate else { return local }
            let newState = PlaybackState(from: serverProg, chapterIndex: chapterIdx)
            saveStateLocal(newState)
            return newState
        } else {
            let newState = PlaybackState(from: serverProg, chapterIndex: chapterIdx)
            saveStateLocal(newState)
            return newState
        }
    }

    // MARK: - Full Sync

    func syncFromServer(onSyncingChanged: (@Sendable (Bool) -> Void)? = nil) async {
        guard let api = self.api, isOnline else {
            AppLogger.general.debug("[PlaybackRepository] Skipping sync — offline or not configured")
            return
        }

        onSyncingChanged?(true)
        defer { onSyncingChanged?(false) }

        do {
            let allProgress = try await api.progress.fetchAllMediaProgress()

            for serverProgress in allProgress {
                let itemId = serverProgress.libraryItemId

                if let localState = states[itemId] {
                    if localState.needsSync {
                        AppLogger.general.debug("[PlaybackRepository] Item \(itemId) has pending local changes, pushing to server")
                        await syncToServer(localState)
                        continue
                    }
                    if serverProgress.lastUpdate > localState.lastUpdate {
                        // No Book available during bulk sync — chapterIndex stays 0
                        // until the next loadStateForBook call recalculates it.
                        let newState = PlaybackState(from: serverProgress)
                        saveStateLocal(newState)
                        AppLogger.general.debug("[PlaybackRepository] Updated \(itemId) from server")
                    }
                } else {
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

    // MARK: - Delete

    func deletePlaybackState(for bookId: String) async {
        states.removeValue(forKey: bookId)
        _syncStatesSnapshot.removeValue(forKey: bookId)
        userDefaults.removeObject(forKey: "playback_\(bookId)")
        var allIds = userDefaults.stringArray(forKey: "all_playback_items") ?? []
        allIds.removeAll { $0 == bookId }
        userDefaults.set(allIds, forKey: "all_playback_items")
    }

    func clearAllPlaybackStates() async {
        guard let allIds = userDefaults.stringArray(forKey: "all_playback_items") else { return }
        for itemId in allIds { userDefaults.removeObject(forKey: "playback_\(itemId)") }
        userDefaults.removeObject(forKey: "all_playback_items")
        states.removeAll()
        _syncStatesSnapshot.removeAll()
        pendingSyncItems.removeAll()
    }

    // MARK: - Private: Persistence

    private func saveStateLocal(_ state: PlaybackState) {
        let key = "playback_\(state.libraryItemId)"
        // JSONEncoder.encode is nonisolated on Sendable types — safe here.
        guard let data = try? JSONEncoder().encode(state) else { return }
        userDefaults.set(data, forKey: key)
        states[state.libraryItemId] = state
        _syncStatesSnapshot[state.libraryItemId] = state

        var allIds = userDefaults.stringArray(forKey: "all_playback_items") ?? []
        if !allIds.contains(state.libraryItemId) {
            allIds.append(state.libraryItemId)
            userDefaults.set(allIds, forKey: "all_playback_items")
        }
    }

    private func loadAllStates() {
        guard let allIds = userDefaults.stringArray(forKey: "all_playback_items") else { return }
        for itemId in allIds {
            if let data = userDefaults.data(forKey: "playback_\(itemId)"),
               let state = try? JSONDecoder().decode(PlaybackState.self, from: data) {
                states[itemId] = state
                _syncStatesSnapshot[itemId] = state
                if state.needsSync { pendingSyncItems.insert(itemId) }
            }
        }
    }

    // MARK: - Private: Server Sync

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
            let synced = state.updating(needsSync: false)
            saveStateLocal(synced)
        } catch {
            pendingSyncItems.insert(state.libraryItemId)
            AppLogger.general.error("[PlaybackRepository] Failed to sync \(state.libraryItemId): \(error)")
        }
    }

    private func syncPendingItems() async {
        for itemId in pendingSyncItems {
            if let state = states[itemId] { await syncToServer(state) }
        }
    }
}
