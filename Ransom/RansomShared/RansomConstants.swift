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
        /// Minutes earned and not yet spent. Lives here rather than in the app
        /// because the shield extension has to be able to spend from it.
        public static let bankedMinutes = "ransom.bank.minutes"
        /// Start of the day the bank was last touched, for the daily rollover.
        public static let bankDay = "ransom.bank.day"
        /// Minutes actually spent today. Earning and spending stopped being the
        /// same event when the bank arrived, so they need separate counters.
        public static let spentMinutes = "ransom.bank.spentMinutes"
        public static let spentDay = "ransom.bank.spentDay"
        public static let unlockedTokens = "ransom.unlock.tokens"
        public static let pendingUnlockRequest = "ransom.unlock.pendingRequest"
        public static let pendingUnlockAppName = "ransom.unlock.pendingAppName"
        public static let repsPerUnlock = "ransom.config.repsPerUnlock"
        public static let minutesPerUnlock = "ransom.config.minutesPerUnlock"
        public static let exerciseName = "ransom.config.exerciseName"
        public static let shieldHeadline = "ransom.shield.headline"
        /// The user's most-used apps, as opaque tokens, ranked. Written by a
        /// DeviceActivityReport extension - the only place usage can be read -
        /// and read by the app to recommend what to block. See
        /// `UsageSuggestionStore` for why this has to travel as tokens.
        public static let suggestedTokens = "ransom.suggest.tokens"
        public static let suggestedAt = "ransom.suggest.measuredAt"

        // The tariff counter. Both the app and the shield price from these, so
        // they can never quote the user two different numbers.
        public static let unlocksToday = "ransom.tariff.unlocksToday"
        /// Day stamp the count belongs to, so it rolls over without anything
        /// having to run at midnight.
        public static let unlockCountDay = "ransom.tariff.unlockCountDay"
        public static let lastUnlockAt = "ransom.tariff.lastUnlockAt"
        public static let nightSurcharge = "ransom.tariff.nightSurcharge"
    }
}
