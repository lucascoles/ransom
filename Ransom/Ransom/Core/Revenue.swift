import Foundation
import RevenueCat
import StoreKit

/// RevenueCat, used as a recorder and nothing more.
///
/// `SubscriptionManager` still makes, verifies and finishes every purchase with
/// StoreKit 2 exactly as it did before. RevenueCat is configured with
/// `purchasesAreCompletedBy: .myApp`, so it never finishes a transaction or
/// decides who is subscribed; it only sees each purchase and reports it, which
/// is what gives the dashboard trials, conversions, cancellations and revenue.
///
/// Every call here swallows its errors on purpose. By the time RevenueCat is
/// told about a purchase, Apple has already charged for it and the app has
/// already unlocked; a network failure on the way to RevenueCat must never turn
/// that into a failed purchase on screen. Anything missed is not lost either:
/// in this mode the SDK looks for unrecorded transactions every time the app
/// comes to the foreground and syncs them then.
enum Revenue {
    /// The public SDK key for the App Store app. Designed to ship inside the
    /// binary: it identifies the app to RevenueCat and grants nothing else.
    private static let apiKey = "appl_iTQTzPwiXvcQCfmdwqEOiCNOpSp"

    /// Call once, at launch, before anything can reach `record` or `tag`.
    static func configure() {
        let env = ProcessInfo.processInfo.environment
        // SwiftUI previews and unit tests would otherwise create real
        // RevenueCat customers against the production project.
        guard env["XCODE_RUNNING_FOR_PREVIEWS"] != "1",
              env["XCTestConfigurationFilePath"] == nil
        else { return }

        #if DEBUG
        Purchases.logLevel = .debug
        #else
        Purchases.logLevel = .warn
        #endif

        Purchases.configure(
            with: Configuration.Builder(withAPIKey: apiKey)
                .with(purchasesAreCompletedBy: .myApp, storeKitVersion: .storeKit2)
                .build()
        )
    }

    /// Hands a purchase `SubscriptionManager` just made to RevenueCat. Must run
    /// before the transaction is finished, which is RevenueCat's requirement
    /// for purchases the app completes itself.
    static func record(_ result: Product.PurchaseResult) async {
        guard Purchases.isConfigured else { return }
        _ = try? await Purchases.shared.recordPurchase(result)
    }

    /// After a Restore tap. `AppStore.sync()` brings the transactions back to
    /// the device; this sends them on to RevenueCat.
    static func syncAfterRestore() async {
        guard Purchases.isConfigured else { return }
        _ = try? await Purchases.shared.syncPurchases()
    }

    /// Labels this customer with the intake answers that could explain who
    /// converts, so trials and revenue can be split by them in RevenueCat.
    ///
    /// Only answers about how they want to use the app. Name, age, gender,
    /// height and weight are never sent, and neither is their screen time
    /// figure beyond the bucket they picked.
    static func tag(_ profile: UserProfile) {
        guard Purchases.isConfigured else { return }
        var attributes: [String: String] = [
            "primary_exercise": profile.primaryExercise.rawValue,
            "intensity": profile.intensity.rawValue,
            "scrolls_in_bed": profile.peakTimes.contains(.lateNight) ? "yes" : "no",
        ]
        if let identity = profile.identity { attributes["identity"] = identity.rawValue }
        if let load = profile.scrollLoad { attributes["scroll_load"] = load.rawValue }
        if let referral = profile.referral { attributes["referral"] = referral.rawValue }
        Purchases.shared.attribution.setAttributes(attributes)
    }

    // MARK: - Where people leave the intake

    /// How far this launch has got through the intake. Only ever moves forward,
    /// so stepping back to change an answer doesn't look like dropping out.
    @MainActor private static var furthestIntakeStep = -1

    /// Tags the customer with the furthest intake step reached.
    ///
    /// RevenueCat uploads attributes when the app resigns active, which is
    /// exactly the moment someone gives up on the intake, so each customer's
    /// last value is the step they left on. Counting customers by this tag is
    /// the drop-off funnel. Values sort in flow order: `05-reality`.
    @MainActor static func markIntakeStep(_ step: OnboardingStep) {
        guard Purchases.isConfigured, step.rawValue > furthestIntakeStep else { return }
        furthestIntakeStep = step.rawValue
        let label = "\(String(format: "%02d", step.rawValue))-\(step)"
        Purchases.shared.attribution.setAttributes(["intake_step": label])
    }

    /// Past the paywall and into the app: the end of the funnel.
    @MainActor static func markIntakeFinished() {
        guard Purchases.isConfigured else { return }
        Purchases.shared.attribution.setAttributes(["intake_step": "99-finished"])
    }
}
