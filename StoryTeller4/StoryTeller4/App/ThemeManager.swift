import SwiftUI

@MainActor
final class ThemeManager: ObservableObject {
    @Published var backgroundStyle: UserBackgroundStyle {
        didSet {
            UserDefaults.standard.set(backgroundStyle.rawValue, forKey: "userBackgroundStyle")
        }
    }

    @Published var accentColor: UserAccentColor {
        didSet {
            UserDefaults.standard.set(accentColor.rawValue, forKey: "userAccentColor")
        }
    }

    init() {
        let bgRaw = UserDefaults.standard.string(forKey: "userBackgroundStyle")
        backgroundStyle = UserBackgroundStyle(rawValue: bgRaw ?? "") ?? .dynamic

        let accentRaw = UserDefaults.standard.string(forKey: "userAccentColor")
        accentColor = UserAccentColor(rawValue: accentRaw ?? "") ?? .blue
    }

    var textColor: Color {
        backgroundStyle == .light ? .black : .white
    }

    var backgroundColor: Color {
        backgroundStyle == .light ? .white : .black
    }
    
    var backgroundContrastColor: Color {
        backgroundStyle == .light ? .black : .white
    }

    var colorScheme: ColorScheme {
        switch backgroundStyle {
        case .light: .light
        case .dark: .dark
        case .dynamic: .dark
        }
    }

    var accent: Color {
        accentColor.color
    }
}

enum UserBackgroundStyle: String, CaseIterable {
    case dynamic
    case light
    case dark
    
}

enum UserAccentColor: String, CaseIterable, Identifiable {
    case red, orange, green, blue, purple, pink
    
    var id: String { rawValue }
    var color: Color {
        switch self {
        case .red: return .red
        case .orange: return .orange
        case .green: return .green
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        }
    }
}
