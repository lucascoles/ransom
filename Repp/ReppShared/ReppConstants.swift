import Foundation

/// Identifiers shared between the Repp app and its Screen Time extensions.
public enum ReppCore {
    /// App Group used to share unlock state between the app and the shield extensions.
    public static let appGroup = "group.com.repp.app"

    /// Darwin notification posted by the shield action extension when the user
    /// taps "Earn Time" on a blocked app.
    public static let unlockRequestedNotification = "com.repp.app.unlock-requested"

    public static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    public enum Key {
        public static let unlockExpiry = "repp.unlock.expiry"
        public static let unlockedTokens = "repp.unlock.tokens"
        public static let pendingUnlockRequest = "repp.unlock.pendingRequest"
        public static let pendingUnlockAppName = "repp.unlock.pendingAppName"
        public static let repsPerUnlock = "repp.config.repsPerUnlock"
        public static let minutesPerUnlock = "repp.config.minutesPerUnlock"
        public static let exerciseName = "repp.config.exerciseName"
        public static let shieldHeadline = "repp.shield.headline"
    }
}
