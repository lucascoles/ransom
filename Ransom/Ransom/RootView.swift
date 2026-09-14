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

    /// `-RansomSeedHistory 1` fills the Progress tab with a plausible three
    /// weeks: usage history for the trend, and completed sets for the streak,
    /// the totals, the movement breakdown and the recent list.
    ///
    /// Seeding it from outside does not work: the App Group's plist is cached by
    /// cfprefsd, and the `defaults` CLI writes to a different store than the
    /// group container the app reads. The app writing its own is the only route
    /// that goes through the same door as the real thing.
    private func seedHistoryIfAsked() {
        #if DEBUG
        guard UserDefaults.standard.bool(forKey: "RansomSeedHistory") else { return }
        let calendar = Calendar.current

        // Screen time coming down over a fortnight, with one day missing so the
        // chart's gap handling is visible rather than assumed.
        let minutes = [128, 141, 119, 133, 150, 126, 138, 118, 109, 0, 97, 104, 88, 92]
        let usage = UsageHistory()
        for (index, value) in minutes.enumerated() where value > 0 {
            guard let day = calendar.date(byAdding: .day,
                                          value: -(minutes.count - 1 - index),
                                          to: Date()) else { continue }
            usage.record(.guarded, minutes: value, on: day)
        }

        // Sets over three weeks. Deliberately uneven - a couple of rest days, a
        // mix of movements, some days with two sets - because a perfect run makes
        // the streak, the averages and the breakdown all look better than they
        // ever will in life.
        guard model.history.isEmpty else { return }
        let plan = [(0, 2), (1, 1), (2, 1), (3, 0), (4, 2), (5, 1), (6, 1),
                    (7, 1), (8, 0), (9, 1), (10, 2), (11, 1), (12, 1), (13, 0),
                    (14, 1), (15, 1), (16, 2), (17, 0), (18, 1), (19, 1), (20, 1)]
        var seeded: [WorkoutRecord] = []
        for (back, sets) in plan {
            guard sets > 0,
                  let day = calendar.date(byAdding: .day, value: -back, to: Date()),
                  let at = calendar.date(bySettingHour: 18, minute: 20, second: 0, of: day)
            else { continue }
            for set in 0..<sets {
                // Full sets at the seeded profile's own tier, so the history
                // reads as paid sets rather than a run of near-misses once the
                // rep table changes.
                let exercise: Exercise = (back + set) % 3 == 0 ? .squats : .pushUps
                seeded.append(WorkoutRecord(
                    date: at.addingTimeInterval(Double(set) * 3_600),
                    exercise: exercise,
                    reps: model.plan.repsRequired(for: exercise),
                    durationSeconds: 40 + set * 6,
                    minutesGranted: model.plan.minutesPerUnlock
                ))
            }
        }
        model.history = seeded.sorted { $0.date < $1.date }
        #endif
    }

    var body: some View {
        Group {
            if model.hasCompletedOnboarding && !forcesIntake {
                mainTabs
            } else {
                OnboardingFlow()
                    .transition(.opacity)
                    // Intake is light-only, deliberately.
                    //
                    // The flow is sixteen screens of cream paper, hand-placed
                    // illustration and Rex art rendered on a light ground, and in
                    // dark mode it comes apart: the artwork keeps its own
                    // background while the canvas inverts around it. Every colour
                    // here goes through `Palette`, so the app proper handles dark
                    // mode correctly - this is about the pictures, which are
                    // fixed-value PNGs and cannot adapt.
                    //
                    // `preferredColorScheme` overrides the window's interface
                    // style, and `Color.adaptive` reads `userInterfaceStyle` off
                    // the trait collection, so the whole palette resolves light
                    // for these screens without any of them knowing about it.
                    // It is scoped to this branch: finishing intake hands the
                    // user back to the system setting.
                    .preferredColorScheme(.light)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: model.hasCompletedOnboarding)
        .onAppear(perform: seedHistoryIfAsked)
        .fullScreenCover(item: $workoutRequest) { request in
            WorkoutView(
                exercise: request.exercise,
                target: request.target,
                trigger: request.trigger
            )
        }
        .onAppear(perform: bootstrap)
        .overlay {
            if model.showWelcome {
                WelcomeCelebration {
                    withAnimation(.easeInOut(duration: 0.35)) { model.showWelcome = false }
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: model.showWelcome)
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

            // Only for people who chose walking. A tab that is present but empty
            // is a permanent advertisement for a feature somebody declined.
            if model.profile.exercises.contains(.steps) {
                NavigationStack {
                    StepsView()
                        .navigationTitle("Steps")
                }
                .tabItem { Label("Steps", systemImage: "figure.walk") }
                .tag(3)
            }

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

        #if DEBUG
        // `-RansomWelcome 1` shows the post-paywall welcome on launch, so it can
        // be looked at without buying the subscription again.
        if UserDefaults.standard.bool(forKey: "RansomWelcome") { model.showWelcome = true }
        #endif

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
        // A day off asked for last week may have begun while the app was closed.
        model.settleSchedule()
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
