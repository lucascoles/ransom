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
    }

    var blockedCount: Int { store.count }
    var hasSelection: Bool { !store.isEmpty }

    // MARK: - Authorization

    func refreshAuthorization() {
        switch AuthorizationCenter.shared.authorizationStatus {
        case .approved:       authorization = .approved
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

    var isCurrentlyUnlocked: Bool { ledger.isUnlocked }
    var remainingUnlock: TimeInterval { ledger.remaining }

    /// Brings the shield in line with the ledger. Cheap, idempotent, call freely.
    func reconcile() {
        guard isAuthorized else { return }
        store.reconcile(ledger: ledger)
    }

    /// Called after a completed set: lifts the shield and starts the burn-down.
    func grantEarnedTime(minutes: Int) {
        ledger.grant(minutes: minutes)
        guard isAuthorized else { return }
        store.removeShield()
        restartMonitoring(thresholdMinutes: minutes)
        NotificationManager.scheduleTimeUpReminder(in: minutes)
    }

    /// Ends earned time early — used by the "Lock it back up" button.
    func endEarnedTimeNow() {
        ledger.revoke()
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

    /// Removes every restriction Repp put in place. Used by "Turn off blocking".
    func disableBlocking() {
        stopMonitoring()
        store.removeShield()
        ledger.revoke()
    }
}

extension DeviceActivityEvent.Name {
    static let earnedTimeSpent = Self("repp.earned-time-spent")
}
