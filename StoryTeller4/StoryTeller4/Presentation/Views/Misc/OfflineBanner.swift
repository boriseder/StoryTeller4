import SwiftUI

struct OfflineBanner: View {
    // FIX: Use @Environment(Type.self)
    @Environment(AppStateManager.self) var appState
    
    var body: some View {
        if !appState.isDeviceOnline || !appState.isServerReachable {
            HStack(spacing: DSLayout.contentGap) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 16, weight: .semibold))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Offline Mode")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    Text(reasonText)
                        .font(.caption)
                        .opacity(0.9)
                }
                
                Spacer()
                
                if !appState.isDeviceOnline {
                    Button("Reconnect") {
                        appState.debugToggleDeviceOnline()
                    }
                    .font(.caption)
                    .fontWeight(.bold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.2))
                    .clipShape(Capsule())
                }
            }
            .padding()
            .background(Color.orange)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: DSCorners.element))
            .padding(.horizontal, DSLayout.screenPadding)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
    
    private var reasonText: String {
        if !appState.isDeviceOnline {
            return "No internet connection"
        } else {
            return "Server unreachable"
        }
    }
}
