import Foundation

/// Total screen time for the whole phone, as measured by the report extension.
///
/// Distinct from `UsageMeter`, and the difference matters: the meter counts only
/// the apps Ransom guards, in fifteen-minute rungs, using threshold callbacks
/// that Apple documents. This is every app on the phone, to the minute, taken
/// from `DeviceActivityResults` - which only exists inside a
/// `DeviceActivityReport` extension and is never handed to an app.
///
/// The extension writes here; the app reads. That crossing is not a documented
/// capability and a future iOS could close it, so nothing depends on it: when
/// this is empty or stale the app falls back to the meter, and says which number
/// it is showing.
public struct DeviceUsageStore {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = RansomCore.defaults) {
        self.defaults = defaults
    }

    /// Minutes across the whole device today, or nil when the report has never
    /// rendered - which is the normal state until the user opens the screen that
    /// hosts it, since an extension nobody has looked at has never run.
    public var minutesToday: Int? {
        guard let day = defaults.object(forKey: RansomCore.Key.deviceUsageDay) as? Date,
              Calendar.current.isDateInToday(day) else { return nil }
        return defaults.integer(forKey: RansomCore.Key.deviceUsageMinutes)
    }

    public var measuredAt: Date? {
        defaults.object(forKey: RansomCore.Key.deviceUsageDay) as? Date
    }

    /// How many app rows the report drew last time, or nil before it ever has.
    public var appCount: Int? {
        guard minutesToday != nil else { return nil }
        return defaults.integer(forKey: RansomCore.Key.deviceUsageAppCount)
    }

    public func record(totalMinutes: Int, appCount: Int) {
        defaults.set(totalMinutes, forKey: RansomCore.Key.deviceUsageMinutes)
        defaults.set(appCount, forKey: RansomCore.Key.deviceUsageAppCount)
        defaults.set(Date(), forKey: RansomCore.Key.deviceUsageDay)
    }
}
