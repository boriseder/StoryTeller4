
import SwiftUI

struct NoDownloadsView: View {
    var body: some View {
        ZStack {
            Color.white.opacity(0.3)
                .frame(width: 360, height: 240)
                .cornerRadius(DSCorners.comfortable)
                .blur(radius: 0.5)

            VStack(spacing: DSLayout.contentGap) {
                Image(systemName: "arrow.down.circle.badge.xmark")
                    .font(.system(size: 32))
                    .foregroundStyle(.black.gradient)
                    .frame(width: 40, height: 40)

                VStack(spacing: 8) {
                    Text("No downloaded books found")
                        .font(DSText.itemTitle)

                    Text("You haven't downloaded any books.")
                        .font(DSText.footnote)
                        .multilineTextAlignment(.center)
                    
                    Text("Download books to enjoy them offline.")
                        .font(DSText.footnote)
                        .multilineTextAlignment(.center)

                }
            }
            .padding(.horizontal, 40)
        }
    }
}
