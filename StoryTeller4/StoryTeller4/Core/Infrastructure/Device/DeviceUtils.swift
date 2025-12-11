import Foundation
import UIKit

enum DeviceUtils {
    
    // This must run on MainActor to access UIDevice
    @MainActor
    static func createPlaybackRequest() -> PlaybackSessionRequest {
        PlaybackSessionRequest(
            deviceInfo: PlaybackSessionRequest.DeviceInfo(
                clientVersion: getClientVersion(),
                deviceId: getDeviceIdentifier(),
                clientName: getClientName()
            ),
            supportedMimeTypes: ["audio/mpeg", "audio/mp4", "audio/aac"],
            mediaPlayer: "iOS App"
        )
    }
    
    private static func getClientVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    
    @MainActor
    private static func getDeviceIdentifier() -> String? {
        UIDevice.current.identifierForVendor?.uuidString
    }
    
    @MainActor
    private static func getClientName() -> String? {
        "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
    }
}
