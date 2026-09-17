import SwiftUI
import UIKit

// MARK: - Color

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }

    /// A colour that resolves differently in light and dark mode.
    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

/// Ransom's palette. Warm paper, near-black ink, and Rex's tangerine doing the
/// brand's work. Green is a state, not a colour scheme.
enum Palette {
    static let canvas     = Color.adaptive(light: 0xFBFAF6, dark: 0x0C0E0B)
    static let surface    = Color.adaptive(light: 0xFFFFFF, dark: 0x161A15)
    static let surfaceAlt = Color.adaptive(light: 0xF2F1EB, dark: 0x1F241D)

    static let ink        = Color.adaptive(light: 0x0F1410, dark: 0xF4F6F2)
    static let inkSoft    = Color.adaptive(light: 0x5A625A, dark: 0x9AA398)
    static let inkFaint   = Color.adaptive(light: 0x9CA39B, dark: 0x6B736A)

    static let hairline   = Color.adaptive(light: 0xE7E5DC, dark: 0x2A3026)

    /// The field the cards sit on, on the screens you live in. Deliberately a few
    /// steps below `surface` — `canvas` was a percent and a half off white, which
    /// is not enough for a card to read as raised, so the whole screen flattened
    /// into one sheet. Kept separate from `canvas` because onboarding's intro clip
    /// is keyed with `.blendMode(.multiply)` and needs the near-white behind it.
    ///
    /// The dark value sits below `canvas` rather than equalling it, which is what
    /// it used to do: the two were byte-identical, so in dark mode this token did
    /// nothing, the whole treatment was invisible and the screen went back to
    /// being one flat sheet. Cards are lit from `surface` in the dark, so the
    /// field has to get out of their way by going darker, not lighter.
    static let canvasDeep = Color.adaptive(light: 0xF6F2EA, dark: 0x06080A)

    /// Low warm light across the top, and the sun just off the corner. Sampled from
    /// the App Store artwork, which has always shown Rex in a lit scene while the
    /// app itself opened onto flat paper.
    ///
    /// Dark keeps the same idea and inverts the amount: light in a dark room is
    /// a hint, so these lift the field by a few percent instead of washing it,
    /// and stay warm so it reads as a low sun and not as grey haze.
    static let dawn       = Color.adaptive(light: 0xFEF6EF, dark: 0x181A11)
    static let sun        = Color.adaptive(light: 0xFDE7D0, dark: 0x2A2114)

    /// The ground Rex stands on. Two depths, so the masthead has a far hill and a
    /// near one instead of a single flat band. Both are tangerine tints and not the
    /// grass the store art uses: green is the earned state, and a green that's
    /// always on screen stops meaning it.
    static let sandFar    = Color.adaptive(light: 0xFBE2C9, dark: 0x1E1710)
    static let sandNear   = Color.adaptive(light: 0xF7CFA9, dark: 0x2A2016)

    /// Rex's tangerine. The brand colour — the character, the icon, and anything
    /// that needs to sound an alarm. Sampled from the artwork rather than picked,
    /// so the palette follows the character instead of fighting it.
    static let brand      = Color.adaptive(light: 0xF06027, dark: 0xFF7A45)
    static let brandSoft  = Color.adaptive(light: 0xFDEBE2, dark: 0x35190F)

    /// Purely semantic: earned, unlocked, the door is open. Deliberately deeper and
    /// less candy than before, so it reads as a state rather than as a mascot —
    /// Rex used to be this colour, and the two were competing.
    static let green      = Color.adaptive(light: 0x2E9E4E, dark: 0x4CCB6B)
    static let greenSoft  = Color.adaptive(light: 0xE2F4E7, dark: 0x142E1B)

    /// Streaks and milestones. Trophy gold, moved off orange so it stops
    /// colliding with Rex.
    static let flame      = Color.adaptive(light: 0xD99A1F, dark: 0xF0B84A)
    static let flameSoft  = Color.adaptive(light: 0xFBF0D8, dark: 0x322611)

    /// The character's own colours, for anything drawn to match him.
    enum Rex {
        static let body      = Color(hex: 0xF06027)
        static let highlight = Color(hex: 0xF8773B)
        static let shadow    = Color(hex: 0xD15423)
        static let belly     = Color(hex: 0xFCD8B0)
        static let gold      = Color(hex: 0xF7A83B)
    }

    /// A fourth hue nothing in the post-purchase app should need: tangerine is the
    /// brand, gold is the streak, green is earned time. Kept for the confetti mix.
    static let violet     = Color.adaptive(light: 0x6C5CE7, dark: 0x8B7CFF)
    static let danger     = Color.adaptive(light: 0xE23D3D, dark: 0xFF6B6B)

    static let onGreen    = Color.adaptive(light: 0xFFFFFF, dark: 0x07120A)
    static let onBrand    = Color.adaptive(light: 0xFFFFFF, dark: 0x1A0A04)
}

// MARK: - Type

/// Everything is SF Rounded. It's the single biggest lever on how friendly the app feels.
enum RansomFont {
    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy, design: .rounded) }
    static func title(_ size: CGFloat = 28) -> Font { .system(size: size, weight: .bold, design: .rounded) }
    static func headline(_ size: CGFloat = 18) -> Font { .system(size: size, weight: .semibold, design: .rounded) }
    static func body(_ size: CGFloat = 16) -> Font { .system(size: size, weight: .medium, design: .rounded) }
    static func caption(_ size: CGFloat = 13) -> Font { .system(size: size, weight: .semibold, design: .rounded) }
    /// Tabular figures so counters don't jitter as digits change.
    static func counter(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy, design: .rounded).monospacedDigit()
    }
}

// MARK: - Metrics

enum Metrics {
    static let screenPadding: CGFloat = 24
    static let cardRadius: CGFloat = 22
    static let controlRadius: CGFloat = 18
    static let buttonHeight: CGFloat = 56
}

// MARK: - Background

/// The warm field Home and the other card screens sit on: paper, a dawn wash over
/// the top half, and the sun bleeding in off the corner behind the greeting. The
/// wash stops at the middle so it reads as light falling on the screen rather than
/// as a coloured panel.
struct RansomBackground: View {
    var body: some View {
        ZStack {
            Palette.canvasDeep

            LinearGradient(
                colors: [Palette.dawn, Palette.dawn.opacity(0)],
                startPoint: .top,
                endPoint: .center
            )

            GeometryReader { geo in
                RadialGradient(
                    colors: [Palette.sun, Palette.sun.opacity(0)],
                    center: UnitPoint(x: 0.14, y: 0.13),
                    startRadius: 0,
                    endRadius: geo.size.width * 0.95
                )
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - Shared modifiers

extension View {
    /// The standard card treatment: soft surface, hairline edge, barely-there lift.
    func ransomCard(padding: CGFloat = 18, radius: CGFloat = Metrics.cardRadius) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
    }

    func ransomScreenBackground() -> some View {
        background(Palette.canvas.ignoresSafeArea())
    }

    /// The lit version, for the screens with cards on them. Everything in it is
    /// fixed, so the cards travel over a still field — that's what reads as depth
    /// rather than as wallpaper.
    func ransomAmbientBackground() -> some View {
        background(RansomBackground())
    }

    /// Scales a view down slightly while pressed. Applied to every tappable surface.
    func pressable(scale: CGFloat = 0.97) -> some View {
        buttonStyle(PressableButtonStyle(scale: scale))
    }

    /// `-RansomScrollBottom 1` opens a tab's scroll view already at the bottom, so a
    /// screenshot run can see the cards below the fold without a UI-test target to
    /// swipe for it. Debug builds only; a no-op everywhere else.
    @ViewBuilder
    func debugScrollAnchor() -> some View {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "RansomScrollBottom") {
            defaultScrollAnchor(.bottom)
        } else {
            self
        }
        #else
        self
        #endif
    }
}

struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
