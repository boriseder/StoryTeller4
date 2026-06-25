import Foundation

// MARK: - PlaybackRepositoryProtocol
//
// Pure domain interface. No ObservableObject, no @Published, no @MainActor.
// The repository is responsible only for reading and writing PlaybackState —
// it knows nothing about the UI observation system.
//
// Thread-safety contract: all methods are async and safe to call from any
// context. Concrete implementations (actor) enforce the isolation internally.

protocol PlaybackRepositoryProtocol: AnyObject, Sendable {

    // MARK: - Configuration

    /// Wire the API client after authentication. Must be called before any
    /// server-side operations are attempted.
    func configure(api: AudiobookshelfClient)

    /// Notify the repository about connectivity changes. Triggers a sync
    /// flush of pending offline writes when coming back online.
    func setOnlineStatus(_ online: Bool) async

    // MARK: - Read

    /// Returns the locally cached state for a book, or nil if never played.
    func getPlaybackState(for bookId: String) -> PlaybackState?

    /// All known playback states.
    func getAllPlaybackStates() -> [PlaybackState]

    /// The most-recently-played states, up to `limit` items.
    func getRecentlyPlayed(limit: Int) -> [PlaybackState]

    // MARK: - Write

    /// Saves progress locally and queues (or performs) a server sync.
    func saveState(_ state: PlaybackState) async

    // MARK: - Fetch + Merge

    /// Fetches server progress for a single book and merges it with local
    /// state (server wins on timestamp, local wins when needsSync == true).
    func loadStateForBook(_ itemId: String, book: Book) async -> PlaybackState?

    // MARK: - Full Sync

    /// Pulls all server progress and merges into local storage.
    /// isSyncing state is reported via the provided observer closure so
    /// the caller (ViewModel) can surface loading UI without coupling to
    /// the repository's internals.
    func syncFromServer(onSyncingChanged: (@Sendable (Bool) -> Void)?) async

    // MARK: - Delete

    func deletePlaybackState(for bookId: String) async
    func clearAllPlaybackStates() async
}

// MARK: - Default parameter convenience

extension PlaybackRepositoryProtocol {
    func syncFromServer() async {
        await syncFromServer(onSyncingChanged: nil)
    }
}
