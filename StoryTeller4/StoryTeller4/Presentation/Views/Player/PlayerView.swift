import SwiftUI
import AVKit

struct PlayerView: View {
    @State private var viewModel: PlayerViewModel
    
    // FIX: Use @Environment(Type.self)
    @Environment(SleepTimerService.self) private var sleepTimer
    
    @Environment(AppStateManager.self) var appState
    @Environment(ThemeManager.self) var theme
    
    @State private var showBookProgress = false
    @State private var showingAddBookmark = false
    @State private var newBookmarkTitle = ""
    @State private var isCreatingBookmark = false

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
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    moreButton
                }
            }
            .sheet(isPresented: $vm.showingChaptersList) {
                ChaptersListView(player: viewModel.player)
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $vm.showingSleepTimer) {
                SleepTimerView()
                    // FIX: Inject via .environment()
                    .environment(sleepTimer)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
                
            }
            .sheet(isPresented: $vm.showingPlaybackSettings) {
                PlaybackSettingsView(player: viewModel.player)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
                
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
    
    // ... [Rest of Layout and Controls code remains exactly the same as previously fixed] ...
    // Note: Re-stating critical sections to ensure context
    
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
    
    private func standardLayout(geometry: GeometryProxy) -> some View {
        VStack(spacing: DSLayout.contentGap) {
            coverArtSection.frame(height: DSLayout.fullCover)
            controlsSection.frame(maxHeight: .infinity).padding(.horizontal, DeviceType.current == .iPad ? 40 : DSLayout.screenPadding)
        }
    }
    
    // ... [CoverArt, Controls, ProgressSection, etc. - identical to previous turn]
    
    private var coverArtSection: some View {
        VStack(spacing: DSLayout.contentGap) {
            Spacer()
            coverArtView
            Spacer()
        }
        .padding(.horizontal, DeviceType.current == .iPad ? 60 : DSLayout.screenPadding)
    }
    
    private var coverArtView: some View {
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
    }
    
    private var controlsSection: some View {
        VStack(spacing: DeviceType.current == .iPad ? 32 : 24) {
            trackInfoSection
            progressSection
            mainControlsSection
            secondaryControlsSection
            Spacer()
        }
    }
    
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
                Button(action: { viewModel.showingChaptersList = true }) {
                    HStack {
                        Image(systemName: "list.bullet").font(.caption)
                        Text(chapter.title).font(.caption).truncationMode(.middle).lineLimit(1)
                    }
                    .foregroundColor(.accentColor)
                }
            }
        }
    }
    
    private var progressSection: some View {
        VStack(spacing: 8) {
            Slider(
                value: Binding(
                    get: { viewModel.sliderValue },
                    set: { viewModel.updateSliderValue($0) }
                ),
                in: 0...max(progressDuration, 1)
            ) { editing in viewModel.onSliderEditingChanged(editing) }
            .accentColor(.primary)
            
            HStack {
                Text(TimeFormatter.formatTime(progressCurrentTime)).font(.caption).foregroundColor(.secondary).monospacedDigit()
                Spacer()
                Button(action: { showBookProgress.toggle() }) {
                    HStack(spacing: 4) {
                        Image(systemName: showBookProgress ? "book.fill" : "doc.text.fill").font(.caption2)
                        Text(showBookProgress ? "Book" : "Chapter").font(.caption2)
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1)).clipShape(Capsule())
                }
                Spacer()
                let remaining = max(0, progressDuration - progressCurrentTime)
                Text("-\(TimeFormatter.formatTime(remaining))").font(.caption).foregroundColor(.secondary).monospacedDigit()
            }
        }
    }
    
    private var mainControlsSection: some View {
        let controlSpacing: CGFloat = DeviceType.current == .iPad ? 48 : 32
        let buttonSize: CGFloat = DeviceType.current == .iPad ? 72 : 64
        let iconSize: Font = DeviceType.current == .iPad ? .largeTitle : .title
        return HStack(spacing: controlSpacing) {
            Button(action: { viewModel.player.previousChapter() }) {
                Image(systemName: "backward.end.fill").font(iconSize)
                    .foregroundColor(isFirstChapter ? .secondary : .primary)
            }.disabled(isFirstChapter)
            
            Button(action: { viewModel.player.seek15SecondsBack() }) {
                Image(systemName: "gobackward.15").font(iconSize).foregroundColor(.primary)
            }
            
            Button(action: { viewModel.player.togglePlayPause() }) {
                ZStack {
                    Circle().fill(Color.accentColor).frame(width: buttonSize, height: buttonSize)
                    Image(systemName: viewModel.player.isPlaying ? "pause.fill" : "play.fill")
                        .font(iconSize).foregroundColor(.white)
                }
            }
            
            Button(action: { viewModel.player.seek15SecondsForward() }) {
                Image(systemName: "goforward.15").font(iconSize).foregroundColor(.primary)
            }
            
            Button(action: { viewModel.player.nextChapter() }) {
                Image(systemName: "forward.end.fill").font(iconSize)
                    .foregroundColor(isLastChapter ? .secondary : .primary)
            }.disabled(isLastChapter)
        }
    }
    
    private var isFirstChapter: Bool { viewModel.player.currentChapterIndex == 0 }
    private var isLastChapter: Bool {
        guard let book = viewModel.player.book else { return true }
        return viewModel.player.currentChapterIndex >= book.chapters.count - 1
    }
    
    private var secondaryControlsSection: some View {
        let controlSpacing: CGFloat = DeviceType.current == .iPad ? 56 : 40
        return HStack(spacing: controlSpacing) {
            speedButton
            sleepTimerButton
            audioRouteButton
            bookmarkButton
            chaptersButton
        }
        .foregroundColor(.primary)
    }
    
    private var speedButton: some View {
        Button(action: { viewModel.showingPlaybackSettings = true }) {
            VStack(spacing: 4) {
                Text("\(viewModel.player.playbackRate, specifier: "%.1f")x")
                    .font(DeviceType.current == .iPad ? .body : .caption).fontWeight(.medium)
                Text("Speed").font(DeviceType.current == .iPad ? .caption : .caption2).foregroundColor(.secondary)
            }
        }
    }
    
    private var sleepTimerButton: some View {
        Button(action: { viewModel.showingSleepTimer = true }) {
            VStack(spacing: 4) {
                Image(systemName: "moon").font(DeviceType.current == .iPad ? .title2 : .title3)
                Text("Sleep").font(DeviceType.current == .iPad ? .caption : .caption2).foregroundColor(.secondary)
            }
        }
    }
    
    private var audioRouteButton: some View {
        #if targetEnvironment(simulator)
        Menu { Button("iPhone Speaker") {}; Button("Bluetooth Headphones") {} } label: {
            VStack(spacing: 4) {
                Image(systemName: "speaker.fill").font(DeviceType.current == .iPad ? .title2 : .title3)
                Text("Audio").font(DeviceType.current == .iPad ? .caption : .caption2).foregroundColor(.secondary)
            }
        }
        #else
        VStack(spacing: 4) {
            AVRoutePickerViewWrapper()
                .frame(width: DeviceType.current == .iPad ? 24 : 20, height: DeviceType.current == .iPad ? 24 : 20)
            Text("Audio").font(DeviceType.current == .iPad ? .caption : .caption2).foregroundColor(.secondary)
        }
        #endif
    }
    
    private var chaptersButton: some View {
        Button(action: { viewModel.showingChaptersList = true }) {
            VStack(spacing: 4) {
                Image(systemName: "list.bullet").font(DeviceType.current == .iPad ? .title2 : .title3)
                Text("Chapters").font(DeviceType.current == .iPad ? .caption : .caption2).foregroundColor(.secondary)
            }
        }
        .disabled(viewModel.player.book == nil)
    }
    
    private var bookmarkButton: some View {
        Button(action: {
            let currentTime = viewModel.player.absoluteCurrentTime
            newBookmarkTitle = "Bookmark at \(TimeFormatter.formatTime(currentTime))"
            showingAddBookmark = true
        }) {
            VStack(spacing: 4) {
                Image(systemName: "bookmark.fill").font(DeviceType.current == .iPad ? .title2 : .title3)
                Text("Bookmark").font(DeviceType.current == .iPad ? .caption : .caption2).foregroundColor(.secondary)
            }
        }
        .disabled(viewModel.player.book == nil)
        .alert("Add Bookmark", isPresented: $showingAddBookmark) {
            TextField("Bookmark name", text: $newBookmarkTitle).autocorrectionDisabled()
            Button("Cancel", role: .cancel) { newBookmarkTitle = "" }
            Button("Add") { createBookmark() }
            .disabled(newBookmarkTitle.trimmingCharacters(in: .whitespaces).isEmpty)
        } message: {
            Text("Enter a name for this bookmark at \(TimeFormatter.formatTime(viewModel.player.absoluteCurrentTime))")
        }
        .overlay {
            if isCreatingBookmark { ProgressView().scaleEffect(0.8) }
        }
    }
    
    private func createBookmark() {
        guard let book = viewModel.player.book else { return }
        let title = newBookmarkTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        let currentTime = viewModel.player.absoluteCurrentTime
        
        isCreatingBookmark = true
        Task {
            do {
                try await BookmarkRepository.shared.createBookmark(libraryItemId: book.id, time: currentTime, title: title)
                await MainActor.run {
                    isCreatingBookmark = false
                    newBookmarkTitle = ""
                    AppLogger.general.debug("[PlayerView] ✅ Bookmark created")
                }
            } catch {
                await MainActor.run {
                    isCreatingBookmark = false
                    AppLogger.general.error("[PlayerView] ❌ Failed: \(error)")
                }
            }
        }
    }
    
    private var moreButton: some View {
        Menu {
            Button(action: { viewModel.player.pause() }) { Label("Stop Playback", systemImage: "stop") }
        } label: { Image(systemName: "ellipsis") }
    }
    
    private var progressCurrentTime: Double {
        showBookProgress ? viewModel.player.absoluteCurrentTime : viewModel.player.relativeCurrentTime
    }
    private var progressDuration: Double {
        showBookProgress ? viewModel.player.totalBookDuration : viewModel.player.chapterDuration
    }
}
