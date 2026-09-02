import DeviceActivity
import Foundation
import ManagedSettings

public extension ManagedSettingsStore.Name {
    /// The single store Ransom owns. Named so we never clobber another app's settings.
    static let ransom = Self("ransom.block-store")
}

public extension DeviceActivityName {
    /// Always-on schedule that keeps the shield armed day to day.
    static let daily = Self("ransom.daily")
    /// A one-off window that ends exactly when earned scroll time runs out.
    static let unlockWindow = Self("ransom.unlock-window")
}
