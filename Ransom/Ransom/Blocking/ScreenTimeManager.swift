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
    /// Everything after the grant is armed against the time now on the clock,
    /// not against the minutes just added.
    ///
    /// `UnlockLedger.grant` extends: five minutes left plus a fifteen-minute set
    /// is twenty, which is the point of buying more before you run out. But the
    /// two things that end an unlock were both armed at the *delta*. The usage
    /// window's threshold fired after fifteen minutes of use and revoked a
    /// session with five paid-for minutes still on it, and the "time's up"
    /// notification went out five minutes early to say so.
    ///
    /// It stayed hidden because extending was hard to do: you had to open Ransom
    /// mid-unlock and complete a whole set. It stops being hidden the moment
    /// spending banked minutes during an unlock is one tap, which is what Home
    /// now offers.
    /// Whether spending would actually open anything.
    ///
    /// Without Screen Time permission, or with no apps chosen, there is no shield
    /// to lift - so an unlock is an unlock of nothing. The check is public
    /// because the spend buttons need it too: the bank is debited before this is
    /// called, and coins spent on nothing are not refundable from here.
    var canUnlock: Bool { isAuthorized && !store.isEmpty }

    /// Opens the apps for `minutes`. Returns false, having changed nothing, when
    /// there is nothing to open.
    ///
    /// The guard used to sit *below* `ledger.grant`, which meant an unauthorized
    /// user got the full illusion of an unlock: the bank debited, the countdown
    /// running on Home, Rex promising a nudge when time was up - and no shield
    /// had ever been raised, so nothing was unlocked and nothing would lock. The
    /// ledger is the app's source of truth about whether time is running, and
    /// writing to it before knowing the unlock can happen is what made the lie
    /// convincing.
    @discardableResult
    func grantEarnedTime(minutes: Int) -> Bool {
        guard canUnlock else {
            ledger.trace("refused grant of \(minutes)m: authorized=\(isAuthorized) apps=\(store.count)")
            return false
        }

        ledger.grant(minutes: minutes)
        ledger.trace("app granted \(minutes)m")
        syncUnlockState()

        // Rounded up, so the arithmetic never shortens an unlock: a ledger
        // reading 19m01s is nineteen whole minutes plus change the user paid for.
        let total = max(minutes, Int((ledger.remaining / 60).rounded(.up)))

        restartMonitoring()
        startUnlockWindow(minutes: total)
        store.removeShield()
        NotificationManager.scheduleTimeUpReminder(in: total)
        return true
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

    private func restartMonitoring() {
        // Deliberately not gated on a selection any more. The benchmark is total
        // screen time, so the meter has to run from the moment Screen Time is
        // granted - including before any app has been chosen, and on the days
        // somebody guards nothing at all.
        guard isAuthorized else {
            isMonitoring = false
            return
        }

        center.stopMonitoring([.daily])

        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]

        // The usage ladder. iOS will not tell the app how long the user has been
        // on their phone, but it will call the monitor extension each time they
        // cross a threshold, so a rung per quarter hour turns an unanswerable
        // question into a series of callbacks. See `UsageMeter`.
        //
        // **Empty token sets on purpose.** A `DeviceActivityEvent` with no
        // applications, categories or web domains has `includesAllActivity` set,
        // which is what makes this the whole phone rather than the guarded apps.
        // It used to be scoped to `selection`, and that quietly made the app's
        // central number mean something different from the question that asked
        // for it: onboarding took a figure for the whole phone and then compared
        // it against usage of four apps, so "minutes saved" counted every minute
        // spent in Maps and Messages as a win.
        //
        // Blocking is unaffected. The shield reads `selection` separately; this
        // event set only measures.
        for minutes in UsageMeter.milestones {
            events[DeviceActivityEvent.Name(UsageMeter.eventName(forMinutes: minutes))] =
                DeviceActivityEvent(
                    applications: [],
                    categories: [],
                    webDomains: [],
                    threshold: DateComponents(minute: minutes)
                )
        }

        do {
            try center.startMonitoring(.daily, during: dailySchedule, events: events)
            isMonitoring = true
        } catch {
            isMonitoring = false
        }
    }

    /// The burn-down for time the user has just paid for.
    ///
    /// This has to be its own activity, and that is the whole point. A
    /// `DeviceActivityEvent` threshold counts usage across *its schedule's
    /// interval*, and the daily schedule starts at midnight - so an
    /// "expire after 15 minutes of use" event registered there was measuring the
    /// whole day. Anybody who had already spent a quarter of an hour in their own
    /// apps had the event fire the instant monitoring restarted, revoking the
    /// minutes they had just bought and putting the shield straight back up. The
    /// bank emptied and nothing opened.
    ///
    /// A window that starts *now* measures only what happens inside it.
    private func startUnlockWindow(minutes: Int) {
        center.stopMonitoring([.unlockWindow])
        guard !store.isEmpty else { return }

        let calendar = Calendar.current
        let now = Date()
        // The window ends at the ledger's own expiry, to the second. That end is
        // the enforcement: `intervalDidEnd` fires on the wall clock, the same
        // clock the countdown and the "Time's up" notification use, whether the
        // phone is in use or asleep in a pocket.
        let paid = ledger.remaining > 0 ? ledger.remaining : TimeInterval(minutes * 60)
        let end = now.addingTimeInterval(paid)
        // **Backdated, not padded.** Apple refuses a schedule shorter than
        // fifteen minutes, so a five minute unlock used to get a window running
        // fifteen minutes into the future, and a usage threshold was registered
        // inside it to fire at the real figure. That threshold is gone, for two
        // reasons found on a real phone:
        //
        // - Scoped to the guarded apps, it only counted time spent inside them,
        //   so "Time's up" arrived and the shield did not come back.
        // - Scoped to the whole phone (ea7fd98), it fired within seconds of the
        //   window starting - iOS 26 delivers `eventDidReachThreshold` almost
        //   immediately after `startMonitoring`, a regression Apple DTS has
        //   confirmed and which is still present on 26.6 - so buying five more
        //   minutes revoked them before the user reached the app.
        //
        // Starting the interval in the past gives Apple its fifteen minutes and
        // still ends it exactly when the time is up. A start earlier than now is
        // an interval already in progress, which iOS accepts and reports with an
        // immediate `intervalDidStart` - the daily schedule, anchored to
        // midnight, relies on the same thing every time it restarts mid-day. The
        // hour/minute/second components also wrap midnight on their own: 23:48
        // to 00:03 is read as an interval that started twelve minutes ago.
        let start = min(now, end.addingTimeInterval(-(15 * 60 + 10)))

        let schedule = DeviceActivitySchedule(
            intervalStart: calendar.dateComponents([.hour, .minute, .second], from: start),
            intervalEnd: calendar.dateComponents([.hour, .minute, .second], from: end),
            repeats: false
        )
        do {
            try center.startMonitoring(.unlockWindow, during: schedule)
            ledger.trace("window \(start.formatted(date: .omitted, time: .standard))-\(end.formatted(date: .omitted, time: .standard)) paid=\(Int(paid))s")
        } catch {
            // Used to be `try?`, which left a failed window unenforced and silent.
            ledger.trace("window FAILED: \(error)")
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
