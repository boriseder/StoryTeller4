import SwiftUI
import AVKit

// MARK: - AVRoutePickerView Wrapper

struct AVRoutePickerViewWrapper: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.backgroundColor = .clear
        // Use the app's accent color, not a hardcoded systemBlue.
        // This respects ThemeManager and any custom accent set in Assets.
        view.tintColor = UIColor(Color.accentColor)
        // Audio-only app — hide video output devices (Apple TV etc.)
        // to keep the picker clean and relevant.
        view.prioritizesVideoDevices = false
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        // Re-apply tint on trait collection changes (dark/light mode, accent override).
        uiView.tintColor = UIColor(Color.accentColor)
    }
}

// MARK: - Player Jump Overlay View

struct PlayerJumpOverlayView: View {
    let direction: JumpDirection

    enum JumpDirection {
        case forward, backward
    }

    @State private var scale: CGFloat = 0.7
    @State private var opacity: Double = 1.0

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.4))
            Image(systemName: direction == .forward ? "goforward.15" : "gobackward.15")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.white)
        }
        .frame(width: 80, height: 80)
        .scaleEffect(scale)
        .opacity(opacity)
        .onAppear {
            // Spring up to 1.0, then fade out — not to 1.2.
            // Overshooting to 1.2 left a large semi-transparent circle
            // hanging mid-fade; stopping at 1.0 feels natural and premium.
            withAnimation(.spring(response: 0.25, dampingFraction: 0.55)) {
                scale = 1.0
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.15)) {
                opacity = 0
            }
        }
    }
}

// MARK: - Scale Button Style
//
// Defined here (the design-system support file) rather than implicitly
// depended upon from any file that imports SupportingPlayerViews.
// Could be moved to DesignSystem.swift if used outside the player module.

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(DSAnimations.springSnappy, value: configuration.isPressed)
    }
}
