import SwiftUI
import AVKit

// MARK: - AVRoutePickerView Wrapper
struct AVRoutePickerViewWrapper: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let routePickerView = AVRoutePickerView()
        routePickerView.backgroundColor = UIColor.clear
        routePickerView.tintColor = UIColor.systemBlue
        return routePickerView
    }
    
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

// MARK: - Player Marquee Text (UX Improvement)
struct PlayerMarqueeText: View {
    let text: String
    let font: Font
    @State private var animate = false
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(text)
                .font(font)
                .lineLimit(1)
                .fixedSize()
        }
        .disabled(true) // Disable interaction so taps pass through to container
    }
}

// MARK: - Player Jump Overlay View (UX Improvement)
struct PlayerJumpOverlayView: View {
    let direction: JumpDirection
    
    enum JumpDirection {
        case forward
        case backward
    }
    
    @State private var opacity: Double = 1.0
    @State private var scale: CGFloat = 0.8
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .clipShape(Circle())
            
            Image(systemName: direction == .forward ? "goforward.15" : "gobackward.15")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.white)
        }
        .frame(width: 80, height: 80)
        .scaleEffect(scale)
        .opacity(opacity)
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                scale = 1.2
            }
            withAnimation(.easeOut(duration: 0.8)) {
                opacity = 0
            }
        }
    }
}

// MARK: - Chapter Row View (Legacy - keeping for compatibility)
struct ChapterRowView: View {
    let chapter: Chapter
    let chapterIndex: Int
    let currentChapterIndex: Int
    let onTap: () -> Void
    
    private var isCurrentChapter: Bool {
        chapterIndex == currentChapterIndex
    }
    
    var body: some View {
        Button(action: {
            AppLogger.general.debug("[ChapterRow] Chapter \(chapterIndex) tapped: \(chapter.title)")
            onTap()
            
            // Haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(chapter.title)
                        .font(.subheadline)
                        .fontWeight(isCurrentChapter ? .semibold : .regular)
                        .foregroundColor(isCurrentChapter ? .accentColor : .primary)
                        .multilineTextAlignment(.leading)
                    
                    if let start = chapter.start {
                        Text(TimeFormatter.formatTime(start))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                }
                
                Spacer()
                
                if isCurrentChapter {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Enhanced Playback Settings View
struct PlaybackSettingsView: View {
    let player: AudioPlayer
    
    @Environment(\.dismiss) private var dismiss
    
    private let playbackRateOptions: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
    
    var body: some View {
        NavigationView {
            VStack(spacing: 32) {
                playbackSpeedSection
                
                quickAccessTips
                
                Spacer()
            }
            .padding()
            .navigationTitle("Playback Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    // MARK: - Playback Speed Section
    
    private var playbackSpeedSection: some View {
        VStack(spacing: 16) {
            Text("Playback Speed")
                .font(.headline)
            
            VStack(spacing: 12) {
                Text("\(player.playbackRate, specifier: "%.2f")x")
                    .font(.title)
                    .fontWeight(.bold)
                    .monospacedDigit()
                
                Slider(
                    value: Binding(
                        get: { Double(player.playbackRate) },
                        set: { newValue in
                            AppLogger.general.debug("[PlaybackSettings] Speed changed to: \(newValue)x")
                            player.setPlaybackRate(newValue)
                        }
                    ),
                    in: 0.5...2.0,
                    step: 0.05
                ) { editing in
                    if !editing {
                        AppLogger.general.debug("[PlaybackSettings] Speed slider interaction ended, rate applied: \(player.playbackRate)")
                        
                        // Haptic feedback on release
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                    }
                }
                .accentColor(.primary)
                
                HStack {
                    Text("0.5x")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text("2.0x")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Quick Speed Buttons
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(playbackRateOptions, id: \.self) { rate in
                    QuickSpeedButton(
                        rate: rate,
                        isSelected: abs(Double(player.playbackRate) - rate) < 0.01,
                        action: {
                            AppLogger.general.debug("[PlaybackSettings] Quick speed button: \(rate)x")
                            player.setPlaybackRate(rate)
                            
                            // Haptic feedback
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.impactOccurred()
                        }
                    )
                }
            }
        }
    }
    
    // MARK: - Quick Access Tips
    
    private var quickAccessTips: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text("Tip: Tap speed button in player for quick access")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } icon: {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)
                    .font(.caption)
            }
            
            Label {
                Text("Use fine-tune slider for precise speed control")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } icon: {
                Image(systemName: "slider.horizontal.3")
                    .foregroundColor(.accentColor)
                    .font(.caption)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}

// MARK: - Quick Speed Button Component

struct QuickSpeedButton: View {
    let rate: Double
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: action) {
            Text(formatRate(rate))
                .font(.caption)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.accentColor : Color.gray.opacity(0.2))
                )
                .foregroundColor(isSelected ? .white : .primary)
        }
        .buttonStyle(ScaleButtonStyle())
    }
    
    private func formatRate(_ rate: Double) -> String {
        if rate.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(rate))x"
        } else {
            return String(format: "%.2fx", rate)
        }
    }
}

// MARK: - Scale Button Style

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
