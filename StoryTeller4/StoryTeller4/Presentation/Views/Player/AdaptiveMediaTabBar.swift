import SwiftUI
import AVFoundation

// MARK: - Adaptive Media Tab Bar
/// Floating capsule bar with pure soft cross-fade transition between tabs and mini-player.
struct AdaptiveMediaTabBar: View {
    @Environment(ThemeManager.self) private var theme
    
    @Bindable var player: AudioPlayer
    let api: AudiobookshelfClient?
    @Bindable var playerStateManager: PlayerStateManager
    @Binding var selectedTab: TabIndex
    @Binding var isMediaMode: Bool
    
    let onTabSelected: (TabIndex) -> Void
    let onExpandFullscreen: () -> Void
    
    private var isPlayingActive: Bool {
        isMediaMode && player.book != nil
    }

    private var progress: Double {
        guard player.duration > 0 else { return 0 }
        return min(max(player.currentTime / player.duration, 0), 1)
    }

    var body: some View {
        ZStack {
            if isPlayingActive, let book = player.book {
                // MARK: - MiniPlayer Mode Layer (Soft Fade In)
                HStack(spacing: 8) {
                    // Home / Return Button (Far Left)
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isMediaMode = false
                        }
                    }) {
                        Image(systemName: "square.grid.2x2.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(theme.accent)
                            .frame(width: 38, height: 38)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Return to tabs")

                    Divider()
                        .frame(height: 20)

                    // Integrated Mini-Player Body
                    Button(action: onExpandFullscreen) {
                        HStack(spacing: 8) {
                            BookCoverView(
                                book: book,
                                api: api,
                                size: CGSize(width: 36, height: 36)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 6))

                            VStack(alignment: .leading, spacing: 1) {
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
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(theme.accent)
                                    .frame(width: 38, height: 38)
                            }
                            .sensoryFeedback(.impact(weight: .medium), trigger: player.isPlaying)
                            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

                            // Skip 15s Button
                            Button(action: { player.seek(to: player.currentTime + 15) }) {
                                Image(systemName: "goforward.15")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(theme.textColor.opacity(0.8))
                                    .frame(width: 34, height: 34)
                            }
                            .accessibilityLabel("Skip forward 15 seconds")
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .transition(.opacity)
            } else {
                // MARK: - Standard 3-Tab Bar Layer (Soft Fade In)
                HStack(spacing: 0) {
                    tabButton(title: "Explore", icon: "sharedwithyou", tab: .home)
                    tabButton(title: "Library", icon: "books.vertical.fill", tab: .library)
                    tabButton(title: "Authors", icon: "person.2.fill", tab: .authors)

                    if player.book != nil {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                isMediaMode = true
                            }
                        }) {
                            VStack(spacing: 3) {
                                Image(systemName: "waveform")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(theme.accent)
                                Text("Now Playing")
                                    .font(.caption2)
                                    .foregroundColor(theme.accent)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .accessibilityLabel("Switch to media player bar")
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .transition(.opacity)
            }
        }
        .overlay(alignment: .top) {
            // Live Progress Bar (strictly pinned to top edge)
            if isPlayingActive {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(theme.accent)
                    .frame(height: 2)
                    .clipShape(Capsule())
                    .transition(.opacity)
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 6)
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
        .animation(.easeInOut(duration: 0.25), value: isPlayingActive)
    }

    private func tabButton(title: String, icon: String, tab: TabIndex) -> some View {
        Button(action: {
            onTabSelected(tab)
        }) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                Text(title)
                    .font(.caption2)
            }
            .foregroundColor(selectedTab == tab ? theme.accent : theme.textColor.opacity(0.5))
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(title)
        .accessibilityAddTraits(selectedTab == tab ? [.isButton, .isSelected] : [.isButton])
    }
}
