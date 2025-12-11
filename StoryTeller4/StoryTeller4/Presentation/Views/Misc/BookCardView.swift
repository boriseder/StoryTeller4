import SwiftUI

struct BookCardView: View {
    // Standard property for @Observable model
    let viewModel: BookCardViewModel
    let api: AudiobookshelfClient?
    let onTap: () -> Void
    let onDownload: () -> Void
    let onDelete: () -> Void
    
    @EnvironmentObject var theme: ThemeManager
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: DSLayout.tightGap) {
                // Cover Image
                ZStack(alignment: .bottomTrailing) {
                    // FIX: Use bookAspect instead of standard, and provide width
                    BookCoverView.bookAspect(
                        book: viewModel.book,
                        width: DSLayout.cardCoverNoPadding, // Use layout constant
                        api: api,
                        downloadManager: DependencyContainer.shared.downloadManager
                    )
                    .clipShape(RoundedRectangle(cornerRadius: DSCorners.element))
                    // FIX: Explicit Color.black to resolve inference error
                    .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                    
                    // Status Indicators Overlay
                    HStack(spacing: 4) {
                        if viewModel.isDownloaded {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundColor(.green)
                                .background(Circle().fill(.white))
                        }
                        
                        if viewModel.isDownloading {
                            ProgressView(value: viewModel.downloadProgress, total: 1.0)
                                .progressViewStyle(.circular)
                                .scaleEffect(0.6)
                                .frame(width: 16, height: 16)
                                .background(Circle().fill(.white))
                        }
                    }
                    .padding(6)
                }
                // .aspectRatio(0.66, contentMode: .fit) // Removed as BookCoverView.bookAspect handles sizing
                
                // Progress Bar
                if viewModel.currentProgress > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                            
                            Rectangle()
                                .fill(viewModel.isCurrentBook ? Color.accentColor : Color.gray)
                                .frame(width: geo.size.width * viewModel.currentProgress)
                        }
                    }
                    .frame(height: 3)
                    .clipShape(Capsule())
                }
                
                // Metadata
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.book.title)
                        .font(DSText.detail)
                        .foregroundColor(theme.textColor)
                        .lineLimit(1)
                    
                    Text(viewModel.book.author ?? "Unknown Author")
                        .font(DSText.metadata)
                        .foregroundColor(theme.textColor.opacity(0.8))
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(action: onTap) {
                Label("Play", systemImage: "play.fill")
            }
            
            Divider()
            
            if !viewModel.isDownloaded && api != nil {
                Button(action: onDownload) {
                    Label("Download", systemImage: "arrow.down.circle")
                }
            } else if viewModel.isDownloaded {
                Button(role: .destructive, action: onDelete) {
                    Label("Remove Download", systemImage: "trash")
                }
            }
        }
    }
}
