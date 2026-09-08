import Foundation
import UserNotifications

/// Local notifications only — Ransom never needs a server to nag you.
enum NotificationManager {
    private static let timeUpID = RansomNotificationID.timeUp
    private static let warningID = RansomNotificationID.timeWarning
    private static let dailyID = "ransom.notification.daily-nudge"

    /// How long before the minutes run out the heads-up lands.
    public static let warningLeadMinutes = 5

    @discardableResult
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// The two alerts a granted unlock is allowed to raise: one warning shortly
    /// before the minutes run out, and one when they do.
    ///
    /// Both are scheduled against the wall clock, because the wall clock is what
    /// the ledger actually enforces - `grant(minutes:)` writes an expiry `Date`,
    /// and the shield goes back up when that passes whether the apps were used or
    /// not. The monitor extension raises the same two identifiers when the bought
    /// minutes are *spent* first, and identical identifiers are what stop the pair
    /// arriving twice.
    static func scheduleTimeUpReminder(in minutes: Int) {
        cancelTimeUpReminder()
        scheduleWarning(minutes: minutes)

        let content = UNMutableNotificationContent()
        content.title = "Time's up"
        content.body = "Rex is back in the doorway. One more set to keep going."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(60, Double(minutes) * 60),
            repeats: false
        )
        let request = UNNotificationRequest(identifier: timeUpID, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    /// A grant shorter than the lead time gets no warning: there is no useful
    /// moment to place it, and firing it at once would just be the same alert
    /// twice.
    private static func scheduleWarning(minutes: Int) {
        let lead = Double(warningLeadMinutes) * 60
        let total = Double(minutes) * 60
        guard total > lead else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(warningLeadMinutes) minutes left"
        content.body = "Rex is heading back to the door. Wrap it up or earn some more."

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: total - lead, repeats: false)
        let request = UNNotificationRequest(identifier: warningID, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    /// Clears both alerts. Delivered ones go too: a "5 minutes left" banner still
    /// sitting in Notification Centre after the user locked up early is stale.
    static func cancelTimeUpReminder() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [timeUpID, warningID])
        center.removeDeliveredNotifications(withIdentifiers: [warningID])
    }

    /// The 7pm "keep the streak" nudge, retired on purpose.
    ///
    /// It was scheduled once during onboarding and never checked anything: it
    /// claimed "Rex hasn't seen a single rep today" on days the user had already
    /// done their reps, and there was no way to turn it off from inside the app.
    /// A push asking someone to pick their phone back up is also the opposite of
    /// what Ransom sells.
    ///
    /// Deleting the scheduling code is not enough. It was registered with
    /// `repeats: true`, so it is still pending on every device that finished
    /// onboarding before this shipped and would keep firing forever. This runs at
    /// launch to clear those.
    static func removeRetiredDailyNudge() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [dailyID])
    }

    /// Whether the permission has been asked for yet. The trial-reminder step
    /// only raises the system prompt when it has not: asking twice does nothing
    /// on iOS, and a button that promises a prompt it cannot show looks broken.
    static func isPermissionUndetermined() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings()
            .authorizationStatus == .notDetermined
    }

    // MARK: - Trial

    private static let trialEndingID = "ransom.notification.trial-ending"

    /// The reminder the intake promises one screen before the paywall: a
    /// heads-up the day before the free trial ends, so nobody is charged by
    /// surprise.
    ///
    /// Scheduled off the trial length StoreKit reports, never a written number,
    /// and only after a purchase that actually started a trial. Fires at 10am the
    /// day before the trial ends. A trial too short to have a "day before" gets
    /// it the next morning, which is still ahead of the charge.
    static func scheduleTrialEndingReminder(trialDays: Int, from start: Date = Date()) {
        let calendar = Calendar.current
        let daysAhead = max(1, trialDays - 1)
        guard let day = calendar.date(byAdding: .day, value: daysAhead, to: start),
              let fireAt = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: day),
              fireAt > start
        else { return }

        let content = UNMutableNotificationContent()
        content.title = "Your free trial ends tomorrow"
        content.body = "Rex said he'd give you a heads-up. Here it is. Keep going, or cancel in Settings. No surprises."
        content.sound = .default

        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireAt)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: trialEndingID, content: content, trigger: trigger)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [trialEndingID])
        center.add(request)
    }
}
