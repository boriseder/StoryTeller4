
import SwiftUI

enum DebugSheet: Identifiable {
    case error, loading, networkError, noDownloads

    var id: Int { hashValue }
}

struct DebugView: View {
    @State private var selectedSheet: DebugSheet?
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var downloadManager: DownloadManager

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    debugButton("ErrorView") { selectedSheet = .error }
                    debugButton("LoadingView") { selectedSheet = .loading }
                    debugButton("NetworkErrorView") { selectedSheet = .networkError }
                    debugButton("NoDownloadsView") { selectedSheet = .noDownloads }
                }
                .padding()
            }
            .navigationTitle("Debug View")
        }
        .sheet(item: $selectedSheet) { sheet in
            ZStack {
                if theme.backgroundStyle == .dynamic {
                    DynamicBackground()
                }
                switch sheet {
                case .error:
                    ErrorView(error: "Fehler beim Laden")
                case .loading:
                    LoadingView()
                case .networkError:
                    NetworkErrorView(
                        issueType: .serverUnreachable,
                        onRetry: {},
                        onViewDownloads: {},
                        onSettings: {}
                    )
                case .noDownloads:
                    NoDownloadsView()
                }
            }
        }
    }

    private func debugButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
    }
}
