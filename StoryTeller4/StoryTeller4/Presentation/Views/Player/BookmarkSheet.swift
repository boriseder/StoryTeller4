//
//  EnhancedBookmarkSheet.swift
//  StoryTeller4
//
//  Created by Boris Eder on 12.12.25.
//


import SwiftUI

struct BookmarkSheet: View {
    let player: AudioPlayer
    @Binding var isPresented: Bool
    
    @State private var bookmarkTitle = ""
    @State private var useChapterTitle = true
    @State private var isCreating = false
    @FocusState private var isTitleFocused: Bool
    
    var suggestedTitle: String {
        if useChapterTitle, let chapter = player.currentChapter {
            return chapter.title
        }
        return "Bookmark at \(TimeFormatter.formatTime(player.absoluteCurrentTime))"
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    bookmarkPreview
                } header: {
                    Text("Current Position")
                }
                
                Section {
                    Toggle("Use Chapter Title", isOn: $useChapterTitle)
                        .onChange(of: useChapterTitle) { _, newValue in
                            if newValue {
                                bookmarkTitle = suggestedTitle
                            }
                        }
                    
                    TextField("Bookmark Name", text: $bookmarkTitle, axis: .vertical)
                        .focused($isTitleFocused)
                        .lineLimit(2...4)
                        .textInputAutocapitalization(.sentences)
                        .autocorrectionDisabled()
                } header: {
                    Text("Details")
                } footer: {
                    Text("Give this bookmark a memorable name")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section {
                    recentBookmarksSection
                } header: {
                    Text("Recent Bookmarks")
                }
            }
            .navigationTitle("Add Bookmark")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        createBookmark()
                    } label: {
                        if isCreating {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(bookmarkTitle.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
                }
            }
            .onAppear {
                bookmarkTitle = suggestedTitle
                // Auto-focus on title if not using chapter title
                if !useChapterTitle {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        isTitleFocused = true
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
    
    // MARK: - Bookmark Preview
    
    private var bookmarkPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                if let book = player.book {
                    BookCoverView.square(
                        book: book,
                        size: 60,
                        api: nil,
                        downloadManager: player.downloadManagerReference
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(player.book?.title ?? "Unknown")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                    
                    if let chapter = player.currentChapter {
                        Text(chapter.title)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            
            HStack(spacing: 16) {
                Label(
                    TimeFormatter.formatTime(player.absoluteCurrentTime),
                    systemImage: "clock.fill"
                )
                .font(.subheadline)
                .foregroundColor(.accentColor)
                
                if let chapter = player.currentChapter,
                   let start = chapter.start {
                    let chapterTime = player.currentTime - start
                    Divider()
                        .frame(height: 20)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "book.fill")
                            .font(.caption)
                        Text("Chapter: \(TimeFormatter.formatTime(chapterTime))")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color.accentColor.opacity(0.1))
            .cornerRadius(8)
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Recent Bookmarks Section
    
    private var recentBookmarksSection: some View {
        Group {
            if player.book != nil {
                // In a real implementation, fetch recent bookmarks from BookmarkRepository
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your last bookmark was created 15 minutes ago")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Tip: You can view all bookmarks in the Chapters & Bookmarks tab")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.8))
                        .italic()
                }
            } else {
                Text("No recent bookmarks")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Create Bookmark
    
    private func createBookmark() {
        guard let book = player.book else { return }
        let title = bookmarkTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        
        isCreating = true
        
        Task {
            do {
                try await BookmarkRepository.shared.createBookmark(
                    libraryItemId: book.id,
                    time: player.absoluteCurrentTime,
                    title: title
                )
                
                await MainActor.run {
                    // Success haptic
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    
                    isCreating = false
                    isPresented = false
                    
                    AppLogger.general.debug("[EnhancedBookmark] ✅ Bookmark created: \(title)")
                }
            } catch {
                await MainActor.run {
                    // Error haptic
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.error)
                    
                    isCreating = false
                    AppLogger.general.error("[EnhancedBookmark] ❌ Failed: \(error)")
                }
            }
        }
    }
}
