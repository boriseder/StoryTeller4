import Foundation
import SwiftUI

@MainActor
class AuthorsViewModel: ObservableObject {
    
    // MARK: - Published Properties
    @Published var authors: [Author] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showingErrorAlert = false
    
    // MARK: - Dependencies
    private let fetchAuthorsUseCase: FetchAuthorsUseCaseProtocol
    private let libraryRepository: LibraryRepositoryProtocol
    let api: AudiobookshelfClient

    // MARK: - Init
    init(
        fetchAuthorsUseCase: FetchAuthorsUseCaseProtocol,
        libraryRepository: LibraryRepositoryProtocol,
        api: AudiobookshelfClient

    ) {
        self.fetchAuthorsUseCase = fetchAuthorsUseCase
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
            
            let fetchedAuthors = try await fetchAuthorsUseCase.execute(
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
