import SwiftUI
import AVKit

// MARK: - FullscreenPlayerView

struct FullscreenPlayerView: View {
    @State private var viewModel: PlayerViewModel

    @Environment(SleepTimerService.self) private var sleepTimer
    @Environment(AppStateManager.self) var appState
    @Environment(ThemeManager.self) var theme

    @Environment(\.dynamicTypeSize) var dynamicTypeSize

    @State private var showBookProgress = false
    @State private var showingPlaybackSettings = false
    @State private var chaptersSheetTab: ChapterViewTab = .chapters

    @State private var activeJump: PlayerJumpOverlayView.JumpDirection? = nil
    // UUID changes on each triggerJump() call — gives the overlay a new stable
    // identity that forces a fresh .onAppear for back-to-back taps.
    // Previously used Date() which is semantically wrong as a view identity.
    @State private var jumpOverlayID = UUID()
    @State private var jumpResetTask: Task<Void, Never>? = nil

    @ScaledMetric(relativeTo: .largeTitle) private var playButtonSize: CGFloat = 64

    private let minCoverSize: CGFloat = 100

    init(player: AudioPlayer, api: AudiobookshelfClient) {
        self._viewModel = State(initialValue: PlayerViewModel(player: player, api: api))
    }

    var body: some View {
        @Bindable var vm = viewModel

        GeometryReader { geo in
            adaptiveLayout(in: geo)
                .background(DSColor.background)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $vm.showingChaptersList) {
            ChaptersListView(player: viewModel.player, initialTab: chaptersSheetTab)
                .presentationDragIndicator(.visible)
                .presentationDetents([.medium, .large])
                .onDisappear { chaptersSheetTab = .chapters }
        }
        .sheet(isPresented: $vm.showingSleepTimer) {
            SleepTimerView()
                .environment(sleepTimer)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingPlaybackSettings) {
            PlaybackSpeedView(player: viewModel.player)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            viewModel.sliderValue = showBookProgress
                ? viewModel.player.absoluteCurrentTime
                : viewModel.player.relativeCurrentTime
        }
        .onChange(of: viewModel.player.currentTime) { _, _ in
            let displayTime = showBookProgress
                ? viewModel.player.absoluteCurrentTime
                : viewModel.player.relativeCurrentTime
            viewModel.updateSliderFromPlayer(displayTime)
        }
        .onChange(of: showBookProgress) { _, newValue in
            viewModel.sliderValue = newValue
                ? viewModel.player.absoluteCurrentTime
                : viewModel.player.relativeCurrentTime
        }
    }

    // MARK: - Adaptive Layout

    private func adaptiveLayout(in geo: GeometryProxy) -> some View {
        // geo.size is zero on the very first layout pass — guard against it
        guard geo.size.width > 0, geo.size.height > 0 else {
            return AnyView(Color.clear)
        }

        let safeWidth = geo.size.width - (DSLayout.screenPadding * 2)
        let coverSize = min(safeWidth, geo.size.height * 0.5)

        return AnyView(
            VStack(spacing: 0) {
                // Cover — fixed square, never grows beyond safeWidth or 50% of height
                coverArtView(size: coverSize)

                // Controls — fill all remaining space; internal Spacers distribute it
                controlsStack
                    .padding(.bottom, max(geo.safeAreaInsets.bottom, DSLayout.screenPadding))
            }
            .padding(.horizontal, DSLayout.screenPadding)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        )
    }

    // MARK: - Controls Stack

    private var controlsStack: some View {
        VStack(spacing: DSLayout.contentGap) {
            trackInfoSection
            progressSection
            Spacer(minLength: 0)
            mainControlsSection
            Spacer(minLength: 0)
            secondaryControlsSection
        }
        .padding(.top, DSLayout.contentGap)
    }

    // MARK: - Cover Art

    private func coverArtView(size: CGFloat) -> some View {
        ZStack {
            if let book = viewModel.player.book {
                BookCoverView.square(
                    book: book,
                    size: size,
                    api: viewModel.api,
                    downloadManager: viewModel.player.downloadManagerReference
                )
                .aspectRatio(1, contentMode: .fit)
                .shadow(radius: DSLayout.shadowRadius, x: 0, y: DSLayout.tightPadding)
            } else {
                RoundedRectangle(cornerRadius: DSCorners.content)
                    .fill(DSColor.surfaceMedium)
                    .aspectRatio(1, contentMode: .fit)
            }

            if let direction = activeJump {
                PlayerJumpOverlayView(direction: direction)
                    .id(jumpOverlayID)
            }
        }
        .frame(width: size, height: size)
    }

    // MARK: - Track Info

    private var trackInfoSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let chapter = viewModel.player.currentChapter {
                Button(action: {
                    chaptersSheetTab = .chapters
                    viewModel.showingChaptersList = true
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }) {
                    HStack {
                        MarqueeText(text: chapter.title, font: DSText.itemTitle)

                        Spacer()
                        
                        Button(action: {
                            chaptersSheetTab = .bookmarks
                            viewModel.showingChaptersList = true
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }) {
                            Label("Add Bookmark", systemImage: "bookmark")
                                .labelStyle(.iconOnly)
                                .font(DSText.itemTitle)

                        }
                        .foregroundStyle(.primary) 
                        .disabled(viewModel.player.book == nil)

                    }
                }
                .buttonStyle(.plain)

                /*
                // Booktitle
                Text(viewModel.player.book?.title ?? "No book selected")
                    .font(DSText.emphasized)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .truncationMode(.tail)

                // Author
                Text(viewModel.player.book?.author ?? "")
                    .font(DSText.emphasized)
                    .foregroundColor(DSColor.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                 
                 */

            }
        }
        //.multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, DSLayout.contentPadding)

    }

    // MARK: - Progress Section

    private var progressSection: some View {
        VStack(spacing: 0) {
            Slider(
                value: Binding(
                    get: { viewModel.sliderValue },
                    set: { viewModel.updateSliderValue($0) }
                ),
                in: 0...max(1, showBookProgress
                    ? viewModel.player.totalBookDuration
                    : viewModel.player.chapterDuration)
            ) { editing in
                if !editing {
                    if showBookProgress {
                        viewModel.player.seek(to: viewModel.sliderValue)
                    } else {
                        if let chapter = viewModel.player.currentChapter {
                            let absoluteTime = (chapter.start ?? 0) + viewModel.sliderValue
                            viewModel.player.seek(to: absoluteTime)
                        }
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
            .tint(showBookProgress ? .purple : DSColor.accent)
            .controlSize(.mini) // Alternativen: .small, .regular

            HStack {
                Text(TimeFormatter.formatTime(progressCurrentTime))
                    .font(.footnote.monospacedDigit())
                    .foregroundColor(DSColor.secondary)
                Spacer()

                Button(action: {
                    withAnimation(DSAnimations.ease) { showBookProgress.toggle() }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }) {
                    HStack(spacing: DSLayout.tightGap) {
                        Image(systemName: showBookProgress ? "book.fill" : "doc.text.fill")
                            .font(DSText.fine)
                        Text(showBookProgress ? "Book" : "Chapter")
                            .font(DSText.fine)
                    }
                    .foregroundColor(showBookProgress ? .purple : DSColor.secondary)
                    .padding(.horizontal, DSLayout.elementPadding)
                    //.padding(.vertical, DSLayout.tightPadding)
                    .background(
                        (showBookProgress ? Color.purple : DSColor.secondary)
                            .opacity(DSLayout.shadowOpacity)
                    )
                    .clipShape(Capsule())
                }

                Spacer()

                Text("-\(TimeFormatter.formatTime(max(0, progressDuration - progressCurrentTime)))")
                    .font(.footnote.monospacedDigit())
                    .foregroundColor(DSColor.secondary)
            }
        }
    }

    // MARK: - Main Controls

    private var mainControlsSection: some View {
        HStack {
            /*

            Button(action: {
                viewModel.player.previousChapter()
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }) {
                Image(systemName: "backward.end.fill")
                    .font(.title2)
                    .foregroundColor(isFirstChapter ? DSColor.secondary : DSColor.primary)
            }
            .disabled(isFirstChapter)
             */
            
            Spacer(minLength: DSLayout.tightGap)

            Button(action: {
                viewModel.player.seek15SecondsBack()
                triggerJump(.backward)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }) {
                Image(systemName: "gobackward.15")
                    .font(.largeTitle)
                    .foregroundColor(DSColor.primary)
            }

            Spacer(minLength: DSLayout.tightGap)

            Button(action: {
                viewModel.player.togglePlayPause()
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }) {
                ZStack {
                    /*
                     Circle()
                        .fill(DSColor.accent)
                        .frame(width: playButtonSize, height: playButtonSize)
                    */
                     Image(systemName: viewModel.player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.white)
                }
            }

            Spacer(minLength: DSLayout.tightGap)

            Button(action: {
                viewModel.player.seek15SecondsForward()
                triggerJump(.forward)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }) {
                Image(systemName: "goforward.15")
                    .font(.largeTitle)
                    .foregroundColor(DSColor.primary)
            }

            Spacer(minLength: DSLayout.tightGap)

            /*
            Button(action: {
                viewModel.player.nextChapter()
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }) {
                Image(systemName: "forward.end.fill")
                    .font(.title2)
                    .foregroundColor(isLastChapter ? DSColor.secondary : DSColor.primary)
            }
            .disabled(isLastChapter)
             */
        }
        .padding(.vertical, DSLayout.tightPadding)
    }

    // MARK: - Secondary Controls

    private var secondaryControlsSection: some View {
        HStack(spacing: 0) {
            Spacer()
            sleepTimerButton
            Spacer()
            chaptersButton
            Spacer()
            airPlayButton
            Spacer()
            speedButton
            Spacer()
        }
        .foregroundColor(DSColor.primary)
        .padding(.top, DSLayout.contentPadding)
    }

    private var sleepTimerButton: some View {
        Button(action: {
            viewModel.showingSleepTimer = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }) {
            Image(systemName: "moon.fill")
                .font(DSText.body)
                .foregroundColor(sleepTimer.isTimerActive ? DSColor.accent : DSColor.primary)
                .frame(width: 44, height: 44)
        }
    }

    private var chaptersButton: some View {
        Button(action: {
            chaptersSheetTab = .chapters
            viewModel.showingChaptersList = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }) {
            Image(systemName: "list.bullet")
                .font(DSText.body)
                .frame(width: 44, height: 44)
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                chaptersSheetTab = .bookmarks
                viewModel.showingChaptersList = true
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        )
        .disabled(viewModel.player.book == nil)
    }

    private var airPlayButton: some View {
        ZStack {
            AVRoutePickerViewWrapper()
                .frame(width: 44, height: 44)
            Image(systemName: "airplayaudio")
                .font(DSText.body)
                .allowsHitTesting(false)
        }
    }

    private var speedButton: some View {
        Button(action: {
            showingPlaybackSettings = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }) {
            Image(systemName: "speedometer")
                .font(DSText.body)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Helpers

    private var isFirstChapter: Bool { viewModel.player.currentChapterIndex == 0 }

    private var isLastChapter: Bool {
        guard let book = viewModel.player.book else { return true }
        return viewModel.player.currentChapterIndex >= book.chapters.count - 1
    }

    private var progressCurrentTime: Double {
        showBookProgress
            ? viewModel.player.absoluteCurrentTime
            : viewModel.player.relativeCurrentTime
    }

    private var progressDuration: Double {
        showBookProgress
            ? viewModel.player.totalBookDuration
            : viewModel.player.chapterDuration
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
