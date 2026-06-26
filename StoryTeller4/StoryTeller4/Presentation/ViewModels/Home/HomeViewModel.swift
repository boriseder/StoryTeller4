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

    // MARK: - Dependencies (alle Domain-Layer Protocols)
    private let fetchPersonalizedSectionsUseCase: FetchPersonalizedSectionsUseCaseProtocol
    private let fetchLibraryStatsUseCase: FetchLibraryStatsUseCaseProtocol
    private let playBookUseCase: PlayBookUseCaseProtocol
    private let libraryRepository: LibraryRepositoryProtocol
    private let coverPreloadService: CoverPreloadServiceProtocol
    private let appState: AppStateManager

    let onBookSelected: () -> Void

    // MARK: - Computed Properties
    var totalItemsCount: Int {
        totalBooksInLibrary
    }

    var downloadedCount: Int {
        // Placeholder: wird via DownloadRepository befüllt sobald refactored
        0
    }

    // MARK: - Init
    init(
        fetchPersonalizedSectionsUseCase: FetchPersonalizedSectionsUseCaseProtocol,
        fetchLibraryStatsUseCase: FetchLibraryStatsUseCaseProtocol,
        playBookUseCase: PlayBookUseCaseProtocol,
        libraryRepository: LibraryRepositoryProtocol,
        coverPreloadService: CoverPreloadServiceProtocol,
        appState: AppStateManager,
        onBookSelected: @escaping () -> Void
    ) {
        self.fetchPersonalizedSectionsUseCase = fetchPersonalizedSectionsUseCase
        self.fetchLibraryStatsUseCase = fetchLibraryStatsUseCase
        self.playBookUseCase = playBookUseCase
        self.libraryRepository = libraryRepository
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

            async let sectionsTask = fetchPersonalizedSectionsUseCase.execute(libraryId: selectedLibrary.id)
            async let statsTask = fetchLibraryStatsUseCase.execute(libraryId: selectedLibrary.id)

            let (fetchedSections, totalBooks) = try await (sectionsTask, statsTask)

            withAnimation(.easeInOut) {
                personalizedSections = fetchedSections
                totalBooksInLibrary = totalBooks
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
                .compactMap { $0.toBook() } // Extension auf LibraryItem – kein Converter nötig
        }
    }
}

// MARK: - Placeholder
extension HomeViewModel {
    @MainActor
    static var placeholder: HomeViewModel {
        HomeViewModel(
            fetchPersonalizedSectionsUseCase: FetchPersonalizedSectionsUseCase(
                bookRepository: BookRepository.placeholder
            ),
            fetchLibraryStatsUseCase: FetchLibraryStatsUseCase(
                libraryStatsRepository: LibraryStatsRepository.placeholder
            ),
            playBookUseCase: PlayBookUseCase(
                metadataService: BookMetadataService(
                    api: AudiobookshelfClient(baseURL: "", authToken: ""),
                    downloadManager: DownloadManager()
                ),
                playbackService: PlaybackService(
                    player: AudioPlayer(),
                    api: AudiobookshelfClient(baseURL: "", authToken: "")
                ),
                downloadManager: DownloadManager(),
                appState: AppStateManager.shared
            ),
            libraryRepository: LibraryRepository.placeholder,
            coverPreloadService: CoverPreloadService.placeholder,
            appState: AppStateManager.shared,
            onBookSelected: {}
        )
    }
}
