import SwiftUI

// MARK: - Exercises

struct ExercisesStep: View {
    @Binding var profile: UserProfile
    var onNext: () -> Void

    var body: some View {
        StepScaffold(
            title: "Pick your currency",
            subtitle: "What you'll do to buy scroll time. Choose at least one — you can swap any time.",
            isButtonEnabled: !profile.exercises.isEmpty,
            onNext: onNext
        ) {
            VStack(spacing: 12) {
                ForEach(Exercise.allCases) { exercise in
                    ChoiceCard(
                        title: exercise.title,
                        subtitle: exercise.coachingCue,
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

    private var plan: ReppPlan { ReppPlan.make(from: profile) }

    var body: some View {
        StepScaffold(
            title: "How hard should Rex push?",
            subtitle: "You can change this whenever. Most people start on Standard.",
            onNext: onNext
        ) {
            VStack(spacing: 12) {
                ForEach(Intensity.allCases) { intensity in
                    ChoiceCard(
                        title: intensity.title,
                        subtitle: intensity.blurb,
                        icon: intensity.symbol,
                        isSelected: profile.intensity == intensity
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            profile.intensity = intensity
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
                    previewStat(value: "\(plan.minutesPerUnlock) min", label: "of scrolling")
                }
                .padding(.vertical, 6)
                .reppCard()
                .padding(.top, 4)
            }
        }
    }

    private func previewStat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(ReppFont.title(24))
                .foregroundStyle(Palette.green)
                .contentTransition(.numericText())
            Text(label)
                .font(ReppFont.caption(12))
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
                line: "One nudge a day if you go quiet. That's the whole deal — I'm not going to blow up your phone.",
                size: 130,
                typewriter: true
            )
            .padding(.horizontal, Metrics.screenPadding)

            VStack(spacing: 10) {
                Text("Let Rex check in?")
                    .font(ReppFont.title(27))
                    .foregroundStyle(Palette.ink)
                Text("A reminder when your earned time runs out, and one evening nudge if you haven't moved.")
                    .font(ReppFont.body(15))
                    .foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }
            .padding(.top, 32)

            Spacer()

            VStack(spacing: 8) {
                PrimaryButton(title: "Allow notifications", isLoading: isRequesting) {
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
            title: "Where did you hear about Repp?",
            subtitle: "Genuinely helps us know where to show up.",
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

            Text("Repp works because it's annoying")
                .font(ReppFont.title(26))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
                .padding(.top, 14)

            Text("In exactly the right way.")
                .font(ReppFont.body(15))
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
                .font(ReppFont.body(15))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("— \(author)")
                .font(ReppFont.caption(12))
                .foregroundStyle(Palette.inkSoft)
        }
        .reppCard()
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
        "Calibrating rep targets",
        "Setting your unlock price",
        "Briefing Rex"
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                ProgressRing(progress: progress, lineWidth: 12)
                    .frame(width: 190, height: 190)
                Text("\(Int(progress * 100))%")
                    .font(ReppFont.counter(40))
                    .foregroundStyle(Palette.ink)
            }

            Text("Building your plan")
                .font(ReppFont.title(25))
                .foregroundStyle(Palette.ink)
                .padding(.top, 28)

            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(index < completedLines ? Palette.green : Palette.surfaceAlt)
                                .frame(width: 24, height: 24)
                            if index < completedLines {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Palette.onGreen)
                            }
                        }
                        Text(line)
                            .font(ReppFont.body(15))
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

// MARK: - Plan reveal

struct PlanRevealStep: View {
    var profile: UserProfile
    var onNext: () -> Void

    private var plan: ReppPlan { ReppPlan.make(from: profile) }

    var body: some View {
        StepScaffold(
            title: "Your plan is ready",
            subtitle: "This is the deal Rex will hold you to.",
            buttonTitle: "Start my first week",
            onNext: onNext
        ) {
            VStack(spacing: 14) {
                dealCard

                HStack(spacing: 12) {
                    metric(
                        value: "\(plan.dailyRepGoal)",
                        unit: plan.exercise.shortTitle.lowercased(),
                        label: "daily goal",
                        tint: Palette.green
                    )
                    metric(
                        value: "\(plan.projectedMinutesSavedPerDay)",
                        unit: "min",
                        label: "saved per day",
                        tint: Palette.flame
                    )
                }

                projectionCard

                RexScene(
                    pose: .flex,
                    line: "That's \(plan.repsPerUnlock * 7 * 3) reps a week if you scroll like you say you do. See you on the floor.",
                    size: 104
                )
                .padding(.top, 2)
            }
        }
    }

    private var dealCard: some View {
        VStack(spacing: 16) {
            Text("THE DEAL")
                .font(ReppFont.caption(11))
                .tracking(1.4)
                .foregroundStyle(Palette.inkFaint)

            HStack(spacing: 0) {
                VStack(spacing: 2) {
                    Text("\(plan.repsPerUnlock)")
                        .font(ReppFont.display(46))
                        .foregroundStyle(Palette.ink)
                    Text(plan.exercise.title.lowercased())
                        .font(ReppFont.caption(13))
                        .foregroundStyle(Palette.inkSoft)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 2) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Palette.green)
                }
                .frame(width: 40)

                VStack(spacing: 2) {
                    Text("\(plan.minutesPerUnlock)")
                        .font(ReppFont.display(46))
                        .foregroundStyle(Palette.green)
                    Text("minutes of scroll")
                        .font(ReppFont.caption(13))
                        .foregroundStyle(Palette.inkSoft)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 6)
        .reppCard()
    }

    private func metric(value: String, unit: String, label: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(ReppFont.title(28)).foregroundStyle(tint)
                Text(unit).font(ReppFont.caption(13)).foregroundStyle(Palette.inkSoft)
            }
            Text(label)
                .font(ReppFont.caption(12))
                .foregroundStyle(Palette.inkSoft)
        }
        .reppCard(padding: 16)
    }

    /// A simple downward slope of projected daily screen time over four weeks.
    private var projectionCard: some View {
        let baseline = (profile.scrollLoad ?? .medium).hoursPerDay
        let points = (0...4).map { week in
            baseline * (1 - 0.35 * (Double(week) / 4))
        }

        return VStack(alignment: .leading, spacing: 14) {
            Text("Projected screen time")
                .font(ReppFont.headline(16))
                .foregroundStyle(Palette.ink)

            ProjectionChart(points: points)
                .frame(height: 96)

            HStack {
                Text("Today · \(formatted(baseline))")
                    .font(ReppFont.caption(12))
                    .foregroundStyle(Palette.inkSoft)
                Spacer()
                Text("Week 4 · \(formatted(points.last ?? baseline))")
                    .font(ReppFont.caption(12))
                    .foregroundStyle(Palette.green)
            }
        }
        .reppCard()
    }

    private func formatted(_ hours: Double) -> String {
        let totalMinutes = Int(hours * 60)
        return totalMinutes >= 60
            ? "\(totalMinutes / 60)h \(totalMinutes % 60)m"
            : "\(totalMinutes)m"
    }
}

/// Filled line chart for the projection. Five points, no dependency needed.
private struct ProjectionChart: View {
    var points: [Double]

    var body: some View {
        GeometryReader { geo in
            let maxValue = (points.max() ?? 1) * 1.15
            let step = points.count > 1 ? geo.size.width / CGFloat(points.count - 1) : 0

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
                }
            }
        }
    }
}
