import SwiftUI

// MARK: - Exercises

struct ExercisesStep: View {
    @Binding var profile: UserProfile
    var onNext: () -> Void

    var body: some View {
        StepScaffold(
            title: "Pick your moves",
            subtitle: "These are what unlock your apps. Pick at least one - you can swap them any time.",
            isButtonEnabled: !profile.exercises.isEmpty,
            onNext: onNext
        ) {
            VStack(spacing: 12) {
                ForEach(Exercise.selectable) { exercise in
                    ChoiceCard(
                        title: exercise.title,
                        subtitle: exercise.pitch,
                        icon: exercise.symbol,
                        isSelected: profile.exercises.contains(exercise),
                        allowsMultiple: true
                    ) {
                        if profile.exercises.contains(exercise) {
                            // Never let them end up with nothing selected.
                            if profile.exercises.count > 1 {
                                profile.exercises.remove(exercise)
                            }
                        } else {
                            profile.exercises.insert(exercise)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Intensity

struct IntensityStep: View {
    @Binding var profile: UserProfile
    var onNext: () -> Void

    private var plan: RansomPlan { RansomPlan.make(from: profile) }

    var body: some View {
        StepScaffold(
            title: "Pick your pace",
            subtitle: "Most people start on Standard. You can move up whenever you like - just not back down until your run is up.",
            onNext: onNext
        ) {
            VStack(spacing: 12) {
                ForEach(Intensity.allCases) { intensity in
                    VStack(spacing: 10) {
                        ChoiceCard(
                            title: intensity.title,
                            subtitle: "\(intensity.blurb)\n\(profile.setSummary(at: intensity))",
                            icon: intensity.symbol,
                            isSelected: profile.intensity == intensity
                        ) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                profile.intensity = intensity
                                // A tier with no run attached is only half a
                                // decision, so picking one seeds the shortest.
                                if profile.commitmentDays == nil {
                                    profile.commitmentDays = CommitmentLength.five.days
                                }
                                profile.commitmentStartedAt = Date()
                            }
                        }

                        // The run sits under the tier it applies to, so "this hard,
                        // for this long" reads as one decision rather than two.
                        if profile.intensity == intensity {
                            VStack(spacing: 8) {
                                Text("Locked in for")
                                    .font(RansomFont.caption(12))
                                    .foregroundStyle(Palette.inkSoft)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                CommitmentPicker(days: Binding(
                                    get: { profile.commitmentDays },
                                    set: {
                                        profile.commitmentDays = $0
                                        profile.commitmentStartedAt = Date()
                                    }
                                ))
                            }
                            .padding(.horizontal, 4)
                            .padding(.bottom, 4)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }

                // Live preview of what the choice actually means.
                HStack(spacing: 0) {
                    previewStat(
                        value: "\(plan.repsPerUnlock)",
                        label: profile.primaryExercise.shortTitle.lowercased()
                    )
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Palette.inkFaint)
                    previewStat(value: "\(plan.minutesPerUnlock) min", label: "banked")
                }
                .padding(.vertical, 6)
                .ransomCard()
                .padding(.top, 4)

                Text("Same rate all day. Do as many sets as you like - the minutes stack up in your bank and clear at midnight.")
                    .font(RansomFont.body(13))
                    .foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
                    .padding(.top, 2)
            }
        }
    }






    private func previewStat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(RansomFont.title(24))
                .foregroundStyle(Palette.brand)
                .contentTransition(.numericText())
            Text(label)
                .font(RansomFont.caption(12))
                .foregroundStyle(Palette.inkSoft)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Notifications

struct NotificationsStep: View {
    var onNext: () -> Void

    @State private var isRequesting = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            RexScene(
                pose: .coach,
                line: "I'll ping you when your minutes are up, and once a day if you've gone quiet. That's it. No spam, promise.",
                size: 130,
                typewriter: true
            )
            .padding(.horizontal, Metrics.screenPadding)

            VStack(spacing: 10) {
                Text("Can Rex check in?")
                    .font(RansomFont.title(27))
                    .foregroundStyle(Palette.ink)
                Text("A heads-up when your unlocked time ends, and one gentle nudge a day if you haven't moved yet.")
                    .font(RansomFont.body(15))
                    .foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }
            .padding(.top, 32)

            Spacer()

            VStack(spacing: 8) {
                PrimaryButton(title: "Yes, keep me posted", isLoading: isRequesting) {
                    isRequesting = true
                    Task {
                        let granted = await NotificationManager.requestPermission()
                        if granted { NotificationManager.scheduleDailyNudge() }
                        isRequesting = false
                        onNext()
                    }
                }
                TextButton(title: "Not now", action: onNext)
            }
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.bottom, 24)
        }
    }
}

// MARK: - Referral

struct ReferralStep: View {
    @Binding var profile: UserProfile
    var onNext: () -> Void

    var body: some View {
        StepScaffold(
            title: "Where did you hear about Ransom?",
            subtitle: "It helps us know where to show up.",
            showsButton: false,
            onNext: onNext
        ) {
            VStack(spacing: 12) {
                ForEach(ReferralSource.allCases) { source in
                    ChoiceCard(
                        title: source.title,
                        emoji: source.emoji,
                        isSelected: profile.referral == source
                    ) {
                        profile.referral = source
                        AutoAdvance.after(onNext)
                    }
                }
            }
        }
    }
}

// MARK: - Social proof

struct SocialProofStep: View {
    var onNext: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            HStack(spacing: 3) {
                ForEach(0..<5, id: \.self) { _ in
                    Image(systemName: "star.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color(hex: 0xFFC531))
                }
            }

            Text("Ransom works because it's annoying")
                .font(RansomFont.title(26))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
                .padding(.top, 14)

            Text("In exactly the right way.")
                .font(RansomFont.body(15))
                .foregroundStyle(Palette.inkSoft)
                .padding(.top, 4)

            VStack(spacing: 12) {
                testimonial(
                    quote: "I've done 1,400 push-ups this month purely because I wanted to look at memes.",
                    author: "Dara K."
                )
                testimonial(
                    quote: "Cut two hours a day off my phone without deleting a single app.",
                    author: "Marcus T."
                )
            }
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.top, 28)

            Spacer()

            PrimaryButton(title: "Build my plan", action: onNext)
                .padding(.horizontal, Metrics.screenPadding)
                .padding(.bottom, 24)
        }
    }

    private func testimonial(quote: String, author: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("“\(quote)”")
                .font(RansomFont.body(15))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("\u{2013} \(author)")
                .font(RansomFont.caption(12))
                .foregroundStyle(Palette.inkSoft)
        }
        .ransomCard()
    }
}

// MARK: - Building the plan

/// The obligatory "we're doing maths about you" beat. It's theatre, but it's the
/// moment the answers turn into something that feels personal.
struct BuildingPlanStep: View {
    var profile: UserProfile
    var onNext: () -> Void

    @State private var progress: Double = 0
    @State private var completedLines = 0

    private let lines = [
        "Reading your answers",
        "Sizing your sets",
        "Setting your unlock rate",
        "Warming up Rex"
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                ProgressRing(progress: progress, lineWidth: 12)
                    .frame(width: 190, height: 190)
                PercentLabel(fraction: progress)
            }

            Text("Building your plan")
                .font(RansomFont.title(25))
                .foregroundStyle(Palette.ink)
                .padding(.top, 28)

            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(index < completedLines ? Palette.brand : Palette.surfaceAlt)
                                .frame(width: 24, height: 24)
                            if index < completedLines {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Palette.onBrand)
                            }
                        }
                        Text(line)
                            .font(RansomFont.body(15))
                            .foregroundStyle(index < completedLines ? Palette.ink : Palette.inkFaint)
                        Spacer()
                    }
                }
            }
            .padding(.top, 30)
            .padding(.horizontal, 44)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: completedLines)

            Spacer()

            RexImage(pose: .idle, size: 110)
                .padding(.bottom, 30)
        }
        .onAppear(perform: run)
    }

    private func run() {
        let duration = 3.4
        withAnimation(.easeInOut(duration: duration)) {
            progress = 1
        }
        for index in lines.indices {
            DispatchQueue.main.asyncAfter(deadline: .now() + duration * (Double(index + 1) / Double(lines.count)) - 0.25) {
                completedLines = index + 1
                Haptics.tap()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.35) {
            Haptics.success()
            onNext()
        }
    }
}

/// A percentage that actually counts up.
///
/// `Text` isn't animatable, so under `withAnimation` it jumps straight to the
/// final value while the ring beneath it sweeps - and cross-fades "0%" over
/// "100%" on the way, which read as a rendering bug in screenshots. Making the
/// fraction animatable data gives the label every intermediate frame.
private struct PercentLabel: View, Animatable {
    var fraction: Double

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    var body: some View {
        Text("\(Int((fraction * 100).rounded()))%")
            .font(RansomFont.counter(40))
            .foregroundStyle(Palette.ink)
    }
}

// MARK: - Plan reveal

/// The promise, one screen before the paywall, in the user's own numbers.
///
/// One hero figure with everything else in its service. The hero is the time
/// they get back each day: the hours they gave on the hours step minus the
/// target they set on the goal step. Two of their own answers, no model between
/// them. An earlier version led with the set size beside a rep-based daily goal,
/// which sold the price rather than the purchase - and under the bank a big rep
/// count is what a day spent scrolling looks like.
struct PlanRevealStep: View {
    var profile: UserProfile
    var onNext: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How much of the screen has arrived. The hero lands alone first so it is
    /// read as the point; the chart and Rex follow as support, not competition.
    @State private var stage = 0

    private var plan: RansomPlan { RansomPlan.make(from: profile) }
    private var exercise: Exercise { profile.primaryExercise }

    private var baselineMinutes: Int { profile.baselineDailyMinutes }
    /// Their hours minus their target. Read off the plan rather than recomputed,
    /// so this card, the chart under it and the paywall's month figure all come
    /// from the same curve and cannot drift apart.
    private var savedMinutes: Int { plan.projectedMinutesSavedPerDay }
    private var goalMinutes: Int { profile.goalDailyMinutes ?? (baselineMinutes - savedMinutes) }
    private var hasSaving: Bool { savedMinutes > 0 }

    var body: some View {
        StepScaffold(
            title: profile.firstName.isEmpty ? "Your plan is ready" : "\(profile.firstName), your plan is ready",
            subtitle: profile.identity.map { "Built to help you \($0.shortForm)." }
                ?? "Here's how your days are about to look.",
            // No number on this button. The commitment length and the trial length
            // are different clocks, and "Start my 5-day run" straight into a 3-day
            // trial read as a bait and switch. The paywall states the trial terms.
            buttonTitle: "Start my plan",
            onNext: onNext
        ) {
            VStack(spacing: 14) {
                staged(heroCard, at: 1)

                if hasSaving {
                    staged(projectionCard, at: 2)
                }

                staged(IntakeRexScene(pose: .thumbsUp, line: rexLine, size: 96), at: 3)
            }
            .onAppear(perform: reveal)
        }
    }

    // MARK: Pieces

    @ViewBuilder
    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if hasSaving {
                eyebrow("BACK IN YOUR HANDS, EVERY DAY")

                // Green is the win: time not spent scrolling. The reps that buy it
                // stay in Rex's mouth below, in the brand colour, as the price.
                Text(clock(savedMinutes))
                    .font(RansomFont.display(56))
                    .foregroundStyle(Palette.green)

                Text("\(capitalised(appsPhrase)), down from \(clock(baselineMinutes)) a day to your \(clock(goalMinutes)) target.")
                    .font(RansomFont.body(14))
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // They set the target where they already are, so there is no time
                // to promise back. The deal itself becomes the headline instead of
                // a zero.
                eyebrow("ONE SET")

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(plan.repsPerUnlock) \(exercise.shortTitle.lowercased())")
                        .font(RansomFont.display(34))
                        .foregroundStyle(Palette.ink)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Palette.brand)
                    Text("\(plan.minutesPerUnlock) min")
                        .font(RansomFont.display(34))
                        .foregroundStyle(Palette.brand)
                }

                Text("Nothing is off-limits. Every minute in \(appsPhrase) just starts with a set.")
                    .font(RansomFont.body(14))
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .ransomCard()
    }

    /// Projected daily screen time over four weeks, ending on their target.
    ///
    /// The points are read back out of `plan.projectedHoursSaved(overDays:)` rather
    /// than re-deriving the curve here. An earlier version of this chart carried its
    /// own copy of the curve's constant, so retuning the plan would have silently
    /// left the picture telling a different story to the numbers above it.
    private var projectionCard: some View {
        let baseline = plan.hoursPerDay
        let points = (0...4).map { projectedHours(onDay: $0 * 7) }
        let monthHours = Int(plan.firstMonthHoursSaved.rounded())

        return VStack(alignment: .leading, spacing: 12) {
            Text("Your screen time from here")
                .font(RansomFont.headline(16))
                .foregroundStyle(Palette.ink)

            ProjectionChart(points: points, progress: stage >= 2 ? 1 : 0)
                .frame(height: 78)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.9), value: stage)

            HStack {
                Text("Today · \(formatted(baseline))")
                    .font(RansomFont.caption(12))
                    .foregroundStyle(Palette.inkSoft)
                Spacer()
                Text("Week 4 · \(formatted(points.last ?? baseline)), your target")
                    .font(RansomFont.caption(12))
                    .foregroundStyle(Palette.green)
            }

            // The assumption, stated. The projection screen earlier does the same:
            // a month figure that can be checked is worth more than a bigger one
            // that can't, and this is the number the paywall repeats next.
            Text("Assumes you ease down to your target over four weeks. That's about \(monthHours)h back in your first month.")
                .font(RansomFont.caption(12))
                .foregroundStyle(Palette.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .ransomCard()
    }

    /// The mechanism, in Rex's voice. Deliberately the only place the set size
    /// appears on this screen: the rate is how the plan works, not what it is for,
    /// and the pace and bank steps just showed it as a figure twice.
    private var rexLine: String {
        let name = profile.firstName.isEmpty ? "" : ", \(profile.firstName)"
        if hasSaving {
            return "\(plan.repsPerUnlock) \(exercise.title.lowercased()) banks \(plan.minutesPerUnlock) minutes\(name). Do a set whenever suits you, spend them when you want them. Let's go."
        }
        return "Do a set whenever suits you\(name), and spend the minutes when you want them. Let's go."
    }

    /// The apps they named, in the order the apps step lists them. Up to four
    /// are spelled out; past that the sentence stops being a sentence.
    private var appsPhrase: String {
        let names = DistractingApp.allCases
            .filter { profile.distractingApps.contains($0) }
            .map(\.title)
        switch names.count {
        case 0:
            return "your apps"
        case 1:
            return names[0]
        case 2...4:
            return names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
        default:
            return names.prefix(3).joined(separator: ", ") + " and \(names.count - 3) more"
        }
    }

    // MARK: Reveal

    private func reveal() {
        guard stage == 0 else { return }
        guard !reduceMotion else {
            stage = 3
            return
        }
        let spring = Animation.spring(response: 0.5, dampingFraction: 0.85)
        withAnimation(spring) { stage = 1 }
        // Beats between arrivals, so each piece is seen landing rather than the
        // whole screen simply being there.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(spring) { stage = 2 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(spring) { stage = 3 }
        }
    }

    private func staged<V: View>(_ view: V, at threshold: Int) -> some View {
        view
            .opacity(stage >= threshold ? 1 : 0)
            .offset(y: stage >= threshold ? 0 : 16)
    }

    // MARK: Helpers

    private func eyebrow(_ text: String) -> some View {
        Text(text)
            .font(RansomFont.caption(11))
            .tracking(1.4)
            .foregroundStyle(Palette.inkFaint)
    }

    /// Hours still scrolled on a given day, taken from the one curve every other
    /// projection in the app reads.
    private func projectedHours(onDay day: Int) -> Double {
        let savedThatDay = plan.projectedHoursSaved(overDays: day + 1)
            - plan.projectedHoursSaved(overDays: day)
        return max(0, plan.hoursPerDay - savedThatDay)
    }

    private func clock(_ minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest)m" }
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }

    /// Rounded, not truncated: the week-4 point is the goal reconstructed through
    /// floating point, and truncation turned a 275-minute target into 274.
    private func formatted(_ hours: Double) -> String {
        clock(Int((hours * 60).rounded()))
    }

    private func capitalised(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }
}

/// Filled line chart for the projection. Five points, no dependency needed.
/// Drawn in green: a falling line here is the win the plan is selling.
///
/// The axis starts at zero, as it must, which makes a third-off drop look like a
/// gentle slope. The dashed guide at the target level is the honest fix: the gap
/// between the line's start and the guide is the hero number, drawn to scale, and
/// the line is seen landing on it rather than trailing off.
private struct ProjectionChart: View {
    var points: [Double]
    /// How much of the line has been drawn, 0 to 1, left to right. The fall is
    /// watched happening rather than presented finished.
    var progress: Double = 1

    var body: some View {
        GeometryReader { geo in
            let maxValue = (points.max() ?? 1) * 1.1
            let step = points.count > 1 ? geo.size.width / CGFloat(points.count - 1) : 0
            let targetY = geo.size.height * (1 - CGFloat((points.last ?? 0) / max(maxValue, 0.001)))

            let coordinates = points.enumerated().map { index, value in
                CGPoint(
                    x: CGFloat(index) * step,
                    y: geo.size.height * (1 - CGFloat(value / max(maxValue, 0.001)))
                )
            }

            ZStack {
                // Fill
                Path { path in
                    guard let first = coordinates.first else { return }
                    path.move(to: CGPoint(x: first.x, y: geo.size.height))
                    path.addLine(to: first)
                    coordinates.dropFirst().forEach { path.addLine(to: $0) }
                    path.addLine(to: CGPoint(x: coordinates.last?.x ?? 0, y: geo.size.height))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [Palette.green.opacity(0.28), Palette.green.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                // Target guide
                Path { path in
                    path.move(to: CGPoint(x: 0, y: targetY))
                    path.addLine(to: CGPoint(x: geo.size.width, y: targetY))
                }
                .stroke(Palette.green.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [4, 5]))

                // Line
                Path { path in
                    guard let first = coordinates.first else { return }
                    path.move(to: first)
                    coordinates.dropFirst().forEach { path.addLine(to: $0) }
                }
                .stroke(Palette.green, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                if let last = coordinates.last {
                    Circle()
                        .fill(Palette.green)
                        .frame(width: 10, height: 10)
                        .position(last)
                        // Arrives with the line's end rather than sitting there
                        // waiting for it.
                        .opacity(progress >= 1 ? 1 : 0)
                }
            }
            .mask(alignment: .leading) {
                // A little wider than the drawn width, or the end dot loses its
                // right half to the mask edge.
                Rectangle()
                    .frame(width: geo.size.width * progress + 8)
            }
        }
    }
}
