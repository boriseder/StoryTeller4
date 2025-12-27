import SwiftUI

struct MiniPlayerView: View {
    let player: AudioPlayer
    
    let api: AudiobookshelfClient?
    let onTap: () -> Void
    let onDismiss: () -> Void
    
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false

    private let progressBarHeight: CGFloat = 6

    private var miniPlayerHeight: CGFloat {
        DeviceType.current == .iPad ? 80 : 54
    }
    
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
                    RoundedRectangle(cornerRadius: 0)
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
        let coverSize: CGFloat = DeviceType.current == .iPad ? 64 : 48
        
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
            let buttonSpacing: CGFloat = DeviceType.current == .iPad ? 20 : 16
            let playButtonSize: CGFloat = DeviceType.current == .iPad ? 48 : 40
            let iconSize: CGFloat = DeviceType.current == .iPad ? 20 : 16
            
            return HStack(spacing: buttonSpacing) {
                Button(action: {
                    player.previousChapter()
                    
                    // Haptic feedback
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                }) {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: iconSize))
                        .foregroundColor(.primary)
                }
                .disabled(player.currentChapterIndex == 0)
                
                Button(action: {
                    player.togglePlayPause()
                    
                    // Haptic feedback
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: playButtonSize, height: playButtonSize)
                        
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: iconSize))
                            .foregroundColor(.white)
                    }
                }
                
                Button(action: {
                    player.nextChapter()
                    
                    // Haptic feedback
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                }) {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: iconSize))
                        .foregroundColor(.primary)
                }
                .disabled(player.book == nil ||
                         player.currentChapterIndex >= (player.book?.chapters.count ?? 1) - 1)
            }
            // FIX: Ersetze highPriorityGesture durch einen leeren onTapGesture.
            // Dies "schluckt" das Event lokal, ohne mit den internen Button-Gesten in einen Timeout-Konflikt zu geraten.
            .onTapGesture {
                // Do nothing - prevents propagation to parent
            }
        }}
