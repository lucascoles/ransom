import DeviceActivity
import Foundation
import ManagedSettings
import UserNotifications

/// Puts the shield back up.
///
/// The app removes the shield when a set is completed; this extension is what
/// restores it — either because the granted minutes of use were spent, or because
/// the monitoring interval rolled over. It runs even if Ransom was force-quit.
final class DeviceActivityMonitorExtension: DeviceActivityMonitor {

    private let selection = BlockedSelectionStore()
    private let ledger = UnlockLedger()

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        // A new day, or monitoring restarted: match the shield to the ledger.
        selection.reconcile(ledger: ledger)
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        ledger.revoke()
        selection.applyShield()
    }

    override func eventDidReachThreshold(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName
    ) {
        super.eventDidReachThreshold(event, activity: activity)

        // The user has burned through the minutes they earned.
        ledger.revoke()
        selection.applyShield()
        postTimeUpNotification()
    }

    override func eventWillReachThresholdWarning(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName
    ) {
        super.eventWillReachThresholdWarning(event, activity: activity)
        postWarningNotification()
    }

    // MARK: - Notifications

    private func postTimeUpNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Time's up"
        content.body = "Rex is back in the doorway. One more set to keep going."
        content.sound = .default
        deliver(content, id: "ransom.monitor.time-up")
    }

    private func postWarningNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Nearly out"
        content.body = "Your earned scroll time is about to run out."
        deliver(content, id: "ransom.monitor.warning")
    }

    private func deliver(_ content: UNMutableNotificationContent, id: String) {
        let request = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }
}
