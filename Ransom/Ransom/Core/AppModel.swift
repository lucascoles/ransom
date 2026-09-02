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

    var plan: RansomPlan { RansomPlan.make(from: profile) }

    /// What the next unlock costs under the tariff — base price for the first
    /// couple of the day, climbing after that.
    var quote: Tariff.Quote { ledger.currentQuote() }

    var unlocksToday: Int { ledger.unlocksToday }

    /// The full ladder, for the rates card. Users have to be able to see what's
    /// coming or the escalation reads as arbitrary.
    var tariffSchedule: [(unlock: Int, reps: Int, multiplier: Double)] {
        Tariff.schedule(base: plan.repsPerUnlock)
    }

    // MARK: Lifecycle

    init() {
        let snapshot = Snapshot.load()
        profile = snapshot.profile
        history = snapshot.history
        hasCompletedOnboarding = snapshot.hasCompletedOnboarding
        isSubscribed = snapshot.isSubscribed
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

    var totalCalories: Double { history.reduce(0) { $0 + $1.calories } }

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

    var lifetimePushUps: Int { lifetimeReps(of: .pushUps) }

    /// Days on which at least one set was completed.
    var activeDays: Int {
        let calendar = Calendar.current
        return Set(history.map { calendar.startOfDay(for: $0.date) }).count
    }

    /// Calendar days Ransom has been installed, at least one.
    var daysSinceStart: Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: history.first?.date ?? profile.createdAt)
        let days = calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: Date())).day ?? 0
        return max(1, days + 1)
    }

    /// Minutes of scrolling the gate has displaced, all time.
    ///
    /// The honest version of this number: what the user told us they used to scroll
    /// per day, times the days since they started, minus every minute they've
    /// actually bought back with reps. It can't go below zero — if someone earns
    /// more time than their old baseline, Ransom hasn't saved them anything and
    /// shouldn't claim it has.
    var lifetimeMinutesSaved: Int {
        let baselinePerDay = (profile.scrollLoad ?? .medium).hoursPerDay * 60
        let wouldHaveScrolled = baselinePerDay * Double(daysSinceStart)
        return max(0, Int(wouldHaveScrolled) - totalMinutesEarned)
    }

    var lifetimeDaysSaved: Double {
        Double(lifetimeMinutesSaved) / (60 * 24)
    }

    /// Average minutes a day actually spent in the gated apps.
    var averageEarnedMinutesPerDay: Int {
        totalMinutesEarned / max(1, daysSinceStart)
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

    /// Records a finished set and grants the earned scroll time.
    @discardableResult
    func completeSet(exercise: Exercise, reps: Int, duration: Int, trigger: String? = nil) -> Int {
        let minutes = plan.minutesPerUnlock
        let record = WorkoutRecord(
            exercise: exercise,
            reps: reps,
            durationSeconds: duration,
            minutesGranted: minutes,
            trigger: trigger
        )
        history.append(record)
        ledger.grant(minutes: minutes)
        ledger.recordUnlock()
        pendingUnlockAppName = nil
        return minutes
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
            reps: plan.repsPerUnlock,
            minutes: plan.minutesPerUnlock,
            exercise: plan.exercise
        )
        // They flagged late-night scrolling during intake; charge for it.
        ledger.nightSurchargeEnabled = profile.peakTimes.contains(.lateNight)
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
        model.profile.fitnessLevel = .sometimes
        model.profile.scrollLoad = .heavy
        model.profile.exercises = [.pushUps, .jumpingJacks]
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
