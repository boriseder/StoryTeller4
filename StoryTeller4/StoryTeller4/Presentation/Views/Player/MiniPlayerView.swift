import SwiftUI

struct MiniPlayerView: View {
    let player: AudioPlayer
    
    let api: AudiobookshelfClient?
    let onTap: () -> Void
    let onDismiss: () -> Void
    
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    
    private let progressBarHeight: CGFloat = 6
    
    private let miniPlayerHeight: CGFloat = 54
    
    var body: some View {
        VStack(spacing: 0) {
            if let book = player.book {
                
                VStack(spacing: 0) {
                    
                    progressBar
                        .frame(height: progressBarHeight)
                        .clipped()
                    
                    miniPlayerContent(book: book)
                        .frame(height: miniPlayerHeight)
                }
                .background {
                    Rectangle()
                        .fill(.regularMaterial)
                        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: -2)
                }
                .clipped()
                .onTapGesture {
                    onTap()
                    
                    // Haptic feedback
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                }
            }
        }
    }
    
    
    @ViewBuilder
    private func miniPlayerContent(book: Book) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                bookCoverSection(book: book)
                
                VStack(alignment: .leading, spacing: 2) {
                    if let chapter = player.currentChapter {
                        Text(chapter.title)
                            .font(.system(size: 11))
                            .lineLimit(1)
                            .foregroundColor(.primary)
                        
                        Text(book.title)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                            .foregroundColor(.secondary.opacity(0.8))
                    } else {
                        Text(book.title)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                            .foregroundColor(.primary)
                        
                    }
                    
                    
                    Text(book.author ?? "Unbekannter Autor")
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .foregroundColor(.secondary)
                    
                }
                
                Spacer(minLength: 8)
                
                playbackControls
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
    
    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.8))
                    .frame(height: progressBarHeight)
                
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.accentColor,
                                Color.accentColor.opacity(0.8)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(
                        width: geometry.size.width * CGFloat(player.currentTime / max(player.duration, 1)),
                        height: progressBarHeight
                    )
                    .animation(.linear(duration: 0.1), value: player.currentTime)
            }
        }
        .frame(height: progressBarHeight)
    }
    
    
    private func bookCoverSection(book: Book) -> some View {
        let coverSize: CGFloat = 48
        
        return Group {
            if let api = api {
                BookCoverView.square(
                    book: book,
                    size: coverSize,
                    api: api,
                    downloadManager: player.downloadManagerReference
                )
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: coverSize, height: coverSize)
                    .overlay(
                        Image(systemName: "book.fill")
                            .font(.system(size: coverSize * 0.4))
                            .foregroundColor(.gray)
                    )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
    
    private var playbackControls: some View {
        HStack(spacing: 16) {
            Button(action: {
                player.previousChapter()
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
            }) {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.primary)
            }
            .disabled(player.currentChapterIndex == 0)
            
            Button(action: {
                player.togglePlayPause()
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
            }) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                }
            }
            
            Button(action: {
                player.nextChapter()
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
            }) {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.primary)
            }
            .disabled(player.book == nil ||
                      player.currentChapterIndex >= (player.book?.chapters.count ?? 1) - 1)
        }
        .onTapGesture {
            // Prevents propagation to parent tap handler
        }
    }
}
