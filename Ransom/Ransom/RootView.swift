import SwiftUI

/// Decides between the intake flow and the app proper, and owns the two things
/// that can interrupt anything: a workout, and a shield tap arriving from outside.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(ScreenTimeManager.self) private var screenTime
    @Environment(SubscriptionManager.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    @State private var workoutRequest: WorkoutRequest?
    @State private var selectedTab = 0
    @State private var hasWiredDarwinObserver = false

    var body: some View {
        Group {
            if model.hasCompletedOnboarding {
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
        TabView(selection: $selectedTab) {
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
            Task { @MainActor in
                model.consumePendingShieldRequest()
                startPendingWorkoutIfNeeded()
            }
        }
    }

    private func refresh() {
        screenTime.refreshAuthorization()
        // Earned time may have run out while the app was closed.
        screenTime.reconcile()
        screenTime.startMonitoring()
        model.consumePendingShieldRequest()
        Task { await store.refreshEntitlement() }
        startPendingWorkoutIfNeeded()
    }

    /// If the user got here by tapping the shield, drop them straight into the set.
    private func startPendingWorkoutIfNeeded() {
        guard model.pendingUnlockAppName != nil,
              workoutRequest == nil,
              model.hasCompletedOnboarding else { return }

        selectedTab = 0
        workoutRequest = WorkoutRequest(
            exercise: model.plan.exercise,
            target: model.quote.reps,
            trigger: model.pendingUnlockAppName
        )
    }
}

#Preview {
    RootView()
        .environment(AppModel.preview)
        .environment(ScreenTimeManager())
        .environment(SubscriptionManager())
}
