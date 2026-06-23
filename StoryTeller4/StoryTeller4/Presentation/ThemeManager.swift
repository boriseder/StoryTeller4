import SwiftUI
import Observation

// MARK: - Enums wiederhergestellt
enum UserBackgroundStyle: String, CaseIterable, Identifiable {
    case dynamic
    case light
    case dark
    
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

@MainActor
@Observable
final class ThemeManager {
    
    // MARK: - Properties
    var backgroundStyle: UserBackgroundStyle {
        didSet {
            // Nutzt den Key aus Swift 6 (user_background_style) für Konsistenz,
            // oder ändern Sie es zu "userBackgroundStyle", falls Sie alte Settings retten wollen.
            UserDefaults.standard.set(backgroundStyle.rawValue, forKey: "user_background_style")
        }
    }
    
    var accentColor: UserAccentColor {
        didSet {
            UserDefaults.standard.set(accentColor.rawValue, forKey: "user_accent_color")
        }
    }
    
    // MARK: - Computed Properties
    
    // Wiederhergestellte Logik für das Farbschema der App
    var colorScheme: ColorScheme? {
        switch backgroundStyle {
        case .light:
            return .light
        case .dark:
            return .dark
        case .dynamic:
            // Swift 5 Logik: Dynamic erzwingt Dark Mode (für den Glow-Effekt)
            return .dark
        }
    }
    
    // Wiederhergestellte Logik für Textfarben
    var textColor: Color {
        switch backgroundStyle {
        case .light:
            return .black
        case .dark, .dynamic:
            return .white
        }
    }
    
    var accent: Color {
        accentColor.color
    }
    
    // MARK: - Init
    init() {
        // Load saved settings
        // Hier prüfen wir den gespeicherten String. Falls "plain" (aus der fehlerhaften Swift 6 Version) drinsteht,
        // fallbacken wir auf .dynamic oder .dark, damit die App nicht crasht.
        let savedBg = UserDefaults.standard.string(forKey: "user_background_style") ?? UserBackgroundStyle.dynamic.rawValue
        
        // Fallback-Logik, falls "plain" gespeichert wurde
        if savedBg == "plain" {
            self.backgroundStyle = .dark // Oder .light, je nach Präferenz als Standard
        } else {
            self.backgroundStyle = UserBackgroundStyle(rawValue: savedBg) ?? .dynamic
        }
        
        let savedAccent = UserDefaults.standard.string(forKey: "user_accent_color") ?? UserAccentColor.blue.rawValue
        self.accentColor = UserAccentColor(rawValue: savedAccent) ?? .blue
    }
}
