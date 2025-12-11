import SwiftUI

struct BookmarkRow: View {
    let enriched: EnrichedBookmark
    var showBookInfo: Bool = true
    let onTap: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    // FIX: Use @Environment(Type.self)
    @Environment(ThemeManager.self) var theme
    
    @State private var isPressed = false
    @State private var showDeleteConfirm = false
    
    var body: some View {
        HStack(spacing: DSLayout.elementGap) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.orange, Color.orange.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: DSLayout.largeIcon, height: DSLayout.largeIcon)
                
                Image(systemName: "bookmark.fill")
                    .font(DSText.button)
                    .foregroundColor(.white)
            }
            .padding(.leading, DSLayout.elementPadding)
            
            VStack(alignment: .leading, spacing: DSLayout.elementGap) {
                Text(enriched.bookmark.title)
                    .font(DSText.emphasized)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .foregroundColor(theme.textColor) // Using theme here
                
                HStack(spacing: DSLayout.elementGap) {
                    HStack(spacing: DSLayout.tightGap) {
                        Image(systemName: "clock")
                            .font(DSText.metadata)
                        Text(enriched.bookmark.formattedTime)
                            .font(DSText.metadata)
                            .monospacedDigit()
                    }
                    .foregroundColor(.secondary)
                    
                    HStack(spacing: DSLayout.tightGap) {
                        Image(systemName: "calendar")
                            .font(DSText.metadata)
                        Text(enriched.bookmark.createdAt.formatted(date: .abbreviated, time: .omitted))
                            .font(DSText.metadata)
                    }
                    .foregroundColor(.secondary)
                                        
                    if showBookInfo {
                        if enriched.isBookLoaded {
                            Text(enriched.bookTitle)
                                .font(DSText.metadata)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        } else {
                            HStack(spacing: 4) {
                                ProgressView()
                                    .scaleEffect(0.6)
                                Text("Loading...")
                                    .font(.caption)
                            }
                            .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            Spacer()
            
            HStack(spacing: DSLayout.tightGap) {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 16))
                        .foregroundColor(.accentColor)
                        .frame(width: 32, height: 32)
                        .background(Color.accentColor.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                
                Button(action: { showDeleteConfirm = true }) {
                    Image(systemName: "trash")
                        .font(.system(size: 16))
                        .foregroundColor(.red)
                        .frame(width: 32, height: 32)
                        .background(Color.red.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.trailing, DSLayout.elementPadding)
        }
        .padding(DSLayout.elementPadding)
        .background(
            RoundedRectangle(cornerRadius: DSCorners.element)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(
                    color: Color.black.opacity(0.05),
                    radius: isPressed ? 4 : 8,
                    x: 0,
                    y: isPressed ? 2 : 4
                )
        )
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeIn(duration: 0.1)) {
                isPressed = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeOut(duration: 0.1)) {
                    isPressed = false
                }
                onTap()
            }
        }
        .alert("Delete Bookmark?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("This action cannot be undone.")
        }
    }
}
