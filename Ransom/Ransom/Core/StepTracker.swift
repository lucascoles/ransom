import CoreMotion
import Foundation
import Observation

/// Turns the steps the phone has already counted into banked minutes.
///
/// The pedometer is the one earning path that costs the user nothing: the phone
/// has been counting all day whether or not this app was open, and `CMPedometer`
/// will hand back history from midnight on request. So a user who picks Step to
/// Scroll opens the app and finds minutes already waiting, which no amount of
/// push-up prompting can match for a first impression.
///
/// Only the steps taken *since the day started* are ever paid, and only once —
/// `paidStepsToday` is the high-water mark, so re-reading the same steps can't
/// mint the same minutes twice.
@Observable
final class StepTracker {

    private(set) var stepsToday = 0
    /// Metres covered today, when the phone is willing to say. Distance is a
    /// separate capability from step counting and some devices have one without
    /// the other, so it stays optional rather than defaulting to zero - nobody
    /// walks 570 steps and covers no ground, and printing that would say the
    /// pedometer is broken rather than unavailable.
    private(set) var metresToday: Double?
    /// The last week, oldest first. iOS keeps seven days of pedometer history
    /// and hands it over on request, so the week costs nothing to show and is
    /// the only thing on this screen that says whether today was a good day.
    private(set) var week: [DayCount] = []
    private(set) var isAvailable = CMPedometer.isStepCountingAvailable()

    /// One day's walking. The count is optional because a day the phone did not
    /// record and a day nobody moved are different claims, and a bar sitting on
    /// the floor makes the second one.
    struct DayCount: Identifiable {
        let date: Date
        let steps: Int?
        var id: Date { date }
    }
    /// Set when the user has refused motion access, so the screen can say why
    /// nothing is being counted rather than showing a permanent zero.
    private(set) var isDenied = false

    private let pedometer = CMPedometer()
    private let defaults = UserDefaults.standard
    private var isLive = false

    private enum Key {
        static let paidSteps = "ransom.steps.paidToday"
        static let paidDay = "ransom.steps.paidDay"
    }

    /// Minutes walking has put into the bank today.
    ///
    /// Earnings, not a balance. This only ever goes up, because it is what the
    /// day's walking paid in - spending is a separate fact and lives in the
    /// ledger. Named for that after the two were shown as one number: the screen
    /// said "32 minutes banked" beside a bank holding 47, having earned 107 and
    /// spent 60, and the gap read as minutes going missing.
    ///
    /// Derived from the paid step count rather than stored beside it. Keeping a
    /// second running total meant two facts that had to agree and one day did
    /// not: the phone came back with five hundred steps marked paid and no
    /// minutes recorded against them, so the screen sat on "0 minutes banked"
    /// while the step counter beside it read five hundred and seventy. Paid
    /// steps only ever move in whole-minute blocks, so this is exact, and there
    /// is now no second copy to drift.
    func minutesEarnedToday(plan: RansomPlan) -> Int {
        let perMinute = plan.repsPerMinute(for: .steps)
        guard perMinute > 0 else { return 0 }
        return paidStepsToday / perMinute
    }

    /// Steps already converted into minutes today. Reset by the date rolling over
    /// rather than by a timer, so a phone that sleeps through midnight still gets
    /// a clean slate on the next read.
    private var paidStepsToday: Int {
        get {
            guard let day = defaults.object(forKey: Key.paidDay) as? Date,
                  Calendar.current.isDateInToday(day) else { return 0 }
            return defaults.integer(forKey: Key.paidSteps)
        }
        set {
            defaults.set(newValue, forKey: Key.paidSteps)
            defaults.set(Date(), forKey: Key.paidDay)
        }
    }

    /// Reads today's steps and banks whatever hasn't been paid for yet.
    /// Returns the minutes just credited, so the caller can say so out loud.
    @MainActor
    @discardableResult
    func syncToday(plan: RansomPlan, ledger: UnlockLedger = UnlockLedger()) async -> Int {
        guard isAvailable else { return 0 }

        let start = Calendar.current.startOfDay(for: Date())
        // CMPedometer predates async/await and still only offers a completion
        // handler, so it gets bridged here rather than at every call site.
        let today: (steps: Int, metres: Double?)? = await withCheckedContinuation { continuation in
            pedometer.queryPedometerData(from: start, to: Date()) { data, _ in
                guard let data else { return continuation.resume(returning: nil) }
                continuation.resume(returning: (data.numberOfSteps.intValue, data.distance?.doubleValue))
            }
        }

        guard let steps = today?.steps else {
            // A refusal and a genuinely stepless morning look identical in the
            // count, so the failure is what distinguishes them.
            isDenied = CMPedometer.authorizationStatus() == .denied
            return 0
        }
        isDenied = false
        stepsToday = steps
        metresToday = today?.metres
        StepLog().record(steps, on: start)

        let perMinute = plan.repsPerMinute(for: .steps)
        guard perMinute > 0 else { return 0 }

        // What the whole day is worth, worked out from scratch each time rather
        // than accumulated. Rounded down, so the app never pays for a minute
        // that has not been walked, and capped - without a ceiling a day of
        // ordinary walking funds an evening of scrolling and nothing about the
        // habit has to change, which is why steps were withheld at first.
        let payable = min(plan.stepMinutesCap, steps / perMinute)
        let minutes = payable - minutesEarnedToday(plan: plan)
        guard minutes > 0 else { return 0 }

        // Paid steps stay a whole multiple of the rate, including at the cap, so
        // the minutes derived from them are always exactly the minutes banked.
        // The remainder is left unpaid and keeps counting toward the next whole
        // minute rather than being rounded away on every sync.
        paidStepsToday = payable * perMinute
        ledger.bank(minutes: minutes)
        return minutes
    }

    /// Fills in the last week, a day at a time.
    ///
    /// `CMPedometer` answers one range per call and keeps roughly seven days, so
    /// this is seven short queries rather than one. The oldest day is the one
    /// most likely to come back empty, since it is right at the edge of what the
    /// phone still remembers - which is why an empty answer is kept as a gap
    /// instead of a zero.
    @MainActor
    func loadWeek(days: Int = 7) async {
        guard isAvailable, days > 0 else { return }
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: Date())
        var result: [DayCount] = []

        for offset in stride(from: days - 1, through: 0, by: -1) {
            guard let dayStart = calendar.date(byAdding: .day, value: -offset, to: midnight)
            else { continue }
            // Today's slice ends now, not at tomorrow's midnight, or the query
            // runs off the end of what has happened yet.
            let dayEnd = min(calendar.date(byAdding: .day, value: 1, to: dayStart) ?? Date(), Date())
            guard dayEnd > dayStart else { continue }

            let count: Int? = await withCheckedContinuation { continuation in
                pedometer.queryPedometerData(from: dayStart, to: dayEnd) { data, _ in
                    continuation.resume(returning: data?.numberOfSteps.intValue)
                }
            }
            result.append(DayCount(date: dayStart, steps: count))
            if let count { StepLog().record(count, on: dayStart) }
        }
        week = result
    }

    /// Live updates while the app is open, so a walk in progress visibly ticks.
    func startLiveUpdates() {
        guard isAvailable, !isLive else { return }
        isLive = true
        pedometer.startUpdates(from: Calendar.current.startOfDay(for: Date())) { [weak self] data, _ in
            guard let data else { return }
            Task { @MainActor in self?.stepsToday = data.numberOfSteps.intValue }
        }
    }

    func stopLiveUpdates() {
        guard isLive else { return }
        pedometer.stopUpdates()
        isLive = false
    }
}
