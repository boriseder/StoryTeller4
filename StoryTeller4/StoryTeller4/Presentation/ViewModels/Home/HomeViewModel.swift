import SwiftUI
import Observation

@MainActor
@Observable
class HomeViewModel {
    // MARK: - UI State
    var personalizedSections: [PersonalizedSection] = []
    var libraryName: String = "Personalized"
    var totalBooksInLibrary: Int = 0
    var isLoading = false
    var errorMessage: String?
    var showingErrorAlert = false

    // For smooth transitions
    var contentLoaded = false
    var sectionsLoaded = false

    // MARK: - Dependencies (Domain Layer Protocols)
    private let bookRepository: any BookRepositoryProtocol
    private let libraryRepository: any LibraryRepositoryProtocol
    private let playBookUseCase: any PlayBookUseCaseProtocol
    private let coverPreloadService: any CoverPreloadServiceProtocol
    private let appState: AppStateManager

    let onBookSelected: () -> Void

    // MARK: - Computed Properties
    var totalItemsCount: Int {
        totalBooksInLibrary
    }

    var downloadedCount: Int {
        0
    }

    // MARK: - Init
    init(
        bookRepository: any BookRepositoryProtocol,
        libraryRepository: any LibraryRepositoryProtocol,
        playBookUseCase: any PlayBookUseCaseProtocol,
        coverPreloadService: any CoverPreloadServiceProtocol,
        appState: AppStateManager,
        onBookSelected: @escaping () -> Void
    ) {
        self.bookRepository = bookRepository
        self.libraryRepository = libraryRepository
        self.playBookUseCase = playBookUseCase
        self.coverPreloadService = coverPreloadService
        self.appState = appState
        self.onBookSelected = onBookSelected
    }

    // MARK: - Actions
    func loadPersonalizedSectionsIfNeeded() async {
        guard appState.isServerReachable else { return }
        if personalizedSections.isEmpty {
            await loadPersonalizedSections()
        }
    }

    func loadPersonalizedSections() async {
        isLoading = true
        errorMessage = nil

        do {
            guard let selectedLibrary = try await libraryRepository.getSelectedLibrary() else {
                personalizedSections = []
                totalBooksInLibrary = 0
                isLoading = false
                return
            }

            let fetchedSections = try await bookRepository.fetchPersonalizedSections(libraryId: selectedLibrary.id)

            withAnimation(.easeInOut) {
                personalizedSections = fetchedSections
                totalBooksInLibrary = fetchedSections.reduce(0) { $0 + $1.entities.count }
            }

            coverPreloadService.preloadCovers(
                for: getAllBooksFromSections(from: fetchedSections),
                limit: 10
            )

        } catch let error as RepositoryError {
            errorMessage = error.localizedDescription
            showingErrorAlert = true
            AppLogger.general.debug("[HomeViewModel] Repository error: \(error)")
        } catch {
            errorMessage = error.localizedDescription
            showingErrorAlert = true
        }

        isLoading = false
    }

    func playBook(_ book: Book, restoreState: Bool = true, autoPlay: Bool = false) async {
        isLoading = true
        do {
            try await playBookUseCase.execute(
                book: book,
                restoreState: restoreState,
                autoPlay: autoPlay
            )
            onBookSelected()
        } catch {
            errorMessage = error.localizedDescription
            showingErrorAlert = true
        }
        isLoading = false
    }

    // MARK: - Private Helpers
    private func getAllBooksFromSections(from sections: [PersonalizedSection]) -> [Book] {
        sections.flatMap { section in
            section.entities
                .compactMap { $0.asLibraryItem }
                .compactMap { $0.toBook() }
        }
    }
}
