import Foundation

/// Identifiers shared between the Ransom app and its Screen Time extensions.
public enum RansomCore {
    /// App Group used to share unlock state between the app and the shield extensions.
    public static let appGroup = "group.com.ransom.app"

    /// Darwin notification posted by the shield action extension when the user
    /// taps "Earn Time" on a blocked app.
    public static let unlockRequestedNotification = "com.ransom.app.unlock-requested"

    public static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    public enum Key {
        public static let unlockExpiry = "ransom.unlock.expiry"
        public static let unlockedTokens = "ransom.unlock.tokens"
        public static let pendingUnlockRequest = "ransom.unlock.pendingRequest"
        public static let pendingUnlockAppName = "ransom.unlock.pendingAppName"
        public static let repsPerUnlock = "ransom.config.repsPerUnlock"
        public static let minutesPerUnlock = "ransom.config.minutesPerUnlock"
        public static let exerciseName = "ransom.config.exerciseName"
        public static let shieldHeadline = "ransom.shield.headline"
    }
}
