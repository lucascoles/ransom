import DeviceActivity
import Foundation
import ManagedSettings

public extension ManagedSettingsStore.Name {
    /// The single store Repp owns. Named so we never clobber another app's settings.
    static let repp = Self("repp.block-store")
}

public extension DeviceActivityName {
    /// Always-on schedule that keeps the shield armed day to day.
    static let daily = Self("repp.daily")
    /// A one-off window that ends exactly when earned scroll time runs out.
    static let unlockWindow = Self("repp.unlock-window")
}
