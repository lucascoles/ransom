import FacebookCore
import Foundation
import RevenueCat

/// Meta's SDK, used to tell Meta which ads brought installs and nothing more.
///
/// Three signals go to Meta: the install and each app open (`activateApp`),
/// and the first time someone reaches the paywall (logged as Meta's standard
/// "Complete Tutorial" event, so an ad set can optimise for it). Trials and
/// purchases are not logged here: RevenueCat sends them to Meta from its
/// servers, and logging them twice would double every count. Automatic event
/// logging is off in Info.plist for the same reason, since it includes
/// in-app purchases.
///
/// There is no tracking prompt and no advertising identifier. Meta matches
/// these events through Apple's SKAdNetwork and its own aggregated measurement.
///
/// Stays switched off while `FACEBOOK_APP_ID` is empty, so the app builds and
/// runs the same before the Meta app exists.
enum AdMeasurement {
    private static var isStarted = false

    /// Call once, at launch, after `Revenue.configure()`.
    static func configure() {
        let env = ProcessInfo.processInfo.environment
        guard env["XCODE_RUNNING_FOR_PREVIEWS"] != "1",
              env["XCTestConfigurationFilePath"] == nil
        else { return }

        let appID = Bundle.main.object(forInfoDictionaryKey: "FacebookAppID") as? String ?? ""
        guard !appID.isEmpty, !appID.hasPrefix("$(") else { return }

        ApplicationDelegate.shared.initializeSDK()
        isStarted = true

        // RevenueCat only forwards a trial or purchase to Meta for a customer
        // that carries this ID. Without a tracking prompt it is the only link
        // between the two.
        if Purchases.isConfigured {
            Purchases.shared.attribution.setFBAnonymousID(AppEvents.shared.anonymousID)
        }
    }

    /// Each time the app comes to the foreground. The first one is the install.
    static func appBecameActive() {
        guard isStarted else { return }
        AppEvents.shared.activateApp()
    }

    private static let paywallLoggedKey = "ransom.meta.paywallReached"

    /// The first time this person reaches the intake paywall, ever.
    static func paywallReached() {
        guard isStarted,
              !UserDefaults.standard.bool(forKey: paywallLoggedKey)
        else { return }
        UserDefaults.standard.set(true, forKey: paywallLoggedKey)
        AppEvents.shared.logEvent(.completedTutorial)
    }
}
