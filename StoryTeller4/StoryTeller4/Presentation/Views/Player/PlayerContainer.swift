import SwiftUI

// MARK: - Fullscreen Player Container

struct PlayerContainer<Content: View>: View {
    let content: Content
    let player: AudioPlayer

    @Bindable var playerStateManager: PlayerStateManager
    let api: AudiobookshelfClient?

    // SleepTimerService is now injected from the call site rather than
    // accessed via DependencyContainer.shared inside the view body.
    // This makes FullscreenPlayerView previewable and testable with a mock.
    let sleepTimerService: SleepTimerService

    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false

    init(
        player: AudioPlayer,
        playerStateManager: PlayerStateManager,
        api: AudiobookshelfClient?,
        sleepTimerService: SleepTimerService,
        @ViewBuilder content: () -> Content
    ) {
        self.player = player
        self.playerStateManager = playerStateManager
        self.api = api
        self.sleepTimerService = sleepTimerService
        self.content = content()
    }

    var body: some View {
        ZStack {
            content

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
               // .zIndex(1)
            }

            if playerStateManager.mode == .fullscreen {
                fullscreenPlayer
            }
        }
        
        .animation(.easeInOut(duration: 0.3), value: playerStateManager.mode)
        .onChange(of: player.book) { _, newBook in
            playerStateManager.updatePlayerState(hasBook: newBook != nil)
        }
    }

    // MARK: - Fullscreen Player

    private var fullscreenPlayer: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea(.all)

                if let api = api {
                    FullscreenPlayerView(player: player, api: api)
                        // Injected from outside — no singleton access in view body.
                        .environment(sleepTimerService)
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

    // MARK: - Swipe Down to Dismiss

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
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        dragOffset = 0
                    }
                }
            }
    }
}
