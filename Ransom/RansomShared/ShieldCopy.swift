import Foundation

/// Rex's lines on the block screen. Rotated so the shield never feels like a
/// static error page: a friend is at the door, not a bouncer. Nothing here
/// carries a number, because the shield quotes the real price in `headline`.
public enum ShieldCopy {
    public static func headline(reps: Int, exercise: String) -> String {
        "\(reps) \(exercise.lowercased()) and it's yours."
    }

    public static func taunt(seed: Int = Int(Date().timeIntervalSince1970 / 60)) -> String {
        let lines = [
            "Quick set first. Then it's all yours.",
            "You and me. A few reps, then scroll away.",
            "Small set now, guilt-free scroll after.",
            "Your thumb is warmed up. Let's do the rest of you.",
            "One set. That's the whole ask.",
            "Rex is here. Let's get you moving.",
            "Do the set, open the app. Easy trade.",
            "A minute of work. You've got this."
        ]
        return lines[abs(seed) % lines.count]
    }

    public static let primaryButton = "Do a quick set"
    public static let secondaryButton = "Not now"

    /// Shown after the user taps the primary button — extensions cannot launch the
    /// host app directly, so the shield hands off with an instruction instead.
    public static let handoff = "Open Ransom to start your set."
}
