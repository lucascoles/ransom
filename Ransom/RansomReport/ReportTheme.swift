import SwiftUI
import UIKit

/// The app's colours and type, for views drawn in this process.
///
/// The app's `Palette` and `RansomFont` live in the app target, which this
/// extension does not compile. Same values as `Theme.swift`; the two must stay in
/// step, or the Progress cards drawn here read as a different app from the ones
/// around them.
enum ReportPalette {
    static let ink        = adaptive(light: 0x0F1410, dark: 0xF4F6F2)
    static let inkSoft    = adaptive(light: 0x5A625A, dark: 0x9AA398)
    static let inkFaint   = adaptive(light: 0x9CA39B, dark: 0x6B736A)
    static let hairline   = adaptive(light: 0xE7E5DC, dark: 0x2A3026)
    static let surfaceAlt = adaptive(light: 0xF2F1EB, dark: 0x1F241D)
    static let brand      = adaptive(light: 0xF06027, dark: 0xFF7A45)
    static let brandSoft  = adaptive(light: 0xFDEBE2, dark: 0x35190F)
    static let green      = adaptive(light: 0x2E9E4E, dark: 0x4CCB6B)
    static let greenSoft  = adaptive(light: 0xE2F4E7, dark: 0x142E1B)
    static let danger     = adaptive(light: 0xE23D3D, dark: 0xFF6B6B)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }
}

enum ReportFont {
    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy, design: .rounded) }
    static func headline(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold, design: .rounded) }
    static func body(_ size: CGFloat) -> Font { .system(size: size, weight: .medium, design: .rounded) }
    static func caption(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold, design: .rounded) }
}
