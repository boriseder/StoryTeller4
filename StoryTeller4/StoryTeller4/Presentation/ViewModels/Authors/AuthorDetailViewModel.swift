import SwiftUI
import Observation

@MainActor
@Observable
class AuthorDetailViewModel {
    var authorBooks: [Book] = []
    var isLoading = false
    var errorMessage: String?
    var showingErrorAlert = false

    let author: Author
    let onBookSelected: () -> Void
    var onDismiss: (() -> Void)?

    // MARK: - Dependencies (nur Domain-Protocols + Services)
    private let bookRepository: BookRepositoryProtocol
    private let libraryRepository: LibraryRepositoryProtocol
    private let playBookUseCase: PlayBookUseCaseProtocol
    private let coverPreloadService: CoverPreloadServiceProtocol
    // downloadManager bleibt für downloadedCount, downloadBook, deleteBook
    private let downloadManager: DownloadManager

    // MARK: - Init
    init(
        bookRepository: BookRepositoryProtocol,
        libraryRepository: LibraryRepositoryProtocol,
        playBookUseCase: PlayBookUseCaseProtocol,
        coverPreloadService: CoverPreloadServiceProtocol,
        downloadManager: DownloadManager,
        author: Author,
        onBookSelected: @escaping () -> Void
    ) {
        self.bookRepository = bookRepository
        self.libraryRepository = libraryRepository
        self.playBookUseCase = playBookUseCase
        self.coverPreloadService = coverPreloadService
        self.downloadManager = downloadManager
        self.author = author
        self.onBookSelected = onBookSelected
    }

    // MARK: - Computed Properties
    var downloadedCount: Int {
        authorBooks.filter { downloadManager.isBookDownloaded($0.id) }.count
    }

    var totalDuration: Double {
        authorBooks.reduce(0.0) { total, book in
            total + book.chapters.reduce(0.0) { $0 + (($1.end ?? 0) - ($1.start ?? 0)) }
        }
    }

    // MARK: - Actions

    func loadAuthorDetails() async {
        isLoading = true
        errorMessage = nil

        do {
            guard let selectedLibrary = try await libraryRepository.getSelectedLibrary() else {
                errorMessage = "No library selected"
                showingErrorAlert = true
                isLoading = false
                return
            }

            defer { isLoading = false }

            let authorDetails = try await bookRepository.fetchAuthorDetails(
                authorId: author.id,
                libraryId: selectedLibrary.id
            )

            let items: [LibraryItem] = authorDetails.libraryItems ?? []
            // LibraryItem.toAnyBook() aus LibraryItem+Domain.swift –
            // kein Converter, kein api-Zugriff im ViewModel
            let books = items.map { $0.toAnyBook() }
            let sortedBooks = books.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }

            withAnimation(.easeInOut(duration: 0.3)) {
                authorBooks = sortedBooks
            }

            coverPreloadService.preloadCovers(for: sortedBooks, limit: sortedBooks.count)

        } catch {
            errorMessage = error.localizedDescription
            showingErrorAlert = true
            AppLogger.general.debug("Error loading author details: \(error)")
        }
    }

    func loadAuthorBooks() async {
        isLoading = true
        errorMessage = nil

        do {
            guard let selectedLibrary = try await libraryRepository.getSelectedLibrary() else {
                errorMessage = "No library selected"
                showingErrorAlert = true
                isLoading = false
                return
            }

            defer { isLoading = false }
            showingErrorAlert = false

            // fetchBooks geht über BookRepository – kein direkter api-Zugriff
            let allBooks = try await bookRepository.fetchBooks(
                libraryId: selectedLibrary.id,
                collapseSeries: false
            )

            let filteredBooks = allBooks
                .filter { $0.author?.localizedCaseInsensitiveContains(author.name) == true }
                .sorted { $0.title.localizedCompare($1.title) == .orderedAscending }

            withAnimation(.easeInOut(duration: 0.3)) {
                authorBooks = filteredBooks
            }

            coverPreloadService.preloadCovers(for: filteredBooks, limit: filteredBooks.count)

        } catch {
            errorMessage = error.localizedDescription
            showingErrorAlert = true
            AppLogger.general.debug("Error loading author books: \(error)")
        }
    }

    func playBook(_ book: Book, restoreState: Bool = true, autoPlay: Bool = false) async {
        isLoading = true
        do {
            try await playBookUseCase.execute(
                book: book,
                restoreState: restoreState,
                autoPlay: autoPlay
            )
            onDismiss?()
            onBookSelected()
        } catch {
            errorMessage = error.localizedDescription
            showingErrorAlert = true
        }
        isLoading = false
    }

    func downloadBook(_ book: Book, api: AudiobookshelfClient) async {
        await downloadManager.downloadBook(book, api: api)
    }

    func deleteBook(_ bookId: String) {
        downloadManager.deleteBook(bookId)
    }
}
