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
            // The one place that knows a blocked app was reached for.
            BlockCountStore().record(app: name)
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
        let deal = ShieldCopy.Deal(appName: appName)
        let theme = ShieldTheme.current()

        return ShieldConfiguration(
            backgroundBlurStyle: theme.blur,
            backgroundColor: theme.background,
            // Rex is the whole point of this screen. The stock shield is an
            // hourglass and the word "Restricted", which reads as a punishment
            // handed down by the phone; the same block with Rex standing in the
            // doorway reads as the thing the user asked for.
            icon: ShieldIcon.rex(),
            title: ShieldConfiguration.Label(
                text: ShieldCopy.title(deal),
                color: theme.title
            ),
            subtitle: ShieldConfiguration.Label(
                text: ShieldCopy.subtitle(deal),
                color: theme.subtitle
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: ShieldCopy.primaryButton(deal),
                color: theme.buttonLabel
            ),
            primaryButtonBackgroundColor: theme.button,
            secondaryButtonLabel: ShieldConfiguration.Label(
                text: ShieldCopy.secondaryButton,
                color: theme.secondary
            )
        )
    }
}
