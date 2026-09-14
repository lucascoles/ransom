import Foundation

/// The days Ransom is on duty, and a quieter week that is on its way if one is.
///
/// Two sets rather than one because a day off, asked for while a run is live,
/// does not start when it is asked for. `days` is what the shield enforces now;
/// `pendingDays` is what it will enforce from `pendingFrom`. Both processes that
/// read this - the app and the monitor extension - resolve the pair the same
/// way through `days(at:)`, so nothing has to run at the exact moment the
/// pending week begins for it to begin.
public struct WeekSchedule: Codable, Equatable {
    /// `Calendar` weekday numbers, 1 = Sunday. Empty means every day, which is
    /// also what a profile that predates this setting decodes to - so the
    /// default is the behaviour everyone already had.
    public var days: Set<Int>

    /// A looser week waiting for its start date. Nil when nothing is waiting.
    /// Never empty: a pending set is always one with at least one day removed
    /// from `days`, so it is stored as the days themselves rather than in the
    /// empty-means-all form.
    public var pendingDays: Set<Int>?
    public var pendingFrom: Date?

    public static let everyDay: Set<Int> = Set(1...7)

    public init(days: Set<Int> = [], pendingDays: Set<Int>? = nil, pendingFrom: Date? = nil) {
        self.days = days
        self.pendingDays = pendingDays
        self.pendingFrom = pendingFrom
    }

    // MARK: - Conventions

    /// Seven real days for the stored empty-means-all convention.
    public static func normalized(_ days: Set<Int>) -> Set<Int> {
        days.isEmpty ? everyDay : days
    }

    /// Back to storage form: all seven days stores as empty, so a picker that
    /// was filled in by hand and one that was never touched persist the same.
    public static func stored(_ days: Set<Int>) -> Set<Int> {
        days.count == everyDay.count ? [] : days
    }

    // MARK: - Reading

    public var hasPending: Bool {
        pendingDays != nil && pendingFrom != nil
    }

    /// The days on duty at a moment, in storage form: the pending week once its
    /// date has come, otherwise `days`.
    public func days(at now: Date = Date()) -> Set<Int> {
        if let pendingDays, let pendingFrom, pendingFrom <= now {
            return Self.stored(pendingDays)
        }
        return days
    }

    /// Where the week is headed: the pending set if there is one, else `days`.
    /// This is what a picker edits, so that a day already asked off shows as
    /// asked off rather than snapping back on.
    public var targetDays: Set<Int> {
        pendingDays.map(Self.stored) ?? days
    }

    public func isActive(on date: Date = Date(), calendar: Calendar = .current) -> Bool {
        let active = days(at: date)
        guard !active.isEmpty else { return true }
        return active.contains(calendar.component(.weekday, from: date))
    }

    /// Folds a pending week that has begun into `days`. Reading through
    /// `days(at:)` already gives the right answer without this; it exists so
    /// the stored value stops carrying a change that has already happened.
    public func settled(at now: Date = Date()) -> WeekSchedule {
        guard let pendingDays, let pendingFrom, pendingFrom <= now else { return self }
        return WeekSchedule(days: Self.stored(pendingDays))
    }
}

// MARK: - The rule for changing it

/// When a change to the days on duty takes effect.
///
/// Ransom is a commitment device, and the days are the softest thing in it to
/// reach for from inside a craving: one tap and today is a day off. The old rule
/// was to lock them for the whole run, which was airtight and also a trap - the
/// intake never asks about days, so everyone starts on all seven, locked, for as
/// long as they committed to.
///
/// The rule now is asymmetric, the same way the difficulty lock is:
///
/// - **Stricter is always immediate.** Turning a day on never needs friction.
/// - **Looser waits a week.** Turning a day off while a run is live is allowed
///   as often as they like, but it starts seven days after it is asked for. A
///   week is long enough that whatever they wanted the day off *for* is over,
///   which is the whole test - a change that survives the craving that
///   prompted it was a real decision.
/// - **The first two days are free.** Everything applies at once while a
///   profile is younger than `graceLength`, so a week that was never really
///   chosen can be chosen. The grace runs from the profile's creation, not the
///   run's start, so extending a run does not reopen it.
/// - **No run, no rule.** Once the commitment has ended, everything is free
///   again, exactly as the difficulty is.
///
/// Waiting rather than rationing ("one change a week") because a ration is a
/// guaranteed escape hatch: whenever it is unspent, the next craving can spend
/// it, and the craving is the exact moment the app is supposed to hold. A wait
/// can be used any number of times and never helps *now*.
public struct ScheduleChangeRule {
    /// How long after the profile is created the days can be changed freely.
    public static let graceHours = 48
    /// How long a day off waits when a run is live.
    public static let waitDays = 7

    /// When the current run ends. Nil when no run has been committed to.
    public var lockEndsAt: Date?
    /// When the grace after intake ends.
    public var graceEndsAt: Date
    public var calendar: Calendar

    public init(lockEndsAt: Date?, graceEndsAt: Date, calendar: Calendar = .current) {
        self.lockEndsAt = lockEndsAt
        self.graceEndsAt = graceEndsAt
        self.calendar = calendar
    }

    /// The grace end for a profile created at a moment.
    public static func graceEnd(forProfileCreatedAt createdAt: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .hour, value: graceHours, to: createdAt) ?? createdAt
    }

    public enum Outcome: Equatable {
        /// The target is what is already on duty. Any pending week is withdrawn.
        case unchanged
        /// Applied on the spot.
        case now
        /// Days added are on duty now; days removed come off on the date.
        case later(Date)
    }

    /// Whether a run is live at a moment.
    public func isLocked(at now: Date) -> Bool {
        guard let lockEndsAt else { return false }
        return lockEndsAt > now
    }

    /// Whether the profile is still inside the grace after intake.
    public func isInGrace(at now: Date) -> Bool {
        now < graceEndsAt
    }

    /// Whether a looser week would start at once rather than wait.
    public func allowsLooseningNow(at now: Date) -> Bool {
        !isLocked(at: now) || isInGrace(at: now)
    }

    /// The schedule after asking for `target` as the week, and what happened.
    ///
    /// `target` uses the storage convention: empty is every day. Anything that
    /// is stricter than what is on duty now lands immediately, anything looser
    /// waits, and the two halves of a mixed change go their separate ways.
    public func applying(_ target: Set<Int>, to schedule: WeekSchedule, now: Date) -> (schedule: WeekSchedule, outcome: Outcome) {
        let current = WeekSchedule.normalized(schedule.days(at: now))
        let wanted = WeekSchedule.normalized(target)

        // Asking for the week that is already on duty withdraws whatever was
        // waiting. Putting a day back on before its day off began is the one
        // kind of change-of-heart that should always be honoured.
        guard wanted != current else {
            return (WeekSchedule(days: WeekSchedule.stored(current)), .unchanged)
        }

        let removed = current.subtracting(wanted)
        if removed.isEmpty || allowsLooseningNow(at: now) {
            return (WeekSchedule(days: WeekSchedule.stored(wanted)), .now)
        }

        // Looser, with a run live. The days being added are on duty from now;
        // the days coming off wait.
        var from = calendar.date(byAdding: .day, value: Self.waitDays, to: now) ?? now
        if let pendingDays = schedule.pendingDays, let pendingFrom = schedule.pendingFrom, pendingFrom > now {
            // A wait already served counts. Putting one pending day back on
            // should not push the others out another week, so the date is kept
            // whenever nothing new is coming off duty. Taking a further day off
            // starts the clock again - for all of them, said plainly on screen,
            // because a fresh removal that inherited an old date would land a
            // day off tomorrow.
            let alreadyComingOff = current.subtracting(WeekSchedule.normalized(pendingDays))
            if removed.isSubset(of: alreadyComingOff) { from = pendingFrom }
        }

        return (
            WeekSchedule(
                days: WeekSchedule.stored(current.union(wanted)),
                pendingDays: wanted,
                pendingFrom: from
            ),
            .later(from)
        )
    }
}
