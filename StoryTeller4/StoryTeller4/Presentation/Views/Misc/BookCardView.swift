import SwiftUI

struct BookCardView: View {
    let viewModel: BookCardViewModel
    let api: AudiobookshelfClient?
    let onTap: () -> Void
    let onDownload: () -> Void
    let onDelete: () -> Void
    
    @Environment(ThemeManager.self) var theme
    @State private var isPressed = false
    
    init(
        viewModel: BookCardViewModel,
        api: AudiobookshelfClient?,
        onTap: @escaping () -> Void,
        onDownload: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.api = api
        self.onTap = onTap
        self.onDownload = onDownload
        self.onDelete = onDelete
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: DSLayout.tightGap) {
                // Cover Image with overlays
                ZStack(alignment: .bottomTrailing) {
                    ZStack(alignment: .bottom) {
                        // Cover with border for light covers
                        BookCoverView.square(
                            book: viewModel.book,
                            size: DSLayout.cardCoverNoPadding,
                            api: api,
                            downloadManager: DependencyContainer.shared.downloadManager
                        )
                        .clipShape(RoundedRectangle(cornerRadius: DSCorners.element))
                        .overlay(
                            RoundedRectangle(cornerRadius: DSCorners.element)
                                .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
                        )
                        .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 3)
                        
                        // Progress Bar - overlay on cover
                        if viewModel.currentProgress > 0 {
                            ProgressBarView(
                                progress: viewModel.currentProgress,
                                isCurrentBook: viewModel.isCurrentBook
                            )
                            .padding(6)
                        }
                    }
                    
                    // Status Indicators Overlay - Top Right
                    VStack(spacing: 4) {
                        if viewModel.isDownloaded {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.green)
                                .background(
                                    Circle()
                                        .fill(.white)
                                        .shadow(color: .black.opacity(0.2), radius: 2)
                                )
                        }
                        
                        if viewModel.isDownloading {
                            ProgressView(value: viewModel.downloadProgress, total: 1.0)
                                .progressViewStyle(.circular)
                                .scaleEffect(0.7)
                                .frame(width: 20, height: 20)
                                .background(
                                    Circle()
                                        .fill(.ultraThinMaterial)
                                        .shadow(color: .black.opacity(0.2), radius: 2)
                                )
                        }
                        
                        // Finished Badge
                        if viewModel.isFinished {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.blue)
                                .background(
                                    Circle()
                                        .fill(.white)
                                        .shadow(color: .black.opacity(0.2), radius: 2)
                                )
                        }
                    }
                    .padding(8)
                }
                .frame(width: DSLayout.cardCoverNoPadding, height: DSLayout.cardCoverNoPadding)
                
                // Metadata - constrained to cover width
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.book.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(theme.textColor)
                        .lineLimit(1)
                    
                    Text(viewModel.book.author ?? "Unknown Author")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(theme.textColor.opacity(0.6))
                        .lineLimit(1)
                }
                .frame(width: DSLayout.cardCoverNoPadding, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if !viewModel.isDownloaded && api != nil {
                Button(action: onDownload) {
                    Label("Download", systemImage: "arrow.down.circle")
                }
            } else if viewModel.isDownloaded {
                Button(role: .destructive, action: onDelete) {
                    Label("Remove Download", systemImage: "trash")
                }
            }
            
            Divider()
            
            Button(action: {}) {
                Label(viewModel.isFinished ? "Mark as Unfinished" : "Mark as Finished",
                      systemImage: viewModel.isFinished ? "checkmark.circle" : "checkmark.circle.fill")
            }
            
            Button(action: {}) {
                Label("Book Details", systemImage: "info.circle")
            }
        }
    }
}

// Enhanced ProgressBar with better visibility
struct ProgressBarView: View {
    let progress: Double
    let isCurrentBook: Bool
    
    var body: some View {
        ZStack(alignment: .leading) {
            // Background with stronger contrast
            Capsule()
                .fill(Color.black.opacity(0.4))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.6), lineWidth: 1)
                )
            
            // Progress bar
            Capsule()
                .fill(
                    LinearGradient(
                        colors: isCurrentBook ?
                            [Color.accentColor, Color.accentColor.opacity(0.8)] :
                            [Color.white, Color.white.opacity(0.9)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
                .scaleEffect(x: progress, y: 1.0, anchor: .leading)
        }
        .frame(height: 6)
    }
}

// Extension for BookCardViewModel (add these properties)
extension BookCardViewModel {
    var isFinished: Bool {
        // Implement: return currentProgress >= 0.98
        return currentProgress >= 0.98
    }
}
