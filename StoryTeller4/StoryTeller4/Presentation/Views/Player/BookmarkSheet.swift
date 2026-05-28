import SwiftUI

// Just a name field, pre-filled, and two buttons.
// The user is listening right now — they know where they are.
struct BookmarkSheet: View {
    let player: AudioPlayer
    @Binding var isPresented: Bool

    @State private var bookmarkTitle = ""
    @State private var isCreating = false
    @FocusState private var isTitleFocused: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var defaultTitle: String {
        player.currentChapter?.title
            ?? "Bookmark at \(TimeFormatter.formatTime(player.absoluteCurrentTime))"
    }

    // Adaptive sheet height — grows with Dynamic Type so the text field
    // and buttons are never clipped at accessibility text sizes.
    private var sheetHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 280 : 200
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 36, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 24)

            TextField("Bookmark name", text: $bookmarkTitle, axis: .vertical)
                .focused($isTitleFocused)
                .font(.body)
                .lineLimit(1...2)
                .textInputAutocapitalization(.sentences)
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, DSLayout.screenPadding)

            Spacer(minLength: 20)

            HStack(spacing: 12) {
                Button("Cancel") { isPresented = false }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(.secondarySystemGroupedBackground))
                    .foregroundColor(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                Button(action: createBookmark) {
                    Group {
                        if isCreating {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text("Save").fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(canSave ? Color.accentColor : Color.accentColor.opacity(0.3))
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .disabled(!canSave)
            }
            .padding(.horizontal, DSLayout.screenPadding)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .presentationDetents([.height(sheetHeight)])
        .presentationDragIndicator(.hidden)
        .onAppear {
            bookmarkTitle = defaultTitle
        }
        // .task runs after the view is in the hierarchy and the sheet has
        // begun presenting. A minimal async yield is enough — no hardcoded
        // 0.5s delay. Keyboard appears as soon as the sheet settles.
        .task {
            await Task.yield()
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
                    // Dismiss first, then fire haptic — the success pulse lands
                    // after the sheet has started closing, not before, which
                    // prevents the animation and vibration from cancelling each other.
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
