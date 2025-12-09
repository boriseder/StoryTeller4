import SwiftUI

struct DynamicBackground: View {
    @EnvironmentObject var theme: ThemeManager

    var body: some View {
        ZStack {
            // Basis dunkler LinearGradient, leicht getönt nach accentColor
            LinearGradient(
                colors: [
                    theme.accent.opacity(0.05),
                    theme.accent.opacity(0.08),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Subtiler Radial Glow in Akzentfarbe
            RadialGradient(
                colors: [
                    theme.accent.opacity(0.2),
                    .clear
                ],
                center: UnitPoint(x: 0.4, y: 0.3),
                startRadius: 100,
                endRadius: 500
            )
            .ignoresSafeArea()

            // Textur für Tiefe
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.015),
                            .clear,
                            .black.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .ignoresSafeArea()
        }
    }
}
