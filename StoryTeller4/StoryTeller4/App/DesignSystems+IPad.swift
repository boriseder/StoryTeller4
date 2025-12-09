import SwiftUI

// MARK: - Device Type Detection
enum DeviceType {
    case iPhone
    case iPad
    
    static var current: DeviceType {
        return UIDevice.current.userInterfaceIdiom == .pad ? .iPad : .iPhone
    }
}

/*

// MARK: - iPad-Optimized Design System
extension DSLayout {
    // Dynamic values based on device
    static var adaptiveScreenPadding: CGFloat {
        DeviceType.current == .iPad ? 32 : 20
    }
    
    static var adaptiveContentGap: CGFloat {
        DeviceType.current == .iPad ? 24 : 16
    }
    
    static var adaptiveElementGap: CGFloat {
        DeviceType.current == .iPad ? 16 : 12
    }
    
    static var adaptiveCardCover: CGFloat {
        DeviceType.current == .iPad ? ResponsiveLayout.iPadCoverSize : ResponsiveLayout.iPhoneCoverSize
    }
    
    static var adaptiveMiniPlayerHeight: CGFloat {
        DeviceType.current == .iPad ? 80 : miniPlayerHeight
    }
}

// MARK: - iPad Grid Columns
extension DSGridColumns {
    static var adaptive: [GridItem] {
        switch DeviceType.current {
        case .iPad:
            return three // iPad uses 3 columns by default
        case .iPhone:
            return two   // iPhone uses 2 columns
        }
    }
    
    static var adaptiveLarge: [GridItem] {
        switch DeviceType.current {
        case .iPad:
            return four  // iPad can show 4 columns in landscape
        case .iPhone:
            return two
        }
    }
}

// MARK: - Responsive Layout Helper
struct ResponsiveLayout {
    // Fixe Cover-Größen
    static let iPhoneCoverSize: CGFloat = 165
    static let iPadCoverSize: CGFloat = 200
    
    static func columns(for size: CGSize, hasSidebar: Bool = false) -> [GridItem] {
        if DeviceType.current == .iPad {
            let isLandscape = size.width > size.height
            
            // Mit Sidebar: weniger Spalten
            if hasSidebar {
                return isLandscape ? DSGridColumns.two : DSGridColumns.two
            }
            
            // Ohne Sidebar (fullscreen): mehr Spalten
            return isLandscape ? DSGridColumns.four : DSGridColumns.three
        } else {
            // iPhone: Standard 2 Spalten
            return DSGridColumns.two
        }
    }
    
    static func coverSize(for size: CGSize? = nil, hasSidebar: Bool = false) -> CGFloat {
        // FIXE Größen, unabhängig vom Container
        return DeviceType.current == .iPad ? iPadCoverSize : iPhoneCoverSize
    }
    
    static var playerCoverSize: CGFloat {
        DeviceType.current == .iPad ? 500 : 356
    }
}
*/
