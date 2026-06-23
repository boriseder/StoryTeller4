import SwiftUI

struct MiniPlayerView: View {
    let player: AudioPlayer
    let api: AudiobookshelfClient?
    let onTap: () -> Void
    let onDismiss: () -> Void

    // Swipe-to-dismiss tracking
    @State private var dragOffset: CGFloat = 0

    @State private var activeJump: PlayerJumpOverlayView.JumpDirection? = nil
    @State private var jumpOverlayID = UUID()
    @State private var jumpResetTask: Task<Void, Never>? = nil

    private let progressBarHeight: CGFloat = 4

    var body: some View {
        VStack(spacing: 0) {
            if let book = player.book {
                VStack(spacing: 0) {
                    progressBar
                        .frame(height: progressBarHeight)

                    miniPlayerContent(book: book)
                        .frame(height: DSLayout.miniPlayerHeight)
                }
                .background {
                    Rectangle()
                        .fill(.ultraThickMaterial)
                        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: -2)
                }
                .clipped()
                .offset(y: dragOffset)
                .gesture(swipeDownGesture)
                .onTapGesture {
                    onTap()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
        }
        .padding(.horizontal, DSLayout.screenPadding)
    }

    // MARK: - Swipe to Dismiss

    private var swipeDownGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                // Only allow downward drag
                let translation = value.translation.height
                if translation > 0 {
                    // Rubber-band: full movement for first 40pt, then resists
                    dragOffset = translation < 40
                        ? translation
                        : 40 + (translation - 40) * 0.3
                }
            }
            .onEnded { value in
                let velocity = value.predictedEndTranslation.height
                if value.translation.height > 40 || velocity > 150 {
                    withAnimation(DSAnimations.ease) {
                        dragOffset = 200
                    }
                    // Short pause so the user sees the slide-out before it vanishes
                    Task {
                        try? await Task.sleep(nanoseconds: 180_000_000)
                        await MainActor.run { onDismiss() }
                    }
                } else {
                    withAnimation(DSAnimations.spring) {
                        dragOffset = 0
                    }
                }
            }
    }

    // MARK: - Content

    @ViewBuilder
    private func miniPlayerContent(book: Book) -> some View {
        HStack(spacing: DSLayout.tightGap) {
            bookCoverSection(book: book)

            VStack(alignment: .leading, spacing: 0) {
                if let chapter = player.currentChapter {
                    Text(chapter.title)
                        .font(DSText.fine)
                        .lineLimit(1)
                        .foregroundColor(.primary)

                    Text(book.title)
                        .font(DSText.fine)
                        .lineLimit(1)
                        .foregroundColor(.secondary.opacity(0.8))
                } else {
                    Text(book.title)
                        .font(DSText.fine)
                        .lineLimit(1)
                        .foregroundColor(.primary)
                }

                /*
                Text(book.author ?? "Unknown Author")
                    .font(DSText.metadata)
                    .lineLimit(1)
                    .foregroundColor(.secondary)
                 */
            }

            Spacer(minLength: DSLayout.elementGap)

            playbackControls
        }
        //.padding(.horizontal, DSLayout.contentPadding)
        //.padding(.vertical, DSLayout.elementPadding)
        // Prevent the HStack's tap gesture propagating to the parent onTapGesture
        // when the user taps a control button.
        .contentShape(Rectangle())
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(
                        width: geometry.size.width * CGFloat(player.currentTime / max(player.duration, 1))
                    )
                    .animation(.linear(duration: 0.5), value: player.currentTime)
            }
        }
    }

    // MARK: - Book Cover

    private func bookCoverSection(book: Book) -> some View {
        let coverSize: CGFloat = 50   // Slightly smaller — better vertical balance

        return Group {
            if let api = api {
                BookCoverView.square(
                    book: book,
                    size: coverSize,
                    api: api,
                    downloadManager: player.downloadManagerReference
                )
            } else {
                RoundedRectangle(cornerRadius: DSCorners.tight)
                    .fill(DSColor.surfaceMedium)
                    .frame(width: coverSize, height: coverSize)
                    .overlay(
                        Image(systemName: "book.fill")
                            .font(.system(size: coverSize * 0.4))
                            .foregroundColor(DSColor.secondary)
                    )
            }
        }
        // Consistent with DSCorners — not a raw magic number.
        //.clipShape(RoundedRectangle(cornerRadius: DSCorners.tight))
    }

    // MARK: - Playback Controls

    private var playbackControls: some View {
        HStack(spacing: DSLayout.contentGap) {
            
            Button(action: {
                player.seek15SecondsBack()
                triggerJump(.backward)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }) {
                Image(systemName: "gobackward.15")
                    .font(.headline)
                    .foregroundColor(DSColor.primary)
            }
            
            Button(action: {
                player.togglePlayPause()
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }) {
                ZStack {
                    /*
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 38, height: 38)
                     */
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(DSText.subsectionTitle)
                        .foregroundColor(.white)
                }
            }

            Button(action: {
                player.seek15SecondsForward()
                triggerJump(.forward)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }) {
                Image(systemName: "goforward.15")
                    .font(.headline)
                    .foregroundColor(DSColor.primary)
            }
        }
        // Stop button taps from triggering the parent onTapGesture (open fullscreen)
        .simultaneousGesture(TapGesture().onEnded { })
        .padding(.trailing, DSLayout.elementPadding)
    }
    
    private func triggerJump(_ direction: PlayerJumpOverlayView.JumpDirection) {
        jumpResetTask?.cancel()
        jumpOverlayID = UUID()
        withAnimation(DSAnimations.springSnappy) { activeJump = direction }
        jumpResetTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            await MainActor.run {
                withAnimation(DSAnimations.ease) { activeJump = nil }
            }
        }
    }

}
