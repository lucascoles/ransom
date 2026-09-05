import UserNotifications
import ManagedSettings
import SwiftUI

/// The home screen answers two questions: what's the next thing to do, and how
/// is today going? In that order.
///
/// The first screenful is for doing: a running unlock if there is one, the
/// setup step while blocking isn't on yet, then earning and spending, with the
/// balance under them. The second is for looking: the reaches Rex caught, the
/// phone's real screen time, the rules. Anything that exists on another tab
/// (the week of reps lives on Progress) or has nothing to say yet stays off.
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
    /// Where `earnSets` was when the current drag began, so the number follows
    /// the finger from wherever it started rather than jumping to it.
    @State private var setsAtDragStart: Int?

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

                // Rex, smaller than he was and without a score beside him. The
                // scoring hero is in the history if it is ever wanted again.
                RexScene(pose: rexPose, line: rexLine, size: 84)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)

                if screenTime.isCurrentlyUnlocked {
                    activeUnlockCard
                }

                // Until blocking is on, earning buys minutes of nothing, so the
                // step that makes the rest of the screen mean something comes
                // first - directly under Rex, who is asking for it. It sat three
                // screenfuls down, behind cards that assumed it was done.
                setupCard

                // Earning and spending lead; the balance sits under them. The
                // bank was on top because it is what you check, but checking it
                // is a glance and the two things you might actually do were being
                // pushed below the fold to make room for it.
                earnCard
                spendCard
                bankCard

                // The second screenful is for looking, and opens with the one
                // number nothing else on the phone can show them.
                ReachesCard()

                // Only once it can show something. Unauthorized, it was a second
                // card asking for the same permission as the setup card above.
                if screenTime.isAuthorized {
                    ScreenTimeReportCard()
                }

                RulesSection()

                if isSetUp {
                    blockedAppsCard
                }
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
        if !screenTime.isAuthorized {
            return "Switch on blocking just below and I'll start keeping an eye on your apps."
        }
        if !screenTime.hasSelection {
            return "Pick a few apps just below and I'll keep an eye on them for you."
        }
        if model.isOverAllowance {
            return "Past today's target. It happens. Tomorrow resets, and anything you've banked carries over."
        }
        if model.todayMinutesUnlocked == 0 {
            return "Nothing used yet today. Best possible start."
        }
        return "You've got \(model.todayMinutesLeft) minutes left today. Plenty of room."
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
                    HStack(spacing: 6) {
                        Text("\(earnReps)")
                            .font(RansomFont.display(40))
                            .foregroundStyle(Palette.ink)
                            .contentTransition(.numericText(value: Double(earnReps)))
                        // The only sign that the number is a control. A slider
                        // said so loudly and took a row to do it; this says so
                        // quietly and takes none.
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Palette.inkFaint)
                            .opacity(earnSets < Self.maximumSets || earnSets > 1 ? 1 : 0.55)
                    }
                    Text(activeExercise.title.lowercased())
                        .font(RansomFont.caption(12))
                        .foregroundStyle(Palette.inkSoft)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                // Tap cycles, drag scrubs. Two ways in because the drag was the
                // only one and it was losing to the page: a vertical drag inside
                // a vertical ScrollView goes to the scroll view unless it is
                // asked for at high priority, so the number needed a firm shove
                // to move at all.
                .onTapGesture { stepSets() }
                .highPriorityGesture(setsDrag)

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

    /// One tap up the ladder, wrapping back to a single set at the top.
    ///
    /// Three values is few enough that tapping through them is faster than
    /// aiming, and it is the gesture people try first on a number that looks
    /// adjustable.
    private func stepSets() {
        Haptics.tick()
        withAnimation(.snappy(duration: 0.16)) {
            earnSets = earnSets >= Self.maximumSets ? 1 : earnSets + 1
        }
    }

    /// Drag the rep count up or down to change how many sets.
    ///
    /// A slider was a whole row of chrome to move between three values, and it
    /// sat away from the numbers it changed, so the thing being adjusted and the
    /// thing being watched were in different places. Dragging the figure itself
    /// puts them in the same place and costs no layout at all.
    private var setsDrag: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                let start = setsAtDragStart ?? earnSets
                if setsAtDragStart == nil { setsAtDragStart = start }
                // Up is more, which is the direction the number grows on screen.
                // 32pt a step, tightened from 44 once the gesture stopped
                // fighting the page for the drag: the whole range is one short
                // pull rather than a haul across the card.
                let steps = Int((-value.translation.height / 32).rounded())
                let next = max(1, min(Self.maximumSets, start + steps))
                guard next != earnSets else { return }
                Haptics.tick()
                withAnimation(.snappy(duration: 0.16)) { earnSets = next }
            }
            .onEnded { _ in setsAtDragStart = nil }
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

    private var isSetUp: Bool { screenTime.isAuthorized && screenTime.hasSelection }

    /// Whichever step is missing, and nothing once both are done: the finished
    /// state is a quiet row at the bottom, not a card up here.
    @ViewBuilder
    private var setupCard: some View {
        if !screenTime.isAuthorized {
            permissionCard
        } else if !screenTime.hasSelection {
            chooseAppsCard
        }
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("One more step", systemImage: "hand.raised.fill")
                .font(RansomFont.headline(16))
                .foregroundStyle(Palette.ink)

            Text("Rex uses Apple's Screen Time to keep your apps closed until you've done a set. Nothing leaves your phone.")
                .font(RansomFont.body(14))
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)

            SecondaryButton(title: "Turn on blocking", icon: "lock.fill") {
                Task {
                    await screenTime.requestAuthorization()
                    screenTime.startMonitoring()
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .fill(Palette.brandSoft)
        )
    }


    private var chooseAppsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Pick your apps", systemImage: "square.grid.2x2.fill")
                .font(RansomFont.headline(16))
                .foregroundStyle(Palette.ink)

            Text("Which apps should take a set to open?")
                .font(RansomFont.body(14))
                .foregroundStyle(Palette.inkSoft)

            SecondaryButton(title: "Choose apps", icon: "square.grid.2x2.fill") { showAppPicker = true }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .fill(Palette.brandSoft)
        )
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
                // No balance in the header: the "all" chip is the balance, and
                // the bank row directly beneath says it again in full.
                Text("Spend from your bank")
                    .font(RansomFont.headline(16))
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)

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

    /// The balance and today's receipt, in one row.
    ///
    /// The balance was a 72pt counter with the card to itself, which is the
    /// size of the thing you opened the app for - and it sits third, under two
    /// cards that are. A glance-sized number in third place is the hierarchy
    /// agreeing with the order. Nothing at all until something has happened
    /// today: a row of zeros on day one is a scoreboard for a game not started.
    @ViewBuilder
    private var bankCard: some View {
        if model.bankedMinutes > 0 || model.todayMinutesEarned > 0 || model.todayReps > 0 {
            HStack(spacing: 0) {
                bankStat(
                    value: "\(model.bankedMinutes)",
                    label: "min banked",
                    tint: model.bankedMinutes > 0 ? Palette.brand : Palette.inkFaint
                )

                Divider().frame(height: 30).overlay(Palette.hairline)
                // Earned, not the exchange rate: the earn card already states the
                // rate, and at 10 push-ups for 15 minutes the rate rounds to
                // "1 reps per minute", which is both wrong and ungrammatical.
                bankStat(value: "\(model.todayMinutesEarned)", label: "min earned")

                // Steps only when they're the chosen movement - otherwise it's a
                // stat about a challenge they didn't take.
                if plan.exercise.isPassive {
                    Divider().frame(height: 30).overlay(Palette.hairline)
                    bankStat(value: steps.stepsToday.formatted(), label: "steps today")
                } else if model.todayReps > 0 {
                    Divider().frame(height: 30).overlay(Palette.hairline)
                    bankStat(value: "\(model.todayReps)", label: "\(plan.exercise.unitLabel) today")
                }
            }
            .ransomCard(padding: 14)
        }
    }

    private func bankStat(value: String, label: String, tint: Color = Palette.ink) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(RansomFont.counter(24))
                .foregroundStyle(tint)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.3), value: value)
            Text(label)
                .font(RansomFont.caption(11))
                .foregroundStyle(Palette.inkSoft)
        }
        .frame(maxWidth: .infinity)
    }
}

/// A request to run a set, raised from anywhere in the app.
struct WorkoutRequest: Identifiable, Equatable {
    let id = UUID()
    var exercise: Exercise
    var target: Int
    var trigger: String?
}
