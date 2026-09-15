import Foundation

/// A rolling record of how long each day cost, so a trend can be drawn.
///
/// Nothing kept history before this. Both usage stores held today and overwrote
/// it at midnight, which is enough to answer "how is today going" and useless for
/// "is this working", the question a progress screen actually exists to answer.
///
/// One series, `guarded`: the monitor extension's threshold ladder, day by day.
/// There was a second, `device`, written by the report extension - but iOS drops
/// every App Group write that extension makes, so it was never filled in. The
/// Progress cards now get exact daily figures by being drawn in the report
/// extension itself (`ScreenTimeSummary`), and nothing on screen reads this.
public struct UsageHistory {
    private var defaults: UserDefaults { RansomCore.defaults }

    public init() {}

    public enum Series {
        case guarded

        var key: String { RansomCore.Key.usageHistory }
    }

    /// Three years, which is effectively "keep it".
    ///
    /// A day is one small integer under one short key, so a full year costs a few
    /// kilobytes and there is no reason to throw any of it away - week-over-week
    /// is the first question this answers and the least interesting one. The cap
    /// exists only so a phone nobody ever reinstalls cannot grow this without
    /// bound.
    private static let daysKept = 1_100

    /// Days since the epoch, which is a cheap timezone-local day identity and the
    /// same one `UnlockLedger` uses for the bank rollover.
    public static func dayStamp(_ date: Date = Date(), calendar: Calendar = .current) -> Int {
        Int(calendar.startOfDay(for: date).timeIntervalSince1970 / 86_400)
    }

    private func read(_ series: Series) -> [String: Int] {
        defaults.dictionary(forKey: series.key) as? [String: Int] ?? [:]
    }

    /// Minutes for a given day, or nil if that day was never recorded. Nil and
    /// zero are different answers - one is "they did not open it", the other is
    /// "they did not use it" - and a chart that draws them the same way is lying.
    public func minutes(_ series: Series, on date: Date) -> Int? {
        read(series)[String(Self.dayStamp(date))]
    }

    /// The last `days` days, oldest first, one entry per calendar day.
    public func recent(_ series: Series, days: Int) -> [(date: Date, minutes: Int?)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<days).reversed().compactMap { back in
            guard let date = calendar.date(byAdding: .day, value: -back, to: today) else { return nil }
            return (date: date, minutes: minutes(series, on: date))
        }
    }

    /// High-water only. A day's figure never goes down: both sources report a
    /// running total that climbs, and a later smaller reading means the source
    /// restarted rather than that the user un-used their phone.
    public func record(_ series: Series, minutes: Int, on date: Date = Date()) {
        var days = read(series)
        let key = String(Self.dayStamp(date))
        days[key] = max(days[key] ?? 0, minutes)

        // Drop anything past the window, so this cannot grow without bound on a
        // phone that is never reinstalled.
        let cutoff = Self.dayStamp(date) - Self.daysKept
        for stamp in days.keys where (Int(stamp) ?? 0) < cutoff {
            days.removeValue(forKey: stamp)
        }
        defaults.set(days, forKey: series.key)
    }
}
