import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(ScreenTimeManager.self) private var screenTime
    @Environment(SubscriptionManager.self) private var store

    @State private var showAppPicker = false
    @State private var showPaywall = false
    @State private var showResetConfirm = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                subscriptionCard
                difficultyCard
                exercisesCard
                blockingCard
                aboutCard
            }
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.bottom, 28)
        }
        .reppScreenBackground()
        .sheet(isPresented: $showAppPicker) { AppPickerView() }
        .sheet(isPresented: $showPaywall) {
            PaywallView(plan: model.plan, context: .standalone, onFinish: {})
        }
        .confirmationDialog(
            "Erase everything?",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Erase all data", role: .destructive) {
                screenTime.disableBlocking()
                model.resetEverything()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your profile, history and blocking settings will be removed from this device.")
        }
    }

    // MARK: - Cards

    private var subscriptionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                RexImage(pose: .flex, size: 66, isAlive: false)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.isSubscribed || model.isSubscribed ? "Repp Pro" : "Repp Free")
                        .font(ReppFont.headline(17))
                        .foregroundStyle(Palette.ink)
                    Text(store.isSubscribed || model.isSubscribed
                         ? store.activePlanLine
                         : "Blocking needs Pro.")
                        .font(ReppFont.body(13))
                        .foregroundStyle(Palette.inkSoft)
                }
                Spacer(minLength: 0)
            }

            if store.isSubscribed || model.isSubscribed {
                SecondaryButton(title: "Manage subscription", icon: "creditcard") {
                    if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                        UIApplication.shared.open(url)
                    }
                }
            } else {
                PrimaryButton(title: "Get Repp Pro") { showPaywall = true }
            }
        }
        .reppCard()
    }

    private var difficultyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Difficulty")
                .font(ReppFont.headline(16))
                .foregroundStyle(Palette.ink)

            ForEach(Intensity.allCases) { intensity in
                ChoiceCard(
                    title: intensity.title,
                    subtitle: intensity.blurb,
                    icon: intensity.symbol,
                    isSelected: model.profile.intensity == intensity
                ) {
                    model.profile.intensity = intensity
                }
            }

            HStack {
                Text("Current price")
                    .font(ReppFont.body(14))
                    .foregroundStyle(Palette.inkSoft)
                Spacer()
                Text("\(model.plan.repsPerUnlock) \(model.plan.exercise.shortTitle.lowercased()) → \(model.plan.minutesPerUnlock) min")
                    .font(ReppFont.caption(13))
                    .foregroundStyle(Palette.green)
            }
            .padding(.top, 2)
        }
        .reppCard()
    }

    private var exercisesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Movements")
                .font(ReppFont.headline(16))
                .foregroundStyle(Palette.ink)

            ForEach(Exercise.allCases) { exercise in
                ChoiceCard(
                    title: exercise.title,
                    icon: exercise.symbol,
                    isSelected: model.profile.exercises.contains(exercise),
                    allowsMultiple: true
                ) {
                    if model.profile.exercises.contains(exercise) {
                        if model.profile.exercises.count > 1 {
                            model.profile.exercises.remove(exercise)
                        }
                    } else {
                        model.profile.exercises.insert(exercise)
                    }
                }
            }
        }
        .reppCard()
    }

    private var blockingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Blocking")
                .font(ReppFont.headline(16))
                .foregroundStyle(Palette.ink)

            row(
                title: "Guarded apps",
                detail: screenTime.hasSelection ? "\(screenTime.blockedCount) selected" : "None yet"
            ) {
                showAppPicker = true
            }

            row(
                title: "Screen Time access",
                detail: screenTime.isAuthorized ? "Granted" : "Not granted"
            ) {
                Task {
                    await screenTime.requestAuthorization()
                    screenTime.startMonitoring()
                }
            }

            if screenTime.isCurrentlyUnlocked {
                SecondaryButton(title: "Lock everything now", icon: "lock.fill") {
                    screenTime.endEarnedTimeNow()
                }
            }
        }
        .reppCard()
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("About")
                .font(ReppFont.headline(16))
                .foregroundStyle(Palette.ink)

            HStack {
                Text("Version")
                    .font(ReppFont.body(14))
                    .foregroundStyle(Palette.inkSoft)
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    .font(ReppFont.caption(13))
                    .foregroundStyle(Palette.ink)
            }

            Text("Repp keeps everything on your device. No account, no analytics, no upload.")
                .font(ReppFont.body(13))
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                Haptics.warning()
                showResetConfirm = true
            } label: {
                Text("Erase all data")
                    .font(ReppFont.caption(14))
                    .foregroundStyle(Palette.danger)
            }
            .padding(.top, 2)
        }
        .reppCard()
    }

    private func row(title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack {
                Text(title)
                    .font(ReppFont.body(15))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text(detail)
                    .font(ReppFont.caption(13))
                    .foregroundStyle(Palette.inkSoft)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Palette.inkFaint)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
