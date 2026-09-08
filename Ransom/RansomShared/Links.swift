import Foundation

/// The app's outward-facing URLs, in one place.
///
/// These were previously written inline in `PaywallView`, force-unwrapped, and
/// pointed at pages that did not exist. App Review opens every one of them, and a
/// dead privacy link is a rejection rather than a note.
///
/// Keeping them here means the domain is changed once rather than hunted for, and
/// `RansomLinks.allReachable` gives you a single thing to check before submitting.
public enum RansomLinks {
    /// Change this one line to move the whole set to a different host.
    private static let host = "https://ransom.app"

    public static let privacy = URL(string: "\(host)/privacy")!
    public static let terms = URL(string: "\(host)/terms")!
    public static let support = URL(string: "\(host)/support")!

    /// Apple's own subscription management screen. Not ours, and not optional:
    /// a subscription app has to offer a route to cancellation.
    public static let manageSubscription = URL(string: "https://apps.apple.com/account/subscriptions")!

    /// Every page App Review will open, so the pre-submission check is one loop
    /// rather than a memory of which links exist.
    public static let mustBeLive: [(name: String, url: URL)] = [
        ("Privacy policy", privacy),
        ("Terms of use", terms),
        ("Support", support),
    ]
}
