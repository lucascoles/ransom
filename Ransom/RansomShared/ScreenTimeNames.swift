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

public extension DeviceActivityEvent.Name {
    /// Fires when the minutes the user bought have been used up.
    ///
    /// Lives here rather than beside the app's monitoring code because the
    /// extension has to recognise it: once more than one kind of event exists,
    /// a callback the extension cannot name is a callback it will treat as this
    /// one and revoke somebody's time for no reason.
    nonisolated(unsafe) static let earnedTimeSpent = Self("ransom.earned-time-spent")
}
