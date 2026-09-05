import Foundation

/// Extensions run in separate processes, so the only way a shield tap can reach a
/// running app is a Darwin notification. Tiny wrapper around the C API.
public enum DarwinNotifications {
    public static func post(_ name: String) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name as CFString),
            nil,
            nil,
            true
        )
    }

    /// Observes a Darwin name for the lifetime of the process. The handler is
    /// always delivered on the main actor — the callback arrives on an arbitrary
    /// thread and every caller wants to touch UI state, so the hop belongs here
    /// rather than being repeated at each call site.
    public static func observe(_ name: String, handler: @escaping @MainActor () -> Void) {
        let callback: CFNotificationCallback = { _, observer, _, _, _ in
            guard let observer else { return }
            let box = Unmanaged<Box>.fromOpaque(observer).takeUnretainedValue()
            Task { @MainActor in box.handler() }
        }

        let box = Box(handler: handler)
        // Retained deliberately: the observer lives as long as the app does.
        let pointer = Unmanaged.passRetained(box).toOpaque()

        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            pointer,
            callback,
            name as CFString,
            nil,
            .deliverImmediately
        )
    }

    private final class Box: Sendable {
        let handler: @MainActor () -> Void
        init(handler: @escaping @MainActor () -> Void) { self.handler = handler }
    }
}
