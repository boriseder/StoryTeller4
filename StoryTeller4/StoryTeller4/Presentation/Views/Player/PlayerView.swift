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
        .onChange(of: showBookProgress) { _, newValue in
            // FIX: Update slider value when switching between book/chapter progress
            viewModel.sliderValue = newValue
                ? viewModel.player.absoluteCurrentTime
                : viewModel.player.relativeCurrentTime
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
        // FIX: Proper layout with safe area consideration
        VStack(spacing: 0) {
            // Cover art takes available space
            coverArtSection
                .frame(maxHeight: geometry.size.height * 0.45)
            
            // Controls section
            ScrollView {
                VStack(spacing: DeviceType.current == .iPad ? 24 : 16) {
                    trackInfoSection
                    progressSection
                    mainControlsSection
                    secondaryControlsSection
                }
                .padding(.horizontal, DeviceType.current == .iPad ? 40 : DSLayout.screenPadding)
                .padding(.bottom, 20) // FIX: Add bottom padding for safe area
            }
            .frame(maxHeight: geometry.size.height * 0.55)
        }
    }
    
    // MARK: - Cover Art Section
    
    private var coverArtSection: some View {
        VStack {
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
                        size: DeviceType.current == .iPad ? DSLayout.fullCover : min(DSLayout.fullCover, 320),
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
                    .id(Date())
            }
        }
    }
    
    // MARK: - Track Info Section
    
    private var trackInfoSection: some View {
        VStack(spacing: 8) {
            if let chapter = viewModel.player.currentChapter {
                Button(action: {
                    viewModel.showingChaptersList = true
                    
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                }) {
                    HStack(spacing: 4) {
                        Text(chapter.title)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.primary)
                            .truncationMode(.middle)
                            .lineLimit(1)
                    }
                }
                
                Text(viewModel.player.book?.title ?? "No book selected")
                    .font(DeviceType.current == .iPad ? .body : .subheadline)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                
                Text(viewModel.player.book?.author ?? "")
                    .font(DeviceType.current == .iPad ? .body : .subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
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
                if editing {
                    viewModel.isDraggingSlider = true
                } else {
                    viewModel.isDraggingSlider = false
                    
                    // FIX: Use correct seek method based on context
                    if showBookProgress {
                        // Seeking in absolute time (book progress)
                        viewModel.player.seek(to: viewModel.sliderValue)
                    } else {
                        // Seeking in relative time (chapter progress)
                        // Add chapter start to get absolute time
                        if let chapter = viewModel.player.currentChapter {
                            let chapterStart = chapter.start ?? 0
                            let absoluteTime = chapterStart + viewModel.sliderValue
                            viewModel.player.seek(to: absoluteTime)
                        }
                    }
                    
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                }
            }
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
        // FIX: Adjusted spacing for iPhone
        let controlSpacing: CGFloat = DeviceType.current == .iPad ? 48 : 24
        let buttonSize: CGFloat = DeviceType.current == .iPad ? 72 : 64
        let iconSize: Font = DeviceType.current == .iPad ? .largeTitle : .title2
        
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
                triggerJump(PlayerJumpOverlayView.JumpDirection.backward)
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
                triggerJump(PlayerJumpOverlayView.JumpDirection.forward)
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
        .padding(.vertical, 8) // FIX: Add vertical padding
    }
    
    private var isFirstChapter: Bool { viewModel.player.currentChapterIndex == 0 }
    private var isLastChapter: Bool {
        guard let book = viewModel.player.book else { return true }
        return viewModel.player.currentChapterIndex >= book.chapters.count - 1
    }
    
    // MARK: - Secondary Controls Section
    
    private var secondaryControlsSection: some View {
        // FIX: Adjusted spacing for iPhone
        let controlSpacing: CGFloat = DeviceType.current == .iPad ? 56 : 32
        
        return HStack(spacing: controlSpacing) {
            speedButton
            chaptersButton
            bookmarkButton
            moreMenuButton
        }
        .foregroundColor(.primary)
        .padding(.vertical, 8) // FIX: Add vertical padding
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
                    .font(DeviceType.current == .iPad ? .title2 : .body)
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
                    .font(DeviceType.current == .iPad ? .title2 : .body)
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
                    .font(DeviceType.current == .iPad ? .title2 : .body)
                Text("More")
                    .font(DeviceType.current == .iPad ? .caption : .caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Progress Helpers
    
    private var progressCurrentTime: Double {
        showBookProgress ? viewModel.player.absoluteCurrentTime : viewModel.player.relativeCurrentTime
    }
    
    private var progressDuration: Double {
        showBookProgress ? viewModel.player.totalBookDuration : viewModel.player.chapterDuration
    }
}
