import SwiftUI

/// Colors ported from `ui/theme/Color.kt` (Material 3 dark graphite/slate + soft teal).
/// iOS keeps the same product identity but renders with native materials.
enum Theme {
    // Brand
    static let teal = Color(red: 0x80/255, green: 0xCB/255, blue: 0xC4/255)      // 0xFF80CBC4 soft teal
    static let tealDeep = Color(red: 0x00/255, green: 0x6A/255, blue: 0x60/255)  // 0xFF006A60
    static let tealContainer = Color(red: 0x00/255, green: 0x50/255, blue: 0x49/255)

    // Dark surfaces
    static let backgroundDark = Color(red: 0x12/255, green: 0x12/255, blue: 0x12/255)
    static let surfaceDark = Color(red: 0x1A/255, green: 0x1C/255, blue: 0x1E/255)
    static let surfaceVariantDark = Color(red: 0x2F/255, green: 0x30/255, blue: 0x33/255)
    static let outlineDark = Color(red: 0x8E/255, green: 0x90/255, blue: 0x99/255)

    // Semantic
    static let success = Color(red: 0x00/255, green: 0xE0/255, blue: 0x96/255)   // #00E096
    static let warning = Color(red: 0xFF/255, green: 0xAA/255, blue: 0x00/255)   // #FFAA00
    static let danger = Color(red: 0xFF/255, green: 0x3D/255, blue: 0x71/255)    // #FF3D71
    static let brandBlue = Color(red: 0x33/255, green: 0x66/255, blue: 0xFF/255) // #3366FF (PDF brand)

    // PDF chart palette (PdfGenerator.kt)
    static let chartColors: [Color] = [
        Color(red: 0x33/255, green: 0x66/255, blue: 0xFF/255),
        Color(red: 0x00/255, green: 0xD6/255, blue: 0x8F/255),
        Color(red: 0xFF/255, green: 0xAA/255, blue: 0xA5/255),
        Color(red: 0xFF/255, green: 0x3D/255, blue: 0x71/255),
        Color(red: 0x8F/255, green: 0x9B/255, blue: 0xB3/255),
    ]
}

/// Dynamic palette helper: the app renders with the OurMoney dark identity
/// (every root view sets `.preferredColorScheme(.dark)`, mirroring the Android
/// app which ships a dark-only theme).
enum OMColor {
    static func background(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Theme.backgroundDark : Color(red: 0xFB/255, green: 0xFD/255, blue: 0xFA/255)
    }
    static func surface(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Theme.surfaceDark : .white
    }
    static func surfaceVariant(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Theme.surfaceVariantDark : Color(red: 0xDB/255, green: 0xE5/255, blue: 0xE0/255)
    }
    static func primary(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Theme.teal : Theme.tealDeep
    }
    static func onBackground(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0xE3/255, green: 0xE2/255, blue: 0xE6/255) : Color(red: 0x19/255, green: 0x1C/255, blue: 0x1B/255)
    }
    static func outline(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Theme.outlineDark : Color(red: 0x6F/255, green: 0x79/255, blue: 0x77/255)
    }
}
