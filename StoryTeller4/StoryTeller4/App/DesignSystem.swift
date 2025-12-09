//
//  SemanticDesignSystem.swift - Semantische Umbenennung deines Systems
//  NavidromeClient
//
//   Behält deine bestehende Struktur, macht sie nur semantisch klar
//

import SwiftUI

// MARK: - Layout (Ersetzt Spacing + Padding + Sizes)

enum DSLayout {
    // MARK: Gaps (zwischen Elementen)
    static let tightGap: CGFloat = 4        // Icon-Text, sehr eng
    static let elementGap: CGFloat = 8      // Standard Icon-Text, Button-Elemente
    static let contentGap: CGFloat = 16     // Zwischen Content-Blöcken
    static let sectionGap: CGFloat = 24     // Zwischen Sections
    static let screenGap: CGFloat = 32      // Zwischen Major Areas
    static let largeGap: CGFloat = 40       // Sehr große Abstände
    
    // MARK: Padding (innerhalb Elementen)
    static let tightPadding: CGFloat = 4    // Sehr enge Innenabstände
    static let elementPadding: CGFloat = 8  // Button-Inhalt, kleine Elemente
    static let contentPadding: CGFloat = 16 // Standard Card/Container-Inhalt
    static let comfortPadding: CGFloat = 24 // Große Container
    static let screenPadding: CGFloat = 16  // Screen-Ränder (16 war zu eng)
    
    // MARK: Feste UI Größen
    static let buttonHeight: CGFloat = 44
    static let searchBarHeight: CGFloat = 44
    static let tabBarHeight: CGFloat = 90
    static let miniPlayerHeight: CGFloat = 90
    
    // MARK: Icon Größen
    static let smallIcon: CGFloat = 16      // Tiny icons
    static let icon: CGFloat = 24          // Standard icons
    static let largeIcon: CGFloat = 32     // Prominent icons
    
    // MARK: Cover/Avatar Größen (Use-Case spezifisch)
    static let miniCover: CGFloat = 50      // Song rows, mini player
    static let listCover: CGFloat = 70      // List items
    static let cardCoverWithPadding: CGFloat = 152     // Grid cards
    static let cardCoverNoPadding: CGFloat = 170     // Grid cards
    //static let cardCover: CGFloat = 140     // Grid cards
    static let detailCover: CGFloat = 300   // Detail views
    static let fullCover: CGFloat = 356     // Full screen
    static let smallAvatar: CGFloat = 60    // Author avatars
    static let avatar: CGFloat = 100        // Large avatars
    
    // MARK: Content Width
    static let maxContentWidth: CGFloat = 400 // Max content width
    
    // MARK: Additional sizes - need consolidation
    static let badgeCornerRadius: CGFloat = 12
    static let actionButtonSize: CGFloat = 36
    static let statusHeight: CGFloat = 28
    static let padding: CGFloat = 8
    static let shadowRadius: CGFloat = 8
    static let shadowOpacity: CGFloat = 0.15

    
}

// MARK: - Corners (Ersetzt Radius)

enum DSCorners {
    static let tight: CGFloat = 4           // AlbumCover mini
    static let element: CGFloat = 8         // Buttons, small elements
    static let content: CGFloat = 16        // Cards, containers
    static let comfortable: CGFloat = 24    // Large containers
    static let spacious: CGFloat = 32       // Very large elements
    static let round: CGFloat = 50          // Circle buttons
}

// MARK: - Typography (Semantisch umbenannt)

enum DSText {
    // MARK: Hierarchy
    static let pageTitle = Font.system(.largeTitle, design: .rounded).weight(.bold)
    static let sectionTitle = Font.system(.title, design: .rounded).weight(.bold)
    static let subsectionTitle = Font.system(.title2, design: .rounded).weight(.semibold)
    static let itemTitle = Font.system(.title3, design: .rounded).weight(.semibold)
    
    // MARK: Content
    static let prominent = Font.headline.weight(.semibold)
    static let emphasized = Font.subheadline.weight(.medium)
    static let body = Font.body
    static let detail = Font.callout
    
    // MARK: Small text
    static let metadata = Font.caption
    static let fine = Font.caption2
    static let footnote = Font.footnote
    
    // MARK: Interactive
    static let button = Font.callout.weight(.semibold)
    static let largeButton = Font.headline.weight(.semibold)
    
    // MARK: Special
    static let numbers = Font.body.monospacedDigit()
}

// MARK: - Colors (Deine bestehenden, semantisch gruppiert)

enum DSColor {
    // MARK: Content colors
    static let primary = SwiftUI.Color.primary
    static let secondary = SwiftUI.Color.secondary
    static let tertiary = SwiftUI.Color(.tertiaryLabel)
    static let quaternary = SwiftUI.Color(.quaternaryLabel)
    
    // MARK: Surfaces
    static let background = SwiftUI.Color(.systemBackground)
    static let surface = SwiftUI.Color(.secondarySystemBackground)
    static let surfaceSecondary = SwiftUI.Color(.tertiarySystemBackground)
    static let surfaceLight = SwiftUI.Color(UIColor.systemGray6)
    static let surfaceMedium = SwiftUI.Color(UIColor.systemGray5)
    
    // MARK: Brand & Status
    static let accent = SwiftUI.Color.accentColor
    static let brand = SwiftUI.Color(.systemBlue)
    static let success = SwiftUI.Color(.systemGreen)
    static let warning = SwiftUI.Color(.systemOrange)
    static let error = SwiftUI.Color(.systemRed)
    static let info = SwiftUI.Color(.systemBlue)
    
    // MARK: Music-specific
    static let playing = SwiftUI.Color(.systemBlue)
    static let offline = SwiftUI.Color(.systemOrange)
    static let downloaded = SwiftUI.Color(.systemGreen)
    
    // MARK: On-colors (für dunkle Hintergründe)
    static let onDark = SwiftUI.Color.white
    static let onDarkSecondary = SwiftUI.Color.white.opacity(0.7)
    static let onLight = SwiftUI.Color.black
    static let onLightSecondary = SwiftUI.Color.black.opacity(0.7)
    
    // MARK: Overlays
    static let overlay = SwiftUI.Color.black.opacity(0.4)
    static let overlayLight = SwiftUI.Color.black.opacity(0.2)
    static let overlayHeavy = SwiftUI.Color.black.opacity(0.6)   
}

enum DSAnimations {
    static let spring = Animation.spring(response: 0.4, dampingFraction: 0.8)
    static let springSnappy = Animation.spring(response: 0.3, dampingFraction: 0.7)
    static let ease = Animation.easeInOut(duration: 0.2)
    static let easeQuick = Animation.easeInOut(duration: 0.1)
    static let easeSlow = Animation.easeInOut(duration: 0.4)
    
    // Interactive
    static let interactive = Animation.interactiveSpring()
    static let bounce = Animation.spring(response: 0.6, dampingFraction: 0.6)
}

// MARK: - Grid Helpers
enum DSGridColumns {
    static let two = Array(repeating: GridItem(.flexible(), spacing: DSLayout.contentGap), count: 2)
    static let three = Array(repeating: GridItem(.flexible(), spacing: DSLayout.elementGap), count: 3)
    static let four = Array(repeating: GridItem(.flexible(), spacing: DSLayout.elementGap), count: 4)
}
