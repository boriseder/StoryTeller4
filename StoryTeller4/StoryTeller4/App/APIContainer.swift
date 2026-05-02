import Foundation
import SwiftUI
import Observation
import Combine

// MARK: - APIContainer
//
// Holds the API client and every repository that requires one.
// Created after successful login and replaced (not mutated) when
// credentials change — callers observe DependencyContainer.apiContainer
// to react to login/logout rather than watching individual repositories.
//
// Rule: nothing in here should be constructed without a real baseURL and token.
// Placeholder clients (baseURL: "", authToken: "") are explicitly banned —
// if you need a nil-safe accessor, check DependencyContainer.apiContainer first.

@MainActor
@Observable
final class APIContainer {

    // MARK: - API Client
    let client: AudiobookshelfClient

    // MARK: - Repositories
    let bookRepository: BookRepository
    let libraryRepository: LibraryRepository
    let playbackRepository: PlaybackRepository
    let bookmarkRepository: BookmarkRepository

    // MARK: - Enrichment
    let bookmarkEnrichment: BookmarkEnrichmentCoordinator

    // MARK: - Init

    init(baseURL: String, token: String, downloadManager: DownloadManager) {
        precondition(!baseURL.isEmpty, "APIContainer requires a real baseURL")
        precondition(!token.isEmpty, "APIContainer requires a real token")

        let client = AudiobookshelfClient(baseURL: baseURL, authToken: token)
        self.client = client

        let bookRepo = BookRepository(api: client)
        self.bookRepository = bookRepo

        self.libraryRepository = LibraryRepository(
            api: client,
            settingsRepository: SettingsRepository()
        )

        let playbackRepo = PlaybackRepository.shared
        playbackRepo.configure(api: client)
        self.playbackRepository = playbackRepo

        let bookmarkRepo = BookmarkRepository.shared
        bookmarkRepo.configure(api: client)
        self.bookmarkRepository = bookmarkRepo

        self.bookmarkEnrichment = BookmarkEnrichmentCoordinator(
            bookmarkRepository: bookmarkRepo,
            bookRepository: bookRepo,
            downloadManager: downloadManager
        )
    }

    // MARK: - Convenience

    var baseURLString: String { client.baseURLString }
    var authToken: String { client.authToken }

    // MARK: - Online Initialisation

    func initialise(isOnline: Bool) async {
        playbackRepository.setOnlineStatus(isOnline)

        if isOnline {
            await playbackRepository.syncFromServer()
            AppLogger.general.debug("[APIContainer] PlaybackRepository synced")

            await bookmarkRepository.syncFromServer()
            AppLogger.general.debug("[APIContainer] BookmarkRepository synced")
        } else {
            AppLogger.general.debug("[APIContainer] Offline — using cached data")
        }
    }
}

