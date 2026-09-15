import Foundation

/// Steps walked, day by day, kept so there is a lifetime total to level up.
///
/// The pedometer only remembers about a week, and sets are the only thing the
/// workout history records, so without this there was no way to say how far
/// somebody had walked since they started. Written whenever the step tracker
/// reads a day, which includes the week it back-fills, so a new user starts
/// with the last seven days already counted.
struct StepLog {
    private let defaults: UserDefaults
    private static let key = "ransom.steps.log"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private var days: [String: Int] {
        defaults.dictionary(forKey: Self.key) as? [String: Int] ?? [:]
    }

    /// High-water per day. The pedometer reports a running total that climbs
    /// through the day, so a smaller reading for the same day is an earlier one,
    /// never a correction.
    func record(_ steps: Int, on date: Date) {
        guard steps > 0 else { return }
        var days = self.days
        let key = String(UsageHistory.dayStamp(date))
        days[key] = max(days[key] ?? 0, steps)
        defaults.set(days, forKey: Self.key)
    }

    var lifetime: Int { days.values.reduce(0, +) }
}
