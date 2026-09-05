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
    private let usage = UsageMeter()

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        // A new day, or monitoring restarted: match the shield to the ledger.
        ledger.trace("start \(activity.rawValue) unlocked=\(ledger.isUnlocked)")
        selection.reconcile(ledger: ledger)
        // The usage ladder starts again from the bottom, or the home screen shows
        // yesterday's total all morning until the first rung fires.
        usage.startDay()
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)

        // Only the unlock window ending means the user's time is up.
        //
        // `intervalDidEnd` is not just "the schedule finished": iOS delivers it
        // whenever a monitored activity is *stopped*, and the app stops and
        // restarts `.daily` on every grant and every change to the app list. So
        // this used to revoke the minutes a moment after they were bought - the
        // apps opened, the countdown appeared, and about a second later the
        // extension woke up, ended the day that had not ended, and took both
        // away. The bank was empty and nothing had been unlocked.
        let left = Int(ledger.remaining)
        ledger.trace("end \(activity.rawValue) left=\(left)s")

        guard activity == .unlockWindow else {
            selection.reconcile(ledger: ledger)
            return
        }

        // A window that "ends" with minutes still on the clock did not end - it
        // was stopped. `startUnlockWindow` stops the previous window before
        // opening a new one, and stopping delivers `intervalDidEnd` exactly like
        // finishing does; taking that at face value revoked each purchase a
        // second after it was made. The ledger's wall clock is the arbiter: time
        // is up when it says so, not when a callback implies it.
        guard left <= 60 else {
            ledger.trace("ignored early end, \(left)s left")
            return
        }

        ledger.revoke()
        selection.applyShield()
    }

    override func eventDidReachThreshold(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName
    ) {
        super.eventDidReachThreshold(event, activity: activity)

        // Which event this is matters enormously. Every threshold used to end the
        // user's earned time, which was fine while there was only one of them -
        // the moment a second kind of event exists, an unrelated callback would
        // slam the shield down mid-session for no reason the user could see.
        ledger.trace("threshold \(event.rawValue) on \(activity.rawValue)")

        if let minutes = UsageMeter.minutes(fromEventName: event.rawValue) {
            usage.record(minutes: minutes)
            return
        }

        // Same discipline as `intervalDidEnd`: only the unlock window's own
        // threshold ends the unlock. Anything else firing here is not about the
        // minutes the user is currently spending.
        guard event == .earnedTimeSpent, activity == .unlockWindow else { return }

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
