import Foundation
import SwiftUI
import Observation

// MARK: - DetailDownloadState

enum DetailDownloadState {
    case notDownloaded
    case queued
    case downloading(progress: Double)
    case downloaded
}

// MARK: - BookDetailViewModel

@MainActor
@Observable
class BookDetailViewModel {

    var book: Book?
    var isLoading = false
    var errorMessage: String?
    var formattedDescription: AttributedString = AttributedString("")

    // MARK: - Dependencies

    private let bookId: String
    private let bookRepository: BookRepository
    private let downloadManager: DownloadManager   // UI state observation only
    private let downloadUseCase: any DownloadBookUseCaseProtocol
    private let api: AudiobookshelfClient

    // MARK: - Init

    init(
        bookId: String,
        bookRepository: BookRepository,
        downloadManager: DownloadManager,
        downloadUseCase: any DownloadBookUseCaseProtocol,
        api: AudiobookshelfClient
    ) {
        self.bookId = bookId
        self.bookRepository = bookRepository
        self.downloadManager = downloadManager
        self.downloadUseCase = downloadUseCase
        self.api = api

        loadBookDetails()
    }

    // MARK: - Loading

    func loadBookDetails() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let fetchedBook = try await bookRepository.fetchBookDetails(bookId: bookId)
                self.book = fetchedBook
                let rawDescription = fetchedBook.description ?? "No description available."
                self.formattedDescription = rawDescription.htmlToAttributedString()
                self.isLoading = false
            } catch {
                self.errorMessage = "Failed to load book details: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }

    // MARK: - Download State
    //
    // Reads from DownloadManager — legitimate use of the UI state layer.

    var downloadState: DetailDownloadState {
        guard let book else { return .notDownloaded }

        if downloadManager.isBookDownloaded(book.id) {
            return .downloaded
        }

        if downloadManager.isDownloadingBook(book.id) {
            let progress = downloadManager.progress(for: book.id)
            return .downloading(progress: progress)
        }

        return .notDownloaded
    }

    // MARK: - Computed Properties

    var title: String        { book?.title ?? "Unknown Title" }
    var author: String       { book?.author ?? "Unknown Author" }
    var hasDescription: Bool { !(book?.description?.isEmpty ?? true) }
    var chapters: [Chapter]  { book?.chapters ?? [] }

    var downloadStage: DownloadStage {
        guard let book else { return .preparing }
        return downloadManager.stage(for: book.id)
    }

    var downloadStatusMessage: String {
        guard let book else { return "" }
        return downloadManager.statusMessage(for: book.id)
    }

    // MARK: - Actions (routed through use case → repository, not DownloadManager)

    func downloadBook() {
        guard let book else { return }
        Task {
            do {
                try await downloadUseCase.execute(book: book, api: api)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func cancelDownload() {
        guard let book else { return }
        downloadUseCase.cancel(bookId: book.id)
    }

    func deleteDownloadedBook() {
        guard let book else { return }
        downloadUseCase.delete(bookId: book.id)
    }
}
