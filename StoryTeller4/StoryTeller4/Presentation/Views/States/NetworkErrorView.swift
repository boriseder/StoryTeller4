
import SwiftUI

struct NetworkErrorView: View {
    let issueType: ConnectionIssueType
    let onRetry: () -> Void
    let onViewDownloads: () -> Void
    let onSettings: () -> Void

    var body: some View {
        ZStack {
            Color.white.opacity(0.3)
                .frame(width: 360, height: 480)
                .cornerRadius(DSCorners.comfortable)
                .blur(radius: 0.5)
            
            VStack(spacing: DSLayout.contentGap) {
                Image(systemName: issueType.systemImage)
                    .font(.system(size: 32))
                    .foregroundStyle(.black.gradient)
                    .frame(width: 40, height: 40)

                VStack(spacing: DSLayout.contentGap) {
                    Text(issueType.userMessage)
                        .font(DSText.itemTitle)

                    Text(issueType.detailMessage)
                        .font(DSText.footnote)
                        .multilineTextAlignment(.center)
                }
                VStack(spacing: 12) {
                   // if issueType.canRetry {
                        Button(action: onRetry) {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                Text("Retry Connection")
                            }
                            .font(DSText.detail)
                            .foregroundColor(.white)
                            .padding(.horizontal, DSLayout.elementPadding)
                            .padding(.vertical, DSLayout.elementPadding)
                            .background(Color.accentColor)
                            .clipShape(Capsule())
                        }
                    //}
                    
                    Button(action: onSettings) {
                        Text("Check Settings")
                            .font(.subheadline)
                            .foregroundColor(.accentColor)
                    }
                }
            }
            .padding(.horizontal, 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.red)
        }
    }
}
