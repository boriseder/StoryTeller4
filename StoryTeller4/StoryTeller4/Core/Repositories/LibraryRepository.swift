import Foundation

// MARK: - Repository Protocol
protocol LibraryRepositoryProtocol {
    func getLibraries() async throws -> [Library]
    func getSelectedLibrary() async throws -> Library?
    func selectLibrary(_ libraryId: String)
    func clearSelection()
}

// MARK: - Library Repository Implementation
class LibraryRepository: LibraryRepositoryProtocol {

    private let api: AudiobookshelfClient
    private let settingsRepository: SettingsRepositoryProtocol
    private var cachedLibraries: [Library]?
    
    init(
        api: AudiobookshelfClient,
        settingsRepository: SettingsRepositoryProtocol = SettingsRepository()
    ) {
        self.api = api
        self.settingsRepository = settingsRepository
    }
    
    // MARK: - Public Methods
    
    func getLibraries() async throws -> [Library] {
        if let cached = cachedLibraries, !cached.isEmpty {
            AppLogger.general.debug("[LibraryRepository] Returning \(cached.count) cached libraries")
            return cached
        }
        
        do {
            let libraries = try await api.libraries.fetchLibraries()
            cachedLibraries = libraries
            
            AppLogger.general.debug("[LibraryRepository] Fetched \(libraries.count) libraries")
            
            return libraries
            
        } catch let urlError as URLError {
            throw RepositoryError.networkError(urlError)
        } catch let decodingError as DecodingError {
            throw RepositoryError.decodingError(decodingError)
        } catch {
            throw RepositoryError.networkError(error)
        }
    }
    
    func getSelectedLibrary() async throws -> Library? {
        guard let selectedId = settingsRepository.getSelectedLibraryId() else {
            AppLogger.general.debug("[LibraryRepository] No library selected")
            return nil
        }
        
        let libraries = try await getLibraries()
        
        if let selected = libraries.first(where: { $0.id == selectedId }) {
            AppLogger.general.debug("[LibraryRepository] Found selected library: \(selected.name)")
            return selected
        }
        
        if let defaultLibrary = libraries.first(where: { $0.name.lowercased().contains("default") }) {
            AppLogger.general.debug("[LibraryRepository] No match, using default library: \(defaultLibrary.name)")
            selectLibrary(defaultLibrary.id)
            return defaultLibrary
        }
        
        if let firstLibrary = libraries.first {
            AppLogger.general.debug("[LibraryRepository] No match, using first library: \(firstLibrary.name)")
            selectLibrary(firstLibrary.id)
            return firstLibrary
        }
        
        return nil
    }
    
    func selectLibrary(_ libraryId: String) {
        settingsRepository.saveSelectedLibraryId(libraryId)
        AppLogger.general.debug("[LibraryRepository] Selected library: \(libraryId)")
    }
    
    func clearSelection() {
        settingsRepository.saveSelectedLibraryId(nil)
        AppLogger.general.debug("[LibraryRepository] Cleared library selection")
    }
    
    func clearCache() {
        cachedLibraries = nil
        AppLogger.general.debug("[LibraryRepository] Cleared library cache")
    }
}

// MARK: - LibraryRepository Enhancement
extension LibraryRepository {
    /// Initialize libraries with smart selection - single source of truth
    func initializeLibrarySelection() async throws -> Library? {
        AppLogger.general.debug("[LibraryRepository] Initializing library selection...")
        
        let libraries = try await getLibraries()
        
        // CASE 1: Empty server (valid state)
        guard !libraries.isEmpty else {
            AppLogger.general.warn("[LibraryRepository] No libraries available")
            clearSelection()
            return nil
        }
        
        // CASE 2: Try to restore previously selected library
        if let savedId = settingsRepository.getSelectedLibraryId(),
           let restoredLibrary = libraries.first(where: { $0.id == savedId }) {
            
            AppLogger.general.debug("[LibraryRepository] Restored library: \(restoredLibrary.name)")
            return restoredLibrary
        }
        
        // CASE 3: Smart default selection
        let defaultLibrary = selectBestDefaultLibrary(from: libraries)
        selectLibrary(defaultLibrary.id)
        
        AppLogger.general.debug("[LibraryRepository] ✓ Auto-selected: \(defaultLibrary.name)")
        return defaultLibrary
    }
    
    /// Smart library selection with priority logic
    private func selectBestDefaultLibrary(from libraries: [Library]) -> Library {
        // Priority 1: Common names
        let priorityNames = ["main", "default", "audiobooks", "library"]
        if let namedLibrary = libraries.first(where: { library in
            let name = library.name.lowercased()
                    return priorityNames.contains { name.contains($0) }
        }) {
            return namedLibrary
        }
        
        // Priority 2: First alphabetically
        let sorted = libraries.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        
        return sorted.first ?? libraries[0]
    }
}
