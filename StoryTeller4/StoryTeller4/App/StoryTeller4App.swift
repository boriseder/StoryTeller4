import UIKit
import SwiftUI

@main
struct StoryTeller4App: App {
    @Environment(\.scenePhase) private var scenePhase
    
    // Alle diese Objekte sind jetzt MainActor, das ist sicher in SwiftUI Views/App struct
    @StateObject private var appState = AppStateManager.shared
    @StateObject private var theme = ThemeManager()
    @StateObject private var dependencies = DependencyContainer.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(theme)
                .environmentObject(dependencies)
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
                        
        // Cache cleanup in background (detached is correct for background work)
        Task.detached(priority: .background) {
            if UserDefaults.standard.bool(forKey: "auto_cache_cleanup") {
                // Must interact with actor from async context
                await CoverCacheManager.shared.optimizeCache()
            }
        }
    }
   
    // MARK: - Memory Warning
    
    private func handleMemoryWarning() {
        AppLogger.general.warn("[App] Memory warning received - triggering cleanup")
        
        // Access MainActor singleton
        Task { @MainActor in
            CoverCacheManager.shared.triggerCriticalCleanup()
        }
        
        // Access Actor singleton
        Task {
            await CoverDownloadManager.shared.cancelAllDownloads()
        }
        
        AppLogger.general.info("[App] Memory cleanup completed")
    }
}
