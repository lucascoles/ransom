import Foundation
import Testing
@testable import Ransom

/// The days on duty, and when a change to them takes effect.
///
/// Every bug here is a bug in a commitment device: either a day off that lands
/// the moment it is asked for, which is the escape hatch the rule exists to
/// close, or a day on that never lands, which is the app refusing to be made
/// stricter. Dates are fixed and the calendar is pinned to one zone so the
/// boundaries are exact rather than "about a week".
@Suite("Days on duty")
struct ScheduleTests {

    /// Sunday 13 September 2026, 09:00 UTC. A Sunday so the weekday numbers
    /// in these tests read the same as `Calendar`'s (1 = Sunday).
    private static let sunday = Date(timeIntervalSince1970: 1_789_290_000)

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private static func days(_ count: Int, after date: Date) -> Date {
        calendar.date(byAdding: .day, value: count, to: date)!
    }

    private static func hours(_ count: Int, after date: Date) -> Date {
        calendar.date(byAdding: .hour, value: count, to: date)!
    }

    private static let weekdays = WeekSchedule.everyDay.subtracting([1, 7])

    /// A run that ends in thirty days, whose grace ended long ago.
    private func lockedRule(now: Date = ScheduleTests.sunday) -> ScheduleChangeRule {
        ScheduleChangeRule(
            lockEndsAt: Self.days(30, after: now),
            graceEndsAt: Self.days(-10, after: now),
            calendar: Self.calendar
        )
    }

    // MARK: - Reading the week

    @Test("The fixed date is the Sunday it claims to be")
    func fixture() {
        #expect(Self.calendar.component(.weekday, from: Self.sunday) == 1)
        #expect(Self.calendar.component(.day, from: Self.sunday) == 13)
        #expect(Self.calendar.component(.month, from: Self.sunday) == 9)
    }

    @Test("Empty means every day")
    func emptyIsEveryDay() {
        let schedule = WeekSchedule()
        for offset in 0..<7 {
            #expect(schedule.isActive(on: Self.days(offset, after: Self.sunday), calendar: Self.calendar))
        }
        #expect(WeekSchedule.normalized([]) == WeekSchedule.everyDay)
        #expect(WeekSchedule.stored(WeekSchedule.everyDay) == [])
    }

    @Test("A day off is a day off")
    func dayOff() {
        let schedule = WeekSchedule(days: Self.weekdays)
        #expect(schedule.isActive(on: Self.sunday, calendar: Self.calendar) == false)
        #expect(schedule.isActive(on: Self.days(1, after: Self.sunday), calendar: Self.calendar))
    }

    /// The monitor extension reads this on its own clock, so the pending week
    /// has to begin by date rather than by anything the app does.
    @Test("A pending week begins on its date, not before")
    func pendingBeginsOnDate() {
        let from = Self.days(7, after: Self.sunday)
        let schedule = WeekSchedule(days: [], pendingDays: Self.weekdays, pendingFrom: from)

        #expect(schedule.days(at: from.addingTimeInterval(-1)) == [])
        #expect(schedule.days(at: from) == Self.weekdays)
        // The following Sunday is off; this Sunday is not.
        #expect(schedule.isActive(on: Self.sunday, calendar: Self.calendar))
        #expect(schedule.isActive(on: Self.days(7, after: Self.sunday), calendar: Self.calendar) == false)
    }

    @Test("Settling folds a pending week in once it has begun")
    func settling() {
        let from = Self.days(7, after: Self.sunday)
        let schedule = WeekSchedule(days: [], pendingDays: Self.weekdays, pendingFrom: from)

        #expect(schedule.settled(at: from.addingTimeInterval(-1)) == schedule)
        #expect(schedule.settled(at: from) == WeekSchedule(days: Self.weekdays))
    }

    // MARK: - When a change lands

    @Test("With no run, a day off lands now")
    func noRunIsFree() {
        let rule = ScheduleChangeRule(lockEndsAt: nil, graceEndsAt: Self.days(-10, after: Self.sunday), calendar: Self.calendar)
        let change = rule.applying(Self.weekdays, to: WeekSchedule(), now: Self.sunday)
        #expect(change.outcome == .now)
        #expect(change.schedule == WeekSchedule(days: Self.weekdays))
    }

    @Test("A run that has ended is no run")
    func endedRunIsFree() {
        let rule = ScheduleChangeRule(lockEndsAt: Self.sunday, graceEndsAt: Self.days(-10, after: Self.sunday), calendar: Self.calendar)
        #expect(rule.isLocked(at: Self.sunday) == false)
        #expect(rule.isLocked(at: Self.sunday.addingTimeInterval(-1)))
        let change = rule.applying(Self.weekdays, to: WeekSchedule(), now: Self.sunday)
        #expect(change.outcome == .now)
    }

    /// The intake never asks about days, so this is the only chance to pick
    /// the week that should have been picked there.
    @Test("Inside the grace, a day off lands now even during a run")
    func graceIsFree() {
        let graceEnds = Self.hours(ScheduleChangeRule.graceHours, after: Self.sunday)
        let rule = ScheduleChangeRule(lockEndsAt: Self.days(30, after: Self.sunday), graceEndsAt: graceEnds, calendar: Self.calendar)

        let inside = rule.applying(Self.weekdays, to: WeekSchedule(), now: graceEnds.addingTimeInterval(-1))
        #expect(inside.outcome == .now)
        #expect(inside.schedule == WeekSchedule(days: Self.weekdays))

        // The grace ends at its end, not a moment later.
        let outside = rule.applying(Self.weekdays, to: WeekSchedule(), now: graceEnds)
        #expect(outside.outcome == .later(Self.days(ScheduleChangeRule.waitDays, after: graceEnds)))
    }

    @Test("The grace is two days from the profile's creation")
    func graceLength() {
        let end = ScheduleChangeRule.graceEnd(forProfileCreatedAt: Self.sunday, calendar: Self.calendar)
        #expect(end == Self.hours(48, after: Self.sunday))
    }

    @Test("During a run, turning a day on lands now")
    func stricterIsImmediate() {
        let rule = lockedRule()
        let change = rule.applying(Self.weekdays.union([7]), to: WeekSchedule(days: Self.weekdays), now: Self.sunday)
        #expect(change.outcome == .now)
        #expect(change.schedule == WeekSchedule(days: Self.weekdays.union([7])))
    }

    @Test("During a run, turning every day on stores as empty")
    func stricterToEveryDay() {
        let rule = lockedRule()
        let change = rule.applying(WeekSchedule.everyDay, to: WeekSchedule(days: Self.weekdays), now: Self.sunday)
        #expect(change.outcome == .now)
        #expect(change.schedule == WeekSchedule())
    }

    /// The rule in one test: the day off is granted, and it is a week away.
    @Test("During a run, a day off waits exactly a week")
    func looserWaits() {
        let rule = lockedRule()
        let from = Self.days(7, after: Self.sunday)
        let change = rule.applying(Self.weekdays, to: WeekSchedule(), now: Self.sunday)

        #expect(change.outcome == .later(from))
        #expect(change.schedule.days == [])
        #expect(change.schedule.pendingDays == Self.weekdays)
        #expect(change.schedule.pendingFrom == from)
        // Today is still a duty day, and so is the day before the date.
        #expect(change.schedule.isActive(on: Self.sunday, calendar: Self.calendar))
        #expect(change.schedule.days(at: from.addingTimeInterval(-1)) == [])
        #expect(change.schedule.days(at: from) == Self.weekdays)
    }

    @Test("A mixed change adds now and removes later")
    func mixedChange() {
        let rule = lockedRule()
        // Saturday off, Sunday on today. Ask for Sunday off and Saturday on.
        let current: Set<Int> = WeekSchedule.everyDay.subtracting([7])
        let wanted: Set<Int> = WeekSchedule.everyDay.subtracting([1])
        let change = rule.applying(wanted, to: WeekSchedule(days: current), now: Self.sunday)

        guard case .later(let from) = change.outcome else {
            Issue.record("expected the removal to wait, got \(change.outcome)")
            return
        }
        #expect(from == Self.days(7, after: Self.sunday))
        // Saturday is on duty from now; Sunday stays on until the date.
        #expect(change.schedule.days == [])
        #expect(change.schedule.pendingDays == wanted)
    }

    @Test("Asking for the week already on duty withdraws a pending week")
    func withdrawingPending() {
        let rule = lockedRule()
        let pending = WeekSchedule(days: [], pendingDays: Self.weekdays, pendingFrom: Self.days(7, after: Self.sunday))
        let change = rule.applying([], to: pending, now: Self.days(1, after: Self.sunday))
        #expect(change.outcome == .unchanged)
        #expect(change.schedule == WeekSchedule())
    }

    /// The date already earned is kept when nothing new is coming off. Putting
    /// Sunday back on should not cost Saturday another week.
    @Test("Narrowing a pending week keeps its date")
    func narrowingKeepsDate() {
        let rule = lockedRule()
        let from = Self.days(7, after: Self.sunday)
        let pending = WeekSchedule(days: [], pendingDays: Self.weekdays, pendingFrom: from)
        let later = Self.days(3, after: Self.sunday)

        let change = rule.applying(Self.weekdays.union([1]), to: pending, now: later)
        #expect(change.outcome == .later(from))
        #expect(change.schedule.pendingDays == Self.weekdays.union([1]))
        #expect(change.schedule.pendingFrom == from)
    }

    /// A further day off cannot ride on a wait that was served for a different
    /// day, or a removal made on day six lands tomorrow.
    @Test("Taking a further day off restarts the wait")
    func wideningRestartsClock() {
        let rule = lockedRule()
        let from = Self.days(7, after: Self.sunday)
        let pending = WeekSchedule(days: [], pendingDays: WeekSchedule.everyDay.subtracting([7]), pendingFrom: from)
        let later = Self.days(6, after: Self.sunday)

        let change = rule.applying(Self.weekdays, to: pending, now: later)
        #expect(change.outcome == .later(Self.days(7, after: later)))
        #expect(change.schedule.pendingDays == Self.weekdays)
        #expect(change.schedule.days == [])
    }

    /// Once the pending week has begun it is the week, and a further change is
    /// measured against it rather than against the days it replaced.
    @Test("A change after the pending week begins is measured against it")
    func changeAfterLanding() {
        let rule = lockedRule()
        let from = Self.days(7, after: Self.sunday)
        let landed = WeekSchedule(days: [], pendingDays: Self.weekdays, pendingFrom: from)

        // Saturday back on: stricter than the landed week, so it lands now.
        let stricter = rule.applying(Self.weekdays.union([7]), to: landed, now: from)
        #expect(stricter.outcome == .now)
        #expect(stricter.schedule == WeekSchedule(days: Self.weekdays.union([7])))

        // Friday off as well: looser than the landed week, so it waits again.
        let looser = rule.applying(Self.weekdays.subtracting([6]), to: landed, now: from)
        #expect(looser.outcome == .later(Self.days(7, after: from)))
        #expect(looser.schedule.days == Self.weekdays)
    }

    // MARK: - The App Group store

    private func freshStore() -> (ScheduleStore, UserDefaults) {
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (ScheduleStore(defaults: defaults), defaults)
    }

    @Test("The store round-trips a pending week")
    func storeRoundTrip() {
        let (store, _) = freshStore()
        let schedule = WeekSchedule(days: Self.weekdays, pendingDays: [2, 3, 4], pendingFrom: Self.days(7, after: Self.sunday))
        store.schedule = schedule
        #expect(store.schedule == schedule)

        store.schedule = WeekSchedule(days: [2, 3])
        #expect(store.schedule == WeekSchedule(days: [2, 3]))
        #expect(store.schedule.hasPending == false)
    }

    /// An install from before pending weeks existed has only the one key.
    @Test("A store with only the old key reads as no pending week")
    func storeMigration() {
        let (store, defaults) = freshStore()
        defaults.set([2, 3, 4, 5, 6], forKey: RansomCore.Key.activeDays)
        #expect(store.schedule == WeekSchedule(days: Self.weekdays))
        #expect(store.isActive(on: Self.sunday, calendar: Self.calendar) == false)
    }

    @Test("The store enforces a pending week by date")
    func storeEnforcesPending() {
        let (store, _) = freshStore()
        store.schedule = WeekSchedule(days: [], pendingDays: Self.weekdays, pendingFrom: Self.days(7, after: Self.sunday))
        #expect(store.isActive(on: Self.sunday, calendar: Self.calendar))
        #expect(store.isActive(on: Self.days(7, after: Self.sunday), calendar: Self.calendar) == false)
    }

    // MARK: - The profile

    /// A profile saved by the version on the App Store has no pending fields.
    /// It has to decode, and it has to decode to "nothing waiting".
    @Test("An old profile decodes with no pending week")
    func profileMigration() throws {
        var old = UserProfile()
        old.activeDays = Self.weekdays
        old.commitmentDays = 30
        old.commitmentStartedAt = Self.sunday
        let data = try JSONEncoder().encode(old)

        let keys = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any]).keys
        #expect(!keys.contains("pendingActiveDays"))
        #expect(!keys.contains("pendingActiveDaysFrom"))

        let decoded = try JSONDecoder().decode(UserProfile.self, from: data)
        #expect(decoded.schedule == WeekSchedule(days: Self.weekdays))
        #expect(decoded.schedule.hasPending == false)
    }

    /// The grace is measured from when the profile was made, so a user who is
    /// mid-run today gets the wait rather than a surprise free-for-all, while
    /// someone who finished intake last night can still fix their week.
    @Test("The profile's rule takes its grace from the creation date")
    func profileGrace() {
        var profile = UserProfile()
        profile.createdAt = Self.sunday
        profile.commitmentDays = 30
        profile.commitmentStartedAt = Self.sunday

        let rule = profile.scheduleRule
        #expect(rule.isInGrace(at: Self.hours(47, after: Self.sunday)))
        #expect(rule.isInGrace(at: Self.hours(49, after: Self.sunday)) == false)
        #expect(rule.isLocked(at: Self.days(29, after: Self.sunday)))
        #expect(rule.isLocked(at: Self.days(31, after: Self.sunday)) == false)
    }

    /// Extending the run in Settings resets `commitmentStartedAt`. It must not
    /// reset the grace, or extending becomes the first tap of an escape.
    @Test("Extending the run does not reopen the grace")
    func extendingKeepsGraceClosed() {
        var profile = UserProfile()
        profile.createdAt = Self.days(-10, after: Self.sunday)
        profile.commitmentDays = 30
        profile.commitmentStartedAt = Self.sunday
        #expect(profile.scheduleRule.isInGrace(at: Self.sunday) == false)
    }
}
