import SwiftUI

// MARK: - Fullscreen Player Container with iPad Optimization
struct FullscreenPlayerContainer<Content: View>: View {
    let content: Content
    @ObservedObject var player: AudioPlayer
    @ObservedObject var playerStateManager: PlayerStateManager
    let api: AudiobookshelfClient?
    
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    
    init(
        player: AudioPlayer,
        playerStateManager: PlayerStateManager,
        api: AudiobookshelfClient?,
        @ViewBuilder content: () -> Content
    ) {
        self.player = player
        self.playerStateManager = playerStateManager
        self.api = api
        self.content = content()
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Main Content
                content
                
                // MiniPlayer overlay
                if playerStateManager.mode == .mini, player.book != nil {
                    VStack {
                        Spacer()
                        
                        MiniPlayerView(
                            player: player,
                            api: api,
                            onTap: {
                                withAnimation(.easeInOut(duration: 0.4)) {
                                    playerStateManager.showFullscreen()
                                }
                            },
                            onDismiss: {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    playerStateManager.hideMiniPlayer()
                                }
                            }
                        )
                        .padding(.bottom, DSLayout.miniPlayerHeight)
                    }
                    .zIndex(1)
                }
                
                // Fullscreen Player
                if playerStateManager.mode == .fullscreen {
                    if DeviceType.current == .iPad {
                        iPadFullscreenPlayer(geometry: geometry)
                    } else {
                        iPhoneFullscreenPlayer
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: playerStateManager.mode)
        .onChange(of: player.book) { _, newBook in
            playerStateManager.updatePlayerState(hasBook: newBook != nil)
        }
    }
    
    // MARK: - iPad Fullscreen Player (Centered Card)
    
    private func iPadFullscreenPlayer(geometry: GeometryProxy) -> some View {
        ZStack {
            // Dimmed Background
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        playerStateManager.dismissFullscreen()
                    }
                }
            
            // Player Card
            GeometryReader { cardGeometry in
                let isLandscape = geometry.size.width > geometry.size.height
                let cardWidth: CGFloat = isLandscape ? min(900, geometry.size.width * 0.7) : min(700, geometry.size.width * 0.85)
                let cardHeight: CGFloat = isLandscape ? geometry.size.height * 0.9 : geometry.size.height * 0.85
                
                VStack(spacing: 0) {
                    // Header with close button
                    HStack {
                        Spacer()
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.4)) {
                                playerStateManager.dismissFullscreen()
                            }
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.secondary)
                        }
                        .padding()
                    }
                    
                    if isLandscape {
                        iPadLandscapePlayerContent(availableSize: CGSize(width: cardWidth, height: cardHeight - 60))
                    } else {
                        iPadPortraitPlayerContent(availableSize: CGSize(width: cardWidth, height: cardHeight - 60))
                    }
                }
                .frame(width: cardWidth, height: cardHeight)
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.3), radius: 30, x: 0, y: 10)
                )
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                .offset(y: dragOffset)
                .gesture(iPadSwipeGesture)
            }
        }
        .transition(.asymmetric(
            insertion: .scale(scale: 0.9).combined(with: .opacity),
            removal: .scale(scale: 0.9).combined(with: .opacity)
        ))
        .zIndex(100)
    }
    
    // MARK: - iPad Landscape Layout
    
    private func iPadLandscapePlayerContent(availableSize: CGSize) -> some View {
        HStack(spacing: 40) {
            // Left: Cover Art
            VStack {
                Spacer()
                if let book = player.book {
                    BookCoverView.square(
                        book: book,
                        size: min(400, availableSize.height * 0.7),
                        api: api,
                        downloadManager: player.downloadManagerReference
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(radius: 12)
                }
                Spacer()
            }
            .frame(maxWidth: availableSize.width * 0.4)
            
            // Right: Controls
            VStack(spacing: 32) {
                Spacer()
                trackInfoSection
                progressSection
                mainControlsSection
                secondaryControlsSection
                Spacer()
            }
            .frame(maxWidth: availableSize.width * 0.5)
            .padding(.trailing, 20)
        }
        .padding(.horizontal, 40)
    }
    
    // MARK: - iPad Portrait Layout
    
    private func iPadPortraitPlayerContent(availableSize: CGSize) -> some View {
        VStack(spacing: 40) {
            Spacer()
            
            // Cover Art
            if let book = player.book {
                BookCoverView.square(
                    book: book,
                    size: min(450, availableSize.width * 0.7),
                    api: api,
                    downloadManager: player.downloadManagerReference
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(radius: 12)
            }
            
            Spacer()
            
            // Controls
            VStack(spacing: 32) {
                trackInfoSection
                progressSection
                mainControlsSection
                secondaryControlsSection
            }
            .padding(.horizontal, 40)
            
            Spacer()
        }
    }
    
    // MARK: - iPhone Fullscreen Player
    
    private var iPhoneFullscreenPlayer: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea(.all)
                
                if let api = api {
                    PlayerView(player: player, api: api)
                        .environmentObject(DependencyContainer.shared.sleepTimerService)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                dismissButton
                            }
                        }
                }
            }
        }
        .offset(y: dragOffset)
        .gesture(swipeDownGesture)
        .zIndex(100)
        .transition(.asymmetric(
            insertion: .move(edge: .bottom),
            removal: .move(edge: .bottom)
        ))
    }
    
    // MARK: - Shared Components
    
    private var trackInfoSection: some View {
        VStack(spacing: 8) {
            Text(player.book?.title ?? "No book selected")
                .font(.title)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            
            Text(player.book?.author ?? "")
                .font(.title3)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(1)
            
            if let chapter = player.currentChapter {
                Button(action: {
                    // Show chapters - would need to be passed through
                }) {
                    HStack {
                        Image(systemName: "list.bullet")
                        Text(chapter.title)
                            .truncationMode(.middle)
                            .lineLimit(1)
                    }
                    .font(.body)
                    .foregroundColor(.accentColor)
                }
            }
        }
    }
    
    private var progressSection: some View {
        VStack(spacing: 12) {
            Slider(
                value: Binding(
                    get: { player.currentTime },
                    set: { player.seek(to: $0) }
                ),
                in: 0...max(player.duration, 1)
            )
            .accentColor(.primary)
            
            HStack {
                Text(TimeFormatter.formatTime(player.currentTime))
                    .font(.body)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                
                Spacer()
                
                let remaining = max(0, player.duration - player.currentTime)
                Text("-\(TimeFormatter.formatTime(remaining))")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
        }
    }
    
    private var mainControlsSection: some View {
        HStack(spacing: 56) {
            Button(action: {
                player.previousChapter()
            }) {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 36))
                    .foregroundColor(player.currentChapterIndex == 0 ? .secondary : .primary)
            }
            .disabled(player.currentChapterIndex == 0)
            
            Button(action: {
                player.seek15SecondsBack()
            }) {
                Image(systemName: "gobackward.15")
                    .font(.system(size: 36))
                    .foregroundColor(.primary)
            }
            
            Button(action: {
                player.togglePlayPause()
            }) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.white)
                }
            }
            
            Button(action: {
                player.seek15SecondsForward()
            }) {
                Image(systemName: "goforward.15")
                    .font(.system(size: 36))
                    .foregroundColor(.primary)
            }
            
            Button(action: {
                player.nextChapter()
            }) {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 36))
                    .foregroundColor(isLastChapter ? .secondary : .primary)
            }
            .disabled(isLastChapter)
        }
    }
    
    private var isLastChapter: Bool {
        guard let book = player.book else { return true }
        return player.currentChapterIndex >= book.chapters.count - 1
    }
    
    private var secondaryControlsSection: some View {
        HStack(spacing: 60) {
            VStack(spacing: 8) {
                Text("\(player.playbackRate, specifier: "%.1f")x")
                    .font(.title3)
                    .fontWeight(.medium)
                Text("Speed")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            VStack(spacing: 8) {
                Image(systemName: "moon")
                    .font(.title2)
                Text("Sleep")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            VStack(spacing: 8) {
                Image(systemName: "speaker.fill")
                    .font(.title2)
                Text("Audio")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            VStack(spacing: 8) {
                Image(systemName: "list.bullet")
                    .font(.title2)
                Text("Chapters")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .foregroundColor(.primary)
    }
    
    private var dismissButton: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.4)) {
                playerStateManager.dismissFullscreen()
            }
        }) {
            Image(systemName: "chevron.down")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.primary)
                .frame(width: 32, height: 32)
                .background(Color.secondary.opacity(0.1))
                .clipShape(Circle())
        }
    }
    
    // MARK: - Gestures
    
    private var swipeDownGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if !isDragging && value.translation.height > 0 {
                    isDragging = true
                }
                
                if isDragging {
                    let translation = max(0, min(value.translation.height, 100))
                    dragOffset = translation
                }
            }
            .onEnded { value in
                isDragging = false
                
                if value.translation.height > 80 || value.predictedEndTranslation.height > 200 {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        playerStateManager.dismissFullscreen()
                        dragOffset = 0
                    }
                } else {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        dragOffset = 0
                    }
                }
            }
    }
    
    private var iPadSwipeGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if !isDragging && value.translation.height > 0 {
                    isDragging = true
                }
                
                if isDragging {
                    let translation = max(0, min(value.translation.height, 150))
                    dragOffset = translation
                }
            }
            .onEnded { value in
                isDragging = false
                
                if value.translation.height > 100 || value.predictedEndTranslation.height > 250 {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        playerStateManager.dismissFullscreen()
                        dragOffset = 0
                    }
                } else {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        dragOffset = 0
                    }
                }
            }
    }
}
