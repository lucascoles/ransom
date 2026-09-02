import ManagedSettings
import UIKit
import UserNotifications

/// Handles taps on the shield's two buttons.
///
/// Extensions can't launch their host app, so "Earn my time" records the request
/// in the App Group and pings the app over Darwin notifications. Whether Repp is
/// backgrounded or cold, it picks the request up and drops the user straight into
/// a set for the app they were reaching for.
final class ShieldActionExtension: ShieldActionDelegate {

    override func handle(
        action: ShieldAction,
        for application: ApplicationToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        respond(to: action, completionHandler: completionHandler)
    }

    override func handle(
        action: ShieldAction,
        for webDomain: WebDomainToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        respond(to: action, completionHandler: completionHandler)
    }

    override func handle(
        action: ShieldAction,
        for category: ActivityCategoryToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        respond(to: action, completionHandler: completionHandler)
    }

    private func respond(
        to action: ShieldAction,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        let ledger = UnlockLedger()

        switch action {
        case .primaryButtonPressed:
            ledger.pendingRequest = Date()
            // Written by the configuration extension the moment the shield appeared.
            ledger.pendingAppName = ReppCore.defaults.string(forKey: ReppCore.Key.shieldHeadline)

            DarwinNotifications.post(ReppCore.unlockRequestedNotification)
            notifyUserToOpenRepp(reps: ledger.repsPerUnlock, exercise: ledger.exerciseName)

            completionHandler(.close)

        case .secondaryButtonPressed:
            ledger.clearPendingRequest()
            completionHandler(.close)

        @unknown default:
            completionHandler(.close)
        }
    }

    /// The handoff. A tap on this notification opens Repp, which then sees the
    /// pending request and starts the set automatically.
    private func notifyUserToOpenRepp(reps: Int, exercise: String) {
        let content = UNMutableNotificationContent()
        content.title = ShieldCopy.handoff
        content.body = "\(reps) \(exercise.lowercased()) and you're back in."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "repp.shield.handoff",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }
}
