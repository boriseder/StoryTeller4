
import SwiftUI

// MARK: - Welcome View
struct WelcomeView: View {
    let onComplete: () -> Void
    
    @State private var currentPage = 0
    private let totalPages = 3
    
    var body: some View {
        VStack(spacing: 0) {
            // Skip button
            HStack {
                Spacer()
                Button("Skip") {
                    onComplete()
                }
                .foregroundColor(.white.opacity(0.8))
                .padding()
            }
            
            Spacer()
            
            // Page content
            TabView(selection: $currentPage) {
                WelcomePageView(
                    systemImage: "headphones.circle.fill",
                    title: "Welcome to StoryTeller",
                    description: "Your personal audiobook library, powered by Audiobookshelf"
                )
                .tag(0)
                
                WelcomePageView(
                    systemImage: "arrow.down.circle.fill",
                    title: "Download & Listen Offline",
                    description: "Download your favorite audiobooks and listen anywhere, anytime"
                )
                .tag(1)
                
                WelcomePageView(
                    systemImage: "server.rack",
                    title: "Connect Your Server",
                    description: "Connect to your Audiobookshelf server to get started"
                )
                .tag(2)
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            
            // Page indicator
            HStack(spacing: 8) {
                ForEach(0..<totalPages, id: \.self) { index in
                    Circle()
                        .fill(index == currentPage ? Color.white : Color.white.opacity(0.3))
                        .frame(width: 8, height: 8)
                        .animation(.easeInOut(duration: 0.2), value: currentPage)
                }
            }
            .padding(.bottom, 32)
            
            // Action button
            Button(action: {
                if currentPage < totalPages - 1 {
                    withAnimation {
                        currentPage += 1
                    }
                } else {
                    onComplete()
                }
            }) {
                Text(currentPage == totalPages - 1 ? "Get Started" : "Next")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.white.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
        .background(
            LinearGradient(
                colors: [
                    Color.accentColor,
                    Color.accentColor.opacity(0.8)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

// MARK: - Welcome Page View
struct WelcomePageView: View {
    let systemImage: String
    let title: String
    let description: String
    
    var body: some View {
        VStack(spacing: 32) {
            Image(systemName: systemImage)
                .font(.system(size: 80))
                .foregroundColor(.white)
            
            VStack(spacing: 16) {
                Text(title)
                    .font(.system(.title, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                
                Text(description)
                    .font(.body)
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .padding()
    }
}
