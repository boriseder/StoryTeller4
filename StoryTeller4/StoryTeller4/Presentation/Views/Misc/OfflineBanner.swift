
import SwiftUI

struct OfflineBanner: View {
    @EnvironmentObject var appState: AppStateManager

    var body: some View {
        
        if !appState.isDeviceOnline {
            
            HStack(spacing: DSLayout.contentGap) {
                Image(systemName: appState.isDeviceOnline ? "wifi" : "wifi.slash")
                    .font(DSText.subsectionTitle)
                    .foregroundColor(.white)
                
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(appState.isDeviceOnline ? "Online" : "Offline")
                        .font(DSText.prominent)
                        .foregroundColor(.white)
                    
                    Text("isDeviceOnline: \(String(describing: appState.isDeviceOnline))")
                        .font(DSText.metadata)
                        .foregroundColor(.white)
                    Text("serverReachable: \(String(describing: appState.isServerReachable))")                        .font(DSText.metadata)
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                Divider()
                    .frame(height: 40)
                
                Button {
                    Task {
                        await appState.checkServerReachability()
                    }
                } label: {
                    Image(systemName: appState.isDeviceOnline ? "icloud" : "icloud.slash")
                        .font(DSText.button)
                        .foregroundColor(Color.white)
                }
            }
            .padding(DSLayout.elementPadding)
            .background(appState.isDeviceOnline ? Color.green : Color.red.opacity(0.8))
        }
    }
    
    private func formatTimestamp(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

}

