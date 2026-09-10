import SwiftUI
import Observation
import Combine

@MainActor
@Observable
class PlayerViewModel {
    // MARK: - UI State
    var showingChaptersList: Bool = false
    var showingSleepTimer: Bool = false
    var showingPlaybackSettings: Bool = false
    var isDraggingSlider: Bool = false
    var sliderValue: Double = 0
    
    // MARK: - Dependencies
    let player: AudioPlayer
    let api: AudiobookshelfClient
    
    init(player: AudioPlayer, api: AudiobookshelfClient) {
        self.player = player
        self.api = api
        self.sliderValue = player.currentTime
    }
    
    // MARK: - Actions
    func updateSliderValue(_ newValue: Double) {
        sliderValue = newValue
        if !isDraggingSlider {
            player.seek(to: newValue)
        }
    }
    
    func onSliderEditingChanged(_ editing: Bool) {
        if editing {
            isDraggingSlider = true
        } else {
            isDraggingSlider = false
            player.seek(to: sliderValue)
        }
    }
    
    func updateSliderFromPlayer(_ time: Double) {
        if !isDraggingSlider {
            sliderValue = time
        }
    }
}
