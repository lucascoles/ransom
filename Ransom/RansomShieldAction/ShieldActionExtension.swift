import ManagedSettings
import UIKit
import UserNotifications

/// Handles taps on the shield's two buttons.
///
/// Extensions can't launch their host app, so "Earn my time" records the request
/// in the App Group and pings the app over Darwin notifications. Whether Ransom is
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
            ledger.pendingAppName = RansomCore.defaults.string(forKey: RansomCore.Key.shieldHeadline)

            DarwinNotifications.post(RansomCore.unlockRequestedNotification)
            notifyUserToOpenRansom(ledger: ledger)

            completionHandler(.close)

        // iOS 26.4 added a three-item secondary submenu to the shield. Ransom
        // configures no submenu, so these cannot fire today, but they have to be
        // named rather than left to `@unknown default`. All of them dismiss:
        // whatever a submenu item might one day mean, it must never take the
        // primary path, which is the one that spends from the bank.
        case .secondaryButtonPressed,
             .firstSecondarySubmenuItemPressed,
             .secondSecondarySubmenuItemPressed,
             .thirdSecondarySubmenuItemPressed:
            ledger.clearPendingRequest()
            completionHandler(.close)

        @unknown default:
            completionHandler(.close)
        }
    }

    /// The handoff. A tap on this notification opens Ransom, which then sees the
    /// pending request and starts the set automatically.
    private func notifyUserToOpenRansom(ledger: UnlockLedger) {
        let banked = ledger.bankedMinutes
        let minutes = ledger.minutesPerUnlock

        let content = UNMutableNotificationContent()
        content.title = ShieldCopy.handoff(banked: banked, minutes: minutes)
        content.body = ShieldCopy.handoffBody(reps: ledger.repsPerUnlock,
                                              exercise: ledger.exerciseName,
                                              minutes: minutes,
                                              banked: banked)
        content.sound = .default
        // Time-sensitive so it breaks through a Focus. This notification is the
        // only route back to Ransom that Apple actually supports - an extension
        // cannot open its host app, `ShieldActionResponse` has no case for it,
        // and `UIApplication.open` does not exist out here - so if it is
        // silenced the primary button has done nothing at all.
        content.interruptionLevel = .timeSensitive

        let request = UNNotificationRequest(
            identifier: "ransom.shield.handoff",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }
}
