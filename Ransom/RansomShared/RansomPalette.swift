import UIKit

/// Rex's colours, in the one place all four targets can reach.
///
/// The app has its own SwiftUI `Palette` in `Theme.swift`, but that lives in the
/// app target — the shield extensions can't see it. These are the same values as
/// `Palette.brand` and `Palette.Rex`, and the two must stay in step: the shield is
/// the surface the user sees most, so a mismatch here reads as a different app.
public enum RansomPalette {
    public static let brand     = UIColor(hex: 0xF06027)
    /// The shield is always dark, so it uses the dark-mode brand value.
    public static let brandDark = UIColor(hex: 0xFF7A45)
    public static let onBrand   = UIColor(hex: 0x1A0A04)

    public enum Rex {
        public static let body      = UIColor(hex: 0xF06027)
        public static let highlight = UIColor(hex: 0xF8773B)
        public static let shadow    = UIColor(hex: 0xD15423)
        public static let belly     = UIColor(hex: 0xFCD8B0)
        public static let gold      = UIColor(hex: 0xF7A83B)
    }

    /// Warm near-black. Neutral enough not to tint Rex, dark enough to sit under
    /// the shield's blur.
    public static let shieldBackground = UIColor(hex: 0x0E0B09)
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
