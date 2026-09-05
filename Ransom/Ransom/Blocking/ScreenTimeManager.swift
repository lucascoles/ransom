import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import Observation

/// Owns everything Screen Time: authorization, which apps are gated, and the
/// arming/disarming of the shield as time is earned and burned.
///
/// Earned time is enforced two ways, and whichever fires first wins:
///  1. A `DeviceActivityEvent` threshold — the shield returns after the granted
///     number of minutes of *actual use* of the gated apps.
///  2. A wall-clock expiry in the shared ledger, re-checked by the app and by the
///     shield extensions every time they run.
@Observable
final class ScreenTimeManager {
    enum AuthorizationState: Equatable {
        case unknown
        case notDetermined
        case approved
        case denied(String)
    }

    private(set) var authorization: AuthorizationState = .unknown
    private(set) var isMonitoring = false

    /// Mirrors the persisted selection so SwiftUI redraws when apps are picked.
    var selection: FamilyActivitySelection {
        didSet {
            store.selection = selection
            reconcile()
            restartMonitoring()
        }
    }

    private let store = BlockedSelectionStore()
    private let ledger = UnlockLedger()
    private let center = DeviceActivityCenter()

    init() {
        selection = BlockedSelectionStore().selection
        refreshAuthorization()
        syncUnlockState()
    }

    var blockedCount: Int { store.count }
    var hasSelection: Bool { !store.isEmpty }

    // MARK: - Authorization

    func refreshAuthorization() {
        switch AuthorizationCenter.shared.authorizationStatus {
        // iOS 26.4 split approval in two: `.approvedWithDataAccess` is `.approved`
        // plus access to usage data. It is still a yes, and it has to be named
        // explicitly — left to `@unknown default` it read as `.unknown`, which
        // makes `isAuthorized` false and silently disables blocking for anyone
        // who granted the stronger permission.
        case .approved, .approvedWithDataAccess:
                              authorization = .approved
        case .denied:         authorization = .denied("Screen Time access was denied.")
        case .notDetermined:  authorization = .notDetermined
        @unknown default:     authorization = .unknown
        }
    }

    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            authorization = .approved
        } catch {
            // The most common failure is running on a device without Screen Time
            // enabled, or a Simulator — surface it rather than failing silently.
            authorization = .denied(error.localizedDescription)
        }
    }

    var isAuthorized: Bool { authorization == .approved }

    // MARK: - Shield state

    /// Mirrors the ledger so SwiftUI redraws when time is granted or revoked.
    ///
    /// The ledger itself lives in the App Group, because the shield extensions read
    /// it too — which means it's UserDefaults-backed and completely invisible to
    /// observation. Reading it through a computed property registered no
    /// dependency at all, so "Lock it back up" revoked the time and the button sat
    /// there unchanged until something unrelated forced a redraw. Same reason
    /// `selection` above is mirrored rather than read straight through.
    private(set) var isCurrentlyUnlocked: Bool = false
    var remainingUnlock: TimeInterval { ledger.remaining }

    /// Pulls the observable mirror back in line with the shared ledger. Cheap;
    /// call it after anything that grants or revokes, and on a tick so time
    /// running out on its own lands too.
    func syncUnlockState() {
        let unlocked = ledger.isUnlocked
        if unlocked != isCurrentlyUnlocked { isCurrentlyUnlocked = unlocked }
    }

    /// Brings the shield in line with the ledger. Cheap, idempotent, call freely.
    func reconcile() {
        syncUnlockState()
        guard isAuthorized else { return }
        store.reconcile(ledger: ledger)
    }

    /// Called after a completed set, or a spend from the bank: lifts the shield
    /// and starts the burn-down.
    ///
    /// **Order matters, and getting it wrong makes the minutes vanish with the
    /// apps still blocked.** The daily schedule covers the whole day, so we are
    /// always inside it, and `startMonitoring` therefore makes iOS call
    /// `intervalDidStart` on the monitor extension straight away. That extension
    /// reconciles the shield against the ledger - and if it runs in its own
    /// process before this one's grant is visible there, it reads "locked" and
    /// puts the shield back up on top of a grant that just happened. Removing the
    /// shield last means the extension can only ever lose that race.
    func grantEarnedTime(minutes: Int) {
        ledger.grant(minutes: minutes)
        syncUnlockState()
        guard isAuthorized else { return }
        restartMonitoring(thresholdMinutes: minutes)
        store.removeShield()
        NotificationManager.scheduleTimeUpReminder(in: minutes)
    }

    /// Ends earned time early — used by the "Lock it back up" button.
    func endEarnedTimeNow() {
        ledger.revoke()
        syncUnlockState()
        guard isAuthorized else { return }
        store.applyShield()
        restartMonitoring()
        NotificationManager.cancelTimeUpReminder()
    }

    // MARK: - Monitoring

    /// A schedule spanning the whole day so the threshold event has a window to
    /// live in. `repeats` keeps it armed across midnight.
    private var dailySchedule: DeviceActivitySchedule {
        DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )
    }

    func startMonitoring() {
        restartMonitoring()
    }

    private func restartMonitoring(thresholdMinutes: Int? = nil) {
        guard isAuthorized, !store.isEmpty else {
            isMonitoring = false
            return
        }

        center.stopMonitoring([.daily])

        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]

        // The usage ladder. iOS will not tell the app how long the user has been
        // in these apps, but it will call the monitor extension each time they
        // cross a threshold, so a rung per quarter hour turns an unanswerable
        // question into a series of callbacks. See `UsageMeter`.
        for minutes in UsageMeter.milestones {
            events[DeviceActivityEvent.Name(UsageMeter.eventName(forMinutes: minutes))] =
                DeviceActivityEvent(
                    applications: selection.applicationTokens,
                    categories: selection.categoryTokens,
                    webDomains: selection.webDomainTokens,
                    threshold: DateComponents(minute: minutes)
                )
        }

        if let thresholdMinutes {
            // Counts only while the gated apps are actually on screen.
            events[.earnedTimeSpent] = DeviceActivityEvent(
                applications: selection.applicationTokens,
                categories: selection.categoryTokens,
                webDomains: selection.webDomainTokens,
                threshold: DateComponents(minute: max(1, thresholdMinutes))
            )
        }

        do {
            try center.startMonitoring(.daily, during: dailySchedule, events: events)
            isMonitoring = true
        } catch {
            isMonitoring = false
        }
    }

    func stopMonitoring() {
        center.stopMonitoring([.daily, .unlockWindow])
        isMonitoring = false
    }

    // MARK: - Teardown

    /// Removes every restriction Ransom put in place. Used by "Turn off blocking".
    func disableBlocking() {
        stopMonitoring()
        store.removeShield()
        ledger.revoke()
    }
}
