import SwiftUI

struct BookmarkSheet: View {
    let player: AudioPlayer
    @Binding var isPresented: Bool

    @State private var bookmarkTitle = ""
    @State private var isCreating = false
    @FocusState private var isTitleFocused: Bool

    private var defaultTitle: String {
        player.currentChapter?.title
            ?? "Bookmark at \(TimeFormatter.formatTime(player.absoluteCurrentTime))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Bookmark name", text: $bookmarkTitle, axis: .vertical)
                        .focused($isTitleFocused)
                        .font(.body)
                        .lineLimit(1...4)
                        .textInputAutocapitalization(.sentences)
                        .submitLabel(.done)
                } footer: {
                    Text("Position: \(TimeFormatter.formatTime(player.absoluteCurrentTime))")
                }
            }
            .navigationTitle("New Bookmark")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                        .disabled(isCreating)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: createBookmark) {
                        if isCreating {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        } else {
                            Text("Save").bold()
                        }
                    }
                    .disabled(!canSave)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            bookmarkTitle = defaultTitle
        }
        .task {
            // Short yield to ensure sheet is fully presented before keyboard opens
            try? await Task.sleep(nanoseconds: 150_000_000)
            isTitleFocused = true
        }
    }

    private var canSave: Bool {
        !bookmarkTitle.trimmingCharacters(in: .whitespaces).isEmpty && !isCreating
    }

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
                    isPresented = false
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            } catch {
                await MainActor.run {
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    isCreating = false
                    AppLogger.general.error("[Bookmark] ❌ Failed: \(error)")
                }
            }
        }
    }
}
