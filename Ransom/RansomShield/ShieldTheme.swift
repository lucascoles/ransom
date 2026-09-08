import UIKit

/// The block screen's look: Rex at the door, on white.
///
/// **One theme, not one per appearance.** There used to be a light and a dark
/// set chosen from `UITraitCollection.current`, which was a guess: the
/// configuration is handed to the system across a process boundary, so a custom
/// dynamic `UIColor` does not survive it as anything but a single resolved
/// value, and the traits the extension happens to launch with are not reliably
/// the ones the shield is drawn in. A shield that sometimes came back in the
/// wrong appearance is a worse outcome than one that always looks the same.
///
/// White also does something the dark version could not. Every guarded app opens
/// on its own splash, and a near-black slab over it reads as a system error
/// rather than as Ransom. Paper reads as a door.
struct ShieldTheme {
    let blur: UIBlurEffect.Style
    /// Painted over the blurred app. Just short of opaque, so a little of the
    /// app underneath still shows and the shield reads as something placed in
    /// front of Instagram rather than a screen that replaced it.
    let background: UIColor
    let title: UIColor
    let subtitle: UIColor
    let button: UIColor
    let buttonLabel: UIColor
    let secondary: UIColor

    /// `Palette.ink` / `inkSoft` / `brand` / `onBrand`, with the canvas pushed to
    /// true white so the shield is unmistakably a fresh surface rather than a
    /// tinted version of whatever is behind it.
    static let paper = ShieldTheme(
        blur: .systemThickMaterialLight,
        background: UIColor(hex: 0xFFFFFF, alpha: 0.96),
        title: UIColor(hex: 0x0F1410),
        subtitle: UIColor(hex: 0x5A625A),
        button: UIColor(hex: 0xF06027),
        buttonLabel: .white,
        secondary: UIColor(hex: 0x5A625A)
    )

    /// Kept as a function so the call site does not have to change if the shield
    /// ever earns a second appearance again.
    static func current(for traits: UITraitCollection = .current) -> ShieldTheme {
        paper
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
