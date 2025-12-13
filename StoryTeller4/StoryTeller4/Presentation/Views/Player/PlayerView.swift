import SwiftUI
import AVKit

struct PlayerView: View {
    @State private var viewModel: PlayerViewModel
    
    @Environment(SleepTimerService.self) private var sleepTimer
    @Environment(AppStateManager.self) var appState
    @Environment(ThemeManager.self) var theme
    
    @State private var showBookProgress = false
    @State private var showingAddBookmark = false
    @State private var showingPlaybackSettings = false
    
    // UX: Visual feedback for jump
    @State private var activeJump: PlayerJumpOverlayView.JumpDirection? = nil
    @State private var jumpResetTask: Task<Void, Never>? = nil

    init(player: AudioPlayer, api: AudiobookshelfClient) {
        self._viewModel = State(initialValue: PlayerViewModel(
            player: player,
            api: api
        ))
    }
  
    var body: some View {
        @Bindable var vm = viewModel
        
        NavigationStack {
            GeometryReader { geometry in
                if DeviceType.current == .iPad && geometry.size.width > geometry.size.height {
                    iPadLandscapeLayout(geometry: geometry)
                } else {
                    standardLayout(geometry: geometry)
                }
            }
            .background(DSColor.background)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)

            /*
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    moreButton
                }
            }
 */
            
            .sheet(isPresented: $vm.showingChaptersList) {
                ChaptersListView(player: viewModel.player)
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $vm.showingSleepTimer) {
                SleepTimerView()
                    .environment(sleepTimer)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingPlaybackSettings) {
                PlaybackSettingsView(player: viewModel.player)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingAddBookmark) {
                BookmarkSheet(
                    player: viewModel.player,
                    isPresented: $showingAddBookmark
                )
            }
        }
        .onAppear {
            viewModel.sliderValue = showBookProgress
                ? viewModel.player.absoluteCurrentTime
                : viewModel.player.relativeCurrentTime
        }
        .onChange(of: viewModel.player.currentTime) { _, time in
            let displayTime = showBookProgress
                ? viewModel.player.absoluteCurrentTime
                : viewModel.player.relativeCurrentTime

            viewModel.updateSliderFromPlayer(displayTime)
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
    
    // MARK: - iPad Landscape Layout
    
    private func iPadLandscapeLayout(geometry: GeometryProxy) -> some View {
        HStack(spacing: 40) {
            VStack {
                Spacer()
                coverArtView.frame(maxWidth: geometry.size.width * 0.3)
                Spacer()
            }
            VStack(spacing: 32) {
                Spacer()
                trackInfoSection
                progressSection
                mainControlsSection
                secondaryControlsSection
                Spacer()
            }
            .frame(maxWidth: geometry.size.width * 0.5)
            .padding(.trailing, 40)
        }
        .padding(.horizontal, 40)
    }
    
    // MARK: - Standard Layout
    
    private func standardLayout(geometry: GeometryProxy) -> some View {
        VStack(spacing: DSLayout.contentGap) {
            coverArtSection.frame(height: DSLayout.fullCover)
            controlsSection.frame(maxHeight: .infinity).padding(.horizontal, DeviceType.current == .iPad ? 40 : DSLayout.screenPadding)
        }
    }
    
    // MARK: - Cover Art Section
    
    private var coverArtSection: some View {
        VStack(spacing: DSLayout.contentGap) {
            Spacer()
            coverArtView
            Spacer()
        }
        .padding(.horizontal, DeviceType.current == .iPad ? 60 : DSLayout.screenPadding)
    }
    
    private var coverArtView: some View {
        ZStack {
            Group {
                if let book = viewModel.player.book {
                    BookCoverView.square(
                        book: book,
                        size: DSLayout.fullCover,
                        api: viewModel.api,
                        downloadManager: viewModel.player.downloadManagerReference
                    )
                    .shadow(radius: 12)
                } else {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: DSLayout.fullCover, height: DSLayout.fullCover)
                        .overlay(Image(systemName: "book.fill").font(.system(size: 60)).foregroundColor(.gray))
                }
            }
            
            // UX: Jump Overlay
            if let direction = activeJump {
                PlayerJumpOverlayView(direction: direction)
                    .id(Date()) // Force refresh
            }
        }
    }
    
    // MARK: - Controls Section
    
    private var controlsSection: some View {
        VStack(spacing: DeviceType.current == .iPad ? 32 : 24) {
            trackInfoSection
            progressSection
            mainControlsSection
            secondaryControlsSection
            Spacer()
        }
    }
    
    // MARK: - Track Info Section
    
    private var trackInfoSection: some View {
        VStack(spacing: 8) {
            Text(viewModel.player.book?.title ?? "No book selected")
                .font(DeviceType.current == .iPad ? .title : .title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            
            Text(viewModel.player.book?.author ?? "")
                .font(DeviceType.current == .iPad ? .body : .subheadline)
                .multilineTextAlignment(.center)
                .lineLimit(1)
            
            if let chapter = viewModel.player.currentChapter {
                Button(action: {
                    viewModel.showingChaptersList = true
                    
                    // Haptic feedback
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "list.bullet").font(.caption)
                        Text(chapter.title).font(.caption).truncationMode(.middle).lineLimit(1)
                    }
                    .foregroundColor(.accentColor)
                }
            }
        }
    }
    
    // MARK: - Progress Section
    
    private var progressSection: some View {
        VStack(spacing: 8) {
            
            // UX: Explicit Label for Context
            HStack {
                Text(showBookProgress ? "Total Book Progress" : "Current Chapter Progress")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .textCase(.uppercase)
                    .foregroundColor(showBookProgress ? .purple : .secondary)
                Spacer()
            }
            .padding(.horizontal, 4)
            
            Slider(
                value: Binding(
                    get: { viewModel.sliderValue },
                    set: { viewModel.updateSliderValue($0) }
                ),
                in: 0...max(progressDuration, 1)
            ) { editing in
                viewModel.onSliderEditingChanged(editing)
                
                // Haptic feedback on release
                if !editing {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                }
            }
            // UX: Color differentiation
            .tint(showBookProgress ? .purple : .accentColor)
            
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
                    // Haptic feedback
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
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
                    .background(
                        (showBookProgress ? Color.purple : Color.secondary).opacity(0.1)
                    )
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
    
    // MARK: - Main Controls Section
    
    private var mainControlsSection: some View {
        let controlSpacing: CGFloat = DeviceType.current == .iPad ? 48 : 32
        let buttonSize: CGFloat = DeviceType.current == .iPad ? 72 : 64
        let iconSize: Font = DeviceType.current == .iPad ? .largeTitle : .title
        
        return HStack(spacing: controlSpacing) {
            Button(action: {
                viewModel.player.previousChapter()
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
            }) {
                Image(systemName: "backward.end.fill")
                    .font(iconSize)
                    .foregroundColor(isFirstChapter ? .secondary : .primary)
            }
            .disabled(isFirstChapter)
            
            Button(action: {
                viewModel.player.seek15SecondsBack()
                triggerJump(PlayerJumpOverlayView.JumpDirection.backward) // UX: Trigger overlay
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
            }) {
                Image(systemName: "gobackward.15")
                    .font(iconSize)
                    .foregroundColor(.primary)
            }
            
            Button(action: {
                viewModel.player.togglePlayPause()
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
            }) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: buttonSize, height: buttonSize)
                    
                    Image(systemName: viewModel.player.isPlaying ? "pause.fill" : "play.fill")
                        .font(iconSize)
                        .foregroundColor(.white)
                }
            }
            
            Button(action: {
                viewModel.player.seek15SecondsForward()
                triggerJump(PlayerJumpOverlayView.JumpDirection.forward) // UX: Trigger overlay
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
            }) {
                Image(systemName: "goforward.15")
                    .font(iconSize)
                    .foregroundColor(.primary)
            }
            
            Button(action: {
                viewModel.player.nextChapter()
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
            }) {
                Image(systemName: "forward.end.fill")
                    .font(iconSize)
                    .foregroundColor(isLastChapter ? .secondary : .primary)
            }
            .disabled(isLastChapter)
        }
    }
    
    private var isFirstChapter: Bool { viewModel.player.currentChapterIndex == 0 }
    private var isLastChapter: Bool {
        guard let book = viewModel.player.book else { return true }
        return viewModel.player.currentChapterIndex >= book.chapters.count - 1
    }
    
    // MARK: - Secondary Controls Section
    
    private var secondaryControlsSection: some View {
        let controlSpacing: CGFloat = DeviceType.current == .iPad ? 56 : 40
        
        return HStack(spacing: controlSpacing) {
            // Speed - Prominent
            speedButton
            
            // Chapters - Secondary (contextual)
            chaptersButton
            
            // Bookmarks - Secondary (contextual)
            bookmarkButton
            
            // More Menu - Tertiary (rare actions)
            moreMenuButton
        }
        .foregroundColor(.primary)
    }
    
    // MARK: - Secondary Control Buttons
    
    private var speedButton: some View {
        Button(action: {
            showingPlaybackSettings = true
            
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        }) {
            VStack(spacing: 4) {
                Text("\(viewModel.player.playbackRate, specifier: "%.1f")x")
                    .font(DeviceType.current == .iPad ? .body : .caption)
                    .fontWeight(.medium)
                Text("Speed")
                    .font(DeviceType.current == .iPad ? .caption : .caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var chaptersButton: some View {
        Button(action: {
            viewModel.showingChaptersList = true
            
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        }) {
            VStack(spacing: 4) {
                Image(systemName: "list.bullet")
                    .font(DeviceType.current == .iPad ? .title2 : .title3)
                Text("Chapters")
                    .font(DeviceType.current == .iPad ? .caption : .caption2)
                    .foregroundColor(.secondary)
            }
        }
        .disabled(viewModel.player.book == nil)
    }
    
    private var bookmarkButton: some View {
        Button(action: {
            showingAddBookmark = true
            
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        }) {
            VStack(spacing: 4) {
                Image(systemName: "bookmark.fill")
                    .font(DeviceType.current == .iPad ? .title2 : .title3)
                Text("Bookmark")
                    .font(DeviceType.current == .iPad ? .caption : .caption2)
                    .foregroundColor(.secondary)
            }
        }
        .disabled(viewModel.player.book == nil)
    }
    
    private var moreMenuButton: some View {
        Menu {
            
            Button(action: {}) {
                Label("Audio Output", systemImage: "speaker.fill")
            }

            Divider()
            
            Button(action: {
                viewModel.showingSleepTimer = true
            }) {
                Label("Sleep Timer", systemImage: "moon")
            }
            
            
            
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "ellipsis")
                    .font(DeviceType.current == .iPad ? .title2 : .title3)
                Text("More")
                    .font(DeviceType.current == .iPad ? .caption : .caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
    
/*
    private var moreButton: some View {
        Menu {
            Button(action: { viewModel.player.pause() }) {
                Label("Stop Playback", systemImage: "stop")
            }
        } label: {
            Image(systemName: "ellipsis")
        }
    }
*/
    
    // MARK: - Progress Helpers
    
    private var progressCurrentTime: Double {
        showBookProgress ? viewModel.player.absoluteCurrentTime : viewModel.player.relativeCurrentTime
    }
    
    private var progressDuration: Double {
        showBookProgress ? viewModel.player.totalBookDuration : viewModel.player.chapterDuration
    }
}
