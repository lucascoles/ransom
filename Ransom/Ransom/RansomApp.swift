import SwiftUI

@main
struct RansomApp: App {
    @State private var model = RansomApp.startingModel()
    @State private var screenTime = ScreenTimeManager()
    @State private var store = SubscriptionManager()

    /// `-RansomPreviewUnlocked 1` starts past onboarding with a lived-in profile, so
    /// the tabs behind the paywall can be looked at without a StoreKit purchase.
    /// The paywall needs the scheme's StoreKit config to sell anything, which a bare
    /// `simctl launch` never loads. Debug builds only.
    private static func startingModel() -> AppModel {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "RansomPreviewUnlocked") {
            return .preview
        }
        #endif
        return AppModel()
    }

    /// Shown once, on the very first launch, ahead of the intake flow.
    ///
    /// Two gates, and both matter. Being view state means it dies with the process,
    /// so it never fires when the app is merely brought back from the background —
    /// which for a screen-time blocker is most of the times it opens. Checking
    /// onboarding keeps it to people meeting the app for the first time: a returning
    /// user opening this because they were just blocked wants their reps, and a
    /// two-second title card between them and the set is a tax on being interrupted.
    @State private var isLaunching = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()
                    .environment(model)
                    .environment(screenTime)
                    .environment(store)
                    .tint(Palette.brand)

                if isLaunching && !model.hasCompletedOnboarding {
                    LaunchSplash { isLaunching = false }
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
        }
    }
}
