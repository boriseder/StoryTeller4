//
//  SafeAreaTestApp.swift
//  safeAreaDummy
//

import SwiftUI
/*
@main
struct SafeAreaTestApp: App {
    
    @State private var theme = ThemeManager()

    var body: some Scene {
        WindowGroup {
            SafeAreaTestRoot()
                .environment(theme)
                .preferredColorScheme(.dark) // simulate what your app does

        }
    }
}
struct SafeAreaTestRoot: View {
    @State private var isReady = false
    @State private var selectedTab = 0
    
    var body: some View {
        ZStack {
            Color.blue.ignoresSafeArea()
            
            if isReady {
                mainContent
                    .ignoresSafeArea()
            } else {
                Text("Loading...")
            }
        }
        .ignoresSafeArea()  // ← add this too
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { // simulate async setup
                isReady = true
            }
        }
    }
}
*/
struct ScrollTestView: View {
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(0..<30) { i in
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.blue.opacity(0.3))
                        .frame(height: 100)
                        .overlay(Text("Item \(i)").foregroundColor(.white))
                }
            }
            .padding(.horizontal, 16)
        }
        .background(Color.red.opacity(0.2))
    }
}
