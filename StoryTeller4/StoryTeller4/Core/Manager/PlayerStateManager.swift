import SwiftUI

class PlayerStateManager: ObservableObject {
    @Published var mode: PlayerMode = .hidden
    
    func showFullscreen() {
        mode = .fullscreen
    }
    
    func showMini() {
        mode = .mini
    }
    
    func dismissFullscreen() {
        mode = .mini
    }
    
    func hideMiniPlayer() {
        if mode == .mini {
            mode = .hidden
        }
    }
    
    func showPlayerBasedOnSettings() {
        let openFullscreen = UserDefaults.standard.bool(forKey: "open_fullscreen_player")
        mode = openFullscreen ? .fullscreen : .mini
    }

    func updatePlayerState(hasBook: Bool) {
        mode = hasBook ? (mode == .hidden ? .mini : mode) : .hidden
    }
    
    func toggleMiniPlayer() {
        mode = (mode == .mini) ? .hidden : .mini
    }
    
    func reset() {
        mode = .hidden
    }
    
    var isPlayerVisible: Bool {
        mode != .hidden
    }
}

enum PlayerMode {
    case hidden
    case mini
    case fullscreen
}
