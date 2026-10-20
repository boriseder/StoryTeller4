import SwiftUI
import AVFoundation

struct MiniPlayerView: View {
    @Environment(ThemeManager.self) private var theme
    
    @Bindable var player: AudioPlayer
    let api: AudiobookshelfClient?
    let onExpandFullscreen: () -> Void
    
    private var progress: Double {
        guard player.duration > 0 else { return 0 }
        return min(max(player.currentTime / player.duration, 0), 1)
    }
    
    var body: some View {
        if let book = player.book {
            VStack(spacing: 0) {
                // Progress Bar
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(theme.accent)
                    .frame(height: 2)
                
                // Mini Player Content
                Button(action: onExpandFullscreen) {
                    HStack(spacing: 12) {
                        BookCoverView(
                            book: book,
                            api: api,
                            size: CGSize(width: 44, height: 44)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(book.title)
                                .font(.headline)
                                .foregroundColor(theme.textColor)
                                .lineLimit(1)
                            
                            Text(book.author ?? "Unknown Author")
                                .font(.caption)
                                .foregroundColor(theme.textColor.opacity(0.6))
                                .lineLimit(1)
                        }
                        
                        Spacer(minLength: 4)
                        
                        // Play / Pause Button
                        Button(action: { player.togglePlayPause() }) {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.title3.bold())
                                .foregroundColor(theme.textColor)
                                .frame(width: 44, height: 44)
                        }
                        .sensoryFeedback(.impact(weight: .medium), trigger: player.isPlaying)
                        .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                        
                        // Skip 15s Button
                        Button(action: { player.seek(to: player.currentTime + 15) }) {
                            Image(systemName: "goforward.15")
                                .font(.title3)
                                .foregroundColor(theme.textColor)
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Skip forward 15 seconds")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
