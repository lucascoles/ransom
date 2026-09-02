import Foundation
import UserNotifications

/// Local notifications only — Ransom never needs a server to nag you.
enum NotificationManager {
    private static let timeUpID = "ransom.notification.time-up"
    private static let dailyID = "ransom.notification.daily-nudge"

    @discardableResult
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Fires the moment earned scroll time runs out, so the block never feels
    /// like the app silently yanked something away.
    static func scheduleTimeUpReminder(in minutes: Int) {
        cancelTimeUpReminder()

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

    static func cancelTimeUpReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [timeUpID])
    }

    /// A single evening check-in. One a day, no more — this is not that kind of app.
    static func scheduleDailyNudge(hour: Int = 19) {
        let content = UNMutableNotificationContent()
        content.title = "Keep the streak"
        content.body = "Rex hasn't seen a single rep today. Thirty seconds fixes that."
        content.sound = .default

        var components = DateComponents()
        components.hour = hour
        components.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: dailyID, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    static func cancelDailyNudge() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [dailyID])
    }
}
