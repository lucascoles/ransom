import Foundation

/// The single source of truth for "is scrolling currently allowed", shared between
/// the app (which grants time) and the extensions (which enforce it).
///
/// Everything lives in the App Group so the shield extensions — which run in their
/// own processes and can be spun up at any moment — always read fresh state.
public struct UnlockLedger {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = ReppCore.defaults) {
        self.defaults = defaults
    }

    // MARK: - Earned time

    /// When the current unlock expires, if one is active.
    public var expiry: Date? {
        get {
            let seconds = defaults.double(forKey: ReppCore.Key.unlockExpiry)
            guard seconds > 0 else { return nil }
            return Date(timeIntervalSince1970: seconds)
        }
        nonmutating set {
            if let newValue {
                defaults.set(newValue.timeIntervalSince1970, forKey: ReppCore.Key.unlockExpiry)
            } else {
                defaults.removeObject(forKey: ReppCore.Key.unlockExpiry)
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

    // MARK: - Unlock requests from the shield

    /// Set by the shield action extension when the user taps "Earn Time" on a blocked
    /// app, so the app can drop the user straight into a workout on next launch.
    public var pendingRequest: Date? {
        get {
            let seconds = defaults.double(forKey: ReppCore.Key.pendingUnlockRequest)
            guard seconds > 0 else { return nil }
            return Date(timeIntervalSince1970: seconds)
        }
        nonmutating set {
            if let newValue {
                defaults.set(newValue.timeIntervalSince1970, forKey: ReppCore.Key.pendingUnlockRequest)
            } else {
                defaults.removeObject(forKey: ReppCore.Key.pendingUnlockRequest)
            }
        }
    }

    public var pendingAppName: String? {
        get { defaults.string(forKey: ReppCore.Key.pendingUnlockAppName) }
        nonmutating set { defaults.set(newValue, forKey: ReppCore.Key.pendingUnlockAppName) }
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
        defaults.removeObject(forKey: ReppCore.Key.pendingUnlockAppName)
    }

    // MARK: - The tariff counter

    /// Unlocks bought today. Rolls over on its own at midnight, so nothing has to
    /// run at midnight to reset it.
    public var unlocksToday: Int {
        let storedDay = defaults.integer(forKey: ReppCore.Key.unlockCountDay)
        guard storedDay == Self.dayStamp() else { return 0 }
        return defaults.integer(forKey: ReppCore.Key.unlocksToday)
    }

    public var lastUnlockAt: Date? {
        let seconds = defaults.double(forKey: ReppCore.Key.lastUnlockAt)
        guard seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    /// Call once per completed set, after the time is granted.
    public func recordUnlock(now: Date = Date()) {
        let today = Self.dayStamp(now)
        let current = defaults.integer(forKey: ReppCore.Key.unlockCountDay) == today
            ? defaults.integer(forKey: ReppCore.Key.unlocksToday)
            : 0
        defaults.set(current + 1, forKey: ReppCore.Key.unlocksToday)
        defaults.set(today, forKey: ReppCore.Key.unlockCountDay)
        defaults.set(now.timeIntervalSince1970, forKey: ReppCore.Key.lastUnlockAt)
    }

    public var nightSurchargeEnabled: Bool {
        get {
            // Absent means on: the late-night rate is the default.
            defaults.object(forKey: ReppCore.Key.nightSurcharge) as? Bool ?? true
        }
        nonmutating set { defaults.set(newValue, forKey: ReppCore.Key.nightSurcharge) }
    }

    /// What the next unlock costs right now. The shield and the app both price
    /// from here, so they can never disagree.
    public func currentQuote(now: Date = Date()) -> Tariff.Quote {
        Tariff.quote(
            base: repsPerUnlock,
            unlocksToday: unlocksToday,
            lastUnlockAt: lastUnlockAt,
            nightSurchargeEnabled: nightSurchargeEnabled,
            now: now
        )
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
        defaults.set(reps, forKey: ReppCore.Key.repsPerUnlock)
        defaults.set(minutes, forKey: ReppCore.Key.minutesPerUnlock)
        defaults.set(exercise.title, forKey: ReppCore.Key.exerciseName)
    }

    public var repsPerUnlock: Int {
        let value = defaults.integer(forKey: ReppCore.Key.repsPerUnlock)
        return value > 0 ? value : 10
    }

    public var minutesPerUnlock: Int {
        let value = defaults.integer(forKey: ReppCore.Key.minutesPerUnlock)
        return value > 0 ? value : 15
    }

    public var exerciseName: String {
        defaults.string(forKey: ReppCore.Key.exerciseName) ?? Exercise.pushUps.title
    }
}
