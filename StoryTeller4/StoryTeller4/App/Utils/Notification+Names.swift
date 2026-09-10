import Foundation

// MARK: - Strongly-Typed Notification Names
extension Notification.Name {
    static let appWillEnterForeground = Notification.Name("AppWillEnterForeground")
    static let refreshCurrentView = Notification.Name("RefreshCurrentView")
    static let serverSettingsChanged = Notification.Name("ServerSettingsChanged")
    static let showSettings = Notification.Name("ShowSettings")
}
