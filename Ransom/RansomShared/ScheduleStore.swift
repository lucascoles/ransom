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
///
/// The app writes the whole `WeekSchedule`, pending week included, so a day off
/// that is still waiting begins on time in every process without any of them
/// being told. The extensions only ever read.
public struct ScheduleStore {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = RansomCore.defaults) {
        self.defaults = defaults
    }

    public var schedule: WeekSchedule {
        get {
            let days = (defaults.array(forKey: RansomCore.Key.activeDays) as? [Int]).map(Set.init) ?? []
            // Both halves or neither. A pending set with no date, or a date with
            // no set, is not a pending week and is read as none - which is also
            // what an install from before pending weeks existed has.
            guard let pending = (defaults.array(forKey: RansomCore.Key.pendingDays) as? [Int]).map(Set.init),
                  let from = defaults.object(forKey: RansomCore.Key.pendingFrom) as? Date
            else {
                return WeekSchedule(days: days)
            }
            return WeekSchedule(days: days, pendingDays: pending, pendingFrom: from)
        }
        nonmutating set {
            defaults.set(Array(newValue.days).sorted(), forKey: RansomCore.Key.activeDays)
            if let pending = newValue.pendingDays, let from = newValue.pendingFrom {
                defaults.set(Array(pending).sorted(), forKey: RansomCore.Key.pendingDays)
                defaults.set(from, forKey: RansomCore.Key.pendingFrom)
            } else {
                defaults.removeObject(forKey: RansomCore.Key.pendingDays)
                defaults.removeObject(forKey: RansomCore.Key.pendingFrom)
            }
        }
    }

    public func isActive(on date: Date = Date(), calendar: Calendar = .current) -> Bool {
        schedule.isActive(on: date, calendar: calendar)
    }
}
