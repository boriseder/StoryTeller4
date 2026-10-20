import SwiftUI

struct DynamicBackground: View {
    @Environment(ThemeManager.self) var theme
    
    // Add subtle animation for the ambient background
    @State private var isAnimating = false
    
    var body: some View {
        if theme.backgroundStyle == .dynamic {
            ZStack {
                // Base ambient layer
                theme.accent
                    .opacity(0.1)
                    .ignoresSafeArea()
                
                // Animated mesh gradient points
                GeometryReader { geometry in
                    ZStack {
                        Circle()
                            .fill(theme.accent)
                            .opacity(0.4)
                            .blur(radius: 90)
                            .frame(width: geometry.size.width * 0.8)
                            .position(
                                x: isAnimating ? geometry.size.width : 0,
                                y: isAnimating ? geometry.size.height * 0.2 : 0
                            )
                        
                        Circle()
                            .fill(Color.blue)
                            .opacity(0.3)
                            .blur(radius: 100)
                            .frame(width: geometry.size.width * 0.9)
                            .position(
                                x: isAnimating ? 0 : geometry.size.width,
                                y: isAnimating ? geometry.size.height * 0.8 : geometry.size.height * 0.4
                            )
                        
                        Circle()
                            .fill(Color.purple)
                            .opacity(0.3)
                            .blur(radius: 100)
                            .frame(width: geometry.size.width * 0.7)
                            .position(
                                x: isAnimating ? geometry.size.width * 0.2 : geometry.size.width * 0.8,
                                y: isAnimating ? geometry.size.height : geometry.size.height * 0.8
                            )
                    }
                    .drawingGroup() // Optimize rendering
                }
                .ignoresSafeArea()
                
                // Glassy overlay to blend everything smoothly
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 15.0).repeatForever(autoreverses: true)) {
                    isAnimating = true
                }
            }
            // Transition for smooth appearance when toggling settings
            .transition(.opacity.animation(.easeInOut(duration: 0.5)))
        } else {
            // Native standard OS background
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
        }
    }
}
