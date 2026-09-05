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
        let exercise = ledger.exerciseName
        let minutes = ledger.minutesPerUnlock
        let reps = ledger.repsPerUnlock
        let banked = ledger.bankedMinutes

        let title = appName.map { "\($0)? \(reps) \(exercise.lowercased()) first" }
            ?? ShieldCopy.headline(reps: reps, exercise: exercise)

        // A balance already earned is the most useful thing the shield can say:
        // it turns "you're blocked" into "you're one tap from being unblocked".
        let lead = banked > 0 ? "You've got \(banked) minutes banked." : ShieldCopy.taunt()
        let subtitle = "\(lead)\nOne set banks you \(minutes) more."

        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: RansomPalette.shieldBackground.withAlphaComponent(0.92),
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
                color: RansomPalette.onBrand
            ),
            primaryButtonBackgroundColor: RansomPalette.brandDark,
            secondaryButtonLabel: ShieldConfiguration.Label(
                text: ShieldCopy.secondaryButton,
                color: UIColor(white: 1, alpha: 0.6)
            )
        )
    }
}
