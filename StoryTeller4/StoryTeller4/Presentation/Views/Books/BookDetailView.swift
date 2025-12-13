//
//  BookDetailView.swift
//  StoryTeller4
//
//  Created by Boris Eder on 12.12.25.
//

import SwiftUI

struct BookDetailView: View {
    @State var viewModel: BookDetailViewModel
    @Environment(\.dismiss) var dismiss
    
    // Dependencies for PlayBookUseCase
    @Environment(PlayerStateManager.self) private var playerStateManager
    @Environment(DependencyContainer.self) private var container
    @Environment(AppStateManager.self) private var appState

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    LoadingView()
                } else if let errorMessage = viewModel.errorMessage {
                    ErrorView(error: errorMessage)
                } else if let book = viewModel.book {
                    bookDetailContent(book: book)
                } else {
                    ErrorView(error: "Book details could not be loaded.")
                }
            }
            .navigationTitle(viewModel.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .background(DSColor.background.ignoresSafeArea())
    }
    
    @ViewBuilder
    private func bookDetailContent(book: Book) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSLayout.contentGap) {
                
                // MARK: - Cover and Main Info
                HStack(alignment: .top, spacing: DSLayout.elementGap) {
                    
                    BookCoverView.bookAspect(
                        book: book,
                        width: 120, // Approx large/detail size
                        api: container.apiClient,
                        downloadManager: container.downloadManager
                    )
                    .clipShape(RoundedRectangle(cornerRadius: DSCorners.element))
                    
                    VStack(alignment: .leading, spacing: DSLayout.tightGap) {
                        Text(viewModel.title)
                            .font(DSText.sectionTitle)
                            .foregroundColor(DSColor.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Text(viewModel.author)
                            .font(DSText.emphasized)
                            .foregroundColor(DSColor.secondary)
                        
                        // Download Controls
                        downloadControlView(book: book)
                            .padding(.top, DSLayout.tightPadding)
                    }
                }
                .padding(.horizontal, DSLayout.screenPadding)
                
                // MARK: - Play Button
                HStack {
                    Button(action: {
                        playBook(book)
                    }) {
                        Label("Play Book", systemImage: "play.fill")
                            .font(DSText.largeButton)
                            .frame(maxWidth: .infinity)
                            .padding(DSLayout.elementPadding)
                            .background(DSColor.accent)
                            .foregroundColor(DSColor.onDark)
                            .cornerRadius(DSCorners.content)
                    }
                }
                .padding(.horizontal, DSLayout.screenPadding)
                
                // MARK: - Description
                if viewModel.hasDescription {
                    VStack(alignment: .leading, spacing: DSLayout.elementGap) {
                        Text("Description")
                            .font(DSText.prominent)
                            .foregroundColor(DSColor.primary)
                        
                        Text(viewModel.formattedDescription)
                            .font(DSText.body)
                            .foregroundColor(DSColor.secondary)
                        
                    }
                    .padding(.horizontal, DSLayout.screenPadding)
                }

                // MARK: - Chapters List (Interactive)
                if !viewModel.chapters.isEmpty {
                    InteractiveChapterListView(
                        chapters: viewModel.chapters,
                        onChapterTap: { index in
                            playChapter(book, at: index)
                        }
                    )
                    .padding(.horizontal, DSLayout.screenPadding)
                }
            }
            .padding(.vertical, DSLayout.contentGap)
        }
    }
    
    @ViewBuilder
    private func downloadControlView(book: Book) -> some View {
        switch viewModel.downloadState {
        case .notDownloaded:
            Button(action: viewModel.downloadBook) {
                Label("Download", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.bordered)
            .tint(DSColor.accent)
            
        case .queued:
            Button(action: viewModel.cancelDownload) {
                Label("Cancel Queue", systemImage: "pause.circle")
            }
            .buttonStyle(.bordered)
            .tint(DSColor.warning)
            
        case .downloading(let progress):
            ProgressView(value: progress) {
                Text(String(format: "Downloading %.0f%%", progress * 100))
                    .font(DSText.metadata)
            }
            .progressViewStyle(.linear)
            .tint(DSColor.accent)
            
        case .downloaded:
            Menu {
                Button(role: .destructive, action: viewModel.deleteDownloadedBook) {
                    Label("Delete Download", systemImage: "trash")
                }
            } label: {
                Label("Downloaded", systemImage: "checkmark.circle.fill")
                    .foregroundColor(DSColor.downloaded)
                    .font(DSText.button)
            }
        }
    }
    
    private func playBook(_ book: Book) {
        guard let api = container.apiClient else { return }
        
        Task {
            let useCase = PlayBookUseCase()
            do {
                try await useCase.execute(
                    book: book,
                    api: api,
                    player: container.player,
                    downloadManager: container.downloadManager,
                    appState: appState,
                    restoreState: true,
                    autoPlay: true
                )
                playerStateManager.showPlayerBasedOnSettings()
                dismiss()
            } catch {
                AppLogger.general.error("Failed to play book: \(error)")
            }
        }
    }
    
    private func playChapter(_ book: Book, at index: Int) {
        guard let api = container.apiClient else { return }
        
        Task {
            let useCase = PlayBookUseCase()
            do {
                // Start playing the book
                try await useCase.execute(
                    book: book,
                    api: api,
                    player: container.player,
                    downloadManager: container.downloadManager,
                    appState: appState,
                    restoreState: false, // Don't restore, we want to jump to chapter
                    autoPlay: true
                )
                
                // Jump to the selected chapter
                container.player.setCurrentChapter(index: index)
                
                playerStateManager.showPlayerBasedOnSettings()
                dismiss()
            } catch {
                AppLogger.general.error("Failed to play chapter: \(error)")
            }
        }
    }
}
