import Foundation

/// The single source of truth for "is scrolling currently allowed", shared between
/// the app (which grants time) and the extensions (which enforce it).
///
/// Everything lives in the App Group so the shield extensions — which run in their
/// own processes and can be spun up at any moment — always read fresh state.
public struct UnlockLedger {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = RansomCore.defaults) {
        self.defaults = defaults
    }

    // MARK: - Earned time

    /// When the current unlock expires, if one is active.
    public var expiry: Date? {
        get {
            let seconds = defaults.double(forKey: RansomCore.Key.unlockExpiry)
            guard seconds > 0 else { return nil }
            return Date(timeIntervalSince1970: seconds)
        }
        nonmutating set {
            if let newValue {
                defaults.set(newValue.timeIntervalSince1970, forKey: RansomCore.Key.unlockExpiry)
            } else {
                defaults.removeObject(forKey: RansomCore.Key.unlockExpiry)
            }
        }
    }

    public var isUnlocked: Bool {
        guard let expiry else { return false }
        return expiry > Date()
    }

    public var remaining: TimeInterval {
        guard let expiry else { return 0 }
        return max(0, expiry.timeIntervalSinceNow)
    }

    /// Adds earned minutes, stacking on top of any time that is still running.
    @discardableResult
    public func grant(minutes: Int, now: Date = Date()) -> Date {
        let base = (expiry.map { max($0, now) }) ?? now
        let newExpiry = base.addingTimeInterval(TimeInterval(minutes * 60))
        expiry = newExpiry
        return newExpiry
    }

    public func revoke() {
        expiry = nil
    }

    // MARK: - The minute bank

    /// Minutes earned and not yet spent.
    ///
    /// The bank is what separates earning from spending. Under the old model a set
    /// bought one unlock right now, so exercising was only ever worth doing at the
    /// moment you were already blocked and already annoyed. Banking means a walk at
    /// lunchtime is worth something at nine in the evening, which is the only way
    /// the exercise becomes a habit rather than a toll.
    /// Cleared at midnight, deliberately.
    ///
    /// A balance that carries forever turns into a stockpile: a keen first week
    /// funds a month of scrolling, and the exercise stops being a daily habit and
    /// becomes a chore you front-load and then coast on. Use it or lose it keeps
    /// the deal the same every morning.
    ///
    /// The rollover is read on access rather than run by a timer, so a phone that
    /// slept through midnight still wakes to an empty bank.
    public var bankedMinutes: Int {
        get {
            guard let day = defaults.object(forKey: RansomCore.Key.bankDay) as? Date,
                  Calendar.current.isDateInToday(day) else { return 0 }
            return defaults.integer(forKey: RansomCore.Key.bankedMinutes)
        }
        nonmutating set {
            defaults.set(max(0, newValue), forKey: RansomCore.Key.bankedMinutes)
            defaults.set(Date(), forKey: RansomCore.Key.bankDay)
        }
    }

    /// Minutes spent from the bank today.
    ///
    /// Read by the daily screen-time target, which is about consumption. Before
    /// the bank existed a set granted its own minutes immediately, so "earned
    /// today" and "spent today" were the same number and one counter did both
    /// jobs. They are now entirely different quantities: someone can bank two
    /// hours on a long walk and spend none of it.
    public var spentMinutesToday: Int {
        get {
            guard let day = defaults.object(forKey: RansomCore.Key.spentDay) as? Date,
                  Calendar.current.isDateInToday(day) else { return 0 }
            return defaults.integer(forKey: RansomCore.Key.spentMinutes)
        }
        nonmutating set {
            defaults.set(max(0, newValue), forKey: RansomCore.Key.spentMinutes)
            defaults.set(Date(), forKey: RansomCore.Key.spentDay)
        }
    }

    /// Minutes earned go here rather than straight into an unlock.
    public func bank(minutes: Int) {
        guard minutes > 0 else { return }
        bankedMinutes += minutes
    }

    /// Debits the bank and reports what it actually took, which is less than
    /// asked for when the balance is short.
    ///
    /// It deliberately does **not** start the clock. Granting belongs to
    /// `ScreenTimeManager.grantEarnedTime`, which also lifts the shield, restarts
    /// monitoring and schedules the reminder — and callers have to invoke that
    /// anyway. When this granted as well, the two stacked and a fifteen-minute
    /// spend opened the apps for thirty. The same mistake was made once before
    /// with `completeSet`; the comment there records it too.
    @discardableResult
    public func spend(minutes: Int) -> Int {
        let spent = min(max(0, minutes), bankedMinutes)
        guard spent > 0 else { return 0 }
        bankedMinutes -= spent
        spentMinutesToday += spent
        return spent
    }

    // MARK: - Unlock requests from the shield

    /// Set by the shield action extension when the user taps "Earn Time" on a blocked
    /// app, so the app can drop the user straight into a workout on next launch.
    public var pendingRequest: Date? {
        get {
            let seconds = defaults.double(forKey: RansomCore.Key.pendingUnlockRequest)
            guard seconds > 0 else { return nil }
            return Date(timeIntervalSince1970: seconds)
        }
        nonmutating set {
            if let newValue {
                defaults.set(newValue.timeIntervalSince1970, forKey: RansomCore.Key.pendingUnlockRequest)
            } else {
                defaults.removeObject(forKey: RansomCore.Key.pendingUnlockRequest)
            }
        }
    }

    public var pendingAppName: String? {
        get { defaults.string(forKey: RansomCore.Key.pendingUnlockAppName) }
        nonmutating set { defaults.set(newValue, forKey: RansomCore.Key.pendingUnlockAppName) }
    }

    /// A request only counts if it is fresh — a two-day-old tap shouldn't hijack a launch.
    public func consumePendingRequest(maxAge: TimeInterval = 15 * 60) -> String?? {
        guard let pendingRequest, Date().timeIntervalSince(pendingRequest) < maxAge else {
            clearPendingRequest()
            return nil
        }
        let name = pendingAppName
        clearPendingRequest()
        return .some(name)
    }

    public func clearPendingRequest() {
        pendingRequest = nil
        defaults.removeObject(forKey: RansomCore.Key.pendingUnlockAppName)
    }

    // MARK: - The tariff counter

    /// Unlocks bought today. Rolls over on its own at midnight, so nothing has to
    /// run at midnight to reset it.
    public var unlocksToday: Int {
        let storedDay = defaults.integer(forKey: RansomCore.Key.unlockCountDay)
        guard storedDay == Self.dayStamp() else { return 0 }
        return defaults.integer(forKey: RansomCore.Key.unlocksToday)
    }

    public var lastUnlockAt: Date? {
        let seconds = defaults.double(forKey: RansomCore.Key.lastUnlockAt)
        guard seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    /// Call once per completed set, after the time is granted.
    public func recordUnlock(now: Date = Date()) {
        let today = Self.dayStamp(now)
        let current = defaults.integer(forKey: RansomCore.Key.unlockCountDay) == today
            ? defaults.integer(forKey: RansomCore.Key.unlocksToday)
            : 0
        defaults.set(current + 1, forKey: RansomCore.Key.unlocksToday)
        defaults.set(today, forKey: RansomCore.Key.unlockCountDay)
        defaults.set(now.timeIntervalSince1970, forKey: RansomCore.Key.lastUnlockAt)
    }

    public var nightSurchargeEnabled: Bool {
        get {
            // Absent means on: the late-night rate is the default.
            defaults.object(forKey: RansomCore.Key.nightSurcharge) as? Bool ?? true
        }
        nonmutating set { defaults.set(newValue, forKey: RansomCore.Key.nightSurcharge) }
    }


    /// Days since the epoch — a cheap, timezone-local day identity.
    private static func dayStamp(_ date: Date = Date(), calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: date)
        return Int(start.timeIntervalSince1970 / 86_400)
    }

    // MARK: - Config mirrored for the extensions

    /// The shield extensions can't read the app's main store, so the app mirrors the
    /// handful of values the shield needs to render accurate copy.
    public func mirrorConfig(reps: Int, minutes: Int, exercise: Exercise) {
        defaults.set(reps, forKey: RansomCore.Key.repsPerUnlock)
        defaults.set(minutes, forKey: RansomCore.Key.minutesPerUnlock)
        defaults.set(exercise.title, forKey: RansomCore.Key.exerciseName)
    }

    public var repsPerUnlock: Int {
        let value = defaults.integer(forKey: RansomCore.Key.repsPerUnlock)
        return value > 0 ? value : 10
    }

    public var minutesPerUnlock: Int {
        let value = defaults.integer(forKey: RansomCore.Key.minutesPerUnlock)
        return value > 0 ? value : 15
    }

    public var exerciseName: String {
        defaults.string(forKey: RansomCore.Key.exerciseName) ?? Exercise.pushUps.title
    }
}
