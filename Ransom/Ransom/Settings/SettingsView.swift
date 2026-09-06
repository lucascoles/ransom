import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(ScreenTimeManager.self) private var screenTime
    @Environment(SubscriptionManager.self) private var store

    @State private var showAppPicker = false
    @State private var showPaywall = false
    @State private var showResetConfirm = false
    /// A tier being considered, not yet applied. Changing difficulty is the
    /// single most consequential thing in this screen - it locks the user out of
    /// anything easier for days - so it takes a deliberate second action rather
    /// than landing on the first tap of a row.
    @State private var pendingIntensity: Intensity?
    @State private var pendingDays: Int?


    /// Spells out the consequence with the real date, because "you can't go back"
    /// means very little next to "you can't go back until the 19th".
    private var commitMessage: String {
        let days = pendingDays ?? CommitmentLength.five.days
        let until = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
        let formatted = until.formatted(.dateTime.weekday(.wide).day().month(.wide))
        guard let pendingIntensity else { return "" }
        return "\(pendingIntensity.baseReps) push-up sets for \(days) days. You can move up again whenever you like, but you won't be able to drop back until \(formatted)."
    }

    /// Reads the state of the current run in one line. When it has run out it
    /// says so plainly: the tier stays, the lock doesn't, and everything is
    /// changeable again including going easier.
    private var commitmentSummary: String {
        guard model.profile.isCommitted else {
            return "No commitment - change this freely"
        }
        let left = model.profile.commitmentDaysLeft
        return "Locked in for \(left) more day\(left == 1 ? "" : "s")"
    }

    private func applyPendingCommitment() {
        guard let pendingIntensity else { return }
        // Shortening a live run would be the same escape hatch by another name.
        if model.profile.isCommitted,
           pendingIntensity == model.profile.intensity,
           let days = pendingDays, days < (model.profile.commitmentDays ?? 0) {
            Haptics.warning()
            return
        }
        Haptics.success()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            model.profile.intensity = pendingIntensity
            model.profile.commitmentDays = pendingDays ?? CommitmentLength.five.days
            model.profile.commitmentStartedAt = Date()
            self.pendingIntensity = nil
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                subscriptionCard
                difficultyCard
                exercisesCard
                scheduleCard
                blockingCard
                aboutCard
            }
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.bottom, 28)
        }
        .debugScrollAnchor()
        .ransomScreenBackground()
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
            Text("Your profile, history and app picks will be removed from this phone.")
        }
    }

    // MARK: - Cards

    private var subscriptionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                RexImage(pose: .flex, size: 66, isAlive: false)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.isSubscribed || model.isSubscribed ? "Ransom Pro" : "Ransom Free")
                        .font(RansomFont.headline(17))
                        .foregroundStyle(Palette.ink)
                    Text(subscriptionLine)
                        .font(RansomFont.body(13))
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
                PrimaryButton(title: "Get Ransom Pro") { showPaywall = true }
            }
        }
        .ransomCard()
    }

    /// The store only knows a plan once StoreKit has loaded one. A subscription
    /// the app already trusts shouldn't read as "needs Pro" while that happens.
    private var subscriptionLine: String {
        if store.isSubscribed { return store.activePlanLine }
        if model.isSubscribed { return "Active on this phone." }
        return "Blocking needs Pro."
    }

    private var difficultyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Difficulty")
                .font(RansomFont.headline(16))
                .foregroundStyle(Palette.ink)

            // Harder is always allowed; easier is not, while the commitment runs.
            //
            // This is the one place the app deliberately refuses the user, and it
            // refuses them on purpose: the moment someone can drop to the easiest
            // setting from inside a craving, the setting they chose calmly stops
            // meaning anything at all. Locking only the downward direction keeps
            // that honest without making the app a jailer.
            if model.profile.isCommitted {
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Palette.brand)
                    Text("Locked for \(model.profile.commitmentDaysLeft) more day\(model.profile.commitmentDaysLeft == 1 ? "" : "s"). You can still make it harder.")
                        .font(RansomFont.caption(12))
                        .foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, 2)
            }

            ForEach(Intensity.allCases) { intensity in
                let isEasier = intensity.baseReps < model.profile.intensity.baseReps
                let isLocked = model.profile.isCommitted && isEasier
                let isCurrent = model.profile.intensity == intensity

                VStack(spacing: 10) {
                    ChoiceCard(
                        title: intensity.title,
                        subtitle: isLocked
                            ? "\(model.profile.setSummary(at: intensity))\nLocked until your run is up."
                            : "\(intensity.blurb)\n\(model.profile.setSummary(at: intensity))",
                        icon: isLocked ? "lock.fill" : intensity.symbol,
                        isSelected: isCurrent
                    ) {
                        guard !isLocked else {
                            Haptics.warning()
                            return
                        }
                        Haptics.select()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            // Selected, not applied. Nothing reaches the account
                            // until it has been confirmed twice - including a
                            // change to the current tier's own run.
                            if pendingIntensity == intensity {
                                pendingIntensity = nil
                            } else {
                                pendingIntensity = intensity
                                pendingDays = model.profile.commitmentDays ?? CommitmentLength.five.days
                            }
                        }
                    }
                    .opacity(isLocked ? 0.5 : 1)

                    if pendingIntensity == intensity {
                        VStack(spacing: 10) {
                            Text(isCurrent && model.profile.isCommitted ? "Extend your run" : "Locked in for")
                                .font(RansomFont.caption(12))
                                .foregroundStyle(Palette.inkSoft)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            CommitmentPicker(days: $pendingDays)

                            // What the second tap used to say, said before the
                            // hold rather than after it. The date is the whole
                            // point of confirming - "30 days" is abstract and
                            // "until Sunday 4 October" is a decision - so it has
                            // to be on screen while they are holding, not in a
                            // sheet they dismissed to get here.
                            Text(commitMessage)
                                .font(RansomFont.caption(12))
                                .foregroundStyle(Palette.inkSoft)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            HoldToCommitButton(
                                title: isCurrent && model.profile.isCommitted
                                    ? "Hold to extend" : "Hold to commit",
                                // Longer than the rule editor's second. This one
                                // cannot be undone for the length of the run, and
                                // the hold should feel like that.
                                duration: 1.6
                            ) {
                                applyPendingCommitment()
                            }
                        }
                        .padding(.horizontal, 4)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    } else if isCurrent {
                        // A summary only. Every change, including a longer run on
                        // the tier already running, goes through the same two taps.
                        HStack(spacing: 6) {
                            Image(systemName: model.profile.isCommitted ? "lock.fill" : "lock.open.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text(commitmentSummary)
                                .font(RansomFont.caption(12))
                            Spacer()
                            Text("Change")
                                .font(RansomFont.caption(12))
                                .foregroundStyle(Palette.brand)
                        }
                        .foregroundStyle(Palette.inkSoft)
                        .padding(.horizontal, 8)
                    }
                }
            }

            HStack {
                Text("Each unlock")
                    .font(RansomFont.body(14))
                    .foregroundStyle(Palette.inkSoft)
                Spacer()
                Text("\(model.plan.repsPerUnlock) \(model.plan.exercise.shortTitle.lowercased()) → \(model.plan.minutesPerUnlock) min")
                    .font(RansomFont.caption(13))
                    .foregroundStyle(Palette.brand)
            }
            .padding(.top, 2)
        }
        .ransomCard()
    }

    private var exercisesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your moves")
                .font(RansomFont.headline(16))
                .foregroundStyle(Palette.ink)

            ForEach(Exercise.selectable) { exercise in
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
        .ransomCard()
    }

    /// Which days Ransom is on duty.
    ///
    /// Guarding your apps Monday to Friday and taking Saturday back is not
    /// cheating - an app that is all or nothing is one people switch off entirely
    /// rather than turn down. But it is obviously the softest thing in here to
    /// reach for mid-craving, so it locks with everything else: harder whenever
    /// you like, easier never, until the run is over.
    private var scheduleCard: some View {
        let locked = model.profile.isCommitted

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Days on duty", systemImage: "calendar")
                    .font(RansomFont.headline(16))
                    .foregroundStyle(Palette.ink)
                Spacer()
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Palette.inkFaint)
                }
            }

            Text(locked
                 ? "Locked until your run ends. You picked these, and picking a quieter week from inside a craving is the thing this stops."
                 : "Tap a day to take it off. Rex stands down and your apps open normally.")
                .font(RansomFont.body(14))
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                ForEach(1...7, id: \.self) { weekday in
                    dayToggle(weekday, locked: locked)
                }
            }

            Text(scheduleSummary)
                .font(RansomFont.caption(12))
                .foregroundStyle(model.profile.activeDays.isEmpty ? Palette.inkFaint : Palette.brand)
        }
        .ransomCard()
    }

    private func dayToggle(_ weekday: Int, locked: Bool) -> some View {
        // Empty means every day, so an untouched picker shows all seven on and
        // reads as "always" rather than as a control nobody has filled in.
        let days = model.profile.activeDays
        let isOn = days.isEmpty || days.contains(weekday)

        return Button {
            guard !locked else {
                Haptics.warning()
                return
            }
            Haptics.tick()
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { toggleDay(weekday) }
        } label: {
            Text(Self.dayInitials[weekday - 1])
                .font(RansomFont.headline(14))
                .foregroundStyle(isOn ? Palette.onBrand : Palette.inkSoft)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(Circle().fill(isOn ? Palette.brand : Palette.surfaceAlt))
        }
        .buttonStyle(.plain)
        .opacity(locked ? 0.55 : 1)
    }

    private static let dayInitials = ["S", "M", "T", "W", "T", "F", "S"]

    private func toggleDay(_ weekday: Int) {
        var days = model.profile.activeDays.isEmpty ? Set(1...7) : model.profile.activeDays
        if days.contains(weekday) { days.remove(weekday) } else { days.insert(weekday) }
        // Every day off is just the app switched off, which Settings already has a
        // clearer way to say. The last day on stays on.
        guard !days.isEmpty else {
            Haptics.warning()
            return
        }
        model.profile.activeDays = days.count == 7 ? [] : days
        // Take effect now rather than at the next thing that happens to reconcile.
        // Turning today off and finding your apps still shielded reads as the
        // setting not working.
        screenTime.reconcile()
    }

    private var scheduleSummary: String {
        let days = model.profile.activeDays
        guard !days.isEmpty, days.count < 7 else { return "On every day." }
        let symbols = Calendar.current.shortWeekdaySymbols
        let off = (1...7).filter { !days.contains($0) }.map { symbols[$0 - 1] }
        return "Off on \(off.joined(separator: ", "))."
    }

    private var blockingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your apps")
                .font(RansomFont.headline(16))
                .foregroundStyle(Palette.ink)

            row(
                title: "Apps with Rex",
                detail: screenTime.hasSelection ? "\(screenTime.blockedCount) picked" : "None yet"
            ) {
                showAppPicker = true
            }

            row(
                title: "Screen Time access",
                detail: screenTime.isAuthorized ? "On" : "Off"
            ) {
                Task {
                    await screenTime.requestAuthorization()
                    screenTime.startMonitoring()
                }
            }

            if screenTime.isCurrentlyUnlocked {
                SecondaryButton(title: "Lock my apps now", icon: "lock.fill") {
                    screenTime.endEarnedTimeNow()
                }
            }
        }
        .ransomCard()
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("About")
                .font(RansomFont.headline(16))
                .foregroundStyle(Palette.ink)

            HStack {
                Text("Version")
                    .font(RansomFont.body(14))
                    .foregroundStyle(Palette.inkSoft)
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    .font(RansomFont.caption(13))
                    .foregroundStyle(Palette.ink)
            }

            Text("Everything stays on your phone. No account, no analytics, no upload.")
                .font(RansomFont.body(13))
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                Haptics.warning()
                showResetConfirm = true
            } label: {
                Text("Erase all data")
                    .font(RansomFont.caption(14))
                    .foregroundStyle(Palette.danger)
            }
            .padding(.top, 2)
        }
        .ransomCard()
    }

    private func row(title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack {
                Text(title)
                    .font(RansomFont.body(15))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text(detail)
                    .font(RansomFont.caption(13))
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
