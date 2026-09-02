import ManagedSettings
import ManagedSettingsUI
import UIKit

/// Renders the screen the user sees instead of Instagram.
///
/// This runs in its own short-lived process every time a shielded app is opened,
/// so it reads everything it needs from the shared App Group and does no work
/// beyond building the view.
final class ShieldConfigurationExtension: ShieldConfigurationDataSource {

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        // The action extension only receives an opaque token, so stash the readable
        // name here — it's the one place the system hands it to us.
        if let name = application.localizedDisplayName {
            RansomCore.defaults.set(name, forKey: RansomCore.Key.shieldHeadline)
        }
        return makeConfiguration(appName: application.localizedDisplayName)
    }

    override func configuration(
        shielding application: Application,
        in category: ActivityCategory
    ) -> ShieldConfiguration {
        configuration(shielding: application)
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        makeConfiguration(appName: webDomain.domain)
    }

    override func configuration(
        shielding webDomain: WebDomain,
        in category: ActivityCategory
    ) -> ShieldConfiguration {
        configuration(shielding: webDomain)
    }

    // MARK: - Shared builder

    private func makeConfiguration(appName: String?) -> ShieldConfiguration {
        let ledger = UnlockLedger()
        let quote = ledger.currentQuote()
        let exercise = ledger.exerciseName
        let minutes = ledger.minutesPerUnlock

        let title = appName.map { "\($0) costs \(quote.reps) \(exercise.lowercased())" }
            ?? ShieldCopy.headline(reps: quote.reps, exercise: exercise)

        // When the tariff is up, say why. An unexplained price rise reads as a bug.
        let lead = quote.explanation ?? ShieldCopy.taunt()
        let subtitle = "\(lead)\nOne set buys you \(minutes) minutes."

        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: UIColor(red: 0.05, green: 0.07, blue: 0.05, alpha: 0.92),
            icon: RexBadge.image(size: 180),
            title: ShieldConfiguration.Label(
                text: title,
                color: .white
            ),
            subtitle: ShieldConfiguration.Label(
                text: subtitle,
                color: UIColor(white: 1, alpha: 0.72)
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: ShieldCopy.primaryButton,
                color: UIColor(red: 0.03, green: 0.09, blue: 0.04, alpha: 1)
            ),
            primaryButtonBackgroundColor: UIColor(red: 0.42, green: 0.87, blue: 0.42, alpha: 1),
            secondaryButtonLabel: ShieldConfiguration.Label(
                text: ShieldCopy.secondaryButton,
                color: UIColor(white: 1, alpha: 0.6)
            )
        )
    }
}
