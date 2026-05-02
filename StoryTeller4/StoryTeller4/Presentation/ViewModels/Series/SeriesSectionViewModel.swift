import Foundation
import SwiftUI
import Observation

@MainActor
@Observable
class SeriesSectionViewModel {
    let series: Series
    let api: AudiobookshelfClient
    let onBookSelected: (Book) -> Void

    var player: AudioPlayer
    var downloadManager: DownloadManager

    var books: [Book] = []
    var isLoading = false
    var error: Error?

    init(
        series: Series,
        api: AudiobookshelfClient,
        onBookSelected: @escaping (Book) -> Void,
        player: AudioPlayer,
        downloadManager: DownloadManager
    ) {
        self.series = series
        self.api = api
        self.onBookSelected = onBookSelected
        self.player = player
        self.downloadManager = downloadManager

        if let seriesBooks = series.books {
            self.books = seriesBooks.compactMap { api.converter.convertLibraryItemToBook($0) }
        }
    }

    /// Called from .task once the environment is available, replacing the
    /// placeholder instances created in the view's init.
    func updateDependencies(player: AudioPlayer, downloadManager: DownloadManager) {
        self.player = player
        self.downloadManager = downloadManager
    }
}
