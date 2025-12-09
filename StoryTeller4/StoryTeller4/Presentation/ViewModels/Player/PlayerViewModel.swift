import SwiftUI

@MainActor
class PlayerViewModel: ObservableObject {
    // MARK: - Published UI State
    @Published var controlState = PlayerControlState()
    
    let player: AudioPlayer
    let api: AudiobookshelfClient
    
    // Convenience accessors for view binding
    var showingChaptersList: Bool {
        get { controlState.showingChaptersList }
        set { controlState.showingChaptersList = newValue }
    }
    
    var showingSleepTimer: Bool {
        get { controlState.showingSleepTimer }
        set { controlState.showingSleepTimer = newValue }
    }
    
    var showingPlaybackSettings: Bool {
        get { controlState.showingPlaybackSettings }
        set { controlState.showingPlaybackSettings = newValue }
    }
    
    var isDraggingSlider: Bool {
        get { controlState.isDraggingSlider }
        set { controlState.isDraggingSlider = newValue }
    }
    
    var sliderValue: Double {
        get { controlState.sliderValue }
        set { controlState.sliderValue = newValue }
    }
    
    init(player: AudioPlayer, api: AudiobookshelfClient) {
        self.player = player
        self.api = api
        
        self.controlState.sliderValue = player.currentTime
    }
    
    // MARK: - Actions
    func updateSliderValue(_ newValue: Double) {
        controlState.updateSliderValue(newValue)
        if !controlState.isDraggingSlider {
            player.seek(to: newValue)
        }
    }
    
    func onSliderEditingChanged(_ editing: Bool) {
        if editing {
            controlState.startDragging()
        } else {
            controlState.stopDragging()
            player.seek(to: controlState.sliderValue)
        }
    }
    
    func updateSliderFromPlayer(_ time: Double) {
        if !controlState.isDraggingSlider {
            controlState.updateSliderValue(time)
        }
    }
}
