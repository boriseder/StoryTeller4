 import Foundation

import UIKit

// MARK: - Device Utilities
enum DeviceUtils {
    static func getDeviceIdentifier() -> String {
        return UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
    }
    
    static func createPlaybackRequest() -> PlaybackSessionRequest {
        PlaybackSessionRequest(
            deviceInfo: PlaybackSessionRequest.DeviceInfo(
                clientVersion: "1.0.0",
                deviceId: getDeviceIdentifier(),
                clientName: getClientName()
            ),
            supportedMimeTypes: ["audio/mpeg", "audio/mp4", "audio/m4a", "audio/flac"],
            mediaPlayer: "AVPlayer"
        )
    }
    
    private static func getClientName() -> String {
            return "iOS AudioBook Client"
    }
}
