import Foundation

/// Rex's lines on the block screen. A friend at the door, not a bouncer.
///
/// The shield is a fixed template - Apple gives an icon, a title, a subtitle and
/// two buttons, and no way to lay out anything else - so every word here is
/// carrying weight it would not have to carry on a screen we controlled.
public enum ShieldCopy {
    /// Why the app did not open, in the fewest words that still explain it.
    /// Named for the app when the system tells us which one, because "Instagram
    /// needs a set first" is a sentence about the user's own phone and
    /// "This app is restricted" is a sentence about somebody's policy.
    public static func headline(appName: String?) -> String {
        guard let appName else { return "Reps first" }
        return "\(appName) needs a set first"
    }

    /// The trade, stated plainly with the real numbers. No taunt: the line the
    /// user reads twenty times a day has to still be readable the twentieth time,
    /// and a joke that has worn out is worse than a fact.
    public static func subtitle(reps: Int, exercise: String, minutes: Int, banked: Int) -> String {
        let trade = "\(reps) \(exercise.lowercased()) banks you \(minutes) minutes."
        // A balance already earned turns "you are blocked" into "you are one tap
        // from not being blocked", which is a different screen entirely.
        guard banked > 0 else { return trade }
        return "You have \(banked) minutes banked. \(trade)"
    }

    public static let primaryButton = "Do my reps"
    public static let secondaryButton = "Close"

    /// Tapping the primary button cannot open Ransom - iOS gives an extension no
    /// way to launch its host app - so the shield hands off through a
    /// notification, and the tap on that is what actually opens the camera.
    public static let handoff = "Tap to start your set"
}
