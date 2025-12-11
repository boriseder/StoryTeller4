import Foundation
import SwiftUI
import Combine

@MainActor
class SeriesSectionViewModel: ObservableObject {
    let series: Series
    let api: AudiobookshelfClient
    let onBookSelected: () -> Void
    var container: DependencyContainer
    
    var player: AudioPlayer { container.player }
    var downloadManager: DownloadManager { container.downloadManager }
    
    @Published var books: [Book] = []
    @Published var isLoading = false
    @Published var error: Error?
    
    init(
        series: Series,
        api: AudiobookshelfClient,
        onBookSelected: @escaping () -> Void,
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
