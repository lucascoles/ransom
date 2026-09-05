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

        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: RansomPalette.shieldBackground.withAlphaComponent(0.94),
            // Rex is the whole point of this screen. The stock shield is an
            // hourglass and the word "Restricted", which reads as a punishment
            // handed down by the phone; the same block with Rex on it reads as
            // the thing the user asked for.
            icon: RexBadge.image(size: 200),
            title: ShieldConfiguration.Label(
                text: ShieldCopy.headline(appName: appName),
                color: .white
            ),
            subtitle: ShieldConfiguration.Label(
                text: ShieldCopy.subtitle(
                    reps: ledger.repsPerUnlock,
                    exercise: ledger.exerciseName,
                    minutes: ledger.minutesPerUnlock,
                    banked: ledger.bankedMinutes
                ),
                color: UIColor(white: 1, alpha: 0.75)
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: ShieldCopy.primaryButton(banked: ledger.bankedMinutes,
                                               minutes: ledger.minutesPerUnlock),
                // White, not the near-black `onBrand`. On the shield's dark
                // background the tangerine button is much darker than it is on
                // paper, and ink on it reads as a disabled control.
                color: .white
            ),
            primaryButtonBackgroundColor: RansomPalette.brandDark,
            secondaryButtonLabel: ShieldConfiguration.Label(
                text: ShieldCopy.secondaryButton,
                color: UIColor(white: 1, alpha: 0.65)
            )
        )
    }
}
