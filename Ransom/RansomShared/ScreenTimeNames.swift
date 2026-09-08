import DeviceActivity
import Foundation
import ManagedSettings

// `ManagedSettingsStore.Name` and `DeviceActivityName` are both structs wrapping a
// String, so these constants are immutable and safe to share across the four
// targets. Apple has simply never marked either type Sendable, which makes a
// plain `static let` an error under the Swift 6 language mode; `nonisolated(unsafe)`
// says what is actually true here rather than conforming someone else's type.

public extension ManagedSettingsStore.Name {
    /// The single store Ransom owns. Named so we never clobber another app's settings.
    nonisolated(unsafe) static let ransom = Self("ransom.block-store")
}

public extension DeviceActivityName {
    /// Always-on schedule that keeps the shield armed day to day.
    nonisolated(unsafe) static let daily = Self("ransom.daily")
    /// A one-off window that ends exactly when earned scroll time runs out.
    nonisolated(unsafe) static let unlockWindow = Self("ransom.unlock-window")
}

/// Notification identifiers, shared because two *processes* raise the same two
/// alerts and iOS only collapses them when the identifier matches.
///
/// Time is up for one of two reasons: the wall clock ran out, which the app knows
/// in advance and schedules a timer for, or the bought minutes were actually spent,
/// which only the monitor extension is told about. Both are the same event to the
/// person holding the phone. They used to carry different identifiers and both
/// arrive.
public enum RansomNotificationID {
    /// "Time's up." Raised by the app on the wall clock and by the monitor on usage.
    public static let timeUp = "ransom.time-up"
    /// The heads-up a few minutes before the above.
    public static let timeWarning = "ransom.time-warning"
}

public extension DeviceActivityEvent.Name {
    /// Fires when the minutes the user bought have been used up.
    ///
    /// Lives here rather than beside the app's monitoring code because the
    /// extension has to recognise it: once more than one kind of event exists,
    /// a callback the extension cannot name is a callback it will treat as this
    /// one and revoke somebody's time for no reason.
    nonisolated(unsafe) static let earnedTimeSpent = Self("ransom.earned-time-spent")
}
