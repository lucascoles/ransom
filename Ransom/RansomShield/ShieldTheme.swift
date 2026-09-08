import UIKit

/// The block screen's look: Rex at the door, on Ransom's own paper or ink.
///
/// Colours mirror `Palette` in the app's `Theme.swift` (warm paper, near-black
/// ink, Rex's tangerine). They are copied rather than shared because that
/// palette is SwiftUI in the app target and the extension cannot see it; if one
/// moves, move both. The shield is the surface the user sees most, and a shield
/// in different colours from the app reads as a different app.
///
/// Why one fixed set per appearance instead of dynamic colours: the
/// configuration is handed to the system across a process boundary, and a custom
/// dynamic `UIColor` does not survive that as anything but a single resolved
/// value. Resolving here, against the traits the extension was launched with,
/// and choosing the blur to match, means the worst case is a shield in the other
/// appearance, never a shield whose text has lost its background.
struct ShieldTheme {
    let blur: UIBlurEffect.Style
    /// Painted over the blurred app. Not quite opaque, so a little of Instagram's
    /// colour leaks through and the shield reads as a door in front of that app
    /// rather than a wall that replaced it.
    let background: UIColor
    let title: UIColor
    let subtitle: UIColor
    let button: UIColor
    let buttonLabel: UIColor
    let secondary: UIColor

    /// `Palette.canvas` / `ink` / `inkSoft` / `brand` / `onBrand`, light.
    static let light = ShieldTheme(
        blur: .systemThickMaterialLight,
        background: UIColor(hex: 0xFBFAF6, alpha: 0.9),
        title: UIColor(hex: 0x0F1410),
        subtitle: UIColor(hex: 0x5A625A),
        button: UIColor(hex: 0xF06027),
        buttonLabel: .white,
        secondary: UIColor(hex: 0x5A625A)
    )

    /// The same slots, dark. The button label is the app's dark-mode `onBrand`
    /// ink rather than white: the app's own buttons are ink on tangerine in dark
    /// mode, and white on this orange is under 3:1 contrast.
    static let dark = ShieldTheme(
        blur: .systemThickMaterialDark,
        background: UIColor(hex: 0x0C0E0B, alpha: 0.9),
        title: UIColor(hex: 0xF4F6F2),
        subtitle: UIColor(hex: 0x9AA398),
        button: UIColor(hex: 0xFF7A45),
        buttonLabel: UIColor(hex: 0x1A0A04),
        secondary: UIColor(hex: 0x9AA398)
    )

    static func current(for traits: UITraitCollection = .current) -> ShieldTheme {
        traits.userInterfaceStyle == .dark ? dark : light
    }
}

/// The picture on the shield.
enum ShieldIcon {
    /// Rex in the doorway: the "blocking the way" pose the app already ships,
    /// arms out, feet planted. It is the one illustration in the set that was
    /// drawn for exactly this moment, and it had never been shown here.
    ///
    /// The artwork lives in this extension's own asset catalog because an
    /// extension cannot read its host app's. If the asset is ever missing, the
    /// drawn badge stands in rather than leaving the slot blank.
    static func rex() -> UIImage {
        let bundle = Bundle(for: ShieldConfigurationExtension.self)
        if let art = UIImage(named: "RexBlocked", in: bundle, compatibleWith: nil) {
            return art
        }
        return RexBadge.image(size: 200)
    }
}
