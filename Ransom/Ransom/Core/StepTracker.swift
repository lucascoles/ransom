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
    private(set) var isAvailable = CMPedometer.isStepCountingAvailable()
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

    /// Minutes already credited from walking today, which the cap is measured
    /// against. Rolls over with the date rather than on a timer, like everything
    /// else that resets at midnight here.
    var minutesFromStepsToday: Int {
        get {
            guard let day = defaults.object(forKey: RansomCore.Key.stepMinutesDay) as? Date,
                  Calendar.current.isDateInToday(day) else { return 0 }
            return defaults.integer(forKey: RansomCore.Key.stepMinutes)
        }
        set {
            defaults.set(newValue, forKey: RansomCore.Key.stepMinutes)
            defaults.set(Date(), forKey: RansomCore.Key.stepMinutesDay)
        }
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
        let steps: Int? = await withCheckedContinuation { continuation in
            pedometer.queryPedometerData(from: start, to: Date()) { data, _ in
                continuation.resume(returning: data?.numberOfSteps.intValue)
            }
        }

        guard let steps else {
            // A refusal and a genuinely stepless morning look identical in the
            // count, so the failure is what distinguishes them.
            isDenied = CMPedometer.authorizationStatus() == .denied
            return 0
        }
        isDenied = false
        stepsToday = steps

        let unpaid = steps - paidStepsToday
        guard unpaid > 0 else { return 0 }

        let earned = plan.minutesEarned(reps: unpaid, exercise: .steps)
        guard earned > 0 else { return 0 }

        // The cap is the whole reason steps can be offered at all. Without it a
        // day of ordinary walking funds an evening of scrolling and nothing has
        // to change, which is why they were withheld from the app in the first
        // place.
        let minutes = min(earned, max(0, plan.stepMinutesCap - minutesFromStepsToday))
        guard minutes > 0 else {
            // Still mark them paid. Leaving capped steps unpaid means the moment
            // the day rolls over they are all credited at once.
            paidStepsToday = steps
            return 0
        }

        // Only credit the steps that actually paid out. Anything left over is
        // fractional and stays on the clock toward the next whole minute, rather
        // than being rounded away every time this runs.
        let stepsPerMinute = plan.repsPerMinute(for: .steps)
        paidStepsToday += minutes * stepsPerMinute
        minutesFromStepsToday += minutes
        ledger.bank(minutes: minutes)
        return minutes
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
