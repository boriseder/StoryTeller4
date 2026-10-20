import Foundation

// MARK: - AppStorageKeys
enum AppStorageKey: String, CaseIterable {
    case serverScheme = "server_scheme"
    case serverHost = "server_host"
    case serverPort = "server_port"
    case storedUsername = "stored_username"
    case baseURL = "baseURL"
    case apiKey = "apiKey"
    case autoCacheCleanup = "auto_cache_cleanup"
    case coverCacheLimit = "cover_cache_limit"
    case memoryCacheSize = "memory_cache_size"
    case hasLaunchedBefore = "has_launched_before"
    case lastBackgroundTime = "lastBackgroundTime"
    case selectedLibraryId = "selected_library_id"
    case libraryShowDownloadedOnly = "library_show_downloaded_only"
    case libraryShowSeriesGrouped = "library_show_series_grouped"
    case librarySortAscending = "library_sort_ascending"
    case librarySortOption = "library_sort_option"
    case userBackgroundStyle = "user_background_style"
    case userAccentColor = "user_accent_color"
    case sleepTimerState = "sleep_timer_state"
    case openFullscreenPlayer = "open_fullscreen_player"
}

// MARK: - UserDefaults Extension for Type-Safe Storage
extension UserDefaults {
    func string(forKey key: AppStorageKey) -> String? {
        string(forKey: key.rawValue)
    }

    func set(_ value: Any?, forKey key: AppStorageKey) {
        set(value, forKey: key.rawValue)
    }

    func bool(forKey key: AppStorageKey) -> Bool {
        bool(forKey: key.rawValue)
    }

    func integer(forKey key: AppStorageKey) -> Int {
        integer(forKey: key.rawValue)
    }

    func data(forKey key: AppStorageKey) -> Data? {
        data(forKey: key.rawValue)
    }

    func removeObject(forKey key: AppStorageKey) {
        removeObject(forKey: key.rawValue)
    }
}
