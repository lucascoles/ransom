import Foundation

/// How many times each app has been stopped at the door today.
///
/// The shield configuration extension is the only thing that reliably knows a
/// blocked app was reached for: it is asked to build a screen every time one is
/// opened, and it is handed the app's name while doing it. Counting there turns
/// the block screen into a record of the reflex - twelve reaches for Instagram
/// before lunch is a fact about the day that nothing else in the app can see.
///
/// Kept as names rather than tokens because that is what the extension is given,
/// and because a count is only worth showing if it can be read out loud.
public struct BlockCountStore {
    private var defaults: UserDefaults { RansomCore.defaults }

    public init() {}

    /// Repeat calls for the same app inside this window count once.
    ///
    /// iOS asks for a shield configuration more than once per presentation - on
    /// rotation, on re-render, sometimes twice on the way in - and a counter that
    /// believed every call would report a number the user knows is wrong, which
    /// discredits the one screen whose whole job is to be believed.
    private static let dedupeWindow: TimeInterval = 3

    public var countsToday: [String: Int] {
        guard let day = defaults.object(forKey: RansomCore.Key.blockCountDay) as? Date,
              Calendar.current.isDateInToday(day),
              let counts = defaults.dictionary(forKey: RansomCore.Key.blockCounts) as? [String: Int]
        else { return [:] }
        return counts
    }

    public var totalToday: Int { countsToday.values.reduce(0, +) }

    /// Most-reached-for first, then alphabetical so equal counts do not shuffle
    /// between redraws.
    public var rankedToday: [(name: String, count: Int)] {
        countsToday.sorted { ($0.value, $1.key) > ($1.value, $0.key) }
            .map { (name: $0.key, count: $0.value) }
    }

    /// Called from the shield each time it is asked to block `app`.
    public func record(app: String) {
        let now = Date()
        let isToday = (defaults.object(forKey: RansomCore.Key.blockCountDay) as? Date)
            .map { Calendar.current.isDateInToday($0) } ?? false

        if isToday,
           defaults.string(forKey: RansomCore.Key.blockCountLastApp) == app,
           let last = defaults.object(forKey: RansomCore.Key.blockCountLastAt) as? Date,
           now.timeIntervalSince(last) < Self.dedupeWindow {
            defaults.set(now, forKey: RansomCore.Key.blockCountLastAt)
            return
        }

        var counts = isToday ? countsToday : [:]
        counts[app, default: 0] += 1
        defaults.set(counts, forKey: RansomCore.Key.blockCounts)
        defaults.set(now, forKey: RansomCore.Key.blockCountDay)
        defaults.set(app, forKey: RansomCore.Key.blockCountLastApp)
        defaults.set(now, forKey: RansomCore.Key.blockCountLastAt)
    }
}
