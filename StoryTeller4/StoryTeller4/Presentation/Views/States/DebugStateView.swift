
import SwiftUI

enum DebugSheet: Identifiable {
    case error, loading, networkError, noDownloads

    var id: Int { hashValue }
}


struct DebugStateView: View {
    @Environment(ThemeManager.self) var theme
    @Environment(DependencyContainer.self) var dependencies
    
    // Derived from dependencies
    private var downloadManager: DownloadManager { dependencies.downloadManager }
    
    var body: some View {
        List {
            Section("Download Manager") {
                LabeledContent("Books Downloaded", value: "\(downloadManager.downloadedBooks.count)")
                LabeledContent("Active Downloads", value: "\(downloadManager.isDownloading.count)")
            }
            
            Section("Active Downloads Details") {
                ForEach(Array(downloadManager.isDownloading.keys), id: \.self) { bookId in
                    VStack(alignment: .leading) {
                        Text("Book ID: \(bookId)")
                            .font(.caption)
                        if let progress = downloadManager.downloadProgress[bookId] {
                            ProgressView(value: progress)
                        }
                    }
                }
            }
        }
        .navigationTitle("Debug State")
    }
}
