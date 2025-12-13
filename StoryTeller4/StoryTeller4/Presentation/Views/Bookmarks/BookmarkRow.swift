import SwiftUI

struct BookmarkRow: View {
    let enriched: EnrichedBookmark
    var showBookInfo: Bool = true
    let onTap: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    @Environment(ThemeManager.self) var theme
    @State private var isPressed = false
    @State private var showDeleteConfirm = false
    
    var body: some View {
        Button(action: handleTap) {
            HStack(spacing: 16) {
                // Leading: Icon
                bookmarkIcon
                
                // Center: Content
                VStack(alignment: .leading, spacing: 6) {
                    // Title (prominent)
                    Text(enriched.bookmark.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(theme.textColor)
                        .lineLimit(2)
                    
                    // Metadata Stack
                    VStack(alignment: .leading, spacing: 3) {
                        // Primary: Time (most important for bookmarks!)
                        HStack(spacing: 6) {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.accentColor)
                            Text(enriched.bookmark.formattedTime)
                                .font(.system(size: 14, weight: .medium))
                                .monospacedDigit()
                                .foregroundColor(.accentColor)
                        }
                        
                        // Secondary: Date & Book
                        HStack(spacing: 12) {
                            HStack(spacing: 4) {
                                Image(systemName: "calendar")
                                    .font(.system(size: 10))
                                Text(enriched.bookmark.createdAt.formatted(.dateTime.day().month().year(.twoDigits)))
                                    .font(.system(size: 13))
                            }
                            
                            if showBookInfo {
                                HStack(spacing: 4) {
                                    Image(systemName: "book.closed.fill")
                                        .font(.system(size: 10))
                                    
                                    if enriched.isBookLoaded {
                                        Text(enriched.bookTitle)
                                            .font(.system(size: 13))
                                            .lineLimit(1)
                                    } else {
                                        ProgressView()
                                            .scaleEffect(0.6)
                                    }
                                }
                            }
                        }
                        .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Trailing: Actions
                actionButtons
            }
            .padding(16)
            .background(rowBackground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .confirmationDialog("Delete Bookmark?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
    }
    
    // MARK: - Subviews
    
    private var bookmarkIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: [Color.orange, Color.orange.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 44, height: 44)
            
            Image(systemName: "bookmark.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
        }
    }
    
    private var actionButtons: some View {
        VStack(spacing: 8) {
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.accentColor)
                    .frame(width: 32, height: 32)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            
            Button(action: { showDeleteConfirm = true }) {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.red)
                    .frame(width: 32, height: 32)
                    .background(Color.red.opacity(0.12))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }
    
    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(.secondarySystemGroupedBackground))
            .shadow(
                color: Color.black.opacity(0.08),
                radius: isPressed ? 2 : 6,
                x: 0,
                y: isPressed ? 1 : 3
            )
    }
    
    // MARK: - Actions
    
    private func handleTap() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        
        withAnimation(.easeIn(duration: 0.1)) {
            isPressed = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isPressed = false
            }
            onTap()
        }
    }
}
