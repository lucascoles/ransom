import Foundation

/// Rex's lines on the block screen. Rotated so the shield never feels like a
/// static error page — it should feel like a character is standing in the doorway.
public enum ShieldCopy {
    public static func headline(reps: Int, exercise: String) -> String {
        "\(reps) \(exercise.lowercased()) and it's yours."
    }

    public static func taunt(seed: Int = Int(Date().timeIntervalSince1970 / 60)) -> String {
        let lines = [
            "Nice try. Rex saw that.",
            "The doorman needs a toll.",
            "You and me. Right now. On the floor.",
            "Ten seconds of work for fifteen minutes of scroll.",
            "Your thumb is warmed up. Let's do the rest of you.",
            "Rex is blocking the door. Rex does not blink.",
            "Earn it. Then scroll guilt-free.",
            "One set. That's the whole ask."
        ]
        return lines[abs(seed) % lines.count]
    }

    public static let primaryButton = "Earn my time"
    public static let secondaryButton = "Not now"

    /// Shown after the user taps the primary button — extensions cannot launch the
    /// host app directly, so the shield hands off with an instruction instead.
    public static let handoff = "Open Ransom to start your set."
}
