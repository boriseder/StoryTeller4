import SwiftUI

enum DebugSheet: Identifiable {
    case error, loading, networkError, noDownloads

    var id: Int { hashValue }
}

struct DebugStateView: View {
    @Environment(ThemeManager.self) var theme
    @Environment(DependencyContainer.self) var dependencies

    private var downloadManager: DownloadManager { dependencies.downloadManager }

    // Active downloads are entries in downloadStates where isDownloading == true
    private var activeStates: [(bookId: String, state: DownloadState)] {
        downloadManager.downloadStates
            .filter { $0.value.isDownloading }
            .map { (bookId: $0.key, state: $0.value) }
            .sorted { $0.bookId < $1.bookId }
    }

    var body: some View {
        List {
            Section("Download Manager") {
                LabeledContent("Books Downloaded", value: "\(downloadManager.downloadedBooks.count)")
                LabeledContent("Active Downloads", value: "\(activeStates.count)")
            }

            Section("Active Downloads Details") {
                ForEach(activeStates, id: \.bookId) { entry in
                    VStack(alignment: .leading) {
                        Text("Book ID: \(entry.bookId)")
                            .font(.caption)
                        Text(entry.state.statusMessage)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        ProgressView(value: entry.state.progress)
                    }
                }
            }
        }
        .navigationTitle("Debug State")
    }
}
