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
        /// Today's ceiling in minutes, mirrored for the report extension: the
        /// brain is coloured against it, and the extension is the only process
        /// that can see the screen time to compare it with.
        public static let allowanceMinutes = "ransom.config.allowanceMinutes"
        public static let repsPerUnlock = "ransom.config.repsPerUnlock"
        public static let minutesPerUnlock = "ransom.config.minutesPerUnlock"
        public static let exerciseName = "ransom.config.exerciseName"
        public static let shieldHeadline = "ransom.shield.headline"
        /// Day-by-day readings of the usage ladder. See `UsageHistory`.
        public static let usageHistory = "ransom.usage.history"
        /// A short breadcrumb trail written by the monitor extension. The
        /// extension runs in its own process, on iOS's schedule, and leaves no
        /// other trace - without this every question about what it did is a
        /// guess, and three separate bugs have already hidden in that gap.
        public static let monitorTrace = "ransom.debug.monitorTrace"
        /// Times each app has been stopped at the door today, and the day the
        /// tally belongs to. Written by the shield - see `BlockCountStore`.
        public static let blockCounts = "ransom.block.counts"
        public static let blockCountDay = "ransom.block.countDay"
        public static let blockCountLastApp = "ransom.block.lastApp"
        public static let blockCountLastAt = "ransom.block.lastAt"
        /// The user's most-used apps, as opaque tokens, ranked. Written by a
        /// DeviceActivityReport extension - the only place usage can be read -
        /// and read by the app to recommend what to block. See
        /// `UsageSuggestionStore` for why this has to travel as tokens.
        public static let suggestedTokens = "ransom.suggest.tokens"
        public static let suggestedAt = "ransom.suggest.measuredAt"
        /// The user's named focus windows. In the App Group because the shield
        /// prices against them too - see `FocusRuleStore`.
        public static let focusRules = "ransom.rules.focus"
        /// Weekdays Ransom guards. Empty is every day. Read by the shield and the
        /// monitor as well as the app - see `ScheduleStore`.
        public static let activeDays = "ransom.schedule.activeDays"
        /// A quieter week waiting for its date, and the date. Absent on any
        /// install from before days off could wait - see `WeekSchedule`.
        public static let pendingDays = "ransom.schedule.pendingDays"
        public static let pendingFrom = "ransom.schedule.pendingFrom"
        /// Minutes credited from steps today, and the day that belongs to. The
        /// cap is enforced against this - see `RansomPlan.stepMinutesCap`.
        public static let stepMinutes = "ransom.steps.minutesToday"
        public static let stepMinutesDay = "ransom.steps.minutesDay"
        /// Highest usage rung reached today, and the day it belongs to. Written
        /// by the monitor extension - see `UsageMeter` for why usage has to
        /// arrive as callbacks rather than be read.
        public static let usageMinutes = "ransom.usage.minutes"
        public static let usageDay = "ransom.usage.day"

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
