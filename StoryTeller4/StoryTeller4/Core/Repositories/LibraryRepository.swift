import Foundation

// MARK: - Repository Protocol
protocol LibraryRepositoryProtocol: Sendable {
    @MainActor func getLibraries() async throws -> [Library]
    @MainActor func getSelectedLibrary() async throws -> Library?
    @MainActor func selectLibrary(_ libraryId: String)
    @MainActor func clearSelection()
}

// MARK: - Library Repository Implementation
@MainActor
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
            return nil
        }
        
        let libraries = try await getLibraries()
        
        if let selected = libraries.first(where: { $0.id == selectedId }) {
            return selected
        }
        
        // Fallback logic
        if let defaultLibrary = libraries.first(where: { $0.name.lowercased().contains("default") }) {
            selectLibrary(defaultLibrary.id)
            return defaultLibrary
        }
        
        if let firstLibrary = libraries.first {
            selectLibrary(firstLibrary.id)
            return firstLibrary
        }
        
        return nil
    }
    
    func selectLibrary(_ libraryId: String) {
        settingsRepository.saveSelectedLibraryId(libraryId)
    }
    
    func clearSelection() {
        settingsRepository.saveSelectedLibraryId(nil)
    }
    
    func clearCache() {
        cachedLibraries = nil
    }
}
