import SwiftUI

struct BookmarkRow: View {
    let enriched: EnrichedBookmark
    var showBookInfo: Bool = true
    
    var body: some View {
        HStack(spacing: 16) {
            // Leading: Icon
            bookmarkIcon
            
            // Center: Content
            VStack(alignment: .leading, spacing: 4) {
                Text(enriched.bookmark.title)
                    .font(.headline)
                    .lineLimit(2)
                
                // Metadata Stack
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 10))
                        Text(enriched.bookmark.formattedTime)
                            .monospacedDigit()
                    }
                    .foregroundColor(.accentColor)
                    .font(.subheadline.weight(.medium))
                    
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.system(size: 10))
                        Text(enriched.bookmark.createdAt.formatted(.dateTime.day().month().year(.twoDigits)))
                    }
                    .foregroundColor(.secondary)
                    .font(.caption)
                    
                    if showBookInfo {
                        HStack(spacing: 4) {
                            Image(systemName: "book.closed")
                                .font(.system(size: 10))
                            if enriched.isBookLoaded {
                                Text(enriched.bookTitle)
                                    .lineLimit(1)
                            } else {
                                ProgressView()
                                    .scaleEffect(0.5)
                            }
                        }
                        .foregroundColor(.secondary)
                        .font(.caption)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }
    
    private var bookmarkIcon: some View {
        Image(systemName: "bookmark.fill")
            .font(.title3)
            .foregroundColor(.white)
            .frame(width: 40, height: 40)
            .background(Color.accentColor.gradient)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
