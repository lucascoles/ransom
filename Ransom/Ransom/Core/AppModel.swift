import Foundation
import Observation
import SwiftUI

/// The app's single store. Holds the profile, the derived plan, the workout history
/// and the subscription state, and writes itself to disk on every change.
@Observable
final class AppModel {
    // MARK: Persisted state

    var profile: UserProfile {
        didSet { persist(); syncPlanToExtensions() }
    }

    var history: [WorkoutRecord] {
        didSet { persist() }
    }

    var hasCompletedOnboarding: Bool {
        didSet { persist() }
    }

    var isSubscribed: Bool {
        didSet { persist() }
    }

    /// Set when the user arrives from a shield tap, so the home screen can jump
    /// straight into a set for the app they were trying to open.
    var pendingUnlockAppName: String?

    // MARK: Services

    let ledger = UnlockLedger()
    let rules = FocusRuleStore()
    let usage = UsageMeter()

    /// Bumped when the app comes back to the foreground. The meter is written by
    /// the monitor extension in another process, so nothing here observes it -
    /// re-reading on return is the only moment it can have changed.
    var usageRevision = 0

    /// Set when intake finishes, so Root can show the welcome over Home. Not
    /// persisted: it is a moment, and a relaunch should never replay it.
    var showWelcome = false

    /// Bumped whenever the rules change or the clock crosses a window's edge, so
    /// the views that quote a price redraw. `FocusRuleStore` reads the App Group
    /// and is not observable on its own.
    var ruleRevision = 0

    /// The plan at today's price: doubled while one of the user's focus rules is
    /// running, otherwise exactly what they signed up to.
    ///
    /// Everything downstream reads this - the set target, the shield's copy, the
    /// home screen's exchange rate - so there is no path by which one screen can
    /// quote a rule price and another the plain one.
    var plan: RansomPlan {
        _ = ruleRevision
        return basePlan.scaled(by: rules.multiplier())
    }

    /// The plan as committed to, ignoring any rule. Projections and the intake's
    /// promises are made against this: a temporary window must not appear to
    /// change the deal.
    var basePlan: RansomPlan { RansomPlan.make(from: profile) }

    /// The rule making things expensive right now, if any.
    var activeRule: FocusRule? {
        _ = ruleRevision
        return rules.activeRule()
    }

    /// What a set costs. Flat, now that the bank is the economy.
    ///
    /// The escalating tariff priced an unlock, and there are no unlocks to price
    /// any more — minutes are earned at a rate and spent from a balance. Charging
    /// more for the fourth top-up than the first would have meant the exchange
    /// rate moving under the user while they were mid-set, which is the one thing
    /// a currency cannot do and stay trusted.
    var repsPerSet: Int { plan.setTarget }

    /// Records a change to the rules and re-prices everything that depends on
    /// them, including the copy the shield extension will render.
    func rulesChanged() {
        ruleRevision += 1
        syncPlanToExtensions()
    }

    var unlocksToday: Int { ledger.unlocksToday }

    // MARK: Lifecycle

    init() {
        let snapshot = Snapshot.load()
        profile = snapshot.profile
        history = snapshot.history
        hasCompletedOnboarding = snapshot.hasCompletedOnboarding
        isSubscribed = snapshot.isSubscribed

        // `-RansomPro 1` drops straight into the unlocked app, skipping intake and
        // the paywall. On a real device the paywall is otherwise impassable during
        // testing: it only finishes on a completed purchase, and StoreKit has no
        // products to sell unless the app was launched from Xcode's scheme.
        //
        //     xcrun devicectl device process launch --device UDID com.ransom.app -- -RansomPro 1
        //
        // Debug builds only, so it can never ship as a way around the paywall.
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "RansomPro") {
            hasCompletedOnboarding = true
            isSubscribed = true
        }
        // `-RansomBank 60` seeds the balance. The bank starts empty on a fresh
        // profile, so without this every screen that only appears when there is
        // something to spend is unreachable in a screenshot run.
        let seededBank = UserDefaults.standard.integer(forKey: "RansomBank")
        if seededBank > 0 { ledger.bankedMinutes = seededBank }
        // `-RansomWalking 1` adds walking to the movements, which is the only way
        // to reach its tab in a screenshot run - the tab is deliberately absent
        // for anybody who did not choose it.
        if UserDefaults.standard.bool(forKey: "RansomWalking") {
            profile.exercises.insert(.steps)
        }
        // `-RansomStartedDaysAgo 3` backdates the profile, which is the only way
        // to see the days-on-duty card past its two-day grace without waiting
        // two days. Persists like the rest of the profile, so a test phone's
        // "days since start" reads the backdated figure afterwards.
        let startedDaysAgo = UserDefaults.standard.integer(forKey: "RansomStartedDaysAgo")
        if startedDaysAgo > 0,
           let backdated = Calendar.current.date(byAdding: .day, value: -startedDaysAgo, to: Date()) {
            profile.createdAt = backdated
        }
        #endif

        syncPlanToExtensions()
    }

    // MARK: Derived stats

    var todayReps: Int {
        reps(on: Date())
    }

    var todayProgress: Double {
        guard plan.dailyRepGoal > 0 else { return 0 }
        return min(1, Double(todayReps) / Double(plan.dailyRepGoal))
    }

    var totalReps: Int { history.reduce(0) { $0 + $1.reps } }

    var totalCalories: Double {
        history.reduce(0) { $0 + $1.calories(forWeightKg: profile.weightKg) }
    }

    var totalMinutesEarned: Int { history.reduce(0) { $0 + $1.minutesGranted } }

    /// Consecutive days ending today (or yesterday, if today isn't logged yet)
    /// on which at least one set was completed.
    var streak: Int {
        let calendar = Calendar.current
        let days = Set(history.map { calendar.startOfDay(for: $0.date) })
        guard !days.isEmpty else { return 0 }

        var cursor = calendar.startOfDay(for: Date())
        if !days.contains(cursor) {
            // A day isn't broken until it's over — fall back to yesterday.
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor),
                  days.contains(yesterday) else { return 0 }
            cursor = yesterday
        }

        var count = 0
        while days.contains(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    // MARK: Lifetime

    /// Every rep of one movement, all time. The headline number on the Progress tab.
    func lifetimeReps(of exercise: Exercise) -> Int {
        history.filter { $0.exercise == exercise }.reduce(0) { $0 + $1.reps }
    }

    /// Every rep of every movement, all time.
    ///
    /// The headline used to count push-ups only, so anybody training squats saw
    /// a lifetime of zero next to a day's work. The number is reps now, and the
    /// label says so.
    var lifetimeReps: Int { history.reduce(0) { $0 + $1.reps } }

    /// Days on which at least one set was completed.
    var activeDays: Int {
        let calendar = Calendar.current
        return Set(history.map { calendar.startOfDay(for: $0.date) }).count
    }

    /// Calendar days Ransom has been installed, at least one.
    var daysSinceStart: Int {
        let calendar = Calendar.current
        // The earliest record, not the first one in the array: history is appended
        // in order, but nothing guarantees it (the preview seed isn't).
        let start = calendar.startOfDay(for: history.map(\.date).min() ?? profile.createdAt)
        let days = calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: Date())).day ?? 0
        return max(1, days + 1)
    }

    /// Minutes of gated-app time bought back today. The number that decides
    /// whether today went well.
    var todayMinutesUnlocked: Int { ledger.spentMinutesToday }

    /// Measured minutes in the guarded apps today, when Screen Time is actually
    /// reporting. Nil means nothing has ever been measured - a phone without
    /// authorization and a genuinely quiet morning both read zero otherwise, and
    /// the first would be shown a saving nobody earned.
    ///
    /// It is a floor, not a reading: the meter knows which rung has been passed,
    /// not the minute. Anything quoted from it says "45+" and never interpolates.
    ///
    /// Always nil on iOS 26, where the meter reports rungs that were never
    /// reached (`UsageMeter.isReliable`). Home then falls back to minutes bought,
    /// which can only under-state the day, so "Fresh start tomorrow" appears
    /// when the unlocks alone are past the allowance and never on a false 10h.
    var measuredScreenMinutes: Int? {
        _ = usageRevision
        guard UsageMeter.isReliable else { return nil }
        return usage.isMeasuring ? usage.minutesToday : nil
    }

    /// What today has cost, measured where it can be and inferred where it can't.
    ///
    /// Minutes spent from the bank are a poor stand-in - they are what the user
    /// *bought*, not what they used, and they miss every minute in an app that was
    /// never guarded - but they are the only number available until Screen Time is
    /// granted, and a screen with nothing on it teaches nobody anything.
    var todayScreenMinutes: Int { measuredScreenMinutes ?? todayMinutesUnlocked }

    /// Whether the figure above was measured or inferred. The copy has to say
    /// which, or the app is quietly claiming to know something it doesn't.
    var isScreenTimeMeasured: Bool { measuredScreenMinutes != nil }

    /// Minutes banked today, which is the opposite side of the ledger from the
    /// one above and must not be confused with it.
    var todayMinutesEarned: Int {
        let calendar = Calendar.current
        return history
            .filter { calendar.isDateInToday($0.date) }
            .reduce(0) { $0 + $1.minutesGranted }
    }

    /// Today's ceiling. The user's own goal when they set one; otherwise the
    /// plan's curve, so a profile from before goals existed still works.
    var todayAllowance: Int {
        profile.goalDailyMinutes ?? plan.dailyMinuteAllowance(onDay: daysSinceStart)
    }

    /// What a day used to cost them, and what every saving is measured against.
    var baselineMinutes: Int { profile.baselineDailyMinutes }

    /// Whether that baseline is about the same thing as what gets measured now.
    ///
    /// False for anyone who onboarded while the benchmark was the guarded apps
    /// rather than the whole phone. Their figure counted four apps; today's
    /// measurement counts the device, so every comparison between the two is a
    /// claim about a quantity nobody ever gave us.
    var hasComparableBaseline: Bool { profile.hasComparableBaseline }

    /// Minutes saved today against that baseline. Negative when they've spent more
    /// than they used to — which has to be sayable, or the number is just flattery.
    ///
    /// Nil rather than a guess when the baseline was measured against something
    /// else. There is no honest conversion from "three hours in Instagram" to a
    /// whole-phone figure, and a saving invented to fill the gap would land on
    /// the one screen that exists to prove the app works.
    var todaySavedMinutes: Int? {
        guard hasComparableBaseline else { return nil }
        return baselineMinutes - todayScreenMinutes
    }

    /// Minutes of the allowance still unspent. Never negative — going over is
    /// reported separately rather than as a negative amount of time left.
    var todayMinutesLeft: Int { max(0, todayAllowance - todayScreenMinutes) }

    /// Never claimed against an allowance built from the old benchmark. A goal of
    /// two hours set as a share of somebody's guarded-app time, checked against a
    /// whole-phone measurement, puts every one of those users permanently over
    /// on their first launch after upgrading.
    var isOverAllowance: Bool {
        hasComparableBaseline && todayScreenMinutes > todayAllowance
    }

    /// How much of today's allowance has been spent, 0-1. Unlike the rep goal this
    /// replaced, filling the ring is the *bad* outcome.
    var todayScreenUsage: Double {
        guard todayAllowance > 0 else { return 0 }
        return min(1, Double(todayScreenMinutes) / Double(todayAllowance))
    }

    /// Minutes back today: the old daily average, less what the phone has
    /// actually taken so far.
    ///
    /// This replaces a lifetime figure that could not be computed honestly.
    /// It multiplied the stated baseline by the days installed and subtracted
    /// minutes *earned* - a number from the history of sets, which is what the
    /// user banked and not what they used. Earning and spending being different
    /// numbers is a rule this app already has, and that calculation broke it in
    /// the one place claiming to prove the app works. Today can be measured, so
    /// today is what gets claimed.
    var minutesBackToday: Int? {
        guard let todaySavedMinutes else { return nil }
        return max(0, todaySavedMinutes)
    }

    /// The longest run of consecutive logged days, ever.
    var bestStreak: Int {
        let calendar = Calendar.current
        let days = Set(history.map { calendar.startOfDay(for: $0.date) }).sorted()
        guard !days.isEmpty else { return 0 }

        var best = 1
        var run = 1
        for index in 1..<days.count {
            let gap = calendar.dateComponents([.day], from: days[index - 1], to: days[index]).day ?? 0
            run = gap == 1 ? run + 1 : 1
            best = max(best, run)
        }
        return best
    }

    func reps(on date: Date) -> Int {
        let calendar = Calendar.current
        return history
            .filter { calendar.isDate($0.date, inSameDayAs: date) }
            .reduce(0) { $0 + $1.reps }
    }

    /// Last seven days, oldest first, for the home screen chart.
    var weekBars: [(label: String, value: Double, isToday: Bool)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        return (0..<7).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let weekday = calendar.component(.weekday, from: day) - 1
            return (
                label: symbols[weekday],
                value: Double(reps(on: day)),
                isToday: offset == 0
            )
        }
    }

    // MARK: Mutations

    /// Records a finished set and pays what it earned into the bank.
    ///
    /// Pays for what was actually done rather than a flat rate per set: someone who
    /// pushes out fifteen when ten were asked banks the extra five, where a flat
    /// rate would quietly teach them to stop the moment the counter hits its target.
    ///
    /// It deliberately does *not* start the clock. Banking and spending are separate
    /// now — minutes earned sit there until the user chooses to spend them, which is
    /// the whole point of a bank.
    @discardableResult
    func completeSet(exercise: Exercise, reps: Int, duration: Int, trigger: String? = nil) -> Int {
        let minutes = plan.minutesEarned(reps: reps, exercise: exercise)
        let record = WorkoutRecord(
            exercise: exercise,
            reps: reps,
            durationSeconds: duration,
            minutesGranted: minutes,
            trigger: trigger
        )
        history.append(record)
        ledger.bank(minutes: minutes)
        pendingUnlockAppName = nil
        return minutes
    }

    /// Minutes sitting in the bank, unspent.
    var bankedMinutes: Int { ledger.bankedMinutes }

    /// Spends from the bank to open the apps. Returns what it actually spent —
    /// less than asked for when the bank is short, and zero when it's empty.
    @discardableResult
    func spendFromBank(minutes: Int) -> Int {
        let spent = ledger.spend(minutes: minutes)
        if spent > 0 { ledger.recordUnlock() }
        pendingUnlockAppName = nil
        return spent
    }

    func resetEverything() {
        profile = UserProfile()
        history = []
        hasCompletedOnboarding = false
        isSubscribed = false
        ledger.revoke()
        ledger.clearPendingRequest()
    }

    /// Picks up an "Earn my time" tap made on the shield while the app was closed.
    func consumePendingShieldRequest() {
        if let appName = ledger.consumePendingRequest() {
            pendingUnlockAppName = appName ?? "that app"
        }
    }

    // MARK: Persistence

    private func syncPlanToExtensions() {
        let plan = self.plan
        ledger.mirrorConfig(
            reps: plan.setTarget,
            minutes: plan.minutesPerUnlock,
            exercise: plan.exercise,
            allowance: todayAllowance
        )
        // They flagged late-night scrolling during intake; charge for it.
        ledger.nightSurchargeEnabled = profile.peakTimes.contains(.lateNight)
        // The extensions enforce the days off, so they have to be told about
        // them - the week that is waiting as well as the one on duty, so a day
        // off begins on its date whether or not the app is opened that day.
        ScheduleStore().schedule = profile.schedule
    }

    /// Folds a quieter week that has begun into the days on duty.
    ///
    /// Nothing depends on this: every reader resolves the pending week by date.
    /// It only stops the profile carrying a change that has already happened,
    /// and it writes nothing when there is nothing to fold, so calling it on
    /// every foreground does not persist on every foreground.
    func settleSchedule(now: Date = Date()) {
        let settled = profile.schedule.settled(at: now)
        guard settled != profile.schedule else { return }
        profile.schedule = settled
    }

    private func persist() {
        Snapshot(
            profile: profile,
            history: history,
            hasCompletedOnboarding: hasCompletedOnboarding,
            isSubscribed: isSubscribed
        ).save()
    }

    // MARK: Snapshot

    private struct Snapshot: Codable {
        var profile: UserProfile
        var history: [WorkoutRecord]
        var hasCompletedOnboarding: Bool
        var isSubscribed: Bool

        static let key = "ransom.snapshot.v1"

        static func load() -> Snapshot {
            guard let data = RansomCore.defaults.data(forKey: key),
                  let decoded = try? JSONDecoder().decode(Snapshot.self, from: data) else {
                return Snapshot(
                    profile: UserProfile(),
                    history: [],
                    hasCompletedOnboarding: false,
                    isSubscribed: false
                )
            }
            return decoded
        }

        func save() {
            guard let data = try? JSONEncoder().encode(self) else { return }
            RansomCore.defaults.set(data, forKey: Self.key)
        }
    }
}

// MARK: - Preview support

extension AppModel {
    /// A populated model so previews and screenshots show a lived-in app.
    static var preview: AppModel {
        let model = AppModel()
        model.hasCompletedOnboarding = true
        model.isSubscribed = true
        model.profile.firstName = "Sam"
        model.profile.scrollLoad = .heavy
        model.profile.exercises = [.pushUps, .squats]
        model.profile.distractingApps = [.instagram, .tiktok]
        let calendar = Calendar.current
        model.history = (0..<6).flatMap { offset -> [WorkoutRecord] in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: Date()) else { return [] }
            return (0..<Int.random(in: 1...4)).map { _ in
                WorkoutRecord(
                    date: day,
                    exercise: .pushUps,
                    reps: Int.random(in: 8...14),
                    durationSeconds: Int.random(in: 25...60),
                    minutesGranted: 15
                )
            }
        }
        return model
    }
}
