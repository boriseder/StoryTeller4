import SwiftUI

struct LoadingView: View {
    let message: String
    
    init(message: String = "Syncing...") {
        self.message = message
    }
    
    var body: some View {
            /*
            Color.white.opacity(0.3)
                .frame(width: 240, height: 120)
                .cornerRadius(DSCorners.comfortable)
                .blur(radius: 0.5)
            */
            VStack(spacing: DSLayout.contentGap) {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.5)

                Text(message)
                    .font(DSText.footnote)
                    .foregroundColor(.white)

            }
            .frame(width: 60, height: 60)
    }
}

