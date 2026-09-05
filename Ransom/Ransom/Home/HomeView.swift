import UserNotifications
import ManagedSettings
import SwiftUI

/// The home screen answers two questions in one glance: how is today going, and
/// what's the next thing to do about it?
///
/// Today is measured in screen time, not reps. The screen-time card sits first
/// because it's the thing the user is actually here to change; the unlock card
/// follows because it's the action. The order flips only when there's a set to
/// run right now (a shield tap, or time already running), since then the action
/// is the reason they opened the app.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(ScreenTimeManager.self) private var screenTime
    @State private var steps = StepTracker()
    /// Nil until the user picks, so the default follows the balance rather than
    /// sticking at a number that may no longer be affordable.
    @State private var spendAmount: Int?
    @State private var showStepsInfo = false

    @Binding var workoutRequest: WorkoutRequest?

    @State private var showAppPicker = false
    /// How many sets' worth to do in one go, 1 to 3. A bigger appetite than the
    /// plan's single set is a good sign and there is no reason to make somebody
    /// return to this screen three times for it.
    @State private var earnSets = 1
    /// The movement the Earn button will start. Nil follows the plan; tapping the
    /// other one in the swap row sets it, and only that.
    @State private var chosenExercise: Exercise?

    private var plan: RansomPlan { model.plan }

    /// What the Earn button is currently pointed at.
    private var activeExercise: Exercise { chosenExercise ?? plan.exercise }

    /// Three is the ceiling. Past about forty-five minutes the thing being bought
    /// stops being a break and starts being the evening, which is the habit this
    /// app exists to interrupt rather than to sell in bulk.
    private static let maximumSets = 3

    private var earnReps: Int { scaledTarget(for: activeExercise) * earnSets }
    private var earnMinutes: Int { plan.minutesPerUnlock * earnSets }

    /// A set is the reason they're here, so the unlock card leads.
    private var unlockLeads: Bool {
        model.pendingUnlockAppName != nil || screenTime.isCurrentlyUnlocked
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                header

                RexScene(pose: rexPose, line: rexLine, size: 118)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)

                // The balance is what you open the app to check, so it leads —
                // except while time is actually running, when the countdown is the
                // only thing anyone is looking at.
                if screenTime.isCurrentlyUnlocked {
                    // The countdown leads, but earning stays on the screen. Time
                    // running is the moment someone is most aware of how little
                    // they have left, and hiding the way to get more turns a
                    // deliberate top-up into a wait.
                    activeUnlockCard
                    bankCard
                    earnCard
                } else {
                    bankCard
                    earnCard
                }

                spendCard

                ReachesCard()

                RulesSection()

                todayCard

                if !screenTime.isAuthorized {
                    permissionCard
                } else if !screenTime.hasSelection {
                    chooseAppsCard
                } else {
                    blockedAppsCard
                }

                weekCard
            }
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.bottom, 28)
        }
        .debugScrollAnchor()
        .ransomScreenBackground()
        // Earned time can end two ways: the user locking it back up, or it simply
        // running out. Neither goes through SwiftUI, so the mirror is refreshed on
        // a tick and the card flips back on its own either way.
        .task {
            // Steps taken while the app was closed are banked on arrival, which is
            // the whole appeal of the walking challenge: you open the app and the
            // minutes are already there.
            await steps.syncToday(plan: plan)
            steps.startLiveUpdates()
            while !Task.isCancelled {
                screenTime.syncUnlockState()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .onDisappear { steps.stopLiveUpdates() }
        .alert("Steps count themselves", isPresented: $showStepsInfo) {
            Button("Got it", role: .cancel) {}
        } message: {
            // Honest about the one limit: iOS doesn't keep this app running, so
            // steps taken while it's closed are banked the next time it opens.
            Text("Your phone is already counting. Every \(plan.stepsPerMinute) steps adds a minute to your bank, live while the app is open and caught up the moment you come back to it. Nothing to start, nothing to tap.")
        }
        .sheet(isPresented: $showAppPicker) {
            AppPickerView()
        }
        .onAppear(perform: debugStartWorkout)
    }

    /// `-RansomWorkout 1` opens the set screen straight away. There's no UI-test
    /// target to tap the button, and the simulator can't otherwise reach the
    /// screen. Debug builds only.
    private func debugStartWorkout() {
        #if DEBUG
        guard UserDefaults.standard.bool(forKey: "RansomWorkout"), workoutRequest == nil else { return }
        workoutRequest = WorkoutRequest(exercise: plan.exercise, target: model.repsPerSet, trigger: nil)
        #endif
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting)
                    .font(RansomFont.caption(13))
                    .foregroundStyle(Palette.inkSoft)
                Text(headline)
                    .font(RansomFont.title(24))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 8)
            if model.streak > 0 {
                Pill(
                    text: "\(model.streak) day\(model.streak == 1 ? "" : "s")",
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

    /// Short enough to share a line with the streak pill, whatever the name.
    private var headline: String {
        let name = model.profile.firstName
        let named = { (line: String) in name.isEmpty ? line : "\(line), \(name)" }
        if screenTime.isCurrentlyUnlocked { return named("Enjoy it") }
        if model.isOverAllowance { return named("Fresh start tomorrow") }
        return named("Let's move")
    }

    /// Never `.blocked` here. Arms-out Rex is the shield's job; on the home
    /// screen he's the friend who helps you get back on track, even on a day
    /// that went over. Cheering is the completion screen's beat; while the time
    /// runs he's off duty, which is a different picture.
    private var rexPose: RexPose {
        screenTime.isCurrentlyUnlocked ? .relax : .coach
    }

    private var rexLine: String {
        let move = plan.exercise.title.lowercased()
        if let pending = model.pendingUnlockAppName {
            return "\(pending)? Sure. \(model.repsPerSet) \(move) and it's all yours."
        }
        if screenTime.isCurrentlyUnlocked {
            return "You earned it. Go enjoy. I'll give you a nudge when time's up."
        }
        if !screenTime.hasSelection {
            return "Pick a few apps and I'll keep an eye on them for you. You can pick them in Settings any time."
        }
        if model.isOverAllowance {
            return "Past today's target. It happens. Tomorrow resets, and anything you've banked carries over."
        }
        if model.todayMinutesUnlocked == 0 {
            return "Nothing used yet today. Best possible start."
        }
        return "You've got \(model.todayMinutesLeft) minutes left today. Plenty of room."
    }

    // MARK: - Today

    /// Today measured the way the user actually wants their day to go: minutes
    /// *not* spent in the apps.
    ///
    /// This used to count reps toward a daily rep goal, which quietly sold the
    /// wrong thing: a big rep number means a lot of unlocks were bought, and a
    /// user who hit it had scrolled all day. Reps are the price, so they stay on
    /// the card as a receipt line, but the goal is the time.
    private var todayCard: some View {
        let over = model.isOverAllowance
        let tint = over ? Palette.danger : Palette.brand

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                // Named for what it actually counts. Screen Time reports usage
                // of the apps Ransom guards and nothing else, so calling it
                // "today's screen time" claimed a whole-device figure the app has
                // no way of getting.
                Text("Time in your apps")
                    .font(RansomFont.headline(16))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text("Goal \(model.todayAllowance) min")
                    .font(RansomFont.caption(13))
                    .foregroundStyle(Palette.inkSoft)
            }

            HStack(spacing: 18) {
                ZStack {
                    ProgressRing(
                        progress: model.todayScreenUsage,
                        lineWidth: 11,
                        tint: tint,
                        showsEmptyDot: false
                    )
                    .frame(width: 96, height: 96)

                    VStack(spacing: -2) {
                        Text("\(over ? model.todayScreenMinutes - model.todayAllowance : model.todayMinutesLeft)")
                            .font(RansomFont.counter(28))
                            .foregroundStyle(over ? Palette.danger : Palette.ink)
                            .contentTransition(.numericText())
                        Text(over ? "min over" : "min left")
                            .font(RansomFont.caption(10))
                            .foregroundStyle(Palette.inkSoft)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(screenTimeLine)
                        .font(RansomFont.body(14))
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    // Against the benchmark, not against zero. "40 min used" means
                    // nothing until you know it used to be two hours.
                    Text(savingLine)
                        .font(RansomFont.caption(12))
                        .foregroundStyle(model.todaySavedMinutes >= 0 ? Palette.green : Palette.danger)
                        .fixedSize(horizontal: false, vertical: true)

                    if model.todayReps > 0 {
                        Label("\(model.todayReps) reps done today", systemImage: "checkmark.circle.fill")
                            .font(RansomFont.caption(12))
                            .foregroundStyle(Palette.inkFaint)
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .ransomCard()
    }

    private var screenTimeLine: String {
        let used = model.todayScreenMinutes
        // Measured usage arrives as rungs on a ladder - Screen Time says "they
        // have passed 45 minutes", never "they are at 52" - so it is quoted as a
        // floor. Writing the rung as an exact figure would be inventing precision
        // iOS never offered.
        let figure = model.isScreenTimeMeasured && used > 0 ? "\(used)+" : "\(used)"
        if model.isOverAllowance {
            return "\(figure) min used. Past today's goal, but every unlock still needs a set."
        }
        if used == 0 {
            return model.isScreenTimeMeasured
                ? "Under 15 min so far today."
                : "0 min used so far."
        }
        return "\(figure) of \(model.todayAllowance) min used."
    }

    private var savingLine: String {
        let saved = model.todaySavedMinutes
        // Nothing spent isn't a saving yet, it's a day that hasn't happened. Saying
        // "90 minutes saved" at breakfast spends the credit before it's earned.
        guard model.todayScreenMinutes > 0 else {
            return "Your old average was \(model.baselineMinutes) min a day"
        }
        if saved > 0 { return "\(saved) min under your old average" }
        if saved == 0 { return "Level with your old average" }
        return "\(-saved) min over your old average"
    }

    // MARK: - Unlock

    private var earnCard: some View {
        VStack(spacing: 14) {
            Text(plan.exercise.isPassive ? "Earning as you walk"
                 : (earnSets == 1 ? "One set" : "\(earnSets) sets"))
                .font(RansomFont.headline(16))
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 0) {
                VStack(spacing: 2) {
                    Text("\(earnReps)")
                        .font(RansomFont.display(40))
                        .foregroundStyle(Palette.ink)
                        .contentTransition(.numericText(value: Double(earnReps)))
                    Text(activeExercise.title.lowercased())
                        .font(RansomFont.caption(12))
                        .foregroundStyle(Palette.inkSoft)
                }
                .frame(maxWidth: .infinity)

                Image(systemName: "arrow.right")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Palette.brand)
                    .frame(width: 36)

                VStack(spacing: 2) {
                    Text("\(earnMinutes) min")
                        .font(RansomFont.display(40))
                        .foregroundStyle(Palette.brand)
                        .contentTransition(.numericText(value: Double(earnMinutes)))
                    Text("of your apps")
                        .font(RansomFont.caption(12))
                        .foregroundStyle(Palette.inkSoft)
                }
                .frame(maxWidth: .infinity)
            }

            if !plan.exercise.isPassive { setsSlider }

            // Spending comes first when there's anything to spend. Someone with a
            // full bank who is made to do another set has been told their earlier
            // effort didn't count for anything.
            // Steps have no set to start: the phone counts them whether or not
            // this app is open, so a button promising to "earn" them would be
            // offering to do something already happening. It explains itself
            // instead.
            if plan.exercise.isPassive {
                Button {
                    Haptics.tap()
                    showStepsInfo = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "figure.walk")
                        Text("\(steps.stepsToday.formatted()) steps today")
                            .font(RansomFont.headline(16))
                        Image(systemName: "info.circle")
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.inkFaint)
                    }
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                            .fill(Palette.brandSoft)
                    )
                }
                .pressable(scale: 0.985)
            } else {
                // The icon names the thing you're about to do. A generic bolt said
                // nothing, and it's the exercise's own symbol so it follows whichever
                // movement the user picked rather than assuming push-ups.
                PrimaryButton(title: "Earn \(earnMinutes) minutes", icon: activeExercise.symbol) {
                    workoutRequest = WorkoutRequest(
                        exercise: activeExercise,
                        target: earnReps,
                        trigger: model.pendingUnlockAppName
                    )
                }
            }

            if model.profile.exercises.count > 1 {
                Text("Or swap the move")
                    .font(RansomFont.caption(12))
                    .foregroundStyle(Palette.inkFaint)
                    .padding(.top, -4)
                swapRow
            }
        }
        .ransomCard()
    }

    /// Lets the user do a different movement without leaving home.
    private var swapRow: some View {
        HStack(spacing: 8) {
            ForEach(Array(model.profile.exercises).sorted { $0.effortWeight > $1.effortWeight }) { exercise in
                Button {
                    Haptics.select()
                    // Choose, then go. Tapping a movement used to drop the user
                    // straight into that camera, so picking squats to see what
                    // squats would cost started a set of them - a control that
                    // answers a question by committing you to it.
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        chosenExercise = exercise
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: exercise.symbol)
                            .font(.system(size: 15, weight: .semibold))
                        Text("\(scaledTarget(for: exercise) * earnSets) \(exercise.shortTitle.lowercased())")
                            .font(RansomFont.caption(12))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(exercise == activeExercise ? Palette.onBrand : Palette.inkSoft)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(exercise == activeExercise ? Palette.brand : Palette.surfaceAlt)
                    )
                }
                .pressable(scale: 0.95)
            }
        }
    }

    /// Keeps every movement worth the same amount of scroll time.
    ///
    /// Deferred to the plan rather than repeated here. The same conversion used
    /// to live in two places and they disagreed, which is how a standard squat
    /// set came to pay sixteen minutes on a fifteen-minute plan.
    private func scaledTarget(for exercise: Exercise) -> Int {
        plan.repsRequired(for: exercise)
    }

    /// How many sets to do in one go.
    ///
    /// A slider rather than a stepper because the interesting number is the one
    /// on the right - people decide how long they want, not how many push-ups -
    /// and dragging keeps both figures moving together under the thumb.
    private var setsSlider: some View {
        VStack(spacing: 6) {
            Slider(
                value: Binding(
                    get: { Double(earnSets) },
                    set: { raw in
                        let value = max(1, min(Self.maximumSets, Int(raw.rounded())))
                        // Only on a real step change, or one drag fires a tap per
                        // frame and the phone buzzes like a fault.
                        guard value != earnSets else { return }
                        Haptics.tick()
                        withAnimation(.snappy(duration: 0.18)) { earnSets = value }
                    }
                ),
                in: 1...Double(Self.maximumSets),
                step: 1
            )
            .tint(Palette.brand)

            HStack {
                Text("1 set")
                Spacer()
                Text("\(Self.maximumSets) sets")
            }
            .font(RansomFont.caption(11))
            .foregroundStyle(Palette.inkFaint)
        }
        .padding(.horizontal, 2)
    }

    private var activeUnlockCard: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let remaining = screenTime.remainingUnlock

            VStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "lock.open.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text("UNLOCKED")
                        .tracking(1.3)
                }
                .font(RansomFont.caption(11))
                .foregroundStyle(Palette.green)

                Text(timeString(remaining))
                    .font(RansomFont.counter(52))
                    .foregroundStyle(Palette.green)

                Text("left on your apps")
                    .font(RansomFont.caption(12))
                    .foregroundStyle(Palette.inkSoft)
                    .padding(.top, -6)

                SecondaryButton(title: "Done early? Lock them", icon: "lock.fill") {
                    screenTime.endEarnedTimeNow()
                    Haptics.success()
                }
            }
            .padding(.vertical, 6)
            .ransomCard()
        }
    }

    private func timeString(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - Blocking state

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("One more step", systemImage: "hand.raised.fill")
                .font(RansomFont.headline(16))
                .foregroundStyle(Palette.ink)

            Text("Rex uses Apple's Screen Time to keep your apps closed until you've done a set. Nothing leaves your phone.")
                .font(RansomFont.body(14))
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)

            PrimaryButton(title: "Turn on blocking") {
                Task {
                    await screenTime.requestAuthorization()
                    screenTime.startMonitoring()
                }
            }
        }
        .ransomCard()
    }


    private var chooseAppsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Pick your apps", systemImage: "square.grid.2x2.fill")
                .font(RansomFont.headline(16))
                .foregroundStyle(Palette.ink)

            Text("Which apps should take a set to open?")
                .font(RansomFont.body(14))
                .foregroundStyle(Palette.inkSoft)

            PrimaryButton(title: "Choose apps") { showAppPicker = true }
        }
        .ransomCard()
    }

    private var blockedAppsCard: some View {
        Button {
            Haptics.tap()
            showAppPicker = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: screenTime.isCurrentlyUnlocked ? "lock.open.fill" : "lock.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(screenTime.isCurrentlyUnlocked ? Palette.green : Palette.brand)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(screenTime.isCurrentlyUnlocked ? Palette.greenSoft : Palette.brandSoft))

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(screenTime.blockedCount) app\(screenTime.blockedCount == 1 ? "" : "s") with Rex")
                        .font(RansomFont.headline(16))
                        .foregroundStyle(Palette.ink)
                    Text(screenTime.isCurrentlyUnlocked ? "Open right now · tap to change" : "Tap to add or remove apps")
                        .font(RansomFont.body(13))
                        .foregroundStyle(Palette.inkSoft)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Palette.inkFaint)
            }
            .ransomCard()
        }
        .pressable(scale: 0.985)
    }

    /// Spending, kept apart from earning on purpose.
    ///
    /// The two were one card, where having a balance replaced the earn button with
    /// a spend button — so the moment a set paid off, the app stopped offering the
    /// thing that had just worked. Separating them means earning is always on
    /// screen and always the loud button, and spending is a deliberate second act
    /// rather than the default next step.
    @ViewBuilder
    private var spendCard: some View {
        if model.bankedMinutes > 0 && !screenTime.isCurrentlyUnlocked {
            VStack(spacing: 12) {
                HStack {
                    Text("Spend from your bank")
                        .font(RansomFont.headline(16))
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    Text("\(model.bankedMinutes) available")
                        .font(RansomFont.caption(12))
                        .foregroundStyle(Palette.inkSoft)
                }

                spendPicker

                SecondaryButton(title: "Spend \(spendChoice) minutes", icon: "hourglass") {
                    Haptics.success()
                    let spent = model.spendFromBank(minutes: spendChoice)
                    if spent > 0 { screenTime.grantEarnedTime(minutes: spent) }
                    spendAmount = nil
                }
            }
            .ransomCard()
        }
    }

    /// How much to take out. Defaults to one set's worth — the amount they just
    /// earned — so the common case is a single tap and the choice is there for
    /// anyone who wants it.
    private var spendChoice: Int {
        let options = plan.spendOptions(banked: model.bankedMinutes)
        guard let amount = spendAmount, options.contains(amount) else {
            return options.first ?? model.bankedMinutes
        }
        return amount
    }

    private var spendPicker: some View {
        let options = plan.spendOptions(banked: model.bankedMinutes)

        return HStack(spacing: 8) {
            ForEach(options, id: \.self) { minutes in
                let isChosen = minutes == spendChoice
                Button {
                    Haptics.select()
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.8)) {
                        spendAmount = minutes
                    }
                } label: {
                    VStack(spacing: 1) {
                        Text("\(minutes)m")
                            .font(RansomFont.headline(16))
                        // Only the option that empties the bank gets labelled, so
                        // the label means something when it appears.
                        if minutes == model.bankedMinutes && options.count > 1 {
                            Text("all")
                                .font(RansomFont.caption(10))
                        }
                    }
                    .foregroundStyle(isChosen ? .white : Palette.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isChosen ? Palette.brand : Palette.surfaceAlt)
                    )
                }
                .pressable(scale: 0.96)
            }
        }
        .onAppear {
            if spendAmount == nil { spendAmount = options.first }
        }
        .onChange(of: model.bankedMinutes) { _, _ in
            // Spending 30 of 47 leaves 17, and a selection of 30 that no longer
            // fits would otherwise sit there looking affordable.
            let current = plan.spendOptions(banked: model.bankedMinutes)
            if let amount = spendAmount, !current.contains(amount) {
                spendAmount = current.first
            }
        }
    }

    // MARK: - The bank

    /// The balance. First on the screen because it's the first thing anyone opens
    /// the app to find out.
    private var bankCard: some View {
        VStack(spacing: 14) {
            VStack(spacing: 0) {
                Text("\(model.bankedMinutes)")
                    .font(RansomFont.counter(72))
                    .foregroundStyle(model.bankedMinutes > 0 ? Palette.brand : Palette.inkFaint)
                    .contentTransition(.numericText(value: Double(model.bankedMinutes)))
                    .animation(.snappy(duration: 0.3), value: model.bankedMinutes)

                Text(model.bankedMinutes == 1 ? "minute banked" : "minutes banked")
                    .font(RansomFont.headline(15))
                    .foregroundStyle(Palette.inkSoft)
            }

            Divider().overlay(Palette.hairline)

            // The rate and the day's earnings, so the balance is never a number
            // that just appeared. Steps only when they're the chosen movement —
            // otherwise it's a stat about a challenge they didn't take.
            HStack(spacing: 0) {
                // Earned, not the exchange rate: the card below already states the
                // rate, and at 10 push-ups for 15 minutes the rate rounds to
                // "1 reps per minute", which is both wrong and ungrammatical.
                bankStat(value: "\(model.todayMinutesEarned)", label: "earned today")

                if plan.exercise.isPassive {
                    Divider().frame(height: 30).overlay(Palette.hairline)
                    bankStat(value: steps.stepsToday.formatted(), label: "steps today")
                } else if model.todayReps > 0 {
                    Divider().frame(height: 30).overlay(Palette.hairline)
                    bankStat(value: "\(model.todayReps)", label: "\(plan.exercise.unitLabel) today")
                }
            }
        }
        .ransomCard()
    }

    private func bankStat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(RansomFont.headline(19))
                .foregroundStyle(Palette.ink)
            Text(label)
                .font(RansomFont.caption(11))
                .foregroundStyle(Palette.inkSoft)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Week

    private var weekCard: some View {
        let weekReps = model.weekBars.reduce(0) { $0 + Int($1.value) }
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("This week")
                    .font(RansomFont.headline(16))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text(weekReps == 0 ? "First set fills this in" : "\(weekReps) reps")
                    .font(RansomFont.caption(13))
                    .foregroundStyle(Palette.inkSoft)
            }
            WeekBars(values: model.weekBars)
        }
        .ransomCard()
    }
}

/// A request to run a set, raised from anywhere in the app.
struct WorkoutRequest: Identifiable, Equatable {
    let id = UUID()
    var exercise: Exercise
    var target: Int
    var trigger: String?
}
