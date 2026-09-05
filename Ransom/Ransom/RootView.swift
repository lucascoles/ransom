import SwiftUI

/// Decides between the intake flow and the app proper, and owns the two things
/// that can interrupt anything: a workout, and a shield tap arriving from outside.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(ScreenTimeManager.self) private var screenTime
    @Environment(SubscriptionManager.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    @State private var workoutRequest: WorkoutRequest?
    @State private var selectedTab = RootView.startingTab()
    @State private var hasWiredDarwinObserver = false

    /// `-RansomTab 1` opens straight onto Progress, `2` onto Settings. Lets a
    /// screenshot run reach every tab without a UI-test target. Debug builds only.
    private static func startingTab() -> Int {
        #if DEBUG
        return UserDefaults.standard.integer(forKey: "RansomTab")
        #else
        return 0
        #endif
    }

    /// `-RansomIntake 1` shows the intake again on a device that has finished it.
    ///
    /// `-RansomStartStep` only chooses a step *within* the flow, so on any phone
    /// that has been past the paywall once it does nothing at all - the flow is
    /// never built to read it. Reviewing intake copy otherwise meant deleting the
    /// app and losing the bank, the app picks and the Screen Time grant with it.
    private var forcesIntake: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "RansomIntake")
        #else
        return false
        #endif
    }

    var body: some View {
        Group {
            if model.hasCompletedOnboarding && !forcesIntake {
                mainTabs
            } else {
                OnboardingFlow()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: model.hasCompletedOnboarding)
        .fullScreenCover(item: $workoutRequest) { request in
            WorkoutView(
                exercise: request.exercise,
                target: request.target,
                trigger: request.trigger
            )
        }
        .onAppear(perform: bootstrap)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refresh() }
        }
        .onChange(of: store.isSubscribed) { _, subscribed in
            // Keep the local flag in step with the real entitlement.
            if subscribed { model.isSubscribed = true }
        }
    }

    private var mainTabs: some View {
        TabView(selection: Binding(
            get: { selectedTab },
            set: {
                if $0 != selectedTab { Haptics.select() }
                selectedTab = $0
            }
        )) {
            NavigationStack {
                HomeView(workoutRequest: $workoutRequest)
                    .navigationTitle("Ransom")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem { Label("Home", systemImage: "house.fill") }
            .tag(0)

            NavigationStack {
                StatsView()
                    .navigationTitle("Progress")
            }
            .tabItem { Label("Progress", systemImage: "chart.bar.fill") }
            .tag(1)

            NavigationStack {
                SettingsView()
                    .navigationTitle("Settings")
            }
            .tabItem { Label("Settings", systemImage: "gearshape.fill") }
            .tag(2)
        }
    }

    // MARK: - Lifecycle

    private func bootstrap() {
        refresh()

        guard !hasWiredDarwinObserver else { return }
        hasWiredDarwinObserver = true

        // Fires when the shield's "Earn my time" button is tapped while Ransom is
        // already running in the background.
        DarwinNotifications.observe(RansomCore.unlockRequestedNotification) {
            model.consumePendingShieldRequest()
        }
    }

    private func refresh() {
        screenTime.refreshAuthorization()
        // Earned time may have run out while the app was closed.
        screenTime.reconcile()
        screenTime.startMonitoring()
        // Written by the monitor extension while we were away.
        model.usageRevision += 1
        model.consumePendingShieldRequest()
        Task { await store.refreshEntitlement() }
    }

    // The shield handoff used to open the camera the moment Ransom came to the
    // front. It was removed because it fired on *every* foreground, not just the
    // one after a shield tap - `pendingUnlockAppName` outlives the launch that
    // set it, so the app reopened the camera each time it was returned to, which
    // is an app that will not let you look at your own home screen.
    //
    // The handoff still lands: Home greets the user by the app they were
    // reaching for, and starting the set is one deliberate tap from there.
}

#Preview {
    RootView()
        .environment(AppModel.preview)
        .environment(ScreenTimeManager())
        .environment(SubscriptionManager())
}
