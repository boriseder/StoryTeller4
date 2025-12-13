//
//  DetailDownloadState.swift
//  StoryTeller4
//
//  Created by Boris Eder on 12.12.25.
//


import Foundation
import SwiftUI
import Observation

enum DetailDownloadState {
    case notDownloaded
    case queued
    case downloading(progress: Double)
    case downloaded
}

@MainActor
@Observable
class BookDetailViewModel {
    var book: Book?
    var isLoading = false
    var errorMessage: String?
    var formattedDescription: AttributedString = AttributedString("")
    
    // Dependencies
    private let bookId: String
    private let bookRepository: BookRepository
    private let downloadManager: DownloadManager
    private let api: AudiobookshelfClient
    
    init(bookId: String, bookRepository: BookRepository, downloadManager: DownloadManager, api: AudiobookshelfClient) {
        self.bookId = bookId
        self.bookRepository = bookRepository
        self.downloadManager = downloadManager
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
                
                // We do this on MainActor because NSAttributedString requires it for HTML
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
    var downloadState: DetailDownloadState {
        guard let book = book else { return .notDownloaded }
        
        if downloadManager.isBookDownloaded(book.id) {
            return .downloaded
        }
        
        if downloadManager.isDownloadingBook(book.id) {
             let progress = downloadManager.getDownloadProgress(for: book.id)
             return .downloading(progress: progress)
        }
        
        return .notDownloaded
    }
    
    // MARK: - Computed Properties for View
    
    var title: String {
        book?.title ?? "Unknown Title"
    }

    var author: String {
        book?.author ?? "Unknown Author"
    }
    
    /*
    var narratedBy: String? {
        book?.narrator
    }
     
    var description: String {
        book?.description ?? "No description available."
    }
     */

    var hasDescription: Bool {
        !(book?.description?.isEmpty ?? true)
    }
    
    var chapters: [Chapter] {
        book?.chapters ?? []
    }
    /*
    var totalDuration: String {
        guard let duration = book?.duration else { return "N/A" }
        // FIX: Use 'formatDuration' which exists in TimeFormatter
        return TimeFormatter.formatDuration(duration)
    }
    */
    /*
    var releaseDate: String? {
        book?.publishedYear
    }
    */
    // MARK: - Actions
    
    func downloadBook() {
        guard let book = book else { return }
        Task {
            // FIX: Pass 'api' and use correct argument labels
            await downloadManager.downloadBook(book, api: api)
        }
    }
    
    func cancelDownload() {
        guard let book = book else { return }
        // FIX: Use 'cancelDownload(for:)'
        downloadManager.cancelDownload(for: book.id)
    }
    
    func deleteDownloadedBook() {
        guard let book = book else { return }
        // FIX: Use 'deleteBook(_:)'
        downloadManager.deleteBook(book.id)
    }
    
    
}
