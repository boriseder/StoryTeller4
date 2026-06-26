//
//  CoverPreloadServiceProtocol.swift
//  StoryTeller4
//
//  Created by Boris Eder on 25.06.26.
//


import Foundation

// MARK: - Protocol (Domain Layer)
// ViewModels und Helper kennen nur dieses Protocol – kein AudiobookshelfClient
@MainActor
protocol CoverPreloadServiceProtocol: AnyObject {
    func preloadCovers(for books: [Book], limit: Int)
    func preloadCover(for book: Book)
}

// MARK: - Implementation (Data Layer)
// Kapselt AudiobookshelfClient und DownloadManager vollständig
@MainActor
final class CoverPreloadService: CoverPreloadServiceProtocol {
    private let api: AudiobookshelfClient
    private let downloadManager: DownloadManager

    init(api: AudiobookshelfClient, downloadManager: DownloadManager) {
        self.api = api
        self.downloadManager = downloadManager
    }

    func preloadCovers(for books: [Book], limit: Int = 6) {
        guard !books.isEmpty else { return }
        CoverCacheManager.shared.preloadCovers(
            for: Array(books.prefix(limit)),
            api: api,
            downloadManager: downloadManager
        )
    }

    func preloadCover(for book: Book) {
        preloadCovers(for: [book], limit: 1)
    }
}

// MARK: - Placeholder
extension CoverPreloadService {
    @MainActor
    static var placeholder: CoverPreloadService {
        CoverPreloadService(
            api: AudiobookshelfClient(baseURL: "", authToken: ""),
            downloadManager: DownloadManager()
        )
    }
}