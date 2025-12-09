import Foundation

struct PlayerControlState {
    var showingChaptersList: Bool = false
    var showingSleepTimer: Bool = false
    var showingPlaybackSettings: Bool = false
    var isDraggingSlider: Bool = false
    var sliderValue: Double = 0
    
    mutating func updateSliderValue(_ newValue: Double) {
        sliderValue = newValue
    }
    
    mutating func startDragging() {
        isDraggingSlider = true
    }
    
    mutating func stopDragging() {
        isDraggingSlider = false
    }
}
