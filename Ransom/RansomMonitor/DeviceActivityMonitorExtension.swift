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

        // The user has burned through the minutes they earned. Whether anything
        // was actually revoked has to be read *before* revoking: a threshold that
        // fires against an already-expired unlock has nothing to announce, and
        // announcing it anyway is a second "Time's up" for one expiry.
        let wasUnlocked = ledger.isUnlocked
        ledger.revoke()
        selection.applyShield()
        if wasUnlocked { postTimeUpNotification() }
    }

    // `eventWillReachThresholdWarning` is deliberately not overridden. The
    // callback exists, but nothing in this SDK can arm it: `DeviceActivityEvent`
    // takes only a `threshold`, and `warningTime` lives on `DeviceActivitySchedule`,
    // where it drives `intervalWillEndWarning` instead. An override here looks like
    // a working "nearly out" warning and is never called. The real one is a
    // wall-clock notification scheduled by the app in `NotificationManager`.

    // MARK: - Notifications

    /// The app has already scheduled this same alert against the wall clock. Getting
    /// here means the minutes were *spent* before that timer was due, so the pending
    /// twin has to go: identical identifiers stop two banners arriving at once, but
    /// they do not stop the app's copy firing again minutes later.
    private func postTimeUpNotification() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [
            RansomNotificationID.timeUp,
            RansomNotificationID.timeWarning,
        ])
        center.removeDeliveredNotifications(withIdentifiers: [RansomNotificationID.timeWarning])

        let content = UNMutableNotificationContent()
        content.title = ShieldCopy.Unlock.timeUpTitle
        content.body = ShieldCopy.Unlock.timeUpBody()
        content.sound = .default
        deliver(content, id: RansomNotificationID.timeUp)
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
