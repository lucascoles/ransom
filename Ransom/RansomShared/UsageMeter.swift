import Foundation

/// How long the user has actually spent in their guarded apps today.
///
/// There is no API that reads screen time as a number. `DeviceActivityReport` can
/// render it and hand back nothing; asking iOS "how many minutes so far" is not a
/// question the system answers.
///
/// What it *will* do is call you back. A `DeviceActivityEvent` fires when usage of
/// a chosen set of apps crosses a threshold, and the monitor extension that
/// receives it can write to the App Group. So registering a ladder of thresholds -
/// 15 minutes, 30, 45, and on - turns "how long have they been in there" into a
/// series of callbacks, and the highest rung reached is the answer.
///
/// The cost is resolution. This knows the user has passed 45 minutes and has not
/// yet passed an hour; it does not know they are at 52. Everything shown from it
/// has to be honest about being a floor rather than a reading, which is why the
/// number is quoted as the rung and never interpolated between two of them.
public struct UsageMeter {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = RansomCore.defaults) {
        self.defaults = defaults
    }

    /// The ladder, fine where it matters and coarse where it stops mattering.
    ///
    /// Every rung is a registered `DeviceActivityEvent`, and iOS will not take an
    /// unlimited number of them, so they are not evenly spaced: a quarter of an
    /// hour is a meaningful step early in the day and a rounding error once
    /// somebody is four hours in.
    public static let milestones: [Int] = {
        let quarterHours = stride(from: 15, through: 240, by: 15)
        let halfHours = stride(from: 270, through: 600, by: 30)
        return Array(quarterHours) + Array(halfHours)
    }()

    private static let eventPrefix = "ransom.usage."

    /// Event name for a rung, and back again. One function each way, next to each
    /// other, because the two halves living in different files is how the app and
    /// the extension end up disagreeing about what a callback meant.
    public static func eventName(forMinutes minutes: Int) -> String {
        "\(eventPrefix)\(minutes)"
    }

    public static func minutes(fromEventName name: String) -> Int? {
        guard name.hasPrefix(eventPrefix) else { return nil }
        return Int(name.dropFirst(eventPrefix.count))
    }

    /// The highest rung reached today. Zero before the first one fires, which is
    /// indistinguishable from "under fifteen minutes" - and deliberately so, since
    /// those are the same thing as far as this can tell.
    public var minutesToday: Int {
        guard let day = defaults.object(forKey: RansomCore.Key.usageDay) as? Date,
              Calendar.current.isDateInToday(day) else { return 0 }
        return defaults.integer(forKey: RansomCore.Key.usageMinutes)
    }

    /// Whether monitoring has ever reported anything at all.
    ///
    /// Without this, a phone that has never been granted Screen Time access and a
    /// phone whose owner has genuinely not opened anything both read zero, and the
    /// first would be shown a saving it has not earned.
    public var isMeasuring: Bool {
        defaults.object(forKey: RansomCore.Key.usageDay) != nil
    }

    /// Records a rung. High-water only: thresholds can fire out of order after a
    /// restart, and a later callback for a lower rung must never walk the day's
    /// usage backwards.
    public nonmutating func record(minutes: Int) {
        let isToday = (defaults.object(forKey: RansomCore.Key.usageDay) as? Date)
            .map { Calendar.current.isDateInToday($0) } ?? false
        let current = isToday ? defaults.integer(forKey: RansomCore.Key.usageMinutes) : 0
        defaults.set(max(current, minutes), forKey: RansomCore.Key.usageMinutes)
        defaults.set(Date(), forKey: RansomCore.Key.usageDay)
    }

    /// Called when monitoring starts, so the ladder begins from the bottom on a
    /// new day rather than reporting yesterday's total until the first rung fires.
    ///
    /// Guarded on the date because `intervalDidStart` is not a once-a-day event:
    /// the schedule spans the whole day, so restarting monitoring - which happens
    /// on every spend and every change to the app list - fires it immediately.
    /// Unguarded, that reset today's usage to zero several times a day and the
    /// number on the home screen only ever counted the last few minutes.
    public nonmutating func startDay() {
        let isToday = (defaults.object(forKey: RansomCore.Key.usageDay) as? Date)
            .map { Calendar.current.isDateInToday($0) } ?? false
        guard !isToday else { return }
        defaults.set(0, forKey: RansomCore.Key.usageMinutes)
        defaults.set(Date(), forKey: RansomCore.Key.usageDay)
    }
}
