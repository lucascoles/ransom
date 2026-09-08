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
}
