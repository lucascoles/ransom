import Foundation

/// Which days of the week Ransom is on duty.
///
/// Somebody who guards their apps Monday to Friday and wants their Saturday back
/// is not cheating; the app being all-or-nothing is what makes people turn it off
/// entirely rather than turn it down. Days off are a supported answer.
///
/// Lives in the App Group because the shield and the monitor extension enforce
/// it in their own processes. A day off that only the app knew about would show
/// a home screen saying "you're free today" over apps that were still shielded.
public struct ScheduleStore {
    private var defaults: UserDefaults { RansomCore.defaults }

    public init() {}

    /// `Calendar` weekday numbers, 1 = Sunday. Empty means every day, which is
    /// also what a profile that predates this setting decodes to - so the
    /// default is the behaviour everyone already had.
    public var activeDays: Set<Int> {
        get {
            guard let raw = defaults.array(forKey: RansomCore.Key.activeDays) as? [Int] else { return [] }
            return Set(raw)
        }
        nonmutating set {
            defaults.set(Array(newValue).sorted(), forKey: RansomCore.Key.activeDays)
        }
    }

    public func isActive(on date: Date = Date(), calendar: Calendar = .current) -> Bool {
        let days = activeDays
        guard !days.isEmpty else { return true }
        return days.contains(calendar.component(.weekday, from: date))
    }
}
