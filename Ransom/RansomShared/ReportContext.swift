import SwiftUI
import DeviceActivity

/// Names the one report Ransom renders.
///
/// Lives in shared code because both halves need the same string: the app asks
/// for a context by name and the extension answers to it, and they are compiled
/// into different processes. Declared in one of them only, the other silently
/// asks for a report nobody provides.
public extension DeviceActivityReport.Context {
    static let totalActivity = Self("Total Activity")
}
