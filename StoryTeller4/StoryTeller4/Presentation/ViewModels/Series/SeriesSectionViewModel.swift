import Foundation
import SwiftUI

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
        
        self.books = series.books.compactMap { api.converter.convertLibraryItemToBook($0) }
    }
}
