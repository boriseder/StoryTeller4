import SwiftUI

struct PlayerView: View {
    @State private var viewModel: PlayerViewModel
    @EnvironmentObject var appState: AppStateManager
    @EnvironmentObject var theme: ThemeManager
    
    // Inject dependencies directly
    init(player: AudioPlayer, api: AudiobookshelfClient) {
        _viewModel = State(initialValue: PlayerViewModel(player: player, api: api))
    }
    
    var body: some View {
        // Use @Bindable to create bindings for the @Observable view model
        @Bindable var vm = viewModel
        
        VStack(spacing: DSLayout.contentGap) {
            // Book Info
            if let book = viewModel.player.book {
                VStack(spacing: 8) {
                    Text(book.title)
                        .font(.title3)
                        .fontWeight(.bold)
                        .lineLimit(1)
                        .foregroundColor(theme.textColor)
                    
                    Text(book.author ?? "Unknown Author")
                        .font(.subheadline)
                        .foregroundColor(theme.textColor.opacity(0.8))
                        .lineLimit(1)
                }
                .padding(.horizontal)
            }
            
            Spacer()
            
            // Progress Slider
            VStack(spacing: 8) {
                Slider(
                    value: $vm.sliderValue,
                    in: 0...viewModel.player.duration,
                    onEditingChanged: viewModel.onSliderEditingChanged
                )
                .accentColor(theme.accent)
                
                HStack {
                    Text(TimeFormatter.formatTime(viewModel.sliderValue))
                    Spacer()
                    Text(TimeFormatter.formatTime(viewModel.player.duration))
                }
                .font(.caption)
                .foregroundColor(theme.textColor.opacity(0.7))
                .monospacedDigit()
            }
            .padding(.horizontal, DSLayout.screenPadding)
            
            // Controls
            HStack(spacing: 40) {
                Button(action: { viewModel.player.seek15SecondsBack() }) {
                    Image(systemName: "gobackward.15")
                        .font(.system(size: 28))
                }
                
                Button(action: { viewModel.player.togglePlayPause() }) {
                    Image(systemName: viewModel.player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 64))
                        .symbolRenderingMode(.hierarchical)
                }
                
                Button(action: { viewModel.player.seek15SecondsForward() }) {
                    Image(systemName: "goforward.15")
                        .font(.system(size: 28))
                }
            }
            .foregroundColor(theme.accent)
            
            Spacer()
            
            // Bottom Tools
            HStack(spacing: 30) {
                Button(action: { viewModel.showingPlaybackSettings = true }) {
                    Image(systemName: "speedometer")
                }
                
                Button(action: { viewModel.showingSleepTimer = true }) {
                    Image(systemName: "moon.zzz")
                }
                
                Button(action: { viewModel.showingChaptersList = true }) {
                    Image(systemName: "list.bullet")
                }
            }
            .font(.system(size: 20))
            .foregroundColor(theme.textColor)
            .padding(.bottom, DSLayout.comfortPadding)
        }
        .onReceive(viewModel.player.$currentTime) { time in
            viewModel.updateSliderFromPlayer(time)
        }
        .sheet(isPresented: $vm.showingChaptersList) {
            // FIX: Removed 'isPresented' argument
            ChaptersListView(player: viewModel.player)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $vm.showingSleepTimer) {
            SleepTimerView()
                .presentationDetents([.medium])
        }
    }
}
