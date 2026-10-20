import Foundation
import SwiftUI
import Observation

@MainActor
@Observable
class AuthorsViewModel {
    
    // MARK: - Properties
    var authors: [Author] = []
    var searchText: String = ""
    var isLoading = false
    var errorMessage: String?
    var showingErrorAlert = false
    
    var filteredAuthors: [Author] {
        if searchText.isEmpty {
            return authors
        }
        return authors.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    // MARK: - Dependencies
    private let bookRepository: any BookRepositoryProtocol
    private let libraryRepository: any LibraryRepositoryProtocol
    let api: AudiobookshelfClient

    // MARK: - Init
    init(
        bookRepository: any BookRepositoryProtocol,
        libraryRepository: any LibraryRepositoryProtocol,
        api: AudiobookshelfClient
    ) {
        self.bookRepository = bookRepository
        self.libraryRepository = libraryRepository
        self.api = api
    }
    
    // MARK: - Public Methods
    
    func loadAuthors() async {
        isLoading = true
        errorMessage = nil
        
        do {
            guard let selectedLibrary = try await libraryRepository.getSelectedLibrary() else {
                authors = []
                isLoading = false
                return
            }
            
            let fetchedAuthors = try await bookRepository.fetchAuthors(
                libraryId: selectedLibrary.id
            )
            
            withAnimation(.easeInOut) {
                authors = fetchedAuthors
            }
            
            AppLogger.general.debug("[AuthorsViewModel] Loaded \(authors.count) authors")
            
        } catch let error as RepositoryError {
            handleRepositoryError(error)
        } catch {
            errorMessage = error.localizedDescription
            showingErrorAlert = true
        }
        
        isLoading = false
    }
    
    func retry() async {
        await loadAuthors()
    }
    
    // MARK: - Computed Properties
    
    var hasAuthors: Bool {
        !authors.isEmpty
    }
    
    // MARK: - Error Handling
    
    private func handleRepositoryError(_ error: RepositoryError) {
        errorMessage = error.localizedDescription
        showingErrorAlert = true
        AppLogger.general.debug("[AuthorsViewModel] Repository error: \(error)")
    }
}
