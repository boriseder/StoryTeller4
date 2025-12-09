
import SwiftUI

@MainActor
class AuthorDetailViewModel: ObservableObject {
    @Published var authorBooks: [Book] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showingErrorAlert = false
    
    let author: Author
    let includeSeries = true
    let includeBooks = true
    
    let onBookSelected: () -> Void
    var onDismiss: (() -> Void)?

    
    // MARK: - Dependencies
    let api: AudiobookshelfClient
    private let downloadManager: DownloadManager
    private let player: AudioPlayer
    private let appState: AppStateManager
    private let bookRepository: BookRepositoryProtocol
    private let playBookUseCase: PlayBookUseCase
    private let libraryRepository: LibraryRepositoryProtocol
    
    init(
        bookRepository: BookRepositoryProtocol,
        libraryRepository: LibraryRepositoryProtocol,
        api: AudiobookshelfClient,
        downloadManager: DownloadManager,
        player: AudioPlayer,
        appState: AppStateManager,
        playBookUseCase: PlayBookUseCase,
        author: Author,
        onBookSelected: @escaping () -> Void
    ) {
        self.bookRepository = bookRepository
        self.libraryRepository = libraryRepository
        self.api = api
        self.downloadManager = downloadManager
        self.player = player
        self.appState = appState
        self.playBookUseCase = playBookUseCase
        self.author = author
        self.onBookSelected = onBookSelected
    }
    
    var downloadedCount: Int {
        authorBooks.filter { downloadManager.isBookDownloaded($0.id) }.count
    }
    
    var totalDuration: Double {
        authorBooks.reduce(0.0) { total, book in
            total + book.chapters.reduce(0.0) { chapterTotal, chapter in
                chapterTotal + ((chapter.end ?? 0) - (chapter.start ?? 0))
            }
        }
    }


    
    func loadAuthorDetails() async {
        isLoading = true
        errorMessage = nil
        
        do {

            guard let selectedLibrary = try await libraryRepository.getSelectedLibrary() else {
                errorMessage = "No library selected"
                showingErrorAlert = true
                return
            }

            defer { isLoading = false }

            
            // Fetch author details from the repository
            let author = try await bookRepository.fetchAuthorDetails(
                authorId: author.id,
                libraryId: selectedLibrary.id
            )

            // Safely unwrap optional libraryItems, fallback to empty array
            let items: [LibraryItem] = author.libraryItems ?? []

            // Convert LibraryItem -> Book
            let converter = DefaultBookConverter()
            let books = items.compactMap { converter.convertLibraryItemToBook($0) }

            // Sort alphabetically by book title
            let sortedBooks = books.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }

            // Assign to published property with animation
            withAnimation(.easeInOut(duration: 0.3)) {
                authorBooks = sortedBooks
            }

            // Preload covers
            CoverPreloadHelpers.preloadIfNeeded(
                books: sortedBooks,
                api: api,
                downloadManager: downloadManager
            )

        } catch {
            errorMessage = error.localizedDescription
            showingErrorAlert = true
            AppLogger.general.debug("Error loading author books: \(error)")
        }
    }

    func loadAuthorBooks() async {
        isLoading = true
        errorMessage = nil
        
        do {
        
            guard let selectedLibrary = try await libraryRepository.getSelectedLibrary() else {
                errorMessage = "No library selected"
                showingErrorAlert = true
                return
            }
        
            defer { isLoading = false }
            showingErrorAlert = false
        
            let allBooks = try await api.books.fetchBooks(
                libraryId: selectedLibrary.id,
                limit: 0,
                collapseSeries: false
            )
            
            let filteredBooks = allBooks.filter { book in
                book.author?.localizedCaseInsensitiveContains(author.name) == true
            }
            
            let sortedBooks = filteredBooks.sorted { book1, book2 in
                book1.title.localizedCompare(book2.title) == .orderedAscending
            }
            
            withAnimation(.easeInOut(duration: 0.3)) {
                authorBooks = sortedBooks
            }
            
            CoverPreloadHelpers.preloadIfNeeded(
                books: sortedBooks,
                api: api,
                downloadManager: downloadManager
            )
            
        } catch {
            errorMessage = error.localizedDescription
            showingErrorAlert = true
            AppLogger.general.debug("Error loading author books: \(error)")
        }
        
        isLoading = false
    }
    
    func playBook(
        _ book: Book,
        appState: AppStateManager,
        restoreState: Bool = true,
        autoPlay: Bool = false

    ) async {
        isLoading = true
        
        do {
            try await playBookUseCase.execute(
                book: book,
                api: api,
                player: player,
                downloadManager: downloadManager,
                appState: appState,
                restoreState: true,
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
    
    func downloadBook(_ book: Book) async {
        await downloadManager.downloadBook(book, api: api)
    }
    
    func deleteBook(_ bookId: String) {
        downloadManager.deleteBook(bookId)
    }
}
