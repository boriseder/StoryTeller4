import SwiftUI

// MARK: - Fullscreen Player Container with Complete iPad Implementation
struct FullscreenPlayerContainer<Content: View>: View {
    let content: Content
    let player: AudioPlayer
    let playerStateManager: PlayerStateManager
    let api: AudiobookshelfClient?
    
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    
    // UX: Visual feedback for jump (iPad)
    @State private var activeJump: PlayerJumpOverlayView.JumpDirection? = nil
    @State private var jumpResetTask: Task<Void, Never>? = nil
    
    // UX: Context (iPad)
    @State private var showBookProgress = false
    
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
    
    // MARK: - Helper: Jump Trigger
    
    private func triggerJump(_ direction: PlayerJumpOverlayView.JumpDirection) {
        // Cancel existing task to restart animation if tapped rapidly
        jumpResetTask?.cancel()
        
        withAnimation {
            activeJump = direction
        }
        
        jumpResetTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000) // 0.6s
            await MainActor.run {
                withAnimation {
                    activeJump = nil
                }
            }
        }
    }
    
    // MARK: - iPad Fullscreen Player
    
    private func iPadFullscreenPlayer(geometry: GeometryProxy) -> some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        playerStateManager.dismissFullscreen()
                    }
                }
            
            GeometryReader { cardGeometry in
                let isLandscape = geometry.size.width > geometry.size.height
                let cardWidth: CGFloat = isLandscape ? min(900, geometry.size.width * 0.7) : min(700, geometry.size.width * 0.85)
                let cardHeight: CGFloat = isLandscape ? geometry.size.height * 0.9 : geometry.size.height * 0.85
                
                VStack(spacing: 0) {
                    // Close button header
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
                    
                    // Player content
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
    
    // MARK: - iPad Landscape Content (Complete Implementation)
    
    private func iPadLandscapePlayerContent(availableSize: CGSize) -> some View {
        HStack(spacing: 40) {
            // Left: Cover Art
            VStack {
                Spacer()
                ZStack {
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
                    
                    // UX: Jump Overlay
                    if let direction = activeJump {
                        PlayerJumpOverlayView(direction: direction)
                            .id(Date())
                    }
                }
                Spacer()
            }
            .frame(maxWidth: availableSize.width * 0.4)
            
            // Right: Controls
            VStack(spacing: 24) {
                Spacer()
                
                iPadTrackInfo
                iPadProgressSection
                iPadMainControls
                iPadSecondaryControls
                
                Spacer()
            }
            .frame(maxWidth: availableSize.width * 0.5)
            .padding(.trailing, 20)
        }
        .padding(.horizontal, 40)
    }
    
    // MARK: - iPad Portrait Content (Complete Implementation)
    
    private func iPadPortraitPlayerContent(availableSize: CGSize) -> some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Cover Art
            ZStack {
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
                
                // UX: Jump Overlay
                if let direction = activeJump {
                    PlayerJumpOverlayView(direction: direction)
                        .id(Date())
                }
            }
            
            // Controls
            VStack(spacing: 24) {
                iPadTrackInfo
                iPadProgressSection
                iPadMainControls
                iPadSecondaryControls
            }
            .padding(.horizontal, 40)
            
            Spacer()
        }
    }
    
    // MARK: - iPad Player Components
    
    private var iPadTrackInfo: some View {
        VStack(spacing: 8) {
            Text(player.book?.title ?? "No book selected")
                .font(.title)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            
            Text(player.book?.author ?? "")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(1)
            
            if let chapter = player.currentChapter {
                HStack(spacing: 4) {
                    Image(systemName: "list.bullet")
                        .font(.caption)
                    Text(chapter.title)
                        .font(.caption)
                        .truncationMode(.middle)
                        .lineLimit(1)
                }
                .foregroundColor(.accentColor)
            }
        }
    }
    
    @State private var sliderValue: Double = 0
    @State private var isEditingSlider = false
    
    private var iPadProgressSection: some View {
        VStack(spacing: 8) {
            // UX: Explicit Label
            HStack {
                Text(showBookProgress ? "Total Book Progress" : "Current Chapter Progress")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .textCase(.uppercase)
                    .foregroundColor(showBookProgress ? .purple : .secondary)
                Spacer()
            }
            
            Slider(
                value: $sliderValue,
                in: 0...max(progressDuration, 1),
                onEditingChanged: { editing in
                    isEditingSlider = editing
                    if !editing {
                        // Correct seeking based on mode
                        if showBookProgress {
                             player.seek(to: sliderValue)
                        } else {
                            player.seek(to: sliderValue)
                        }
                        
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                    }
                }
            )
            .tint(showBookProgress ? .purple : .accentColor)
            .onAppear {
                sliderValue = progressCurrentTime
            }
            .onChange(of: progressCurrentTime) { _, newTime in
                if !isEditingSlider {
                    sliderValue = newTime
                }
            }
            
            HStack {
                Text(TimeFormatter.formatTime(progressCurrentTime))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                
                Spacer()
                
                Button(action: {
                    withAnimation {
                        showBookProgress.toggle()
                    }
                }) {
                     HStack(spacing: 4) {
                        Image(systemName: showBookProgress ? "book.fill" : "doc.text.fill")
                            .font(.caption2)
                        Text(showBookProgress ? "Book" : "Chapter")
                            .font(.caption2)
                    }
                    .foregroundColor(showBookProgress ? .purple : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background((showBookProgress ? Color.purple : Color.secondary).opacity(0.1))
                    .clipShape(Capsule())
                }
                
                Spacer()
                
                let remaining = max(0, progressDuration - progressCurrentTime)
                Text("-\(TimeFormatter.formatTime(remaining))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
        }
    }
    
    private var progressCurrentTime: Double {
        showBookProgress ? player.absoluteCurrentTime : player.relativeCurrentTime
    }
    
    private var progressDuration: Double {
        showBookProgress ? player.totalBookDuration : player.chapterDuration
    }
    
    private var iPadMainControls: some View {
        HStack(spacing: 48) {
            Button(action: {
                player.previousChapter()
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
            }) {
                Image(systemName: "backward.end.fill")
                    .font(.largeTitle)
                    .foregroundColor(player.currentChapterIndex == 0 ? .secondary : .primary)
            }
            .disabled(player.currentChapterIndex == 0)
            
            Button(action: {
                player.seek15SecondsBack()
                triggerJump(PlayerJumpOverlayView.JumpDirection.backward)
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
            }) {
                Image(systemName: "gobackward.15")
                    .font(.largeTitle)
                    .foregroundColor(.primary)
            }
            
            Button(action: {
                player.togglePlayPause()
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
            }) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 72, height: 72)
                    
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.largeTitle)
                        .foregroundColor(.white)
                }
            }
            
            Button(action: {
                player.seek15SecondsForward()
                triggerJump(PlayerJumpOverlayView.JumpDirection.forward)
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
            }) {
                Image(systemName: "goforward.15")
                    .font(.largeTitle)
                    .foregroundColor(.primary)
            }
            
            Button(action: {
                player.nextChapter()
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
            }) {
                Image(systemName: "forward.end.fill")
                    .font(.largeTitle)
                    .foregroundColor(isLastChapter ? .secondary : .primary)
            }
            .disabled(isLastChapter)
        }
    }
    
    private var isLastChapter: Bool {
        guard let book = player.book else { return true }
        return player.currentChapterIndex >= book.chapters.count - 1
    }
    
    private var iPadSecondaryControls: some View {
        HStack(spacing: 56) {
            VStack(spacing: 4) {
                Text("\(player.playbackRate, specifier: "%.1f")x")
                    .font(.body)
                    .fontWeight(.medium)
                Text("Speed")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            VStack(spacing: 4) {
                Image(systemName: "list.bullet")
                    .font(.title2)
                Text("Chapters")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            VStack(spacing: 4) {
                Image(systemName: "bookmark.fill")
                    .font(.title2)
                Text("Bookmark")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .foregroundColor(.primary)
    }
    
    // MARK: - iPhone Fullscreen
    
    private var iPhoneFullscreenPlayer: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea(.all)
                
                if let api = api {
                    PlayerView(player: player, api: api)
                        .environment(DependencyContainer.shared.sleepTimerService)
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
                if !isDragging && value.translation.height > 0 { isDragging = true }
                if isDragging { dragOffset = max(0, min(value.translation.height, 100)) }
            }
            .onEnded { value in
                isDragging = false
                if value.translation.height > 80 || value.predictedEndTranslation.height > 200 {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        playerStateManager.dismissFullscreen()
                        dragOffset = 0
                    }
                } else {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { dragOffset = 0 }
                }
            }
    }
    
    private var iPadSwipeGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if !isDragging && value.translation.height > 0 { isDragging = true }
                if isDragging { dragOffset = max(0, min(value.translation.height, 150)) }
            }
            .onEnded { value in
                isDragging = false
                if value.translation.height > 100 || value.predictedEndTranslation.height > 250 {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        playerStateManager.dismissFullscreen()
                        dragOffset = 0
                    }
                } else {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { dragOffset = 0 }
                }
            }
    }
}
