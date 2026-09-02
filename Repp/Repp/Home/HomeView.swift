import SwiftUI

/// The home screen answers one question in one glance: am I locked or unlocked,
/// and what do I do about it?
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(ScreenTimeManager.self) private var screenTime

    @Binding var workoutRequest: WorkoutRequest?

    @State private var showAppPicker = false

    private var plan: ReppPlan { model.plan }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                header

                RexScene(pose: rexPose, line: rexLine, size: 118)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)

                unlockCard

                if !screenTime.isAuthorized {
                    permissionCard
                } else if !screenTime.hasSelection {
                    chooseAppsCard
                } else {
                    blockedAppsCard
                }

                dailyGoalCard

                tariffCard

                weekCard
            }
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.bottom, 28)
        }
        .reppScreenBackground()
        .sheet(isPresented: $showAppPicker) {
            AppPickerView()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting)
                    .font(ReppFont.caption(13))
                    .foregroundStyle(Palette.inkSoft)
                Text(model.profile.firstName.isEmpty ? "Ready to pay up?" : "\(model.profile.firstName), ready to pay up?")
                    .font(ReppFont.title(24))
                    .foregroundStyle(Palette.ink)
            }
            Spacer(minLength: 8)
            if model.streak > 0 {
                Pill(
                    text: "\(model.streak)",
                    icon: "flame.fill",
                    tint: Palette.flame,
                    background: Palette.flameSoft
                )
            }
        }
        .padding(.top, 4)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12:  return "Good morning"
        case 12..<18: return "Good afternoon"
        default:      return "Good evening"
        }
    }

    private var rexPose: RexPose {
        if screenTime.isCurrentlyUnlocked { return .cheer }
        if model.todayReps == 0 { return .blocked }
        return .coach
    }

    private var rexLine: String {
        if let pending = model.pendingUnlockAppName {
            return "You tried to open \(pending). \(model.quote.reps) \(plan.exercise.title.lowercased()) and I'll step aside."
        }
        if screenTime.isCurrentlyUnlocked {
            return "You paid. Go enjoy it — I'll be here when the time's up."
        }
        if !screenTime.hasSelection {
            return "Pick the apps you want me guarding and we're in business."
        }
        if model.todayReps == 0 {
            return "Zero reps today. The door stays shut until that changes."
        }
        return "\(model.todayReps) down. \(max(0, plan.dailyRepGoal - model.todayReps)) to hit today's goal."
    }

    // MARK: - Unlock

    @ViewBuilder
    private var unlockCard: some View {
        if screenTime.isCurrentlyUnlocked {
            activeUnlockCard
        } else {
            earnCard
        }
    }

    private var earnCard: some View {
        let quote = model.quote

        return VStack(spacing: 14) {
            if let explanation = quote.explanation {
                HStack(spacing: 6) {
                    Image(systemName: quote.isAtCap ? "exclamationmark.triangle.fill" : "arrow.up.right")
                        .font(.system(size: 11, weight: .bold))
                    Text(explanation)
                        .font(ReppFont.caption(12))
                }
                .foregroundStyle(Palette.flame)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 0) {
                VStack(spacing: 2) {
                    Text("\(quote.reps)")
                        .font(ReppFont.display(40))
                        .foregroundStyle(quote.isSurcharged ? Palette.flame : Palette.ink)
                    Text(plan.exercise.title.lowercased())
                        .font(ReppFont.caption(12))
                        .foregroundStyle(Palette.inkSoft)
                }
                .frame(maxWidth: .infinity)

                Image(systemName: "arrow.right")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Palette.green)
                    .frame(width: 36)

                VStack(spacing: 2) {
                    Text("\(plan.minutesPerUnlock)m")
                        .font(ReppFont.display(40))
                        .foregroundStyle(Palette.green)
                    Text("of scroll")
                        .font(ReppFont.caption(12))
                        .foregroundStyle(Palette.inkSoft)
                }
                .frame(maxWidth: .infinity)
            }

            PrimaryButton(title: "Earn my time", icon: "bolt.fill") {
                workoutRequest = WorkoutRequest(
                    exercise: plan.exercise,
                    target: quote.reps,
                    trigger: model.pendingUnlockAppName
                )
            }

            if model.profile.exercises.count > 1 {
                swapRow
            }
        }
        .reppCard()
    }

    /// Lets the user pay in a different currency without leaving home.
    private var swapRow: some View {
        HStack(spacing: 8) {
            ForEach(Array(model.profile.exercises).sorted { $0.effortWeight > $1.effortWeight }) { exercise in
                Button {
                    Haptics.select()
                    let target = scaledTarget(for: exercise)
                    workoutRequest = WorkoutRequest(
                        exercise: exercise,
                        target: target,
                        trigger: model.pendingUnlockAppName
                    )
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: exercise.symbol)
                            .font(.system(size: 15, weight: .semibold))
                        Text("\(scaledTarget(for: exercise))")
                            .font(ReppFont.caption(12))
                    }
                    .foregroundStyle(Palette.inkSoft)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Palette.surfaceAlt)
                    )
                }
                .pressable(scale: 0.95)
            }
        }
    }

    /// Keeps every movement worth the same amount of scroll time.
    private func scaledTarget(for exercise: Exercise) -> Int {
        // Priced from the current quote, not the base rate — otherwise switching
        // movement would be a way to dodge the tariff.
        let equivalents = Double(model.quote.reps) * plan.exercise.effortWeight
        return max(3, Int((equivalents / exercise.effortWeight).rounded()))
    }

    private var activeUnlockCard: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let remaining = screenTime.remainingUnlock

            VStack(spacing: 12) {
                Text("SCROLL TIME REMAINING")
                    .font(ReppFont.caption(11))
                    .tracking(1.3)
                    .foregroundStyle(Palette.inkSoft)

                Text(timeString(remaining))
                    .font(ReppFont.counter(52))
                    .foregroundStyle(Palette.green)

                SecondaryButton(title: "Lock it back up", icon: "lock.fill") {
                    screenTime.endEarnedTimeNow()
                    Haptics.warning()
                }
            }
            .padding(.vertical, 6)
            .reppCard()
        }
    }

    private func timeString(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - Blocking state

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Screen Time access needed", systemImage: "exclamationmark.shield.fill")
                .font(ReppFont.headline(16))
                .foregroundStyle(Palette.ink)

            Text("Repp uses Apple's Screen Time to hold the door. Nothing leaves your device.")
                .font(ReppFont.body(14))
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)

            PrimaryButton(title: "Enable blocking") {
                Task {
                    await screenTime.requestAuthorization()
                    screenTime.startMonitoring()
                }
            }
        }
        .reppCard()
    }

    private var chooseAppsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("No apps guarded yet", systemImage: "square.grid.2x2.fill")
                .font(ReppFont.headline(16))
                .foregroundStyle(Palette.ink)

            Text("Choose what Rex should stand in front of.")
                .font(ReppFont.body(14))
                .foregroundStyle(Palette.inkSoft)

            PrimaryButton(title: "Choose apps") { showAppPicker = true }
        }
        .reppCard()
    }

    private var blockedAppsCard: some View {
        Button {
            Haptics.tap()
            showAppPicker = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Palette.green)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(Palette.greenSoft))

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(screenTime.blockedCount) guarded")
                        .font(ReppFont.headline(16))
                        .foregroundStyle(Palette.ink)
                    Text(screenTime.isCurrentlyUnlocked ? "Open right now" : "Locked until you pay")
                        .font(ReppFont.body(13))
                        .foregroundStyle(Palette.inkSoft)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Palette.inkFaint)
            }
            .reppCard()
        }
        .pressable(scale: 0.985)
    }

    // MARK: - Progress

    private var dailyGoalCard: some View {
        HStack(spacing: 18) {
            ZStack {
                ProgressRing(progress: model.todayProgress, lineWidth: 11)
                    .frame(width: 88, height: 88)
                VStack(spacing: -2) {
                    Text("\(model.todayReps)")
                        .font(ReppFont.counter(24))
                        .foregroundStyle(Palette.ink)
                    Text("reps")
                        .font(ReppFont.caption(10))
                        .foregroundStyle(Palette.inkSoft)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Today's goal")
                    .font(ReppFont.headline(16))
                    .foregroundStyle(Palette.ink)
                Text(model.todayReps >= plan.dailyRepGoal
                     ? "Hit. Everything past this is profit."
                     : "\(plan.dailyRepGoal - model.todayReps) to go out of \(plan.dailyRepGoal).")
                    .font(ReppFont.body(14))
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .reppCard()
    }

    /// The whole price ladder, with today's position marked. Predictability is what
    /// separates a tariff people accept from one that feels like a punishment.
    private var tariffCard: some View {
        let schedule = model.tariffSchedule
        let current = model.quote.unlockNumber

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Today's rates")
                    .font(ReppFont.headline(16))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text("\(model.unlocksToday) used")
                    .font(ReppFont.caption(13))
                    .foregroundStyle(Palette.inkSoft)
            }

            VStack(spacing: 8) {
                ForEach(Array(schedule.enumerated()), id: \.offset) { index, tier in
                    let upper = index + 1 < schedule.count ? schedule[index + 1].unlock - 1 : nil
                    let isNow = current >= tier.unlock && (upper.map { current <= $0 } ?? true)

                    HStack(spacing: 10) {
                        Text(rangeLabel(from: tier.unlock, to: upper))
                            .font(ReppFont.caption(13))
                            .foregroundStyle(isNow ? Palette.ink : Palette.inkSoft)
                            .frame(width: 82, alignment: .leading)

                        Capsule()
                            .fill(isNow ? Palette.flame : Palette.hairline)
                            .frame(height: 4)

                        Text("\(tier.reps)")
                            .font(ReppFont.caption(14))
                            .foregroundStyle(isNow ? Palette.flame : Palette.inkSoft)
                            .frame(width: 30, alignment: .trailing)
                    }
                }
            }

            Text("Leave the apps alone for three hours and you drop a tier.")
                .font(ReppFont.caption(12))
                .foregroundStyle(Palette.inkFaint)
        }
        .reppCard()
    }

    private func rangeLabel(from: Int, to upper: Int?) -> String {
        guard let upper else { return "Unlock \(from)+" }
        return from == upper ? "Unlock \(from)" : "Unlocks \(from)–\(upper)"
    }

    private var weekCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("This week")
                    .font(ReppFont.headline(16))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text("\(model.weekBars.reduce(0) { $0 + Int($1.value) }) reps")
                    .font(ReppFont.caption(13))
                    .foregroundStyle(Palette.inkSoft)
            }
            WeekBars(values: model.weekBars)
        }
        .reppCard()
    }
}

/// A request to run a set, raised from anywhere in the app.
struct WorkoutRequest: Identifiable, Equatable {
    let id = UUID()
    var exercise: Exercise
    var target: Int
    var trigger: String?
}
