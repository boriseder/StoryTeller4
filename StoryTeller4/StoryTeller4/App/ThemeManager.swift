import SwiftUI
import Observation

@MainActor
@Observable
final class ThemeManager {
    
    // MARK: - Properties
    var backgroundStyle: UserBackgroundStyle {
        didSet {
            UserDefaults.standard.set(backgroundStyle.rawValue, forKey: "user_background_style")
        }
    }
    
    var accentColor: UserAccentColor {
        didSet {
            UserDefaults.standard.set(accentColor.rawValue, forKey: "user_accent_color")
        }
    }
    
    // MARK: - Computed
    var colorScheme: ColorScheme? {
        // Return nil to follow system, or specific scheme if implemented
        return nil
    }
    
    var accent: Color {
        accentColor.color
    }
    
    var textColor: Color {
        // Simple dynamic text color logic
        return .primary
    }
    
    // MARK: - Init
    init() {
        // Load saved settings
        let savedBg = UserDefaults.standard.string(forKey: "user_background_style") ?? UserBackgroundStyle.dynamic.rawValue
        self.backgroundStyle = UserBackgroundStyle(rawValue: savedBg) ?? .dynamic
        
        let savedAccent = UserDefaults.standard.string(forKey: "user_accent_color") ?? UserAccentColor.blue.rawValue
        self.accentColor = UserAccentColor(rawValue: savedAccent) ?? .blue
    }
}

// MARK: - Enums
enum UserBackgroundStyle: String, CaseIterable, Identifiable {
    case dynamic
    case plain
    
    var id: String { rawValue }
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
