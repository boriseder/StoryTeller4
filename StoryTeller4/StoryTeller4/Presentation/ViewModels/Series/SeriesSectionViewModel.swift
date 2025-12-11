import Foundation
import SwiftUI
import Observation

@MainActor
@Observable
class SeriesSectionViewModel {
    let series: Series
    let api: AudiobookshelfClient
    let onBookSelected: (Book) -> Void
    var container: DependencyContainer
    
    var player: AudioPlayer { container.player }
    var downloadManager: DownloadManager { container.downloadManager }
    
    var books: [Book] = []
    var isLoading = false
    var error: Error?
    
    init(
        series: Series,
        api: AudiobookshelfClient,
        onBookSelected: @escaping (Book) -> Void,
        container: DependencyContainer
    ) {
        self.series = series
        self.api = api
        self.onBookSelected = onBookSelected
        self.container = container
        
        // Handle optional books array properly
        if let seriesBooks = series.books {
            self.books = seriesBooks.compactMap { api.converter.convertLibraryItemToBook($0) }
        } else {
            self.books = []
        }
    }
}
