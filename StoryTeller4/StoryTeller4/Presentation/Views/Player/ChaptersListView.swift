import SwiftUI
import AVKit

// MARK: - Tab Selection Enum
enum ChapterViewTab {
    case chapters
    case bookmarks
}

struct ChaptersListView: View {
    let player: AudioPlayer
    var initialTab: ChapterViewTab = .chapters

    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: ChapterViewTab = .chapters
    @State private var bookmarkViewModel: BookmarkViewModel
    @State private var showingAddBookmark = false

    // Derived synchronously from player — no Timer, no manual refresh.
    // Recomputed automatically whenever player.currentChapterIndex,
    // player.isPlaying, or player.currentTime changes thanks to @Observable.
    private var chapterVMs: [ChapterStateViewModel] {
        guard let book = player.book else { return [] }
        return book.chapters.enumerated().map { index, chapter in
            ChapterStateViewModel(index: index, chapter: chapter, player: player)
        }
    }

    private var currentBookBookmarks: [EnrichedBookmark] {
        guard let bookId = player.book?.id else { return [] }
        return bookmarkViewModel.allBookmarks
            .filter { $0.bookmark.libraryItemId == bookId }
            .sorted { $0.bookmark.time < $1.bookmark.time }
    }

    init(player: AudioPlayer, initialTab: ChapterViewTab = .chapters) {
        self.player = player
        self.initialTab = initialTab
        _bookmarkViewModel = State(initialValue: BookmarkViewModel())
    }

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader
            segmentedControl
            Divider()

            if selectedTab == .chapters {
                chaptersListView
            } else {
                bookmarksListView
            }
        }
        .background(Color(.systemGroupedBackground))
        .sheet(isPresented: $showingAddBookmark) {
            BookmarkSheet(player: player, isPresented: $showingAddBookmark)
                .onDisappear {
                    Task { await bookmarkViewModel.refresh() }
                }
        }
        .onAppear {
            selectedTab = initialTab
        }
        .alert("Edit Bookmark", isPresented: Binding(
            get: { bookmarkViewModel.editingBookmark != nil },
            set: { if !$0 { bookmarkViewModel.cancelEditing() } }
        )) {
            TextField("Bookmark name", text: Bindable(bookmarkViewModel).editedBookmarkTitle)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) { bookmarkViewModel.cancelEditing() }
            Button("Save") {
                bookmarkViewModel.saveEditedBookmark()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
            .disabled(bookmarkViewModel.editedBookmarkTitle.trimmingCharacters(in: .whitespaces).isEmpty)
        } message: {
            Text("Enter a new name for this bookmark")
        }
    }

    // MARK: - Sheet Header

    private var sheetHeader: some View {
        HStack {
            Text(selectedTab == .chapters ? "Chapters" : "Bookmarks")
                .font(DSText.emphasized)
                .foregroundColor(.primary)

            Spacer()

            if selectedTab == .bookmarks {
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showingAddBookmark = true
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.accentColor, Color.accentColor.opacity(0.15))
                }
                .transition(.scale.combined(with: .opacity))
            }

            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.secondary, Color.secondary.opacity(0.2))
            }
            .padding(.leading, 8)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedTab)
        .padding(.horizontal, DSLayout.screenPadding)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    // MARK: - Segmented Control

    private var segmentedControl: some View {
        Picker("View", selection: $selectedTab) {
            Text("Chapters").tag(ChapterViewTab.chapters)
            Text("Bookmarks").tag(ChapterViewTab.bookmarks)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, DSLayout.screenPadding)
        .padding(.bottom, 12)
        .onChange(of: selectedTab) { _, _ in
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    // MARK: - Chapters List

    private var chaptersListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: DSLayout.tightGap) {
                    ForEach(chapterVMs) { chapterVM in
                        ChapterCardView(
                            viewModel: chapterVM,
                            onTap: { handleChapterTap(index: chapterVM.id) }
                        )
                        .id(chapterVM.id)
                    }
                }
                .padding(.horizontal, DSLayout.screenPadding)
                .padding(.vertical, DSLayout.screenPadding)
            }
            // Scroll to the current chapter whenever this tab appears or the
            // current chapter changes. .task(id:) cancels and re-runs automatically.
            .task(id: player.currentChapterIndex) {
                // One async yield lets the scroll view finish its first layout
                // pass before we ask it to scroll — no hardcoded delay needed.
                await Task.yield()
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(player.currentChapterIndex, anchor: .center)
                }
            }
        }
    }

    // MARK: - Bookmarks List

    private var bookmarksListView: some View {
        ScrollView {
            if currentBookBookmarks.isEmpty {
                VStack(spacing: DSLayout.contentGap) {
                    Image(systemName: "bookmark.slash")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No bookmarks yet")
                        .font(DSText.emphasized)
                        .foregroundColor(.secondary)
                    Text("Tap + to bookmark your current position")
                        .font(DSText.detail)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showingAddBookmark = true
                    }) {
                        Label("Add Bookmark", systemImage: "plus")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
            } else {
                LazyVStack(spacing: DSLayout.tightGap) {
                    ForEach(currentBookBookmarks) { enriched in
                        BookmarkRow(
                            enriched: enriched,
                            showBookInfo: false,
                            onTap: {
                                handleBookmarkTap(enriched)
                            },
                            onEdit: { bookmarkViewModel.startEditingBookmark(enriched) },
                            onDelete: {
                                bookmarkViewModel.deleteBookmark(enriched)
                                // Deletion is a destructive action — .warning, not .success
                                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                            }
                        )
                    }
                }
                .padding(.horizontal, DSLayout.screenPadding)
                .padding(.bottom, DSLayout.screenPadding)
            }
        }
        .refreshable { await bookmarkViewModel.refresh() }
    }

    // MARK: - Actions

    private func handleChapterTap(index: Int) {
        let wasPlaying = player.isPlaying
        player.setCurrentChapter(index: index)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if wasPlaying { player.play() }
        // Dismiss immediately — no arbitrary delay.
        // The chapter switch is synchronous; the sheet animation handles the rest.
        dismiss()
    }

    private func handleBookmarkTap(_ enriched: EnrichedBookmark) {
        player.jumpToBookmark(enriched.bookmark)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        dismiss()
    }
}

// MARK: - Chapter Card View

struct ChapterCardView: View {
    let viewModel: ChapterStateViewModel
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: DSLayout.contentGap) {
                ZStack {
                    Circle()
                        .fill(viewModel.isCurrent ? Color.accentColor : Color.secondary.opacity(0.15))
                        .frame(width: DSLayout.largeIcon, height: DSLayout.largeIcon)

                    if viewModel.isCurrent && viewModel.isPlaying {
                        Image(systemName: "waveform")
                            .font(DSText.button)
                            .foregroundColor(.white)
                            .symbolEffect(.variableColor.iterative, options: .repeating, value: viewModel.isPlaying)
                    } else {
                        Text("\(viewModel.id + 1)")
                            .font(DSText.button)
                            .foregroundColor(viewModel.isCurrent ? .white : .secondary)
                    }
                }

                VStack(alignment: .leading, spacing: DSLayout.elementGap) {
                    Text(viewModel.chapter.title)
                        .font(DSText.emphasized)
                        .fontWeight(viewModel.isCurrent ? .semibold : .regular)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: DSLayout.contentGap) {
                        if let start = viewModel.chapter.start {
                            Text(TimeFormatter.formatTime(start))
                                .font(DSText.metadata)
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }
                        if let start = viewModel.chapter.start, let end = viewModel.chapter.end {
                            Text("·")
                                .foregroundColor(.secondary)
                            Text(TimeFormatter.formatTime(end - start))
                                .font(DSText.metadata)
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }
                    }

                    if viewModel.isCurrent && chapterProgress > 0 {
                        ProgressView(value: chapterProgress)
                            .progressViewStyle(LinearProgressViewStyle(tint: .accentColor))
                            .scaleEffect(x: 1, y: 0.7, anchor: .center)
                    }
                }

                if !viewModel.isCurrent {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(Color.secondary.opacity(0.4))
                }
            }
            .padding(DSLayout.elementPadding)
            .background(
                RoundedRectangle(cornerRadius: DSCorners.element)
                    .fill(viewModel.isCurrent
                          ? Color.accentColor.opacity(0.08)
                          : Color(.secondarySystemGroupedBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: DSCorners.element)
                            .stroke(viewModel.isCurrent ? Color.accentColor.opacity(0.3) : Color.clear,
                                    lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }

    private var chapterProgress: Double {
        guard viewModel.isCurrent,
              let start = viewModel.chapter.start,
              let end = viewModel.chapter.end,
              end > start else { return 0 }
        let duration = end - start
        let elapsed = max(0, min(viewModel.currentTime - start, duration))
        return elapsed / duration
    }
}

// MARK: - Reusable Static Components

struct StaticChapterListView: View {
    let chapters: [Chapter]
    var showSectionTitle: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: DSLayout.elementGap) {
            if showSectionTitle {
                Text("Chapters")
                    .font(DSText.prominent)
                    .foregroundColor(DSColor.primary)
            }
            ForEach(Array(chapters.enumerated()), id: \.offset) { index, chapter in
                StaticChapterRow(index: index, chapter: chapter, isLast: index == chapters.count - 1)
            }
        }
    }
}

struct InteractiveChapterListView: View {
    let chapters: [Chapter]
    let onChapterTap: (Int) -> Void
    var showSectionTitle: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: DSLayout.elementGap) {
            if showSectionTitle {
                Text("Chapters")
                    .font(DSText.prominent)
                    .foregroundColor(DSColor.primary)
            }
            ForEach(Array(chapters.enumerated()), id: \.offset) { index, chapter in
                Button(action: { onChapterTap(index) }) {
                    StaticChapterRow(index: index, chapter: chapter, isLast: index == chapters.count - 1)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct StaticChapterRow: View {
    let index: Int
    let chapter: Chapter
    let isLast: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DSLayout.contentGap) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.secondary.opacity(0.2), Color.secondary.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 36)
                    Text("\(index + 1)")
                        .font(DSText.metadata)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: DSLayout.tightGap) {
                    Text(chapter.title)
                        .font(DSText.body)
                        .foregroundColor(DSColor.primary)
                        .lineLimit(2)

                    HStack(spacing: DSLayout.contentGap) {
                        if let start = chapter.start {
                            HStack(spacing: DSLayout.tightGap) {
                                Image(systemName: "clock")
                                    .font(DSText.metadata)
                                Text(TimeFormatter.formatTime(start))
                                    .font(DSText.metadata)
                                    .monospacedDigit()
                            }
                            .foregroundColor(.secondary)
                        }
                        if let start = chapter.start, let end = chapter.end {
                            HStack(spacing: DSLayout.tightGap) {
                                Image(systemName: "timer")
                                    .font(DSText.metadata)
                                Text(TimeFormatter.formatTime(end - start))
                                    .font(DSText.metadata)
                                    .monospacedDigit()
                            }
                            .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()
            }
            .padding(.vertical, DSLayout.tightPadding)

            if !isLast {
                Divider()
            }
        }
    }
}
