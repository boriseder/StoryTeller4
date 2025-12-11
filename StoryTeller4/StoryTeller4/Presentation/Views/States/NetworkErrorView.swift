import SwiftUI

struct NetworkErrorView: View {
    let issue: ConnectionIssueType
    let retryAction: () -> Void
    
    var body: some View {
        VStack(spacing: DSLayout.contentGap) {
            Image(systemName: issue.systemImage)
                .font(.system(size: 50))
                .foregroundColor(.orange)
            
            Text("Connection Issue")
                .font(DSText.body)
            
            Text(issueDescription)
                .font(DSText.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            
            Button("Retry Connection") {
                retryAction()
            }
            .buttonStyle(.borderedProminent)
            .padding(.top)
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .padding()
    }
    
    private var issueDescription: String {
        switch issue {
        case .noInternet:
            return "No internet connection detected. Please check your network settings."
        case .serverUnreachable:
            return "Cannot reach the server. Please check the URL and ensure the server is online."
        case .serverError:
            return "The server encountered an error. Please try again later."
        }
    }
}

// FIX: Extension to add systemImage to the enum locally
extension ConnectionIssueType {
    var systemImage: String {
        switch self {
        case .noInternet:
            return "wifi.slash"
        case .serverUnreachable:
            return "server.rack"
        case .serverError:
            return "exclamationmark.triangle"
        }
    }
}
