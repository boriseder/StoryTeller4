import UIKit
import SwiftUI

@main
struct StoryTeller4App: App {
    @Environment(\.scenePhase) private var scenePhase
    
    // MIGRATION: Use @State instead of @StateObject for @Observable types
    @State private var appState = AppStateManager.shared
    @State private var theme = ThemeManager()
    @State private var dependencies = DependencyContainer.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                // MIGRATION: Use modern .environment injection
                .environment(appState)
                .environment(theme)
                .environment(dependencies)
                .preferredColorScheme(theme.colorScheme)
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                    handleMemoryWarning()
                }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            handleScenePhaseChange(from: oldPhase, to: newPhase)
        }
    }

    // MARK: - Scene Phase Handling
    
    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            handleBecameActive()
        case .inactive:
            handleWillResignActive()
        case .background:
            handleEnteredBackground()
        @unknown default:
            break
        }
    }
    
    private func handleBecameActive() {
        AppLogger.general.info("[App] App became active")
        NotificationCenter.default.post(name: .init("AppWillEnterForeground"), object: nil)
    }
    
    private func handleWillResignActive() {
        AppLogger.general.info("[App] App will resign active")
    }
    
    private func handleEnteredBackground() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastBackgroundTime")
        AppLogger.general.info("[App] App entered background")
                        
        Task.detached(priority: .background) {
            if UserDefaults.standard.bool(forKey: "auto_cache_cleanup") {
                await CoverCacheManager.shared.optimizeCache()
            }
        }
    }
   
    // MARK: - Memory Warning
    
    private func handleMemoryWarning() {
        AppLogger.general.warn("[App] Memory warning received - triggering cleanup")
        
        Task { @MainActor in
            CoverCacheManager.shared.triggerCriticalCleanup()
        }
        
        Task {
            await CoverDownloadManager.shared.cancelAllDownloads()
        }
        
        AppLogger.general.info("[App] Memory cleanup completed")
    }
}
