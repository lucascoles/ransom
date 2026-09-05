import Foundation

/// A window the user has named and committed to, during which everything costs
/// double.
///
/// The bank makes unlocking a phone a transaction, and a transaction is easy to
/// justify one at a time. A rule is the user deciding in advance that between
/// 5:30 and 6:30 on gym days they would rather not be negotiating with themselves
/// at all - so the price goes up, and going to the phone during the thing they
/// said mattered costs twice what it costs the rest of the day.
///
/// The point is not the revenue, it is the friction. Naming the window is what
/// makes it a decision rather than a mood: "Gym Time" is a promise the user made
/// in a calm moment to a version of themselves who will be looking for a reason.
public struct FocusRule: Codable, Identifiable, Equatable, Hashable {
    public var id: UUID
    /// What they are protecting. Shown back to them everywhere the rule bites.
    public var name: String
    /// Minutes from midnight, local time. Stored rather than a `Date` because a
    /// rule is a time of day, not a moment - it has to survive the date changing.
    public var startMinutes: Int
    public var endMinutes: Int
    /// `Calendar` weekday numbers, 1 = Sunday. Empty means every day.
    public var days: Set<Int>
    public var isEnabled: Bool

    public init(id: UUID = UUID(), name: String, startMinutes: Int, endMinutes: Int,
                days: Set<Int> = [], isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
        self.days = days
        self.isEnabled = isEnabled
    }

    /// What a set costs while a rule is running. Double, and deliberately not
    /// configurable: a dial for how serious you are is a dial you turn down.
    public static let difficultyMultiplier = 2

    /// Runs past midnight. The end time being at or before the start is how the
    /// user says "until the small hours" without a second control for it.
    public var crossesMidnight: Bool { endMinutes <= startMinutes }

    public var lengthMinutes: Int {
        crossesMidnight ? (24 * 60 - startMinutes) + endMinutes : endMinutes - startMinutes
    }

    /// Whether this rule is live right now.
    ///
    /// The weekday is checked against the day the window *started*, not today, or
    /// a rule that runs 11pm to 1am on Mondays would switch itself off at midnight
    /// halfway through the thing it is protecting.
    public func isActive(at date: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard isEnabled else { return false }
        let minutes = calendar.component(.hour, from: date) * 60
            + calendar.component(.minute, from: date)
        let weekday = calendar.component(.weekday, from: date)

        if crossesMidnight {
            if minutes >= startMinutes { return runs(on: weekday) }
            if minutes < endMinutes {
                // Still inside last night's window, so it is yesterday's rule.
                let yesterday = weekday == 1 ? 7 : weekday - 1
                return runs(on: yesterday)
            }
            return false
        }
        return minutes >= startMinutes && minutes < endMinutes && runs(on: weekday)
    }

    public func runs(on weekday: Int) -> Bool {
        days.isEmpty || days.contains(weekday)
    }

    /// The next time this rule starts, for "starts in 20 minutes" copy.
    public func nextStart(after date: Date = Date(), calendar: Calendar = .current) -> Date? {
        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: date),
                  let start = calendar.date(bySettingHour: startMinutes / 60,
                                            minute: startMinutes % 60,
                                            second: 0, of: day)
            else { continue }
            guard start > date, runs(on: calendar.component(.weekday, from: start)) else { continue }
            return start
        }
        return nil
    }
}

/// The user's rules, in the App Group so the shield can price against them too.
///
/// The shield runs in its own process and cannot ask the app anything, so a rule
/// that only existed in the app would double the price on the earn screen and
/// leave the block screen quoting the old number - two prices for the same set,
/// which is the fastest way to make the whole economy look made up.
public struct FocusRuleStore {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = RansomCore.defaults) {
        self.defaults = defaults
    }

    public var rules: [FocusRule] {
        get {
            guard let data = defaults.data(forKey: RansomCore.Key.focusRules),
                  let decoded = try? JSONDecoder().decode([FocusRule].self, from: data)
            else { return [] }
            return decoded
        }
        nonmutating set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: RansomCore.Key.focusRules)
        }
    }

    public func activeRule(at date: Date = Date()) -> FocusRule? {
        rules.first { $0.isActive(at: date) }
    }

    /// 2 while any rule is running, 1 otherwise. Every price in the app goes
    /// through this rather than each screen checking for itself, so there is only
    /// ever one answer to what a set costs.
    public func multiplier(at date: Date = Date()) -> Int {
        activeRule(at: date) == nil ? 1 : FocusRule.difficultyMultiplier
    }
}
