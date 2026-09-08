import SwiftUI

/// The progress tab. Everything the user has done, and what it got them back.
struct StatsView: View {
    @Environment(AppModel.self) private var model

    private enum Window: String, CaseIterable, Identifiable {
        case week, month, allTime
        var id: String { rawValue }
        var title: String {
            switch self {
            case .week:    return "7 days"
            case .month:   return "30 days"
            case .allTime: return "All time"
            }
        }
        var days: Int? {
            switch self {
            case .week:    return 7
            case .month:   return 30
            case .allTime: return nil
            }
        }
    }

    @State private var window: Window = .week

    private var records: [WorkoutRecord] {
        guard let days = window.days,
              let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else {
            return model.history
        }
        return model.history.filter { $0.date >= cutoff }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                ScreenTimeReportCard()
                    .padding(.top, 4)

                ScreenTimeTrendCard()

                headlineCard

                if model.profile.commitmentDays != nil {
                    commitmentCard
                }

                lifetimeCard

                SegmentPicker(
                    options: Window.allCases.map { (value: $0, label: $0.title) },
                    selection: $window
                )

                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                    spacing: 12
                ) {
                    stat(value: "\(totalReps)", label: "reps done", icon: model.profile.primaryExercise.symbol, tint: Palette.brand)
                    stat(value: "\(Int(totalCalories))", label: "calories", icon: "flame.fill", tint: Palette.flame)
                    stat(value: "\(records.count)", label: "sets", icon: "checkmark.seal.fill", tint: Palette.brand)
                    // Earned, not unlocked. These are the minutes the sets paid
                    // out; what was actually spent is a different number, and
                    // this label has already been wrong once on this tab.
                    stat(value: hoursEarned, label: "earned", icon: "lock.open.fill", tint: Palette.green)
                }

                // An empty history already has a Rex line and a streak card saying
                // so; two more empty boxes underneath would just be scolding.
                if !model.history.isEmpty {
                    breakdownCard
                    recentCard
                }
            }
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.bottom, 28)
        }
        .debugScrollAnchor()
        .ransomScreenBackground()
    }

    // MARK: - Derived

    private var totalReps: Int { records.reduce(0) { $0 + $1.reps } }
    private var totalCalories: Double {
        records.reduce(0) { $0 + $1.calories(forWeightKg: model.profile.weightKg) }
    }
    private var totalMinutes: Int { records.reduce(0) { $0 + $1.minutesGranted } }

    private var hoursEarned: String {
        totalMinutes >= 60 ? "\(totalMinutes / 60)h \(totalMinutes % 60)m" : "\(totalMinutes)m"
    }

    /// Reps grouped by movement, biggest first.
    private var breakdown: [(exercise: Exercise, reps: Int)] {
        Dictionary(grouping: records, by: \.exercise)
            .map { (exercise: $0.key, reps: $0.value.reduce(0) { $0 + $1.reps }) }
            .sorted { $0.reps > $1.reps }
    }

    // MARK: - Sections

    /// One number, all time, and nothing else on it.
    ///
    /// Rex used to greet the user here too, which meant two of him on one screen -
    /// the streak card above has the one that has something to say.
    private var lifetimeCard: some View {
        VStack(spacing: 4) {
            Text("LIFETIME")
                .font(RansomFont.caption(11))
                .tracking(1.4)
                .foregroundStyle(Palette.inkFaint)

            Text(model.lifetimeReps, format: .number)
                .font(RansomFont.display(56))
                .foregroundStyle(Palette.ink)
                .contentTransition(.numericText(value: Double(model.lifetimeReps)))

            Text(model.lifetimeReps == 1 ? "rep" : "reps")
                .font(RansomFont.caption(13))
                .foregroundStyle(Palette.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .ransomCard()
    }

    private func minutes(_ value: Int) -> String {
        let v = max(0, value)
        return v >= 60 ? "\(v / 60)h \(v % 60)m" : "\(v)m"
    }

    private var headlineCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                RexImage(pose: model.streak > 2 ? .cheer : .idle, size: 92, isAlive: false)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(model.streak == 0 ? "No streak yet" : "\(model.streak) day streak")
                            .font(RansomFont.title(24))
                            .foregroundStyle(Palette.ink)
                        if model.bestStreak > model.streak {
                            Pill(
                                text: "best \(model.bestStreak)",
                                icon: "trophy.fill",
                                tint: Palette.flame,
                                background: Palette.flameSoft
                            )
                        }
                    }
                    Text(streakLine)
                        .font(RansomFont.body(14))
                        .foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            WeekBars(values: model.weekBars)
        }
        .ransomCard()
    }

    // MARK: - The commitment

    /// Days elapsed out of days promised.
    ///
    /// Derived rather than stored, and clamped on the way out: `commitmentDaysLeft`
    /// adds a day so that the last day of a run still reads "1 day left" rather
    /// than zero, which means on day one it can exceed the length of the run
    /// itself. Left unclamped that produces a negative elapsed count and a ring
    /// that starts out running backwards.
    private var commitmentProgress: (done: Int, total: Int, left: Int, fraction: Double) {
        let total = model.profile.commitmentDays ?? 0
        guard total > 0 else { return (0, 0, 0, 0) }
        let left = min(total, max(0, model.profile.commitmentDaysLeft))
        let done = total - left
        return (done, total, left, Double(done) / Double(total))
    }

    private var isCommitmentComplete: Bool {
        let p = commitmentProgress
        return p.total > 0 && p.left == 0
    }

    /// The run, as a ring that fills a day at a time.
    ///
    /// The number in the middle is days *left*, not days done, because that is the
    /// question somebody opening this tab is actually asking. The ring fills the
    /// other way - it is the part already earned, and a ring that emptied as the
    /// run progressed would make finishing look like loss.
    private var commitmentCard: some View {
        let p = commitmentProgress
        let tint = isCommitmentComplete ? Palette.green : Palette.brand

        return HStack(spacing: 18) {
            ZStack {
                ProgressRing(progress: p.fraction, lineWidth: 11, tint: tint, showsEmptyDot: false)
                    .frame(width: 92, height: 92)

                VStack(spacing: -2) {
                    if isCommitmentComplete {
                        Image(systemName: "checkmark")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(Palette.green)
                    } else {
                        Text("\(p.left)")
                            .font(RansomFont.counter(34))
                            .foregroundStyle(Palette.ink)
                            .contentTransition(.numericText(value: Double(p.left)))
                        Text(p.left == 1 ? "day left" : "days left")
                            .font(RansomFont.caption(11))
                            .foregroundStyle(Palette.inkSoft)
                    }
                }
            }
            .animation(.snappy(duration: 0.35), value: p.fraction)

            VStack(alignment: .leading, spacing: 4) {
                Text(isCommitmentComplete ? "Run complete" : "Your run")
                    .font(RansomFont.headline(17))
                    .foregroundStyle(Palette.ink)

                Text(commitmentLine)
                    .font(RansomFont.body(14))
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)

                if !isCommitmentComplete, let ends = model.profile.commitmentEndsAt {
                    Text("Ends \(ends.formatted(.dateTime.day().month(.abbreviated)))")
                        .font(RansomFont.caption(12))
                        .foregroundStyle(Palette.inkFaint)
                        .padding(.top, 1)
                }
            }

            Spacer(minLength: 0)
        }
        .ransomCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isCommitmentComplete
            ? "Run complete. \(p.total) days finished."
            : "Day \(p.done) of \(p.total). \(p.left) days left in your run.")
    }

    private var commitmentLine: String {
        let p = commitmentProgress
        if isCommitmentComplete {
            return "\(p.total) days, done. Rex held the door the whole way."
        }
        if p.done == 0 {
            return "Day one of \(p.total). The plan is locked until it is up."
        }
        return "Day \(p.done) of \(p.total). You can make it harder, never easier."
    }

    private var streakLine: String {
        switch model.streak {
        case 0:  return "One set today starts it."
        case 1:  return "Day one. Come back tomorrow and it's a streak."
        case 2...6: return "\(model.streak) days in a row. This is how habits start."
        default: return "\(model.streak) days straight and \(model.totalReps.formatted()) reps all time. That's real."
        }
    }

    private func stat(value: String, label: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Takes the user's own movement, so it can be the bundled push-up
            // glyph rather than an SF Symbol.
            ExerciseIcon(name: icon, size: 15)
                .foregroundStyle(tint)
            Text(value)
                .font(RansomFont.title(26))
                .foregroundStyle(Palette.ink)
            Text(label)
                .font(RansomFont.caption(12))
                .foregroundStyle(Palette.inkSoft)
        }
        .ransomCard(padding: 16, radius: 20)
    }

    private var breakdownCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("By move")
                .font(RansomFont.headline(16))
                .foregroundStyle(Palette.ink)

            if breakdown.isEmpty {
                Text("No sets in this range.")
                    .font(RansomFont.body(14))
                    .foregroundStyle(Palette.inkSoft)
            } else {
                ForEach(breakdown, id: \.exercise) { item in
                    HStack(spacing: 12) {
                        ExerciseIcon(name: item.exercise.symbol, size: 14)
                            .foregroundStyle(Palette.brand)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Palette.brandSoft))

                        Text(item.exercise.title)
                            .font(RansomFont.body(15))
                            .foregroundStyle(Palette.ink)

                        Spacer()

                        Text("\(item.reps)")
                            .font(RansomFont.headline(16))
                            .foregroundStyle(Palette.ink)
                    }
                }
            }
        }
        .ransomCard()
    }

    private var recentCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent sets")
                .font(RansomFont.headline(16))
                .foregroundStyle(Palette.ink)

            ForEach(model.history.suffix(6).reversed()) { record in
                HStack(spacing: 12) {
                    Text(record.date, format: .dateTime.weekday(.abbreviated).hour().minute())
                        .font(RansomFont.caption(12))
                        .foregroundStyle(Palette.inkSoft)
                        .frame(width: 96, alignment: .leading)

                    Text("\(record.reps) \(record.exercise.shortTitle.lowercased())")
                        .font(RansomFont.body(14))
                        .foregroundStyle(Palette.ink)

                    Spacer()

                    if record.minutesGranted > 0 {
                        Pill(text: "+\(record.minutesGranted)m")
                    } else {
                        Pill(text: "stopped early", tint: Palette.inkSoft, background: Palette.surfaceAlt)
                    }
                }
            }
        }
        .ransomCard()
    }
}
