import SwiftUI

struct DynamicBackground: View {
    // FIX: Use @Environment(Type.self)
    @Environment(ThemeManager.self) var theme
    
    var body: some View {
        ZStack {
            // Base color
            theme.accent
                .opacity(0.15)
                .ignoresSafeArea()
            
            // Gradient mesh
            GeometryReader { geometry in
                ZStack {
                    Circle()
                        .fill(theme.accent)
                        .opacity(0.3)
                        .blur(radius: 60)
                        .frame(width: 300, height: 300)
                        .position(x: 0, y: 0)
                    
                    Circle()
                        .fill(Color.blue)
                        .opacity(0.2)
                        .blur(radius: 80)
                        .frame(width: 400, height: 400)
                        .position(x: geometry.size.width, y: geometry.size.height * 0.4)
                    
                    Circle()
                        .fill(Color.purple)
                        .opacity(0.2)
                        .blur(radius: 60)
                        .frame(width: 300, height: 300)
                        .position(x: geometry.size.width * 0.2, y: geometry.size.height)
                }
            }
            .ignoresSafeArea()
            
            // Blur overlay for smoothness
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.5)
                .ignoresSafeArea()
        }
    }
}
