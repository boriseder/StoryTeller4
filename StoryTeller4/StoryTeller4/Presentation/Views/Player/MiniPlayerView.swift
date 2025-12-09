import SwiftUI

struct MiniPlayerView: View {
    @ObservedObject var player: AudioPlayer
    let api: AudiobookshelfClient?
    let onTap: () -> Void
    let onDismiss: () -> Void
    
    @State private var isExpanded = false
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    
    private var miniPlayerHeight: CGFloat {
        DeviceType.current == .iPad ? 80 : 64
    }
    
    private var expandedPlayerHeight: CGFloat {
        DeviceType.current == .iPad ? 180 : 140
    }
    
    private let progressBarHeight: CGFloat = 3
    
    var body: some View {
        VStack(spacing: 0) {
            if let book = player.book {
                VStack(spacing: 0) {
                    progressBar
                        .frame(height: progressBarHeight)
                        .clipped()
                    
                    miniPlayerContent(book: book)
                        .frame(height: isExpanded ? expandedPlayerHeight - progressBarHeight : miniPlayerHeight - progressBarHeight)
                }
                .background {
                    RoundedRectangle(cornerRadius: isExpanded ? 20 : 0)
                        .fill(.regularMaterial)
                        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: -2)
                }
                .clipped()
                .offset(y: dragOffset)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isExpanded)
                .animation(.spring(response: 0.3, dampingFraction: 0.9), value: dragOffset)
                .gesture(dragGesture)
            }
        }
    }
    
    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
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
        .onTapGesture { location in
            let progress = location.x / UIScreen.main.bounds.width
            let seekTime = progress * player.duration
            player.seek(to: seekTime)
        }
    }
    
    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                }
                let translation = max(0, value.translation.height)
                dragOffset = translation
            }
            .onEnded { value in
                isDragging = false
                
                if value.translation.height > 80 {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        dragOffset = 200
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        onDismiss()
                        dragOffset = 0
                    }
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        dragOffset = 0
                    }
                }
            }
    }
    
    @ViewBuilder
    private func miniPlayerContent(book: Book) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: DeviceType.current == .iPad ? 16 : 12) {
                bookCoverSection(book: book)
                
                VStack(alignment: .leading, spacing: DeviceType.current == .iPad ? 3 : 2) {
                    Text(book.title)
                        .font(.system(size: DeviceType.current == .iPad ? 16 : 14, weight: .semibold))
                        .lineLimit(1)
                        .foregroundColor(.primary)
                    
                    Text(book.author ?? "Unbekannter Autor")
                        .font(.system(size: DeviceType.current == .iPad ? 14 : 12))
                        .lineLimit(1)
                        .foregroundColor(.secondary)
                    
                    if let chapter = player.currentChapter {
                        Text(chapter.title)
                            .font(.system(size: DeviceType.current == .iPad ? 13 : 11))
                            .lineLimit(1)
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                }
                
                Spacer(minLength: 8)
                
                playbackControls
            }
            .padding(.horizontal, DeviceType.current == .iPad ? 20 : 16)
            .padding(.vertical, DeviceType.current == .iPad ? 12 : 8)
            .contentShape(Rectangle())
            .onTapGesture {
                if !isExpanded {
                    onTap()
                }
            }
            
            if isExpanded {
                expandedContent
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .bottom).combined(with: .opacity)
                    ))
            }
        }
        .onTapGesture(count: 2) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                isExpanded.toggle()
            }
        }
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
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: coverSize, height: coverSize)
                    .overlay(
                        Image(systemName: "book.fill")
                            .font(.system(size: coverSize * 0.4))
                            .foregroundColor(.gray)
                    )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private var playbackControls: some View {
        let buttonSpacing: CGFloat = DeviceType.current == .iPad ? 20 : 16
        let playButtonSize: CGFloat = DeviceType.current == .iPad ? 48 : 40
        let iconSize: CGFloat = DeviceType.current == .iPad ? 20 : 16
        
        return HStack(spacing: buttonSpacing) {
            Button(action: {
                player.previousChapter()
            }) {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: iconSize))
                    .foregroundColor(.primary)
            }
            .disabled(player.currentChapterIndex == 0)
            
            Button(action: {
                player.togglePlayPause()
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
            }) {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: iconSize))
                    .foregroundColor(.primary)
            }
            .disabled(player.book == nil ||
                     player.currentChapterIndex >= (player.book?.chapters.count ?? 1) - 1)
        }
    }
    
    private var expandedContent: some View {
        let controlSpacing: CGFloat = DeviceType.current == .iPad ? 32 : 24
        
        return VStack(spacing: DeviceType.current == .iPad ? 16 : 12) {
            expandedProgressSection
            
            HStack(spacing: controlSpacing) {
                Button(action: {
                    cyclePlaybackSpeed()
                }) {
                    Text("\(player.playbackRate, specifier: "%.1f")x")
                        .font(.system(size: DeviceType.current == .iPad ? 14 : 12, weight: .medium))
                        .foregroundColor(.accentColor)
                        .frame(width: DeviceType.current == .iPad ? 50 : 40,
                               height: DeviceType.current == .iPad ? 28 : 24)
                        .background(Color.accentColor.opacity(0.1))
                        .clipShape(Capsule())
                }
                
                Button(action: {
                    player.seek15SecondsBack()
                }) {
                    Image(systemName: "gobackward.15")
                        .font(.system(size: DeviceType.current == .iPad ? 22 : 18))
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                Button(action: {
                    player.seek15SecondsForward()
                }) {
                    Image(systemName: "goforward.15")
                        .font(.system(size: DeviceType.current == .iPad ? 22 : 18))
                        .foregroundColor(.primary)
                }
                
                Button(action: onTap) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: DeviceType.current == .iPad ? 16 : 14))
                        .foregroundColor(.secondary)
                        .frame(width: DeviceType.current == .iPad ? 28 : 24,
                               height: DeviceType.current == .iPad ? 28 : 24)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, DeviceType.current == .iPad ? 20 : 16)
        }
        .padding(.bottom, DeviceType.current == .iPad ? 12 : 8)
    }
    
    private var expandedProgressSection: some View {
        VStack(spacing: 4) {
            ProgressView(value: player.currentTime, total: max(player.duration, 1))
                .progressViewStyle(LinearProgressViewStyle(tint: .accentColor))
                .scaleEffect(x: 1, y: 1.5)
            
            HStack {
                Text(TimeFormatter.formatTime(player.currentTime))
                    .font(.system(size: DeviceType.current == .iPad ? 12 : 10))
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                
                Spacer()
                
                let remaining = max(0, player.duration - player.currentTime)
                Text("-\(TimeFormatter.formatTime(remaining))")
                    .font(.system(size: DeviceType.current == .iPad ? 12 : 10))
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, DeviceType.current == .iPad ? 20 : 16)
    }
    
    private func cyclePlaybackSpeed() {
        let speeds: [Double] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
        let currentSpeed = Double(player.playbackRate)
        
        if let currentIndex = speeds.firstIndex(where: { abs($0 - currentSpeed) < 0.01 }) {
            let nextIndex = (currentIndex + 1) % speeds.count
            player.setPlaybackRate(speeds[nextIndex])
        } else {
            player.setPlaybackRate(1.0)
        }
    }
}
