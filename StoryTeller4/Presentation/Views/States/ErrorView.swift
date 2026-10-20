
import SwiftUI

struct ErrorView: View {
    let error: String
    
    var body: some View {
        ZStack {
            Color.white.opacity(0.3)
                .frame(width: 360, height: 240)
                .cornerRadius(DSCorners.comfortable)
                .blur(radius: 0.5)
            
            VStack(spacing: DSLayout.contentGap) {
                
                Image(systemName: "icloud.slash")
                    .font(.system(size: 32))
                    .foregroundStyle(.black.gradient)
                    .frame(width: 40, height: 40)

                VStack(spacing: 12) {
                    Text("Connection error")
                        .font(DSText.itemTitle)

                    Text(error)
                        .font(DSText.footnote)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 40)
            }
            .padding(40)
        }
    }
}
